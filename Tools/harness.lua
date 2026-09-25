-- Offline harness. Run from the addon folder with: lua Tools/harness.lua
-- Stubs enough of the client to drive both sources against a fake world, so the dedup, the queue, the
-- calibration, the GatherMate2 hook and the settings panel can be checked without logging in. It proves the
-- logic, never the client behaviour.

local HALF = 70
local VIEW_RADIUS = 100
local BLIP_YARDS = 9

local world = {
  { name = "Peacebloom", x = 0, y = 0 },
  { name = "Silverleaf", x = 60, y = 40 },
  { name = "Peacebloom", x = -70, y = 55 },
  { name = "Copper Vein", x = 30, y = -80 },
}

local player = { x = 0, y = 0, facing = 0, speed = 7, taxi = false }
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

-- Anything the UI touches but the logic never reads answers every call with another stub.
local stubMeta = {}
local function Stub() return setmetatable({}, stubMeta) end
stubMeta.__index = function() return Stub() end
stubMeta.__call = function() return Stub() end

-- The client's bit library, in plain arithmetic so the harness runs on any Lua from 5.2 up.
local function BitAnd(a, b)
  local result, place = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + place end
    a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
  end
  return result
end

_G.bit = {
  band = BitAnd,
  bor = function(a, b) return a + b - BitAnd(a, b) end,
  bxor = function(a, b) return a + b - 2 * BitAnd(a, b) end,
  lshift = function(a, count) return a * 2 ^ count end,
}

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CopyTable = function(t) local copy = {} for k, v in pairs(t) do copy[k] = v end return copy end
_G.unpack = table.unpack
_G.UnitOnTaxi = function() return player.taxi end
_G.InCombatLockdown = function() return false end
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
_G.SOUNDKIT = {
  MAP_PING = 3175, TELL_MESSAGE = 3081, RAID_WARNING = 8959, READY_CHECK = 8960, AUCTION_WINDOW_OPEN = 5274,
  ALARM_CLOCK_WARNING_1 = 18871, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
}
_G.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4 } }
_G.PlaySound = function(id) alerts[#alerts + 1] = id end
_G.NONE, _G.ALL, _G.SECOND_ONELETTER_ABBR = "None", "All", "%d s"
_G.RED_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }

