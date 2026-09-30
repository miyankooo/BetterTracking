local _, ns = ...

local keyed = {}
local queue, queueIndex, queueSilent = nil, 1, false
local lastDisc, lastCalibrate = 0, 0
local primeNext = true

ns.observedTypes = {}

-- Gathering nodes are GameObjects, but the minimap tooltip most likely reports its own MinimapMouseover type
-- for every blip, so both count. Units are party members, NPCs and the townsfolk blips, which are noise
-- here. Untyped data is kept because blip tooltips may carry no type at all, and refusing them would leave
-- the addon silent for the very thing it exists to catch.
local function IsWanted(data)
  local dataType = data.type
  ns.observedTypes[dataType == nil and "untyped" or dataType] = true

  if not ns.db.objectsOnly or dataType == nil then return true end
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

  if isNew and not silent then ns.Alert() end
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
-- so the nodes that were already on screen are recorded rather than announced.
local function Refill()
  local now = GetTime()
  Prune()

  if primeNext then
    primeNext = false
    lastDisc = now
    queue, queueSilent = ns.DiscPoints(), true
  elseif now - lastDisc >= ns.db.discInterval then
    lastDisc = now
    queue, queueSilent = ns.DiscPoints(), false
  else
    queue, queueSilent = ns.RingPoints(), false
  end

  queueIndex = 1
end

-- Speed is secret where unit stats are restricted, and a secret cannot be compared, so an unknown speed
-- counts as standing still.
local function IsMoving()
  local speed = GetUnitSpeed("player")
  return not ns.IsSecret(speed) and speed ~= 0
end

local function TryCalibrate()
  local now = GetTime()
  if now - lastCalibrate < 1 then return end

  lastCalibrate = now
  local ok, detail = ns.CalibrateFromCursor(true)
  if ok then
    ns.Print("calibrated to " .. detail .. " from the blip under your cursor, alerts are live.")
  end
end

local function OnUpdate()
  if not ns.db.blips then return end

  -- Probing rewrites the engine's minimap mouseover, so a cursor that is genuinely on the minimap wins.
  -- That idle moment is also the only chance to work out the coordinate space, so take it.
  if Minimap:IsMouseOver() then
    if not ns.db.space then TryCalibrate() end
    return
  end

  if not ns.db.space or not ns.CanAlert() then return end
  if ns.db.requireMovement and not IsMoving() then return end

  if not queue or queueIndex > #queue then Refill() end
  if not queue or #queue == 0 then return end

  for _ = 1, ns.db.probeBudget do
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
local function OnVignette(vignetteGUID, onMinimap)
  if not ns.db.blips or not ns.db.vignettes or not ns.CanAlert() then return end

  local isNew = onMinimap and not keyed[vignetteGUID]
  keyed[vignetteGUID] = GetTime()
  if isNew then ns.Alert() end
end

-- A new view shows nodes that were already there, so the next sweep records them silently.
local function Reprime()
  primeNext = true
  queue = nil
end

local function OnEvent(_, event, ...)
  if event == "VIGNETTE_MINIMAP_UPDATED" then
    OnVignette(...)
    return
  end

  ns.RebuildGeometry()
  Reprime()
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
