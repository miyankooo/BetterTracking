local _, ns = ...

-- GatherMate2 draws its own tracking circle once a node is within its track distance, so this source
-- alerts on that transition. GatherMate2 is optional: nothing here runs unless it loaded.
local GatherMate, Display
local nativeCircle
local seen = {}
local mergeStamp = 0
local mergeLeaders = {}

local function TypeColor(nodeType)
  local color = GatherMate.db.profile.trackColors[nodeType]
  if color then return color.Red, color.Green, color.Blue end
end

-- The native circle is 10px on GatherMate2's classic branch and 12px on master, and a Forever build could
-- come from either. So it is read off the first circle, which the hook always sees straight after
-- GatherMate2 sized it and before this addon resized anything.
local function NativeCircle(pin)
  if not nativeCircle then nativeCircle = pin:GetHeight() * Minimap:GetScale() end
  return nativeCircle
end

-- GatherMate2 sizes a circle once, when a pin turns into one, so resize right after it in the hook for the
-- setting to stick. Step 1 keeps the native size and each step adds 2px.
local function ApplyCircleSize(pin)
  local size = (NativeCircle(pin) - 2 + 2 * ns.db.circleSize) / Minimap:GetScale()
  if math.abs(pin:GetHeight() - size) > 0.01 then
    pin:SetSize(size, size)
  end
end

-- Nearby nodes are separate spawns with distinct coordinates, so circles that overlap on screen merge by
-- pin distance. GatherMate2 places every pin within one frame, so frame time marks the batch. The lowest
-- coordinate leads, never the first arrival, because full sweeps and per-move updates visit pins in
-- different orders and first-come leadership made the visible circle hop between cluster members.
local function MergeCircle(pin)
  -- GatherMate2 skips positioning a pin it hides at the edge, so a hidden pin has a stale point.
  if not pin:IsShown() then return end
  local _, _, _, x, y = pin:GetPoint(1)
  if not x then return end

  local now = GetTime()
  if mergeStamp ~= now then
    mergeStamp = now
    wipe(mergeLeaders)
  end

  -- Reach stays at the native footprint whatever the size setting, because a scaled reach merged nodes
  -- that never overlapped at default size and moved the visible circle off its node.
  local reach = NativeCircle(pin) / Minimap:GetScale()
  for _, leader in ipairs(mergeLeaders) do
    if leader.pin == pin then return end

    local dx, dy = x - leader.x, y - leader.y
    if dx * dx + dy * dy < reach * reach then
      if pin.nodeType ~= leader.type then leader.mixed = true end

      if pin.coords < leader.coords or (pin.coords == leader.coords and pin.nodeType < leader.type) then
        leader.pin:Hide()
        leader.pin, leader.coords, leader.type = pin, pin.coords, pin.nodeType
        leader.x, leader.y = x, y
      else
        pin:Hide()
      end

      -- Gold marks a cluster of mixed types. Repainting the type colour heals a leader that was gold a
      -- frame earlier.
      if leader.mixed then
        leader.pin.texture:SetVertexColor(unpack(ns.GOLD))
      else
        local r, g, b = TypeColor(leader.type)
        if r then leader.pin.texture:SetVertexColor(r, g, b) end
      end
      return
    end
  end

  mergeLeaders[#mergeLeaders + 1] = { pin = pin, coords = pin.coords, x = x, y = y, type = pin.nodeType }
end

-- The hook runs every frame for every pin, so anything that is not a circle bails out first. It runs
-- right after addMiniPin's own Show, which is why hiding icon pins here wins.
local function OnMiniPin(_, pin)
  if not pin.isCircle then
    if ns.db.hideIcons then pin:Hide() end
    return
  end

  ApplyCircleSize(pin)

  -- Merge before the alert gates, so a hidden duplicate still alerts for its own node type.
  if ns.db.mergeCircles then MergeCircle(pin) end

  if not ns.db.gatherMate or ns.db.mutedTypes[pin.nodeType] or not ns.CanAlert() then return end

  local now = GetTime()
  local byType = seen[pin.nodeType]
  if not byType then
    byType = {}
    seen[pin.nodeType] = byType
  end

  local lastSeen = byType[pin.coords]
  byType[pin.coords] = now
  if lastSeen and now - lastSeen < ns.REMEMBER_FOR then return end

  -- The flash takes the circle's own colour, so the colour alone tells the node type.
  ns.Alert(TypeColor(pin.nodeType))
end

-- GatherMate2 is read through its internals, not an API, so a build that moved them turns this source
-- off with a notice instead of an error.
local function Attach()
  local aceAddon = LibStub and LibStub("AceAddon-3.0", true)
  GatherMate = aceAddon and aceAddon:GetAddon("GatherMate2", true)
  Display = GatherMate and GatherMate:GetModule("Display", true)

  if not (Display and type(Display.addMiniPin) == "function") then
    ns.Print("GatherMate2 is loaded, but its minimap pins were not found. The GatherMate2 source is off.")
    return
  end

  hooksecurefunc(Display, "addMiniPin", OnMiniPin)
  ns.gatherMateReady = true
end

function ns.GatherMateTypes()
  local types = {}
  if ns.gatherMateReady then
    for _, nodeType in pairs(GatherMate.db_types) do
      types[#types + 1] = nodeType
    end
    table.sort(types)
  end
  return types
end

-- Rebuilding GatherMate2's minimap pins makes a display setting apply without moving.
function ns.RefreshGatherMate()
  if ns.gatherMateReady then Display:UpdateMaps() end
end

-- The hook reads settings on every call, so it attaches only once they are loaded.
ns.OnSettingsLoaded(function()
  EventUtil.ContinueOnAddOnLoaded("GatherMate2", Attach)
end)

local zoning = CreateFrame("Frame")
zoning:RegisterEvent("PLAYER_ENTERING_WORLD")
zoning:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoning:SetScript("OnEvent", function() wipe(seen) end)
