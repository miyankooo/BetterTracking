-- Offline harness. Run with: lua Tools/harness.lua
-- Stubs enough of the client to drive the scanner against a fake world, so the dedup, the queue and the
-- calibration can be checked without logging in. It proves the logic, never the client behaviour.

local HALF = 70
local VIEW_RADIUS = 100
local BLIP_YARDS = 9

local world = {
  { name = "Peacebloom", x = 0, y = 0 },
  { name = "Silverleaf", x = 60, y = 40 },
  { name = "Peacebloom", x = -70, y = 55 },
  { name = "Copper Vein", x = 30, y = -80 },
}

local player = { x = 0, y = 0, facing = 0, speed = 7 }
local clock = 0
local alerts = {}
local mouseover

-- Mirrors Geometry.WorldFromOffset so the harness and the addon agree on what a probe point means.
local function WorldFromOffset(dx, dy)
  local yardsPerPixel = VIEW_RADIUS / HALF
  local right, up = dx * yardsPerPixel, dy * yardsPerPixel
  local cos, sin = math.cos(player.facing), math.sin(player.facing)
  return player.x + up * cos + right * sin, player.y + up * sin - right * cos
end

local function NodeAt(dx, dy)
  local x, y = WorldFromOffset(dx, dy)
  for _, node in ipairs(world) do
    local dxx, dyy = node.x - x, node.y - y
    if math.sqrt(dxx * dxx + dyy * dyy) <= BLIP_YARDS then return node end
  end
