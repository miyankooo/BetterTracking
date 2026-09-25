local _, ns = ...

-- 1.60.1 has the hit test, the minimap tooltip and the view radius. Checking them once costs nothing and
-- turns a client that drops one into an idle blip source instead of an error on every frame.
ns.canProbe = Minimap.UpdateMouseoverAtPoint ~= nil
  and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil
  and C_Minimap ~= nil and C_Minimap.GetViewRadius ~= nil

-- Minimap blips are drawn by the engine and are not Lua objects, so the only documented way to read one
-- is to run the engine's own hit test at a point and then ask for the tooltip it produced.
-- UpdateMouseoverAtPoint is documented as two bare numbers with no stated coordinate space, so which of
-- these readings is correct is a runtime question rather than something the sources can answer.
ns.spaces = {
  { key = "center", label = "centre-relative pixels" },
  { key = "corner", label = "frame-local pixels" },
  { key = "normalized", label = "normalised -1 to 1" },
}

local failedSpaces = {}

local function ToSpace(dx, dy, space)
  local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2

  if space == "corner" then
    return halfWidth + dx, halfHeight + dy
  elseif space == "normalized" then
    return dx / halfWidth, dy / halfHeight
  end
  return dx, dy
end

-- A space whose arguments the engine rejects is dropped for the session, so a wrong guess costs one
-- error instead of one per probe.
function ns.ProbeAt(dx, dy, space)
  if failedSpaces[space] then return nil end

  local x, y = ToSpace(dx, dy, space)
  if not pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y) then
    failedSpaces[space] = true
    return nil
  end

  local data = C_TooltipInfo.GetMinimapMouseover()
  if ns.BlipName(data) then return data end
end

function ns.Probe(dx, dy)
  if not ns.db.space then return nil end
  return ns.ProbeAt(dx, dy, ns.db.space)
end

function ns.BlipName(data)
  return data and data.lines and data.lines[1] and data.lines[1].leftText
end

function ns.CursorOffset()
  local centerX, centerY = Minimap:GetCenter()
  if not centerX then return nil end

  local x, y = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  return x / scale - centerX, y / scale - centerY
end

-- Probing moves the engine's minimap mouseover, so it has to be put back where the player's cursor
-- actually is or their own tooltip goes stale.
function ns.RestoreCursorMouseover()
  if not ns.db.space then return end

  local dx, dy = ns.CursorOffset()
  if dx then ns.ProbeAt(dx, dy, ns.db.space) end
end

-- Ground truth is the real cursor sitting on a blip. The right space is the one that reproduces that
-- same tooltip from the cursor's own offset and misses at the mirrored offset, which is what rules out
-- a space that merely happened to land on something else.
function ns.CalibrateFromCursor(quiet)
  if not ns.canProbe then return false, "this client has no minimap hit test" end
  if not Minimap:IsMouseOver() then return false, "hover a tracked blip on the minimap first" end

  local wanted = ns.BlipName(C_TooltipInfo.GetMinimapMouseover())
  if not wanted then return false, "no blip under the cursor" end

  local dx, dy = ns.CursorOffset()
  if not dx then return false, "minimap has no centre yet" end

  -- Near the centre all three candidates land in roughly the same place, so a sample there proves
  -- nothing. Only an off-centre blip separates them.
  local radius = Minimap:GetWidth() / 2
  if math.sqrt(dx * dx + dy * dy) < radius * 0.4 then
    return false, "hover a blip nearer the minimap edge"
  end

  for _, space in ipairs(ns.spaces) do
    local hit = ns.BlipName(ns.ProbeAt(dx, dy, space.key))
    local mirrored = ns.BlipName(ns.ProbeAt(-dx, -dy, space.key))

    if hit == wanted and mirrored ~= wanted then
      ns.db.space = space.key
      ns.RestoreCursorMouseover()
      if not quiet then ns.Print("calibrated to " .. space.label .. ".") end
      return true, space.label
    end
  end

  ns.RestoreCursorMouseover()
  return false, "no candidate coordinate space reproduced the hit"
end

-- The next idle hover over a blip calibrates again, so forgetting is all a recalibration needs.
function ns.Recalibrate()
  ns.db.space = false
  ns.Print("calibration cleared, hover a tracked blip near the minimap edge to calibrate.")
end

function ns.SpaceLabel()
  for _, space in ipairs(ns.spaces) do
    if space.key == ns.db.space then return space.label end
  end
end
