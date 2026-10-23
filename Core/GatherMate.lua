local _, ns = ...

-- GatherMate2 draws its own tracking circle once a node is within its track distance, so this source
-- alerts on that transition. GatherMate2 is optional: nothing here runs unless it loaded.
local GatherMate, Display
local seen = {}

-- GatherMate2 registers seven node types, but its Forever build hides Gas, Archaeology and Logging, so
-- only these four can ever show up there.
local FOREVER_TYPES = { ["Herb Gathering"] = true, Mining = true, Fishing = true, Treasure = true }

local function TypeColor(nodeType)
  local color = GatherMate.db.profile.trackColors[nodeType]
  if color then return color.Red, color.Green, color.Blue end
end

-- GatherMate2 keeps each node's zone coordinates on its pin, and the conversion the blip source uses for the
-- player turns them into the same world yards, so both sources can meet in the shared node memory.
local function PinWorld(pin)
  if not (pin.zone and pin.x and pin.y) then return nil end

  local _, world = C_Map.GetWorldPosFromMapPos(pin.zone, CreateVector2D(pin.x, pin.y))
  if world then return world.x, world.y end
end

-- A circle is keyed by its database entry and named with GatherMate2's node name, which is the game
-- object's own name, so a blip of the same node matches it. Without a world position the circle can only
-- stand for itself.
local function SightPin(pin)
  local x, y = PinWorld(pin)
  if not x then return true, { stamp = GetTime() } end

  return ns.SightNode("gathermate", pin.nodeType .. ":" .. pin.coords, pin.title, x, y)
end

-- The hook runs every frame for every pin, so anything that is not a circle bails out first.
local function OnMiniPin(_, pin)
  if not pin.isCircle then return end
  if not ns.db.gatherMate or ns.db.mutedTypes[pin.nodeType] or not ns.CanAlert() then return end

  local byType = seen[pin.nodeType]
  if not byType then
    byType = {}
    seen[pin.nodeType] = byType
  end

  -- The hook runs every frame, so a circle looks its node up in the shared memory once and then keeps it
  -- fresh through this table.
  local node = byType[pin.coords]
  local now = GetTime()
  if node and now - node.stamp < ns.REMEMBER_FOR then
    node.stamp = now
    return
  end

  local isNew
  isNew, node = SightPin(pin)
  byType[pin.coords] = node

  -- The flash takes the circle's own colour, so the colour alone tells the node type.
  if isNew then ns.Alert(pin.title, TypeColor(pin.nodeType)) end
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
      if FOREVER_TYPES[nodeType] then types[#types + 1] = nodeType end
    end
    table.sort(types)
  end
  return types
end

-- The hook reads settings on every call, so it attaches only once they are loaded.
ns.OnSettingsLoaded(function()
  EventUtil.ContinueOnAddOnLoaded("GatherMate2", Attach)
end)

-- Forgets the circles GatherMate2 already alerted for, so a manual reset re-arms both sources at once.
function ns.ResetGatherMateSeen()
  wipe(seen)
  ns.ForgetNodes("gathermate")
end

-- Counts the circles GatherMate2 still remembers; each keeps its node in the per-type table, whether or
-- not it also sits in the shared memory.
function ns.GatherMateSeenCount()
  local cutoff = GetTime() - ns.REMEMBER_FOR
  local count = 0
  for _, byType in pairs(seen) do
    for _, node in pairs(byType) do
      if node.stamp >= cutoff then count = count + 1 end
    end
  end
  return count
end

ns.OnZoning(function() wipe(seen) end)
