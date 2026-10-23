local _, ns = ...

-- Tuned on the 198 px Forever minimap: eight probes a frame walk the edge ring in eight frames, and a full
-- sweep every five seconds catches nodes that spawn inside the radius.
local PROBE_BUDGET = 8
local DISC_INTERVAL = 5

-- The swapped-in blips may reach the minimap a few frames after MINIMAP_UPDATE_TRACKING (UNVERIFIED), so the
-- alerting sweep waits this long and the edge ring keeps running meanwhile.
local SWEEP_DELAY = 0.3
local READY = "Ready. Minimap alerts are on."

-- Blips exist only while tracking is on, so the hint names that step first.
ns.HOVER_HINT = "Turn on Find Herbs or Find Minerals, then hover a blip near the minimap edge once to switch on minimap alerts."

-- Blizzard GUIDs lead with their object kind. These kinds are units, never gathering nodes.
local UNIT_KINDS = { Creature = true, Player = true, Pet = true, Vehicle = true }

local keyed = {}
local queue, queueIndex, queueSilent = nil, 1, false
local lastDisc, lastCalibrate = 0, 0
local primeNext, sweepNext, sweepAt = true, false, 0
local warnedNoMatch = false

ns.observedTypes = {}

-- Gathering nodes are GameObjects, but the minimap tooltip most likely reports its own MinimapMouseover type
-- for every blip, so both count. Units are party members, NPCs and the townsfolk blips, which are noise
-- here. Untyped data is kept because blip tooltips may carry no type at all, and refusing them would leave
-- the addon silent for the very thing it exists to catch. A secret type can be neither compared nor used
-- as a key, so it reads as unwanted.
local function IsWanted(data)
  local dataType = data.type
  if ns.IsSecret(dataType) then return false end

  ns.observedTypes[dataType == nil and "untyped" or dataType] = true
  if not ns.db.objectsOnly then return true end

  -- The type may not separate units from nodes on the minimap, so a GUID that names a unit kind is the
  -- second, exact test. An unknown or absent GUID passes, so a format change can never silence nodes.
  local guid = data.guid
  if guid and not ns.IsSecret(guid) and UNIT_KINDS[guid:match("^(%a+)%-")] then return false end

  if dataType == nil then return true end
  return dataType == Enum.TooltipDataType.Object or dataType == Enum.TooltipDataType.MinimapMouseover
end

-- Without a world position the best available identity is the key alone, which collapses every node of
-- one kind into a single alert rather than guessing, and cannot meet the other source.
local function RememberKey(key)
  if keyed[key] then return false end

  keyed[key] = GetTime()
  return true
end

local function Consider(data, dx, dy, silent)
  if not IsWanted(data) then return end

  local name = ns.BlipName(data)
  if not name then return end

  -- A guid is an exact identity, so it tells apart two nodes of one kind when the blip tooltip happens to
  -- carry one. A secret guid cannot be a key, so the name stands in.
  local guid = data.guid
  local key = guid and not ns.IsSecret(guid) and guid or name

  local isNew
  local x, y = ns.WorldFromOffset(dx, dy)
  if x then
    isNew = ns.SightNode("blip", key, name, x, y)
  else
    isNew = RememberKey(key)
  end

  if isNew and not silent then ns.Alert(name) end
end

-- Positioned nodes age out in the shared memory, so only the keys kept here need pruning.
local function Prune()
  local cutoff = GetTime() - ns.REMEMBER_FOR

  for key, stamp in pairs(keyed) do
    if stamp < cutoff then keyed[key] = nil end
  end
end

-- One queue drives everything. The edge ring is the default refill because it is cheap and catches the
-- common case; the disc takes its turn on an interval, and jumps the queue silently after a view change
-- so the nodes that were already on screen are recorded rather than announced. A swap jumps the queue too,
-- a moment later and loudly, because the nodes it reveals are new to the player.
local function Refill()
  local now = GetTime()
  Prune()

  if primeNext then
    primeNext, sweepNext = false, false
    lastDisc = now
    queue, queueSilent = ns.DiscPoints(), true
  elseif sweepNext and now < sweepAt then
    queue, queueSilent = ns.RingPoints(), false
  elseif sweepNext or now - lastDisc >= DISC_INTERVAL then
    sweepNext = false
    lastDisc = now
    queue, queueSilent = ns.DiscPoints(), false
  else
    queue, queueSilent = ns.RingPoints(), false
  end

  queueIndex = 1
