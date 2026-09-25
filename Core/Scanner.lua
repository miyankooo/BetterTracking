local _, ns = ...

local remembered = {}
local keyed = {}
local queue, queueIndex, queueSilent = nil, 1, false
local lastDisc, lastCalibrate = 0, 0
local primeNext = true

ns.observedTypes = {}

-- Gathering nodes are GameObjects. Units are party members, NPCs and the townsfolk blips, which are
-- noise here. Untyped data is kept because blip tooltips may carry no type at all, and refusing them
-- would leave the addon silent for the very thing it exists to catch.
local function IsWanted(data)
  local dataType = data.type
  ns.observedTypes[dataType == nil and "untyped" or dataType] = true

  if not ns.db.objectsOnly or dataType == nil then return true end
  return dataType == Enum.TooltipDataType.Object
end

-- Bucketed keys were the first attempt and broke on exactly this: a node straddling a bucket edge
-- alerted twice. Proximity matching makes the tolerance explicit, and Geometry scales it with zoom.

-- Re-seeing a node refreshes its stamp, so a node you are parked next to never ages out and pings again.
local function Recall(name, x, y)
  local tolerance = ns.MergeYards()

  for _, node in ipairs(remembered) do
    if node.name == name then
      local dx, dy = node.x - x, node.y - y
      if dx * dx + dy * dy <= tolerance * tolerance then
        node.stamp = GetTime()
        return true
      end
    end
  end
  return false
end

local function Consider(data, dx, dy, silent)
  if not IsWanted(data) then return end

  local name = ns.BlipName(data)
  if not name then return end

  local now = GetTime()

  -- A guid is an exact identity and needs none of the position maths, so prefer it when the blip
  -- tooltip happens to carry one.
  if data.guid then
    if keyed[data.guid] then return end

    keyed[data.guid] = now
  else
    local x, y = ns.WorldFromOffset(dx, dy)

    -- Without a world position the best available identity is the name, which collapses every node of
    -- one kind into a single alert rather than guessing.
    if not x then
      if keyed[name] then return end

      keyed[name] = now
    else
      if Recall(name, x, y) then return end

      remembered[#remembered + 1] = { name = name, x = x, y = y, stamp = now }
    end
  end

  if not silent then ns.Alert() end
end

local function Prune()
  local cutoff = GetTime() - ns.REMEMBER_FOR

  for key, stamp in pairs(keyed) do
    if stamp < cutoff then keyed[key] = nil end
  end

  for index = #remembered, 1, -1 do
    if remembered[index].stamp < cutoff then tremove(remembered, index) end
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
  if ns.db.requireMovement and GetUnitSpeed("player") == 0 then return end

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

local function OnEvent(_, event, vignetteGUID, onMinimap)
  -- Vignettes are a separate channel that reports minimap arrival directly. Vanilla content probably
  -- never uses them, but the event costs nothing when it never fires and covers rares and treasures
  -- if Forever does.
  if event == "VIGNETTE_MINIMAP_UPDATED" then
    if not ns.db.blips or not ns.db.vignettes or not ns.CanAlert() then return end

    if onMinimap then
      if not keyed[vignetteGUID] then
        keyed[vignetteGUID] = GetTime()
        ns.Alert()
      end
    else
      keyed[vignetteGUID] = nil
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    wipe(remembered)
    wipe(keyed)
  end

  ns.RebuildGeometry()
  primeNext = true
  queue = nil
end

-- Without the engine hit test there is nothing to scan, so the driver never starts.
if ns.canProbe then
  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", OnUpdate)
  driver:SetScript("OnEvent", OnEvent)
  driver:RegisterEvent("PLAYER_ENTERING_WORLD")
  driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  driver:RegisterEvent("MINIMAP_UPDATE_ZOOM")
  driver:RegisterEvent("MINIMAP_UPDATE_TRACKING")
  driver:RegisterEvent("VIGNETTE_MINIMAP_UPDATED")
end

function ns.ResetSeen()
  wipe(remembered)
  wipe(keyed)
  primeNext = true
  queue = nil
end

function ns.SeenCount()
  local count = #remembered
  for _ in pairs(keyed) do count = count + 1 end
  return count
end