end

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.tinsert = table.insert
_G.tremove = table.remove
_G.strupper = string.upper
_G.strlower = string.lower
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.GetTime = function() return clock end
_G.GetUnitSpeed = function() return player.speed end
_G.GetCVarBool = function() return false end
_G.GetPlayerFacing = function() return player.facing end
_G.GetCursorPosition = function() return _G.cursorX or 0, _G.cursorY or 0 end
_G.SOUNDKIT = { MAP_PING = 3175 }
_G.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4 } }
_G.PlaySound = function(id) alerts[#alerts + 1] = id end

local frames = {}
_G.CreateFrame = function()
  local frame = { events = {}, scripts = {} }
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(kind, handler) self.scripts[kind] = handler end
  frames[#frames + 1] = frame
  return frame
end

_G.Minimap = {
  mouseIsOver = false,
  GetWidth = function() return HALF * 2 end,
  GetHeight = function() return HALF * 2 end,
  GetCenter = function() return 500, 400 end,
  GetEffectiveScale = function() return 1 end,
  IsMouseOver = function(self) return self.mouseIsOver end,
  UpdateMouseoverAtPoint = function(_, x, y) mouseover = NodeAt(x, y) end,
}

_G.C_TooltipInfo = {
  GetMinimapMouseover = function()
    if not mouseover then return nil end
    return { type = Enum.TooltipDataType.Object, lines = { { leftText = mouseover.name } } }
  end,
}

_G.C_Minimap = { GetViewRadius = function() return VIEW_RADIUS end }
_G.C_Map = {
  GetBestMapForUnit = function() return 1 end,
  GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end,
  GetWorldPosFromMapPos = function() return 1, { x = player.x, y = player.y } end,
}

_G.EventUtil = { ContinueOnPlayerLogin = function(fn) _G.deferredLogin = fn end }
_G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
_G.Settings = {
  VarType = { Boolean = "boolean", Number = "number", String = "string" },
  RegisterVerticalLayoutCategory = function() return { GetID = function() return 1 end } end,
  RegisterAddOnSetting = function() return { GetValue = function() end, SetValue = function() end } end,
  CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
  CreateCheckbox = function() end,
  CreateSlider = function() end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
_G.SlashCmdList = {}

local ns = {}
for _, path in ipairs({ "Core/Config.lua", "Core/Probe.lua", "Core/Geometry.lua", "Core/Scanner.lua", "UI/Options.lua" }) do
  assert(loadfile(path))("TrackingAlert", ns)
end

local function Fire(event, ...)
  for _, frame in ipairs(frames) do
    if frame.events[event] and frame.scripts.OnEvent then
      frame.scripts.OnEvent(frame, event, ...)
    end
  end
end

local function Tick(count)
  for _ = 1, count do
    clock = clock + 1 / 60

    -- The engine refreshes minimap mouseover from the real cursor every frame, which is what gives
    -- calibration its ground truth and what overwrites whatever the addon last probed.
    if Minimap.mouseIsOver then
      mouseover = NodeAt(_G.cursorX - 500, _G.cursorY - 400)
    end

    for _, frame in ipairs(frames) do
      if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame) end
    end
  end
end

local failures = 0
local function Check(label, condition, detail)
  if condition then
    print("  pass  " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label .. (detail and ("  (" .. detail .. ")") or ""))
  end
end

Fire("ADDON_LOADED", "TrackingAlert")

print("calibration")
Check("idle until a coordinate space is known", ns.db.space == false)

-- Put the cursor on the edge blip the way a player idly hovering one would.
Minimap.mouseIsOver = true
_G.cursorX, _G.cursorY = 500 + 42, 400 + 28
player.x, player.y = 60 - 42 * (VIEW_RADIUS / HALF) * 0, 0
player.x, player.y = 60 - 28 * (VIEW_RADIUS / HALF), 40 + 42 * (VIEW_RADIUS / HALF)
Tick(120)
Check("detects the centre-relative space from the cursor", ns.db.space == "center", tostring(ns.db.space))

Minimap.mouseIsOver = false
_G.cursorX, _G.cursorY = 0, 0

local function Walk(toX, toY, steps)
  local fromX, fromY = player.x, player.y
  for step = 1, steps do
    player.x = fromX + (toX - fromX) * step / steps
    player.y = fromY + (toY - fromY) * step / steps
    Tick(40)
  end
end

print("arrival")

-- Start out of range of everything, so the priming sweep has nothing to record and every node has to
-- be found by arriving rather than by already being there.
player.x, player.y = 0, 500
ns.ResetSeen()
alerts = {}
Tick(500)
Check("the priming sweep is silent", #alerts == 0, #alerts .. " alerts")
Check("nothing is remembered out of range", ns.SeenCount() == 0, ns.SeenCount() .. " remembered")

Walk(0, 0, 25)
Check("every node that came into range is remembered", ns.SeenCount() == #world, ns.SeenCount() .. " of " .. #world)
Check("arriving nodes ping", #alerts > 0, #alerts .. " alerts")

print("no repeats")
local before = #alerts
Tick(1500)
Check("parking among known nodes stays quiet", #alerts == before, (#alerts - before) .. " extra")

Walk(40, 0, 20)
Walk(0, 0, 20)
Check("walking back and forth does not re-alert", #alerts == before, (#alerts - before) .. " extra")

print("leaving and returning")
Walk(0, 500, 25)
local afterLeaving = #alerts
Walk(0, 0, 25)
Check("a node still remembered does not ping again", #alerts == afterLeaving, (#alerts - afterLeaving) .. " extra")

print("zone change")
alerts = {}
Fire("ZONE_CHANGED_NEW_AREA")
Tick(600)
Check("a zone change reprimes without pinging", #alerts == 0, #alerts .. " alerts")
Check("and rebuilds what is in range", ns.SeenCount() == #world, ns.SeenCount() .. " of " .. #world)

print("movement gate")
player.speed = 0
alerts = {}
ns.ResetSeen()
Tick(400)
Check("standing still skips the scan", ns.SeenCount() == 0, ns.SeenCount() .. " remembered")
player.speed = 7

print(failures == 0 and "\nall checks passed" or ("\n" .. failures .. " failing checks"))
os.exit(failures == 0 and 0 or 1)