end

-- Idle hovers fail quietly while the cursor is not on a usable blip. Only a blip that no known reading
-- reproduces is worth one line a session, because then the addon cannot start on its own.
local function TryCalibrate()
  local now = GetTime()
  if now - lastCalibrate < 1 then return end

  lastCalibrate = now
  local ok, detail = ns.CalibrateFromCursor()
  if ok then
    ns.Print(READY)
  elseif detail == ns.NO_MATCH and not warnedNoMatch then
    warnedNoMatch = true
    ns.Print(detail)
  end
end

function ns.CalibrateNow()
  local ok, detail = ns.CalibrateFromCursor()
  ns.Print(ok and READY or detail)
end

local function OnUpdate()
  if not ns.db.blips then return end

  -- Probing rewrites the engine's minimap mouseover, so a cursor that is genuinely on the minimap wins.
  -- That idle moment is also the only chance to work out the coordinate space, so take it.
  if Minimap:IsMouseOver() then
    if not ns.db.space then TryCalibrate() end
    return
  end

  -- A blip can only cross the minimap edge while the player moves, so standing still skips the scan.
  if not ns.db.space or not ns.CanAlert() or not ns.IsMoving() then return end

  if not queue or queueIndex > #queue then Refill() end
  if not queue or #queue == 0 then return end

  for _ = 1, PROBE_BUDGET do
    local point = queue[queueIndex]
    if not point then break end

    local data = ns.Probe(point[1], point[2])
    if data then Consider(data, point[1], point[2], queueSilent) end
    queueIndex = queueIndex + 1
  end
end

-- Vignettes are a separate channel that reports minimap arrival directly. Vanilla content probably never
-- uses them, but the event costs nothing when it never fires and covers rares and treasures if Forever does.
-- Leaving stamps the vignette too, so the remember window runs from when it was last on the minimap and
-- Prune ages it out like any other node.
local function VignetteName(vignetteGUID)
  local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
  if info and not ns.IsSecret(info.name) then return info.name end
end

local function OnVignette(vignetteGUID, onMinimap)
  if not ns.db.blips or not ns.db.vignettes or not ns.CanAlert() then return end

  local isNew = onMinimap and not keyed[vignetteGUID]
  keyed[vignetteGUID] = GetTime()
  if isNew then ns.Alert(VignetteName(vignetteGUID) or "Rare or treasure") end
end

-- A new view shows nodes that were already there, so the next sweep records them silently.
local function Reprime()
  primeNext = true
  queue = nil
end

-- With the swap on, every tracking change reveals the other node type, so the next sweep alerts for each
-- node the shared memory does not hold yet. The memory keeps a node quiet on every later swap.
local function Sweep()
  sweepNext = true
  sweepAt = GetTime() + SWEEP_DELAY
  queue = nil
end

local function OnEvent(_, event, ...)
  if event == "VIGNETTE_MINIMAP_UPDATED" then
    OnVignette(...)
    return
  end

  ns.RebuildGeometry()
  if event == "MINIMAP_UPDATE_TRACKING" and ns.db.swap then
    Sweep()
  else
    Reprime()
  end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", OnUpdate)
driver:SetScript("OnEvent", OnEvent)
driver:RegisterEvent("MINIMAP_UPDATE_ZOOM")
driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")
driver:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")

function ns.ResetSeen()
  wipe(keyed)
  ns.ForgetNodes("blip")
  Reprime()
end

function ns.SeenCount()
  local count = ns.NodeCount("blip")
  for _ in pairs(keyed) do count = count + 1 end
  return count
end

ns.OnZoning(function()
  ns.ResetSeen()
  ns.RebuildGeometry()
end)

-- One line, once per account, because the minimap source cannot start until the player hovers a blip.
ns.OnSettingsLoaded(function()
  if ns.db.hinted or ns.db.space or not ns.db.blips then return end

  ns.db.hinted = true
  ns.Print(ns.HOVER_HINT .. " Type /tra for the settings.")
end)
