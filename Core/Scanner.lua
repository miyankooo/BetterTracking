local _, ns = ...

-- Every sweep takes one second at any frame rate: the edge ring once a second, and a full sweep every five
-- seconds catches nodes that spawn inside the radius.
local SWEEP_SECONDS = 1
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
local credit, trackingOn = 0, false
local warnedNoMatch = false

ns.observedTypes = {}

-- Gathering nodes are GameObjects, but the minimap tooltip most likely reports its own MinimapMouseover type
-- for every blip, so both count. Units are party members, NPCs and the townsfolk blips, which are noise
-- here. Untyped data is kept because blip tooltips may carry no type at all, and refusing them would leave
-- the addon silent for the very thing it exists to catch. A secret type can be neither compared nor used
-- as a key, so it reads as unwanted.
local function IsWanted(data)
  local dataType = data.type
  if not ns.CanAccess(dataType) then return false end

  ns.observedTypes[dataType == nil and "untyped" or dataType] = true
  if not ns.db.objectsOnly then return true end

  -- The type may not separate units from nodes on the minimap, so a GUID that names a unit kind is the
  -- second, exact test. An unknown or absent GUID passes, so a format change can never silence nodes.
  local guid = data.guid
  if guid and ns.CanAccess(guid) and UNIT_KINDS[guid:match("^(%a+)%-")] then return false end

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
  local key = guid and ns.CanAccess(guid) and guid or name

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

  queueIndex, credit = 1, 0
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

-- Temporary, like /tra types: one full sweep now, past every scan gate, shows in one line whether the minimap
-- answers with the cursor elsewhere, whether the filter keeps its blips and whether the scan sees tracking on.
function ns.ProbeNow()
  if not ns.db.space then return ns.Print(ns.HOVER_HINT) end
  if Minimap:IsMouseOver() then return ns.Print("Move the cursor off the minimap, then type /tra probe again.") end

  local points = ns.DiscPoints()
  local hits, wanted, names = 0, 0, {}
  for _, point in ipairs(points) do
    local data = ns.Probe(point[1], point[2])
    if data then
      hits = hits + 1
      if IsWanted(data) then wanted = wanted + 1 end
      local name = ns.BlipName(data)
      if #names < 3 and not tContains(names, name) then names[#names + 1] = name end
    end
  end

  local _, active = ns.ReadTracking()
  local tracking = trackingOn and "yes" or active and "no, but the game says yes" or "no"
  ns.Print(("Probe: %d of %d points hit a blip, %d pass the filter (%s). Tracking on: %s. Moving: %s."):format(
    hits, #points, wanted, #names > 0 and table.concat(names, ", ") or NONE, tracking, ns.IsMoving() and YES or NO))
end

local function OnUpdate(_, elapsed)
  if not ns.db.blips then return end

  -- Probing rewrites the engine's minimap mouseover, so a cursor that is genuinely on the minimap wins.
  -- That idle moment is also the only chance to work out the coordinate space, so take it.
  if Minimap:IsMouseOver() then
    if not ns.db.space then TryCalibrate() end
    return
  end

  -- Blips show only while a spell tracking is on, and can only cross the minimap edge while the player moves.
  if not trackingOn or not ns.db.space or not ns.CanAlert() or not ns.IsMoving() then return end

  if not queue or queueIndex > #queue then Refill() end
  if not queue or #queue == 0 then return end

  -- A hitch counts as a tenth of a second at most, so one frozen frame never bursts into a whole sweep.
  credit = credit + math.min(elapsed, 0.1) * #queue / SWEEP_SECONDS
  while credit >= 1 and queueIndex <= #queue do
    local point = queue[queueIndex]
    local data = ns.Probe(point[1], point[2])
    if data then Consider(data, point[1], point[2], queueSilent) end
    queueIndex, credit = queueIndex + 1, credit - 1
  end
end

-- Vignettes are a separate channel that reports minimap arrival directly. Vanilla content probably never
-- uses them, but the event costs nothing when it never fires and covers rares and treasures if Forever does.
-- Leaving stamps the vignette too, so the remember window runs from when it was last on the minimap and
-- Prune ages it out like any other node.
local function VignetteName(vignetteGUID)
  local info = C_VignetteInfo.GetVignetteInfo(vignetteGUID)
  if info and ns.CanAccess(info.name) then return info.name end
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

-- Swap.lua loads later, so its reader is looked up at call time.
local function ReadTrackingOn()
  local _, active = ns.ReadTracking()
  trackingOn = active ~= nil
end

local function OnEvent(_, event, ...)
  if event == "VIGNETTE_MINIMAP_UPDATED" then
    OnVignette(...)
    return
  end

  -- Blizzard's tracking button notes the tracking list stays empty until SPELLS_CHANGED, so the login read
  -- through the zoning hook can miss a tracking that is already on.
  if event == "SPELLS_CHANGED" then return ReadTrackingOn() end

  ns.RebuildGeometry()
  if event == "MINIMAP_UPDATE_TRACKING" then
    ReadTrackingOn()
    if ns.db.swap then return Sweep() end
  end
  Reprime()
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", OnUpdate)
driver:SetScript("OnEvent", OnEvent)
driver:RegisterEvent("MINIMAP_UPDATE_ZOOM")
driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")
driver:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
driver:RegisterEvent("SPELLS_CHANGED")

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
  ReadTrackingOn()
end)
