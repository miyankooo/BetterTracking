local _, ns = ...

-- Both sources remember a node this long after they last saw it, so walking away and back stays quiet.
ns.REMEMBER_FOR = 180

-- Both sources write their sightings here, so a node that the minimap blips and GatherMate2 both report is
-- one node and one alert. Positions are world yards from C_Map.GetWorldPosFromMapPos, which both sources
-- reach: the blip source through the player's position, GatherMate2 through its pins' zone coordinates.
local nodes = {}

-- Bucketed keys were the first attempt and broke on exactly this: a node straddling a bucket edge alerted
-- twice. Proximity matching makes the tolerance explicit, and Geometry scales it with zoom.
-- A source knows its own nodes by key: a blip by its guid or name, a GatherMate2 circle by its database
-- entry. Across sources only the name can agree, and GatherMate2 names its nodes after the game objects,
-- so the same name inside the merge radius is the same node, while another kind of node close by is not.
local function IsSameNode(node, source, key, name, x, y, tolerance)
  local dx, dy = node.x - x, node.y - y
  if dx * dx + dy * dy > tolerance * tolerance then return false end

  if node.source == source then return node.key == key end
  return node.name == name
end

-- Returns whether the sighting is a new node, and the node it now counts as. Stale nodes are dropped on the
-- way, so the list stays short whichever source is running.
function ns.SightNode(source, key, name, x, y)
  local now = GetTime()
  local cutoff = now - ns.REMEMBER_FOR
  local tolerance = ns.MergeYards()
  local found

  for index = #nodes, 1, -1 do
    local node = nodes[index]
    if node.stamp < cutoff then
      tremove(nodes, index)
    elseif not found and IsSameNode(node, source, key, name, x, y, tolerance) then
      found = node
    end
  end

  -- Re-seeing a node refreshes its stamp, whichever source sees it, so a node you are parked next to never
  -- ages out and pings again.
  if found then
    found.stamp = now
    return false, found
  end

  local node = { source = source, key = key, name = name, x = x, y = y, stamp = now }
  nodes[#nodes + 1] = node
  return true, node
end

-- A node one source recorded stays remembered when only the other source forgets, so it cannot alert twice.
function ns.ForgetNodes(source)
  for index = #nodes, 1, -1 do
    if nodes[index].source == source then tremove(nodes, index) end
  end
end

function ns.NodeCount(source)
  local cutoff = GetTime() - ns.REMEMBER_FOR
  local count = 0
  for _, node in ipairs(nodes) do
    if node.source == source and node.stamp >= cutoff then count = count + 1 end
  end
  return count
end

ns.OnZoning(function() wipe(nodes) end)