local frames = {}
_G.CreateFrame = function()
  local frame = setmetatable({ events = {}, scripts = {} }, stubMeta)
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(kind, handler) self.scripts[kind] = handler end
  frames[#frames + 1] = frame
  return frame
end

_G.Minimap = {
  mouseIsOver = false,
  GetScale = function() return 1 end,
  GetFrameLevel = function() return 1 end,
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

-- A fake GatherMate2 whose Display calls the hook the way addMiniPin does, once per pin per update.
local hooks = {}
local display = { addMiniPin = function() end, UpdateMaps = function() end }
local gatherMate = {
  db = { profile = { trackColors = { Mining = { Red = 1, Green = 0, Blue = 0 } } } },
  db_types = { "Herb Gathering", "Mining" },
  GetModule = function() return display end,
}
local function GatherMateStub() return { GetAddon = function() return gatherMate end } end
_G.LibStub = GatherMateStub
_G.hooksecurefunc = function(_, name, hook) hooks[name] = hook end

local loaded = { GatherMate2 = true }
local addonCallbacks = {}
_G.EventUtil = {
  ContinueOnPlayerLogin = function(fn) _G.deferredLogin = fn end,
  ContinueOnAddOnLoaded = function(name, fn)
    if loaded[name] then fn() else addonCallbacks[name] = fn end
  end,
}
_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
_G.GameTooltip = Stub()
_G.SlashCmdList = {}

-- A fake of Blizzard's Settings API that keeps the rules the panel leans on: a proxy setter runs only when
-- the value changes (SettingMixin:ApplyValue), a default must match its declared type, a checkbox needs a
-- boolean and a slider a number, and a button needs an explicit addSearchTags.
local panel

local function NewInitializer(kind, data)
  local initializer = { kind = kind, data = data, predicates = {} }

  function initializer:SetParentInitializer(parent, predicate)
    self.parent = parent
    if predicate then self.predicates[#self.predicates + 1] = predicate end
  end

  function initializer:AddModifyPredicate(predicate)
    self.predicates[#self.predicates + 1] = predicate
  end

  function initializer:IsEnabled()
    for _, predicate in ipairs(self.predicates) do
      if not predicate() then return false end
    end
    return true
  end

  return initializer
end

local function AddRow(kind, data)
  local row = NewInitializer(kind, data)
  panel.rows[#panel.rows + 1] = row
  return row
end

local function ProxySetting(_, variable, varType, name, default, get, set)
  assert(type(name) == "string", variable .. " needs a string name")
  assert(type(default) == varType, variable .. " has a " .. type(default) .. " default for a " .. varType)

  local setting = { variable = variable, name = name, notified = 0 }
  function setting:GetValue() return get() end
  function setting:GetVariableType() return varType end
  function setting:NotifyUpdate() self.notified = self.notified + 1 end
  function setting:SetValueToDefault() self:SetValue(default) end
  function setting:SetValue(value)
    if get() == value then return end
    assert(type(value) == varType, variable .. " takes a " .. varType)
    set(value)
  end

  panel.settings[variable] = setting
  return setting
end

_G.Settings = {
  RegisterVerticalLayoutCategory = function(name)
    panel.title = name
    local layout = { AddInitializer = function(_, row) panel.rows[#panel.rows + 1] = row end }
    return { GetID = function() return 1 end }, layout
  end,
  RegisterProxySetting = ProxySetting,
  CreateCheckbox = function(_, setting, tooltip)
    assert(setting:GetVariableType() == "boolean", setting.variable .. " is not a boolean")
    return AddRow("checkbox", { setting = setting, tooltip = tooltip })
  end,
  CreateSlider = function(_, setting, options, tooltip)
    assert(setting:GetVariableType() == "number" and options, setting.variable .. " is not a number slider")
    return AddRow("slider", { setting = setting, options = options, tooltip = tooltip })
  end,
  CreateDropdown = function(_, setting, options, tooltip)
    assert(options, setting.variable .. " has no options")
    return AddRow("dropdown", { setting = setting, options = options, tooltip = tooltip })
  end,
  CreateSliderOptions = function(minValue, maxValue, rate)
    local options = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate }
    function options:SetLabelFormatter(_, format) self.format = format end
    return options
  end,
  CreateControlTextContainer = function()
    local container = { data = {} }
    function container:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
    function container:AddCheckbox(value, label) self.data[#self.data + 1] = { value = value, label = label } end
    function container:GetData() return self.data end
    return container
  end,
  RegisterAddOnCategory = function() panel.registered = true end,
  OpenToCategory = function() panel.opened = true end,
}

_G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
  return NewInitializer("header", { name = name, tooltip = tooltip })
end

_G.CreateSettingsButtonInitializer = function(name, buttonText, buttonClick, tooltip, addSearchTags)
  assert(addSearchTags ~= nil, name .. " has no addSearchTags")
  return NewInitializer("button", { name = name, buttonText = buttonText, buttonClick = buttonClick, tooltip = tooltip })
end

-- Reads the file list from the toc, so the harness loads exactly what the client loads, in the same order.
local function TocFiles()
  local files = {}
  for line in io.lines("TrackingAlert.toc") do
    if line:match("%S") and not line:match("^#") then
      files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
  end
  return files
end

-- Fires the addon's own ADDON_LOADED the way the client does, after every file ran.
local function LoadAddon()
  local namespace = {}
  loaded.TrackingAlert = nil
  for _, path in ipairs(TocFiles()) do
    assert(loadfile(path))("TrackingAlert", namespace)
  end
  loaded.TrackingAlert = true
  addonCallbacks.TrackingAlert()
  return namespace
end

local function BuildPanel()
  panel = { settings = {}, rows = {} }
  return pcall(_G.deferredLogin)
end

local function Row(name)
  for _, row in ipairs(panel.rows) do
    local rowName = row.data.setting and row.data.setting.name or row.data.name
    if rowName == name then return row end
  end
end

local function Setting(key)
  return panel.settings["TRACKING_ALERT_" .. key:upper()]
end

local function Tooltip(name)
  local tooltip = Row(name).data.tooltip
  return type(tooltip) == "function" and tooltip() or tooltip
end

local function Click(name)
  local button = { SetText = function(self, text) self.text = text end }
  Row(name).data.buttonClick(button, "LeftButton", false)
  return button
end

local function RestoreDefaults()
  for _, setting in pairs(panel.settings) do setting:SetValueToDefault() end
end

local ns = LoadAddon()

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
    print("  FAIL  " .. label .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

print("calibration")
Check("idle until a coordinate space is known", ns.db.space == false)

-- Put the cursor on the edge blip the way a player idly hovering one would.
Minimap.mouseIsOver = true
_G.cursorX, _G.cursorY = 500 + 42, 400 + 28
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
clock = clock + 10
Check("a zone change reprimes without pinging", #alerts == 0, #alerts .. " alerts")
Check("and rebuilds what is in range", ns.SeenCount() == #world, ns.SeenCount() .. " of " .. #world)

print("movement gate")
player.speed = 0
alerts = {}
ns.ResetSeen()
Tick(400)
Check("standing still skips the scan", ns.SeenCount() == 0, ns.SeenCount() .. " remembered")
player.speed = 7

print("gathermate2 source")
ns.db.blips = false
alerts = {}
clock = clock + 10
Check("the hook attached", hooks.addMiniPin ~= nil and ns.gatherMateReady)

local function Pin(nodeType, coords, isCircle, height)
  local pin = { nodeType = nodeType, coords = coords, isCircle = isCircle, shown = true, height = height or 10 }
  pin.texture = Stub()
  function pin:IsShown() return self.shown end
  function pin:Hide() self.shown = false end
  function pin:GetHeight() return self.height end
  function pin:SetSize(size) self.height = size end
  function pin:GetPoint() return "CENTER", Minimap, "CENTER", coords, 0 end
  return pin
end

local far = Pin("Mining", 100, false)
hooks.addMiniPin(display, far)
Check("an icon pin outside track distance stays silent", #alerts == 0, #alerts .. " alerts")

local ore = Pin("Mining", 200, true)
hooks.addMiniPin(display, ore)
Check("a pin turning into a circle alerts", #alerts == 1, #alerts .. " alerts")

clock = clock + 5
hooks.addMiniPin(display, ore)
Check("the same circle on the next update stays quiet", #alerts == 1, #alerts .. " alerts")

clock = clock + 5
ns.db.mutedTypes["Herb Gathering"] = true
hooks.addMiniPin(display, Pin("Herb Gathering", 300, true))
Check("a muted node type stays silent", #alerts == 1, #alerts .. " alerts")
ns.db.mutedTypes["Herb Gathering"] = nil

player.taxi = true
local herb = Pin("Herb Gathering", 400, true)
hooks.addMiniPin(display, herb)
Check("a circle reached on a flight path stays silent", #alerts == 1, #alerts .. " alerts")
player.taxi = false
hooks.addMiniPin(display, herb)
Check("and alerts once the flight is over", #alerts == 2, #alerts .. " alerts")

clock = clock + 5
ns.db.gatherMate = false
hooks.addMiniPin(display, Pin("Mining", 500, true))
Check("the source toggle silences it", #alerts == 2, #alerts .. " alerts")
ns.db.gatherMate = true

clock = clock + 5
hooks.addMiniPin(display, Pin("Mining", 600, true))
hooks.addMiniPin(display, Pin("Mining", 700, true))
Check("two circles inside the cooldown are one alert", #alerts == 3, #alerts .. " alerts")

ns.db.circleSize = 3
local sized = Pin("Mining", 800, true)
hooks.addMiniPin(display, sized)
Check("the circle size setting resizes the pin", sized.height == 14, tostring(sized.height))

print("settings panel")
local built, buildError = BuildPanel()
Check("the vertical layout registers at login", built and panel.registered and panel.title == "Tracking Alert", buildError)

local unbound = {}
for key in pairs(ns.defaults) do
  if key ~= "space" and not Setting(key) then unbound[#unbound + 1] = key end
end
table.sort(unbound)
Check("every saved key but the calibration has a control", #unbound == 0, table.concat(unbound, ", "))
Check("the calibration has none, so Defaults cannot clear it", Setting("space") == nil)

local headers = {}
for _, row in ipairs(panel.rows) do
  if row.kind == "header" then headers[#headers + 1] = row.data.name end
end
Check("three sections in order", table.concat(headers, "|") == "Alert|Minimap nodes|GatherMate2", table.concat(headers, "|"))

Check("the sound dropdown offers all six sounds", #Row("Sound").data.options() == #ns.sounds)
alerts = {}
Setting("soundId"):SetValue(SOUNDKIT.RAID_WARNING)
Check("picking a sound saves and previews it", ns.db.soundId == SOUNDKIT.RAID_WARNING and alerts[1] == SOUNDKIT.RAID_WARNING)
Setting("soundId"):SetValue(SOUNDKIT.RAID_WARNING)
Check("picking the same sound again writes nothing", #alerts == 1, #alerts .. " sounds")

Setting("channel"):SetValue(false)
local mutedChannel = ns.db.channel
Setting("channel"):SetValue(true)
Check("the muted-effects box maps to the channel", mutedChannel == "SFX" and ns.db.channel == "Master", mutedChannel)

Setting("sound"):SetValue(false)
local greyedOut = not Row("Sound"):IsEnabled() and not Row("Play while sound effects are muted"):IsEnabled()
Setting("sound"):SetValue(true)
Check("sound rows grey out while the sound is off", greyedOut and Row("Sound"):IsEnabled())
Check("flash thickness nests under the flash", Row("Flash thickness").parent == Row("Flash the minimap edge"))
Check("minimap rows nest under their switch", Row("Probes per frame").parent == Row("Alert on minimap nodes")
  and Row("Only while moving").parent == Row("Alert on minimap nodes"))
Check("the cooldown reads in seconds", Row("Cooldown").data.options.format(3) == "3 s")

-- Blizzard's checkbox dropdown flips one option bit per click, so the harness does the same.
local picker = Row("Node types")
local typeMask = Setting("mutedTypes")
Check("the node types list GatherMate2's types", picker and #picker.data.options() == #gatherMate.db_types)
Check("every type starts ticked", typeMask:GetValue() == 3 and picker.getSelectionTextFunc({ 1, 2 }) == "All")
typeMask:SetValue(bit.bxor(typeMask:GetValue(), 2))
Check("unticking a type mutes only that one", ns.db.mutedTypes.Mining and not ns.db.mutedTypes["Herb Gathering"])
Check("a partial pick lists the ticked names", picker.getSelectionTextFunc({ 1 }) == nil)
Check("no pick reads None", picker.getSelectionTextFunc({}) == "None")
Check("node types nest under the GatherMate2 switch", picker.parent == Row("Alert on GatherMate2 circles"))

Setting("cooldown"):SetValue(10)
Setting("flashThickness"):SetValue(7)
Setting("blips"):SetValue(false)
Setting("channel"):SetValue(false)
RestoreDefaults()
local drifted = {}
for key, value in pairs(ns.defaults) do
  if type(value) ~= "table" and key ~= "space" and ns.db[key] ~= value then drifted[#drifted + 1] = key end
end
table.sort(drifted)
Check("Defaults restore every setting", #drifted == 0 and next(ns.db.mutedTypes) == nil, table.concat(drifted, ", "))
Check("Defaults keep the calibration", ns.db.space == "center", tostring(ns.db.space))
alerts = {}
RestoreDefaults()
Check("Defaults that change nothing play nothing", #alerts == 0, #alerts .. " sounds")

alerts = {}
Click("Preview")
Check("Test plays the alert sound", alerts[1] == ns.db.soundId, tostring(alerts[1]))

Check("Calibration offers a recalibration once calibrated", Row("Calibration").data.buttonText() == "Recalibrate")
Check("and leads its tooltip with the live state", Tooltip("Calibration"):find("^Calibrated to centre%-relative pixels") ~= nil)
local calibrate = Click("Calibration")
Check("clicking it clears the space and relabels the button", ns.db.space == false and calibrate.text == "Calibrate")
Check("and the tooltip follows", Tooltip("Calibration"):find("^Not calibrated") ~= nil)
ns.db.space = "center"

ns.ResetSeen()
Tick(600)
local remembered = ns.SeenCount()
Check("the reset tooltip counts the remembered nodes", Tooltip("Remembered nodes"):find(remembered .. " right now", 1, true) ~= nil)
Click("Remembered nodes")
Check("Reset forgets every remembered node", remembered > 0 and ns.SeenCount() == 0, remembered .. " before")

TrackingAlert_OnClick("TrackingAlert", "RightButton")
Check("the compartment toggle turns both outputs off", not ns.db.sound and not ns.db.flash)
Check("and tells both controls to read again", Setting("sound").notified == 1 and Setting("flash").notified == 1)
TrackingAlert_OnClick("TrackingAlert", "RightButton")
TrackingAlert_OnClick("TrackingAlert", "LeftButton")
Check("a left click opens the category", panel.opened)

print("without gathermate2")
loaded.GatherMate2, _G.LibStub, hooks = nil, nil, {}
local bare = LoadAddon()
Check("the GatherMate2 source stays detached", not bare.gatherMateReady and hooks.addMiniPin == nil)
Check("it offers no node types", #bare.GatherMateTypes() == 0)
Check("the panel still builds", BuildPanel())
Check("without an empty node types row", Row("Node types") == nil and Setting("mutedTypes") == nil)
Check("the GatherMate2 rows are greyed", not Row("Alert on GatherMate2 circles"):IsEnabled()
  and not Row("Hide node icons"):IsEnabled() and not Row("Circle size"):IsEnabled())
Check("and their tooltips say why", Tooltip("Merge stacked circles into one"):find("Needs GatherMate2", 1, true) ~= nil)
Check("the minimap rows stay live", Row("Alert on minimap nodes"):IsEnabled() and Row("Only while moving"):IsEnabled())
Check("and the saved calibration carries over", bare.db.space == "center", tostring(bare.db.space))

-- GatherMate2's master branch draws a 12px circle where classic draws 10px, and a Forever build could come
-- from either, so the native size has to be read, not assumed.
print("gathermate2 master circles")
loaded.GatherMate2, _G.LibStub, hooks = true, GatherMateStub, {}
local master = LoadAddon()
master.db.circleSize = 1
local native = Pin("Mining", 900, true, 12)
hooks.addMiniPin(display, native)
Check("step 1 keeps a 12px circle at 12px", native.height == 12, tostring(native.height))
master.db.circleSize = 3
local grown = Pin("Mining", 1000, true, 12)
hooks.addMiniPin(display, grown)
Check("and each step adds 2px to it", grown.height == 16, tostring(grown.height))

print("without the hit test")
for index = #frames, 1, -1 do frames[index] = nil end
Minimap.UpdateMouseoverAtPoint = nil
local idle = LoadAddon()
Check("the blip source knows it cannot probe", idle.canProbe == false)

local scans = false
for _, frame in ipairs(frames) do
  if frame.scripts.OnUpdate or frame.events.VIGNETTE_MINIMAP_UPDATED then scans = true end
end
Check("no scanner frame runs or registers the vignette event", not scans)
Check("moving around raises no error", pcall(Tick, 200))

Minimap.mouseIsOver = true
Check("calibrating raises no error", pcall(SlashCmdList.TRACKINGALERT, "calibrate"))
Minimap.mouseIsOver = false
Check("status raises no error", pcall(SlashCmdList.TRACKINGALERT, "status"))
Check("the panel builds", BuildPanel())

-- The exact shape 1.0.0 wrote after its own default fill, with the settings a player could have changed.
print("upgrading a 1.0.0 save")
_G.TrackingAlertDB = {
  enabled = false, sound = false, channel = "SFX", cooldown = 0.75, requireMovement = false, objectsOnly = true,
  allowUntyped = true, vignettes = false, ringPoints = 64, discSpacing = 8, discInterval = 7, probeBudget = 12,
  space = "corner",
}
local upgraded = LoadAddon().db
Check("the default-ping false becomes sound on with the default ping",
  upgraded.sound == true and upgraded.soundId == SOUNDKIT.MAP_PING)
Check("enabled carries into the minimap source switch", upgraded.blips == false)
Check("the cooldown is clamped to the slider minimum", upgraded.cooldown == 1, tostring(upgraded.cooldown))
Check("the obsolete keys are dropped", upgraded.enabled == nil and upgraded.allowUntyped == nil
  and upgraded.ringPoints == nil and upgraded.discSpacing == nil)
Check("keys with the same meaning are kept", upgraded.channel == "SFX" and upgraded.requireMovement == false
  and upgraded.vignettes == false and upgraded.discInterval == 7 and upgraded.probeBudget == 12
  and upgraded.space == "corner")
Check("new keys get their defaults", upgraded.flash == true and upgraded.gatherMate == true
  and type(upgraded.mutedTypes) == "table")

_G.TrackingAlertDB = { enabled = true, sound = SOUNDKIT.RAID_WARNING, cooldown = 2.25, channel = "Master", space = false }
local picked = LoadAddon().db
Check("a sound kit id becomes the picked sound", picked.sound == true and picked.soundId == SOUNDKIT.RAID_WARNING)
Check("and an enabled scan stays on", picked.blips == true)
Check("a cooldown off the whole-second grid snaps onto it", picked.cooldown == 2, tostring(picked.cooldown))

picked.sound = false
local reloaded = LoadAddon().db
Check("it runs once, so a 2.0.0 sound off stays off", reloaded.sound == false)

print(failures == 0 and "\nall checks passed" or ("\n" .. failures .. " failing checks"))
os.exit(failures == 0 and 0 or 1)
