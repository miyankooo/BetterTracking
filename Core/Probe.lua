local _, ns = ...

-- Minimap blips are drawn by the engine and are not Lua objects, so the only documented way to read one
-- is to run the engine's own hit test at a point and then ask for the tooltip it produced.
-- UpdateMouseoverAtPoint is documented as two bare numbers with no stated coordinate space, so which of
-- these readings is correct is a runtime question rather than something the sources can answer.
ns.spaces = {
  { key = "center", label = "centre-relative pixels" },
  { key = "corner", label = "frame-local pixels" },
  { key = "normalized", label = "normalised -1 to 1" },
  { key = "screen", label = "screen pixels" },
  { key = "unit", label = "normalised 0 to 1" },
}

ns.NO_MATCH = "No known way to read this minimap matched the blip under your cursor. Hover another blip near the edge."

local failedSpaces = {}

local function ToSpace(dx, dy, space)
  local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2

  if space == "corner" then
    return halfWidth + dx, halfHeight + dy
  elseif space == "normalized" then
    return dx / halfWidth, dy / halfHeight
  elseif space == "unit" then
    return (dx / halfWidth + 1) / 2, (dy / halfHeight + 1) / 2
  elseif space == "screen" then
    local centerX, centerY = Minimap:GetCenter()
    if not centerX then return nil end

    local scale = Minimap:GetEffectiveScale()
    return (centerX + dx) * scale, (centerY + dy) * scale
  end
  return dx, dy
end

-- A space whose arguments the engine rejects is dropped for the session, so a wrong guess costs one
-- error instead of one per probe. Losing the calibrated space stops the minimap source, so that one says so.
function ns.ProbeAt(dx, dy, space)
  if failedSpaces[space] then return nil end

  local x, y = ToSpace(dx, dy, space)
  if not x then return nil end

  if not pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y) then
    failedSpaces[space] = true
    if space == ns.db.space then
      ns.readFailed = true
      ns.Print("The minimap stopped answering, so minimap alerts are off. Type /reload to start them again.")
    end
    return nil
  end

  local data = C_TooltipInfo.GetMinimapMouseover()
  if ns.BlipName(data) then return data end
end

function ns.Probe(dx, dy)
  if not ns.db.space then return nil end
  return ns.ProbeAt(dx, dy, ns.db.space)
end

-- A secret name can be neither compared nor used as a key, so it reads as no blip at all.
function ns.BlipName(data)
  local name = data and data.lines and data.lines[1] and data.lines[1].leftText
  if name and not ns.IsSecret(name) then return name end
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
function ns.CalibrateFromCursor()
  if not Minimap:IsMouseOver() then return false, "Hover a tracked blip on the minimap first." end

  local wanted = ns.BlipName(C_TooltipInfo.GetMinimapMouseover())
  if not wanted then return false, "No blip is under the cursor. Hover a tracked blip on the minimap." end

  local dx, dy = ns.CursorOffset()
  if not dx then return false, "The minimap is not placed yet. Try again in a moment." end

  -- Near the centre the frame-relative candidates land in roughly the same place, so a sample there
  -- proves nothing. Only an off-centre blip separates them.
  local radius = Minimap:GetWidth() / 2
  if math.sqrt(dx * dx + dy * dy) < radius * 0.4 then
    return false, "Hover a blip nearer the minimap edge."
  end

  for _, space in ipairs(ns.spaces) do
    local hit = ns.BlipName(ns.ProbeAt(dx, dy, space.key))
    local mirrored = ns.BlipName(ns.ProbeAt(-dx, -dy, space.key))

    if hit == wanted and mirrored ~= wanted then
      ns.db.space = space.key
      ns.readFailed = false
      ns.RestoreCursorMouseover()
      return true
    end
  end

  ns.RestoreCursorMouseover()
  return false, ns.NO_MATCH
end

-- The next idle hover over a blip calibrates again, so forgetting is all a recalibration needs.
function ns.Recalibrate()
  ns.db.space = false
  ns.Print("Calibration cleared. Hover a tracked blip near the minimap edge to calibrate again.")
end

function ns.SpaceLabel()
  for _, space in ipairs(ns.spaces) do
    if space.key == ns.db.space then return space.label end
  end
end
