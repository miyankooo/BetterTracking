local addonName, ns = ...

local TICK = 0.5
local NEEDS_SPELLS = "needs Find Herbs and Find Minerals"

-- A timed swap that does not read as active this long after SetTracking counts as dropped. It stays under
-- the 2 s interval, so the check always runs before the next swap.
local TAKE_TIME = 1.5
local MISSES_TO_BLOCK = 2

-- Each swap spends a global cooldown, so this reason is part of normal running and the status text skips it.
ns.SWAP_COOLDOWN = "on cooldown"

-- Blizzard answers ADDON_ACTION_FORBIDDEN with a popup whose first button disables the addon and reloads.
local FORBIDDEN_HINT = " Choose Ignore in Blizzard's warning."

-- Both ranks the Forever client knows, as listed in Blizzard's tracking menu (Mainline/Minimap.lua).
local KIND_BY_SPELL = { [2383] = "herb", [8387] = "herb", [2580] = "ore", [8388] = "ore" }

-- Blizzard's movement and steering bindings (Bindings_Camelot.xml), the player's own input in input mode.
-- A key that starts travel may still read speed 0 inside its own press (UNVERIFIED), so those skip the
-- standing-still guard. Turning, jumping and clicks do not move the player on their own.
local INPUT_FUNCTIONS = {
  { name = "MoveForwardStart", startsMoving = true },
  { name = "MoveBackwardStart", startsMoving = true },
  { name = "StrafeLeftStart", startsMoving = true },
  { name = "StrafeRightStart", startsMoving = true },
  { name = "MoveAndSteerStart", startsMoving = true },
  { name = "TurnLeftStart" },
  { name = "TurnRightStart" },
  { name = "JumpOrAscendStart" },
  { name = "TurnOrActionStart" },
  { name = "CameraOrSelectOrMoveStart" },
}

local ticker
local lastSwap = 0
local swapping = false
local inputMode = false
local blocked = false
local pendingKind, pendingAt, misses = nil, 0, 0

-- Indices can shift when the player learns or forgets a tracking spell, so every look starts afresh.
-- Only spell tracking counts: one spell is active at a time, while the townsfolk filters are not spells.
function ns.ReadTracking()
  local found, active = {}, nil
  for index = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(index)
    if info and info.type == "spell" then
      info.index = index
      local kind = KIND_BY_SPELL[info.spellID] or "other"
      found[kind] = found[kind] or info
      if info.active then active = info end
    end
  end
  return found, active
end

-- Herbs come first when neither is on, otherwise the type that is off.
local function NextKind(active)
  local kind = active and KIND_BY_SPELL[active.spellID]
  return kind == "herb" and "ore" or "herb"
end

local function IsCasting()
  local casting, channeling = UnitCastingInfo("player"), UnitChannelInfo("player")

  -- A secret cast name cannot be compared, so it counts as a cast in progress.
  return ns.IsSecret(casting) or ns.IsSecret(channeling) or casting ~= nil or channeling ~= nil
end

local function IsEnemy(unit)
  return UnitCanAttack("player", unit) and not UnitIsDead(unit)
end

-- A pull should never start on a global cooldown the swap spent. A click picks its target only on release,
-- after the input hook ran, so the unit under the cursor counts as well.
local function HasEnemyNear()
  return IsEnemy("target") or IsEnemy("mouseover")
end

-- isActive is NeverSecret (SpellSharedDocumentation.lua), so it is readable where cooldowns are secret, and
-- it covers the global cooldown too.
local function OnCooldown(spellID)
  local cooldown = C_Spell.GetSpellCooldown(spellID)
  return cooldown and cooldown.isActive
end

-- The first rule that holds names why the swap waits. A fixed order keeps the tooltip and /tra status
-- naming the same reason.
local function WaitReason(found, active, target, startsMoving)
  if blocked then return "Blizzard blocks it until you type /reload" end
  if not (found.herb and found.ore) then return NEEDS_SPELLS end
  if active and not KIND_BY_SPELL[active.spellID] then return "another tracking is on" end
  if InCombatLockdown() or UnitAffectingCombat("player") then return "in combat" end
  if UnitIsDeadOrGhost("player") then return "dead or a ghost" end
  if UnitOnTaxi("player") then return "on a flight" end
  if IsInInstance() then return "in an instance" end
  if IsResting() then return "resting in a town or inn" end
  if not startsMoving and not ns.IsMoving() then return "standing still" end
  if IsCasting() then return "casting" end
  if LootFrame:IsShown() then return "looting" end
  if HasEnemyNear() then return "an enemy is targeted or under the cursor" end
  if OnCooldown(target.spellID) then return ns.SWAP_COOLDOWN end
end

function ns.SwapWaitReason(startsMoving)
  local found, active = ns.ReadTracking()
  local target = found[NextKind(active)]
  return WaitReason(found, active, target, startsMoving), target
