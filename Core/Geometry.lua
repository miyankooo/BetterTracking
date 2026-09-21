local _, ns = ...

local RING_INSET = 6
local MERGE_PIXELS = 20

local ring = {}
local disc = {}
local builtFor = 0

-- A blip can only become newly visible at the edge unless the view itself changed, so the hot path
-- walks one annulus. The disc exists for the cases the edge cannot see: a node spawning inside the
-- radius, and priming the seen list after a zone change so already-visible nodes do not all ping.
local function Build()
  local radius = Minimap:GetWidth() / 2
  if radius <= 0 or radius == builtFor then return end

  builtFor = radius
  wipe(ring)
  wipe(disc)

  local edge = radius - RING_INSET
  local count = ns.db.ringPoints
  for index = 1, count do
    local angle = (index / count) * math.pi * 2
    ring[index] = { math.cos(angle) * edge, math.sin(angle) * edge }
  end

  local spacing = ns.db.discSpacing
  disc[1] = { 0, 0 }
  local step = spacing
  while step <= edge do
    local perRing = math.max(6, math.floor(2 * math.pi * step / spacing))
    for index = 1, perRing do
      local angle = (index / perRing) * math.pi * 2
      disc[#disc + 1] = { math.cos(angle) * step, math.sin(angle) * step }
    end
    step = step + spacing
  end
end

function ns.RebuildGeometry()
  builtFor = 0
  Build()
end

function ns.RingPoints()
  Build()
  return ring
end

function ns.DiscPoints()
  Build()
  return disc
end

-- Minimap-local offsets shift with every step the player takes, so a key that has to survive movement
-- needs world yards. Screen-up is north when the minimap is fixed and the player's facing when it
-- rotates, which is the whole difference between the two cases.
function ns.WorldFromOffset(dx, dy)
  local uiMapID = C_Map.GetBestMapForUnit("player")
  if not uiMapID then return nil end

  local mapPos = C_Map.GetPlayerMapPosition(uiMapID, "player")
  if not mapPos then return nil end

  local _, playerWorld = C_Map.GetWorldPosFromMapPos(uiMapID, mapPos)
  if not playerWorld then return nil end

  local facing = 0
  if GetCVarBool("rotateMinimap") then
    facing = GetPlayerFacing()

    -- Documented as nilable, and a wrong facing would scatter one node across many keys, so give up
    -- and let the caller fall back to a name-only key instead.
    if not facing then return nil end
  end

  local yardsPerPixel = C_Minimap.GetViewRadius() / (Minimap:GetWidth() / 2)
  local right, up = dx * yardsPerPixel, dy * yardsPerPixel
  local cos, sin = math.cos(facing), math.sin(facing)

  return playerWorld.x + up * cos + right * sin, playerWorld.y + up * sin - right * cos
end

-- Two probes that hit the same blip disagree about where it is by up to the blip's own width, and a
-- blip is a fixed size in pixels while a pixel is worth more yards the further the minimap is zoomed
-- out. So the tolerance that decides "same node" has to be measured in pixels and converted, never
-- fixed in yards.
function ns.MergeYards()
  return MERGE_PIXELS * C_Minimap.GetViewRadius() / (Minimap:GetWidth() / 2)
end