end

function ns.SwapRunsOnInput()
  return inputMode
end

-- Ticks land a few milliseconds either side of the half second, so half a tick of slack keeps the swap on
-- the interval instead of slipping to the next tick.
local function IsDue()
  return GetTime() - lastSwap >= ns.db.swapInterval - TICK / 2
end

-- Casting the other spell replaces the active one, so the swap only ever turns tracking on.
-- ADDON_ACTION_BLOCKED and ADDON_ACTION_FORBIDDEN are synchronous, so they fire inside this call.
local function TrySwap(startsMoving)
  if not IsDue() then return end

  local reason, target = ns.SwapWaitReason(startsMoving)
  if reason then return end

  lastSwap = GetTime()

  -- Only a timed swap is checked, and the expectation is set first because the cast event confirming it may
  -- arrive inside the call. A block inside the call moves the swap to input mode, which clears it again.
  if not inputMode then pendingKind, pendingAt = KIND_BY_SPELL[target.spellID], lastSwap end
  swapping = true
  C_Minimap.SetTracking(target.index, true)
  swapping = false
end

-- At most one swap per key press or click. While the player only holds a key or autoruns, no new input
-- arrives, so the swap pauses until the next one.
local function OnInput(startsMoving)
  if inputMode and ns.db.swap then TrySwap(startsMoving) end
end

local function EnterInputMode(line)
  inputMode = true
  pendingKind = nil
  if ticker then ticker:Cancel() end
  ticker = nil

  for _, input in ipairs(INPUT_FUNCTIONS) do
    hooksecurefunc(input.name, function() OnInput(input.startsMoving) end)
  end
  ns.Print(line)
end

-- The tracking mirror can lag the cast, so the cast event confirms a timed swap first. The spell ID is secret
-- while casts are restricted, and a secret confirms nothing.
local function OnCastSucceeded(spellID)
  if pendingKind and not ns.IsSecret(spellID) and KIND_BY_SPELL[spellID] == pendingKind then
    pendingKind, misses = nil, 0
  end
end

-- The client might drop a timed SetTracking without a block event (UNVERIFIED), which would leave the swap
-- silently idle. A timed swap that has not taken is a miss, and misses in a row count as a block.
local function CheckTaken()
  if not pendingKind or GetTime() - pendingAt < TAKE_TIME then return end

  local _, active = ns.ReadTracking()
  local took = active and KIND_BY_SPELL[active.spellID] == pendingKind
  pendingKind = nil
  misses = took and 0 or misses + 1
  if misses >= MISSES_TO_BLOCK then
    EnterInputMode("Timed swaps did not take, so the swap now runs on your movement keys.")
  end
end

local function OnTick()
  CheckTaken()
  if not inputMode then TrySwap() end
end

-- A block during a timed swap moves the swap onto the player's own input, once a session. A block there
-- too leaves nothing to try, so the swap stops before Blizzard's warning can repeat on every key press.
-- Missing hardware events may well come as FORBIDDEN, so both events move to input mode first.
local function OnBlocked(_, event, blockedAddon)
  if not swapping or blockedAddon ~= addonName then return end

  local hint = event == "ADDON_ACTION_FORBIDDEN" and FORBIDDEN_HINT or ""
  if not inputMode then
    EnterInputMode("Blizzard blocked timed swaps, so the swap now runs on your movement keys." .. hint)
  elseif not blocked then
    blocked = true
    ns.Print("Blizzard blocks the swap on movement keys too, so it stays off until you type /reload." .. hint)
  end
end

local function OnEvent(self, event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    OnCastSucceeded(select(3, ...))
  else
    OnBlocked(self, event, ...)
  end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

-- The ticker runs only while the swap is on and timed swaps work.
function ns.ApplySwap()
  local wanted = ns.db.swap and not inputMode
  if wanted and not ticker then
    pendingKind, misses = nil, 0
    ticker = C_Timer.NewTicker(TICK, OnTick)
  elseif not wanted and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- The setting is account-wide, so it turns on even for a character without both spells, and says why it
-- waits there.
function ns.ToggleSwap()
  ns.db.swap = not ns.db.swap
  ns.ApplySwap()

  -- The settings checkbox reads its value only when shown, so an open panel needs telling.
  Settings.NotifyUpdate("BETTER_TRACKING_SWAP")

  if not ns.db.swap then
    ns.Print("Herb and ore swap off.")
  elseif blocked then
    ns.Print("Herb and ore swap stays off until you type /reload, because Blizzard blocks it.")
  elseif ns.SwapWaitReason() == NEEDS_SPELLS then
    ns.Print("Herb and ore swap needs Find Herbs and Find Minerals.")
  else
    ns.Print("Herb and ore swap on.")
  end
end

ns.OnSettingsLoaded(ns.ApplySwap)
