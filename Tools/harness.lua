-- Offline harness. Run from the addon folder with: lua Tools/harness.lua
-- Stubs enough of the client to drive both sources against a fake world, so the dedup, the queue, the
-- calibration, the GatherMate2 hook, the herb and ore swap, the launcher and the settings panel can be
-- checked without logging in. It proves the logic, never the client behaviour.

-- The harness reports through its own print, while the addon's chat lines land in chat for checking.
local print = print
local chat = {}
_G.print = function(line) chat[#chat + 1] = line end

local function Said(text)
  local count = 0
  for _, line in ipairs(chat) do
    if line:find(text, 1, true) then count = count + 1 end
  end
  return count
end

local HALF = 70
local VIEW_RADIUS = 100
local BLIP_YARDS = 9

local world = {
  { name = "Peacebloom", x = 0, y = 0 },
  { name = "Silverleaf", x = 60, y = 40 },
  { name = "Peacebloom", x = -70, y = 55 },
  { name = "Copper Vein", x = 30, y = -80 },
}

local player = { x = 0, y = 0, facing = 0, speed = 7, taxi = false, dead = false, combat = false, instance = false,
  resting = false, casting = nil, channeling = nil }
local target = { attackable = false, dead = false }
local underCursor = { attackable = false, dead = false }
local cooldownActive = false
local clock = 0
local alerts = {}
local mouseover
local cvars = { rotateMinimap = false }
local rotateIgnored = false
local secretNames = false

-- How long the blips of a newly tracked type take to reach the minimap after a swap.
local blipDelay, trackingChangedAt = 0, -math.huge
local inCombat = false

-- The coordinate space the fake engine reads UpdateMouseoverAtPoint in. "none" answers no point at all.
local engineSpace = "center"

-- The object kind the fake blip tooltips put in front of their GUID, or nil for no GUID at all.
local guidKind

-- A secret is an opaque marker the addon may only hand to issecretvalue, as on the live client.
local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

-- Mirrors Geometry.WorldFromOffset so the harness and the addon agree on what a probe point means.
local function WorldFromOffset(dx, dy)
  local yardsPerPixel = VIEW_RADIUS / HALF
  local right, up = dx * yardsPerPixel, dy * yardsPerPixel
  local cos, sin = math.cos(player.facing), math.sin(player.facing)
  return player.x + up * cos + right * sin, player.y + up * sin - right * cos
end

-- The client's tracking list: two gathering spells, another tracking spell and a townsfolk filter that is
-- on, which is never a spell. A node with a kind shows only while its spell is active, as on the minimap.
local tracking = {
  { name = "Find Herbs", texture = 133939, type = "spell", subType = 0, spellID = 2383, active = false },
  { name = "Find Minerals", texture = 136025, type = "spell", subType = 0, spellID = 2580, active = false },
  { name = "Find Fish", texture = 133888, type = "spell", subType = 0, spellID = 43308, active = false },
  { name = "Flight Master", texture = 132161, type = "other", subType = 1, active = true },
}
local KIND_SPELL = { herb = 2383, ore = 2580 }

local function IsShown(node)
  if not node.kind then return true end
  if clock < trackingChangedAt + blipDelay then return false end
  for _, info in ipairs(tracking) do
    if info.spellID == KIND_SPELL[node.kind] then return info.active end
  end
  return false
end

local function NodeAt(dx, dy)
  local x, y = WorldFromOffset(dx, dy)
  for _, node in ipairs(world) do
    local dxx, dyy = node.x - x, node.y - y
    if IsShown(node) and math.sqrt(dxx * dxx + dyy * dyy) <= BLIP_YARDS then return node end
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
_G.InCombatLockdown = function() return inCombat end
_G.UnitIsDeadOrGhost = function() return player.dead end
_G.UnitAffectingCombat = function() return player.combat end
_G.IsInInstance = function() return player.instance, player.instance and "party" or "none" end
_G.IsResting = function() return player.resting end
_G.UnitCastingInfo = function() return player.casting end
_G.UnitChannelInfo = function() return player.channeling end
local units = { target = target, mouseover = underCursor }
_G.UnitCanAttack = function(_, unit) return units[unit].attackable end
_G.UnitIsDead = function(unit) return units[unit].dead end
_G.C_Spell = { GetSpellCooldown = function() return { isActive = cooldownActive } end }
_G.LootFrame = { shown = false, IsShown = function(self) return self.shown end }

-- Blizzard's movement and steering functions, which the swap hooks once timed swaps are blocked.
for _, name in ipairs({ "MoveForwardStart", "MoveBackwardStart", "StrafeLeftStart", "StrafeRightStart", "TurnLeftStart",
  "TurnRightStart", "JumpOrAscendStart", "MoveAndSteerStart", "TurnOrActionStart", "CameraOrSelectOrMoveStart" }) do
  _G[name] = function() end
end

-- Tickers run from Tick, on the same clock as the frames.
local tickers = {}
_G.C_Timer = {
  NewTicker = function(seconds, callback)
    local ticker = { seconds = seconds, callback = callback, nextAt = GetTime() + seconds }
    function ticker:Cancel() self.cancelled = true end
    tickers[#tickers + 1] = ticker
    return ticker
  end,
}

local function LiveTickers()
  local count = 0
  for _, ticker in ipairs(tickers) do
    if not ticker.cancelled then count = count + 1 end
  end
  return count
end
_G.tinsert = table.insert
_G.tremove = table.remove
_G.strupper = string.upper
_G.strmatch = string.match
_G.strlower = string.lower
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.GetTime = function() return clock end
_G.GetUnitSpeed = function() return player.speed end
_G.GetCVarBool = function(name) return cvars[name] == true end
_G.GetPlayerFacing = function() return player.facing end
_G.GetCursorPosition = function() return _G.cursorX or 0, _G.cursorY or 0 end
_G.SOUNDKIT = {
  MAP_PING = 3175, TELL_MESSAGE = 3081, RAID_WARNING = 8959, READY_CHECK = 8960, AUCTION_WINDOW_OPEN = 5274,
  ALARM_CLOCK_WARNING_1 = 18871, IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
}
_G.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4, MinimapMouseover = 21 } }
_G.issecretvalue = function(value) return value == SECRET end
local lastChannel
_G.PlaySound = function(id, channel)
  alerts[#alerts + 1] = id
  lastChannel = channel
end
_G.NONE, _G.ALL, _G.RESET, _G.SECOND_ONELETTER_ABBR = "None", "All", "Reset", "%d s"
_G.NORMAL_FONT_COLOR = { GetRGB = function() return 1, 0.82, 0 end }
_G.RED_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }
_G.YELLOW_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }

local frames = {}
_G.CreateFrame = function()
  local frame = setmetatable({ events = {}, scripts = {} }, stubMeta)
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:RegisterUnitEvent(event) self.events[event] = true end
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
  UpdateMouseoverAtPoint = function(_, x, y)
    if engineSpace == "screen" then
      x, y = x - 500, y - 400
    elseif engineSpace == "unit" then
      x, y = (x * 2 - 1) * HALF, (y * 2 - 1) * HALF
    elseif engineSpace == "none" then
      x, y = 1e9, 1e9
    end
    mouseover = NodeAt(x, y)
  end,
}

-- Forever's minimap tooltip most likely reports its own type for every blip, so that is the default here.
local blipType = Enum.TooltipDataType.MinimapMouseover

_G.C_TooltipInfo = {
  GetMinimapMouseover = function()
    if not mouseover then return nil end
    local name = secretNames and SECRET or mouseover.name
    local guid = guidKind and (guidKind .. "-0-" .. mouseover.name .. mouseover.x .. mouseover.y)
    return { type = blipType, guid = guid, lines = { { leftText = name } } }
  end,
}

_G.C_VignetteInfo = { GetVignetteInfo = function() return { name = "Rare Elite" } end }

-- SetTracking answers through events the way the client does: a block fires ADDON_ACTION_BLOCKED inside the
-- call, and a cast fires MINIMAP_UPDATE_TRACKING. Fire is defined once the addon is loaded.
local Fire
local trackingCalls = {}
local blockTimed, blockAll, dropTimed, hardwareInput = false, false, false, false

-- A lagging mirror casts the spell but leaves GetTrackingInfo's active flag behind.
local lagMirror = false
local blockedAs, blockEvent = "BetterTracking", "ADDON_ACTION_BLOCKED"

_G.C_Minimap = {
  GetViewRadius = function() return VIEW_RADIUS end,
  IsRotateMinimapIgnored = function() return rotateIgnored end,
  GetNumTrackingTypes = function() return #tracking end,
  GetTrackingInfo = function(index)
    local info = tracking[index]
    return info and CopyTable(info)
  end,
  SetTracking = function(index, on)
    trackingCalls[#trackingCalls + 1] = { index = index, on = on }
    if blockAll or (blockTimed and not hardwareInput) then
      Fire(blockEvent, blockedAs, "C_Minimap.SetTracking()")
      return
    end

    -- A dropped call changes nothing and says nothing.
    if dropTimed and not hardwareInput then return end

    local cast = tracking[index]
    if cast and cast.type == "spell" then Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-0", cast.spellID) end
    if lagMirror then return end

    trackingChangedAt = clock

    for spellIndex, info in ipairs(tracking) do
      if info.type == "spell" then info.active = spellIndex == index and on end
    end
    Fire("MINIMAP_UPDATE_TRACKING")
  end,
}
-- One fake zone laid out like the game's: map x runs east and map y south, while world x runs north and
-- world y west. Both sources convert through it, so a mix-up of axes would break the cross-source match.
local ZONE_YARDS, ZONE_TOP, ZONE_LEFT = 2000, 1000, 1000

local function MapFromWorld(x, y)
  return (ZONE_LEFT - y) / ZONE_YARDS, (ZONE_TOP - x) / ZONE_YARDS
end

_G.CreateVector2D = function(x, y) return { x = x, y = y } end
_G.C_Map = {
  GetBestMapForUnit = function() return 1 end,
  GetPlayerMapPosition = function() return CreateVector2D(MapFromWorld(player.x, player.y)) end,
  GetWorldPosFromMapPos = function(_, pos)
    return 1, CreateVector2D(ZONE_TOP - pos.y * ZONE_YARDS, ZONE_LEFT - pos.x * ZONE_YARDS)
  end,
}

-- A fake GatherMate2 whose Display calls the hook the way addMiniPin does, once per pin per update.
local hooks = {}
local loaded = { GatherMate2 = true }
local display = { addMiniPin = function() end, UpdateMaps = function() end }
local gatherMate = {
  db = { profile = { trackColors = { Mining = { Red = 1, Green = 0, Blue = 0 } } } },
  db_types = { "Herb Gathering", "Mining", "Extract Gas" },
  GetModule = function() return display end,
}

-- Records a table hook for GatherMate2, and wraps a global the way the client does, original first.
_G.hooksecurefunc = function(owner, name, hook)
  if type(owner) == "table" then
    hooks[name] = hook
    return
  end

  local original = _G[owner]
  _G[owner] = function(...)
    original(...)
    name(...)
  end
end

-- The real LibStub and LibNativeUI load from disk. The launcher's libraries and AceAddon are reduced to the
-- calls the addon makes, and installed right after LibStub loads.
local brokers, icons = {}, {}

local function InstallLibraryStubs()
  local ldb = LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function ldb:NewDataObject(name, object) brokers[name] = object return object end
  function ldb:GetDataObjectByName(name) return brokers[name] end

  local dbIcon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
  function dbIcon:IsRegistered(name) return icons[name] ~= nil end
  function dbIcon:Register(name, object, db) icons[name] = { object = object, db = db, shown = not db.hide } end
  function dbIcon:AddButtonToCompartment(name) icons[name].compartment = true end
  function dbIcon:Show(name) icons[name].shown = true end
  function dbIcon:Hide(name) icons[name].shown = false end

  if loaded.GatherMate2 then
    local aceAddon = LibStub:NewLibrary("AceAddon-3.0", 1)
    function aceAddon:GetAddon() return gatherMate end
  end
end

local STUBBED = {
  ["Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua"] = true,
  ["Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua"] = true,
  ["Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua"] = true,
}

local addonCallbacks = {}
_G.EventUtil = {
  ContinueOnPlayerLogin = function(fn) _G.deferredLogin = fn end,
  ContinueOnAddOnLoaded = function(name, fn)
    if loaded[name] then fn() else addonCallbacks[name] = fn end
  end,
  RegisterOnceFrameEventAndCallback = function(event, fn)
    local frame = CreateFrame()
    frame:RegisterEvent(event)
    frame:SetScript("OnEvent", function(self)
      self:UnregisterEvent(event)
      fn()
    end)
  end,
}
_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
_G.GameTooltip = Stub()
_G.SlashCmdList = {}

local tooltipLines = {}
local function TooltipLine(_, text) tooltipLines[#tooltipLines + 1] = text end
_G.GameTooltip_SetTitle, _G.GameTooltip_AddHighlightLine, _G.GameTooltip_AddInstructionLine =
  TooltipLine, TooltipLine, TooltipLine
_G.GameTooltip_AddNormalLine = TooltipLine

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
  NotifyUpdate = function(variable)
    local setting = panel.settings[variable]
    if setting then setting:NotifyUpdate() end
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
  for line in io.lines("BetterTracking.toc") do
    if line:match("%S") and not line:match("^#") then
      files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
  end
  return files
end

-- Fires the addon's own ADDON_LOADED the way the client does, after every file ran.
local function LoadAddon()
  local namespace = {}
  loaded.BetterTracking = nil
  for _, path in ipairs(TocFiles()) do
    if not STUBBED[path] then assert(loadfile(path))("BetterTracking", namespace) end
    if path == "Libs/LibStub/LibStub.lua" then InstallLibraryStubs() end
  end
  loaded.BetterTracking = true
  addonCallbacks.BetterTracking()
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
  return panel.settings["BETTER_TRACKING_" .. key:upper()]
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

function Fire(event, ...)
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

    for _, ticker in ipairs(tickers) do
      if not ticker.cancelled and clock >= ticker.nextAt then
        ticker.nextAt = ticker.nextAt + ticker.seconds
        ticker.callback(ticker)
      end
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

print("load")
local zoningFrames, scanner = 0, nil
for _, frame in ipairs(frames) do
  if frame.events.PLAYER_ENTERING_WORLD then zoningFrames = zoningFrames + 1 end
  if frame.scripts.OnUpdate and frame.events.VIGNETTE_MINIMAP_UPDATED then scanner = frame end
end
Check("one frame handles zoning for both sources", zoningFrames == 1, zoningFrames .. " frames")
Check("the scanner always runs and registers the vignette event", scanner ~= nil)

print("first run")
local HINT = "Turn on Find Herbs or Find Minerals, then hover a blip"
Check("the first load prints one hint", Said(HINT) == 1, Said(HINT) .. " hints")

print("calibration")
Check("idle until a coordinate space is known", ns.db.space == false)

-- Put the cursor on the edge blip the way a player idly hovering one would.
local function HoverEdgeBlip(ticks)
  Minimap.mouseIsOver = true
  _G.cursorX, _G.cursorY = 500 + 42, 400 + 28
  player.x, player.y = 60 - 28 * (VIEW_RADIUS / HALF), 40 + 42 * (VIEW_RADIUS / HALF)
  Tick(ticks)
  Minimap.mouseIsOver = false
  _G.cursorX, _G.cursorY = 0, 0
end

for _, space in ipairs({ "screen", "unit" }) do
  engineSpace, ns.db.space = space, false
  HoverEdgeBlip(120)
  Check("detects the " .. space .. " space from the cursor", ns.db.space == space, tostring(ns.db.space))
end

engineSpace, ns.db.space = "none", false
local saidBefore = #chat
HoverEdgeBlip(300)
Check("a blip no space reproduces says so once a session", Said(ns.NO_MATCH) == 1 and #chat == saidBefore + 1,
  Said(ns.NO_MATCH) .. " lines")

engineSpace = "center"
HoverEdgeBlip(120)
Check("detects the centre-relative space from the cursor", ns.db.space == "center", tostring(ns.db.space))
Check("and says it is ready in plain words", chat[#chat]:find("Ready. Minimap alerts are on.", 1, true) ~= nil, chat[#chat])

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
Check("on the Master channel", lastChannel == "Master", tostring(lastChannel))
local lastName = ns.lastAlertName
local named = false
for _, node in ipairs(world) do named = named or node.name == lastName end
Check("the last alert keeps the node's name", named, tostring(lastName))

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

-- Starts out of range so the priming sweep records nothing, then walks into every node.
local function WalkInCount()
  player.x, player.y = 0, 500
  ns.ResetSeen()
  Tick(500)
  Walk(0, 0, 25)
  return ns.SeenCount()
end

print("tooltip types")
Check("the types report records the minimap tooltip type", ns.observedTypes[Enum.TooltipDataType.MinimapMouseover])
blipType = Enum.TooltipDataType.Unit
local unitCount = WalkInCount()
Check("gathering nodes only skips unit blips", unitCount == 0, unitCount .. " remembered")
ns.db.objectsOnly = false
local allCount = WalkInCount()
Check("and lets them through when off", allCount == #world, allCount .. " of " .. #world)
ns.db.objectsOnly = true
blipType = Enum.TooltipDataType.MinimapMouseover

guidKind = "Creature"
local creatureCount = WalkInCount()
Check("gathering nodes only skips blips whose GUID names a unit", creatureCount == 0, creatureCount .. " remembered")
guidKind = "GameObject"
local objectCount = WalkInCount()
Check("and keeps blips whose GUID names a game object", objectCount == #world, objectCount .. " of " .. #world)
guidKind = "Creature"
ns.db.objectsOnly = false
local unfilteredCount = WalkInCount()
Check("the GUID test is off with the setting", unfilteredCount == #world, unfilteredCount .. " of " .. #world)
ns.db.objectsOnly, guidKind = true, nil

-- With the filter off a type is never compared, so only the secret guard can skip it.
blipType, ns.db.objectsOnly = SECRET, false
local secretTypeCount = WalkInCount()
Check("a secret tooltip type is skipped", secretTypeCount == 0, secretTypeCount .. " remembered")
blipType, ns.db.objectsOnly = Enum.TooltipDataType.MinimapMouseover, true

print("secret values")
player.speed = SECRET
local secretSpeed = WalkInCount()
Check("a secret speed counts as standing still", secretSpeed == 0, secretSpeed .. " remembered")
player.speed = 7

secretNames = true
alerts = {}
local secretCount = WalkInCount()
Check("a secret blip name is never keyed or announced", secretCount == 0 and #alerts == 0, secretCount .. " remembered")
secretNames = false

local realIsSecret = _G.issecretvalue
_G.issecretvalue = function() error("secret argument from tainted code") end
local raisedCount = WalkInCount()
Check("a guard that raises reads as secret", raisedCount == 0, raisedCount .. " remembered")
_G.issecretvalue = realIsSecret

print("vignettes")
player.x, player.y = 0, 500
ns.ResetSeen()
alerts = {}
clock = clock + 10
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
Check("a vignette reaching the minimap alerts", #alerts == 1, #alerts .. " alerts")
Check("under the vignette's own name", ns.lastAlertName == "Rare Elite", tostring(ns.lastAlertName))
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", false)
clock = clock + 60
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
Check("leaving and returning within the window stays quiet", #alerts == 1, #alerts .. " alerts")
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", false)
clock = clock + ns.REMEMBER_FOR + 1
Tick(200)
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-1", true)
Check("and it alerts again once the window has passed", #alerts == 2, #alerts .. " alerts")
_G.C_VignetteInfo.GetVignetteInfo = function() return nil end
clock = clock + 10
Fire("VIGNETTE_MINIMAP_UPDATED", "Vignette-2", true)
Check("a vignette without a readable name keeps a last alert name", ns.lastAlertName == "Rare or treasure", tostring(ns.lastAlertName))
_G.C_VignetteInfo.GetVignetteInfo = function() return { name = "Rare Elite" } end

print("rotating minimap")
local function Near(ax, ay, bx, by) return math.abs(ax - bx) < 1e-6 and math.abs(ay - by) < 1e-6 end
player.x, player.y, player.facing = 0, 0, 1
cvars.rotateMinimap = true
local rotatedX, rotatedY = ns.WorldFromOffset(10, 0)
local turnedX, turnedY = WorldFromOffset(10, 0)
Check("a rotating minimap turns offsets by the facing", Near(rotatedX, rotatedY, turnedX, turnedY))
rotateIgnored = true
local ignoredX, ignoredY = ns.WorldFromOffset(10, 0)
player.facing = 0
local fixedX, fixedY = WorldFromOffset(10, 0)
Check("an ignored rotation reads the minimap as fixed", Near(ignoredX, ignoredY, fixedX, fixedY))
cvars.rotateMinimap, rotateIgnored = false, false

print("gathermate2 source")
Check("the GatherMate2 source starts off", ns.db.gatherMate == false)
ns.db.blips, ns.db.gatherMate = false, true
alerts = {}
clock = clock + 10
Check("the hook attached", hooks.addMiniPin ~= nil and ns.gatherMateReady)

local function Pin(nodeType, coords, isCircle)
  return { nodeType = nodeType, coords = coords, isCircle = isCircle, title = nodeType .. " " .. coords }
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
Check("under GatherMate2's node name", ns.lastAlertName == herb.title, tostring(ns.lastAlertName))

clock = clock + 5
player.dead = true
local corpseRun = Pin("Herb Gathering", 450, true)
hooks.addMiniPin(display, corpseRun)
Check("a circle reached while dead stays silent", #alerts == 2, #alerts .. " alerts")
player.dead = false
hooks.addMiniPin(display, corpseRun)
Check("and alerts once alive", #alerts == 3, #alerts .. " alerts")

clock = clock + 5
ns.db.gatherMate = false
hooks.addMiniPin(display, Pin("Mining", 500, true))
Check("the source toggle silences it", #alerts == 3, #alerts .. " alerts")
ns.db.gatherMate = true

clock = clock + 5
hooks.addMiniPin(display, Pin("Mining", 600, true))
hooks.addMiniPin(display, Pin("Mining", 700, true))
Check("two circles inside the cooldown are one alert", #alerts == 4, #alerts .. " alerts")

alerts = {}
Fire("ZONE_CHANGED_NEW_AREA")
clock = clock + 6
hooks.addMiniPin(display, ore)
Check("a zone change forgets GatherMate2 circles", #alerts == 1, #alerts .. " alerts")

-- A circle for a real node, carrying the zone coordinates and node name GatherMate2 gives its minimap pins.
local function PlacedPin(nodeType, coords, node, name)
  local pin = Pin(nodeType, coords, true)
  pin.zone, pin.title = 1, name or node.name
  pin.x, pin.y = MapFromWorld(node.x, node.y)
  return pin
end

-- One node at a time, so the cooldown never folds two alerts into one and every count is exact.
print("one ping per node across sources")
local allNodes = world
local silverleaf, copper = allNodes[2], allNodes[4]
ns.db.blips = true
clock = clock + 10

world = { silverleaf }
alerts = {}
WalkInCount()
local blipFirst = #alerts
clock = clock + 5
hooks.addMiniPin(display, PlacedPin("Herb Gathering", 5100, silverleaf))
Check("a blip then a GatherMate2 circle for the same node pings once", blipFirst == 1 and #alerts == 1, blipFirst .. " then " .. #alerts)

clock = clock + 5
hooks.addMiniPin(display, PlacedPin("Mining", 5200, { x = silverleaf.x + 10, y = silverleaf.y }, "Tin Vein"))
Check("another kind of node inside the merge radius still pings", #alerts == 2, #alerts .. " alerts")

clock = clock + 5
hooks.addMiniPin(display, PlacedPin("Mining", 5300, copper))
Check("two different nodes still ping twice", #alerts == 3, #alerts .. " alerts")

world = { copper }
player.x, player.y = 0, 500
ns.ResetSeen()
Tick(100)
alerts = {}
clock = clock + ns.REMEMBER_FOR + 1
local copperCircle = PlacedPin("Mining", 5400, copper)
hooks.addMiniPin(display, copperCircle)
clock = clock + 5
WalkInCount()
Check("a GatherMate2 circle then a blip for the same node pings once", #alerts == 1, #alerts .. " alerts")
Check("and the blip refreshes the circle's node instead of adding one", ns.SeenCount() == 0, ns.SeenCount() .. " blip nodes")
Tick(60 * (ns.REMEMBER_FOR + 10))
hooks.addMiniPin(display, copperCircle)
Check("a node the blip keeps seeing stays one node past REMEMBER_FOR", #alerts == 1, #alerts .. " alerts")

-- The blip's node is still in the shared memory but stale, so a new circle for it is a new sighting.
world = { silverleaf }
alerts = {}
clock = clock + 5
WalkInCount()
player.x, player.y = 0, 500
Tick(100)
clock = clock + ns.REMEMBER_FOR + 1
hooks.addMiniPin(display, PlacedPin("Herb Gathering", 5500, silverleaf))
Check("after REMEMBER_FOR the same node alerts again", #alerts == 2, #alerts .. " alerts")
clock = clock + 5
hooks.addMiniPin(display, copperCircle)
Check("and a circle GatherMate2 still shows re-arms the same way", #alerts == 3, #alerts .. " alerts")

world = { copper }
alerts = {}
clock = clock + 5
hooks.addMiniPin(display, PlacedPin("Mining", 5600, copper))
Fire("ZONE_CHANGED_NEW_AREA")
clock = clock + 6
WalkInCount()
Check("a zone change forgets the shared memory too", #alerts == 2, #alerts .. " alerts")

world = allNodes
player.x, player.y = 0, 0
ns.db.blips = false

print("settings panel")
local built, buildError = BuildPanel()
Check("the vertical layout registers at login", built and panel.registered and panel.title == "Better Tracking", buildError)

-- These keys are state, not preferences, so the panel's Defaults button must never reach them.
local STATE_KEYS = { space = true, paused = true, hinted = true, minimap = true }

local unbound, stateBound = {}, {}
for key in pairs(ns.defaults) do
  if STATE_KEYS[key] and Setting(key) then stateBound[#stateBound + 1] = key end
  if not STATE_KEYS[key] and not Setting(key) then unbound[#unbound + 1] = key end
end
table.sort(unbound)
Check("every saved preference has a control", #unbound == 0, table.concat(unbound, ", "))
Check("the state keys have none, so Defaults cannot clear them", #stateBound == 0, table.concat(stateBound, ", "))

local headers = {}
for _, row in ipairs(panel.rows) do
  if row.kind == "header" then headers[#headers + 1] = row.data.name end
end
Check("four sections in order", table.concat(headers, "|") == "Herb and Ore Swap|Alert|Minimap Nodes|GatherMate2",
  table.concat(headers, "|"))
Check("the swap interval nests under the swap and offers 2 and 4 seconds", Row("Swap Every").parent == Row("Swap Herbs and Minerals")
  and #Row("Swap Every").data.options() == 2 and not Row("Swap Every"):IsEnabled())
Check("the swap tooltip names the global cooldown and the middle click", Tooltip("Swap Herbs and Minerals"):find("global cooldown", 1, true)
  and Tooltip("Swap Herbs and Minerals"):find("Middle-click", 1, true))
Setting("swap"):SetValue(true)
Check("the swap checkbox starts the ticker", LiveTickers() == 1, LiveTickers())
Setting("swap"):SetValue(false)
Check("and stops it", LiveTickers() == 0, LiveTickers())

Check("the sound dropdown offers all six sounds", #Row("Sound").data.options() == #ns.sounds)
alerts = {}
Setting("soundId"):SetValue(SOUNDKIT.RAID_WARNING)
Check("picking a sound saves and previews it", ns.db.soundId == SOUNDKIT.RAID_WARNING and alerts[1] == SOUNDKIT.RAID_WARNING)
Setting("soundId"):SetValue(SOUNDKIT.RAID_WARNING)
Check("picking the same sound again writes nothing", #alerts == 1, #alerts .. " sounds")

Setting("sound"):SetValue(false)
local greyedOut = not Row("Sound"):IsEnabled()
Setting("sound"):SetValue(true)
Check("the sound picker greys out while the sound is off", greyedOut and Row("Sound"):IsEnabled())
Check("minimap rows nest under their switch", Row("Gathering Nodes Only").parent == Row("Alert on Minimap Nodes")
  and Row("Rares and Treasures").parent == Row("Alert on Minimap Nodes"))
Check("the cooldown reads in seconds", Row("Cooldown").data.options.format(3) == "3 s")

-- Blizzard's checkbox dropdown flips one option bit per click, so the harness does the same.
local picker = Row("Node Types")
local typeMask = Setting("mutedTypes")
Check("the node types list only GatherMate2's Forever types", picker and #picker.data.options() == 2,
  picker and #picker.data.options())
Check("every type starts ticked", typeMask:GetValue() == 3 and picker.getSelectionTextFunc({ 1, 2 }) == "All")
typeMask:SetValue(bit.bxor(typeMask:GetValue(), 2))
Check("unticking a type mutes only that one", ns.db.mutedTypes.Mining and not ns.db.mutedTypes["Herb Gathering"])
Check("a partial pick lists the ticked names", picker.getSelectionTextFunc({ 1 }) == nil)
Check("no pick reads None", picker.getSelectionTextFunc({}) == "None")
Check("node types nest under the GatherMate2 switch", picker.parent == Row("Also Ping at Spots GatherMate2 Remembers"))

Setting("cooldown"):SetValue(10)
Setting("blips"):SetValue(false)
ns.db.paused = true
RestoreDefaults()
local drifted = {}
for key, value in pairs(ns.defaults) do
  if type(value) ~= "table" and not STATE_KEYS[key] and ns.db[key] ~= value then drifted[#drifted + 1] = key end
end
table.sort(drifted)
Check("Defaults restore every setting", #drifted == 0 and next(ns.db.mutedTypes) == nil, table.concat(drifted, ", "))
Check("Defaults keep the calibration and the pause", ns.db.space == "center" and ns.db.paused, tostring(ns.db.space))
ns.db.paused = false
alerts = {}
RestoreDefaults()
Check("Defaults that change nothing play nothing", #alerts == 0, #alerts .. " sounds")

alerts = {}
Click("Preview")
Check("Test plays the alert sound", alerts[1] == ns.db.soundId, tostring(alerts[1]))

Check("Calibration offers a recalibration once calibrated", Row("Calibration").data.buttonText() == "Recalibrate")
Check("and leads its tooltip with the live state in plain words", Tooltip("Calibration"):find("^Minimap alerts are ready%.") ~= nil)
local calibrate = Click("Calibration")
Check("clicking it clears the space and relabels the button", ns.db.space == false and calibrate.text == "Calibrate")
Check("and the tooltip follows", Tooltip("Calibration"):find("^Not calibrated") ~= nil)
Click("Calibration")
Check("with nothing to clear it says how to start", chat[#chat]:find(HINT, 1, true) ~= nil, chat[#chat])
ns.db.space = "center"

ns.db.gatherMate = true
ns.ResetSeen()
Tick(600)
local remembered = ns.SeenCount()
Check("the reset tooltip counts the remembered nodes", Tooltip("Remembered Nodes"):find(remembered .. " right now", 1, true) ~= nil)
clock = clock + 5
hooks.addMiniPin(display, Pin("Mining", 4242, true))
local circles = ns.GatherMateSeenCount()
Check("the reset tooltip counts GatherMate2's nodes too", Tooltip("Remembered Nodes"):find((remembered + circles) .. " right now", 1, true) ~= nil)
SlashCmdList.BETTERTRACKING("status")
Check("status counts both sources", chat[#chat]:find("Nodes remembered: " .. (remembered + circles), 1, true) ~= nil, chat[#chat])
Click("Remembered Nodes")
Check("Reset forgets every remembered node", remembered > 0 and ns.SeenCount() == 0, remembered .. " before")
Check("and every node GatherMate2 remembers", circles > 0 and ns.GatherMateSeenCount() == 0, circles .. " before")

print("launcher")
local function Launcher() return LibStub("LibDataBroker-1.1"):GetDataObjectByName("Better Tracking") end
local function ClickLauncher(button) Launcher().OnClick(nil, button) end
local function TooltipText()
  tooltipLines = {}
  Launcher().OnTooltipShow(GameTooltip)
  return tooltipLines
end

local toc = io.open("BetterTracking.toc"):read("a")
Check("the toc lists no compartment functions, LibDBIcon adds the entry", not toc:find("AddonCompartmentFunc", 1, true)
  and icons["Better Tracking"].compartment)
Check("the minimap button is shown by default and saves into the account db", icons["Better Tracking"].shown
  and icons["Better Tracking"].db == ns.db.minimap)

ClickLauncher("RightButton")
Check("a right click pauses and says so", ns.db.paused and chat[#chat]:find("Alerts paused.", 1, true) ~= nil, chat[#chat])
Check("and keeps the sound and flash choices", ns.db.sound and ns.db.flash)
alerts = {}
clock = clock + 5
hooks.addMiniPin(display, Pin("Mining", 4343, true))
Check("a paused addon stays silent", #alerts == 0, #alerts .. " alerts")

local lines = TooltipText()
Check("the tooltip shows the title, the pause, the swap and the last alert", lines[1] == "Better Tracking"
  and lines[2] == "Alerts are paused." and lines[3] == "Swap is off." and lines[4] == "Last alert: " .. ns.lastAlertName .. ".",
  table.concat(lines, " | "))
Check("then the three clicks, offering to resume", lines[5] == "Left-click to open the settings."
  and lines[6] == "Middle-click to turn the herb and ore swap on or off." and lines[7] == "Right-click to resume alerts.",
  table.concat(lines, " | "))

ClickLauncher("RightButton")
Check("a second right click resumes", not ns.db.paused and chat[#chat]:find("Alerts resumed.", 1, true) ~= nil, chat[#chat])

ns.db.space = false
Check("an uncalibrated tooltip says what to hover", TooltipText()[2]:find(HINT, 1, true) == 1, tooltipLines[2])
ns.db.space = "center"

inCombat = true
ClickLauncher("LeftButton")
Check("a left click in combat waits", not panel.opened and chat[#chat] == "[Better Tracking]: Opens after combat.", chat[#chat])
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Check("and opens the category once combat ends", panel.opened)

SlashCmdList.BETTERTRACKING("minimap")
Check("/tra minimap hides the button and says how to bring it back", not icons["Better Tracking"].shown and ns.db.minimap.hide
  and chat[#chat] == "[Better Tracking]: Minimap button hidden. Type /tra minimap to show it again.", chat[#chat])
SlashCmdList.BETTERTRACKING("minimap")
Check("and shows it again", icons["Better Tracking"].shown and chat[#chat] == "[Better Tracking]: Minimap button shown.", chat[#chat])

print("herb and ore swap")
local function Advance(seconds) Tick(math.floor(seconds * 60 + 0.5)) end

local function ActiveSpell()
  for _, info in ipairs(tracking) do
    if info.type == "spell" and info.active then return info end
  end
end

local function SetActive(name)
  for _, info in ipairs(tracking) do
    if info.type == "spell" then info.active = info.name == name end
  end
end

local function LastCall() return trackingCalls[#trackingCalls] end

world = { { name = "Peacebloom", x = 30, y = 0, kind = "herb" }, { name = "Copper Vein", x = -30, y = 20, kind = "ore" } }
player.x, player.y, player.speed = 0, 0, 7
ns.db.blips, ns.db.space, ns.db.paused = true, "center", false
SetActive("Find Minerals")
Fire("PLAYER_ENTERING_WORLD")
Check("login shows a tracking that is already on", brokers["Better Tracking"].icon == 136025,
  tostring(brokers["Better Tracking"].icon))
SetActive(nil)
Advance(5)

Check("the swap starts off", ns.db.swap == false and LiveTickers() == 0 and TooltipText()[3] == "Swap is off.")
local notifiedBefore = Setting("swap").notified
SlashCmdList.BETTERTRACKING("swap")
Check("/tra swap turns it on with one line", ns.db.swap and LiveTickers() == 1
  and chat[#chat] == "[Better Tracking]: Herb and ore swap on.", chat[#chat])
Check("and tells an open settings panel", Setting("swap").notified == notifiedBefore + 1)

Advance(1)
Check("herbs come first when neither is on", #trackingCalls == 1 and LastCall().index == 1 and ActiveSpell().name == "Find Herbs",
  #trackingCalls .. " calls")
Check("the button shows the active tracking", brokers["Better Tracking"].icon == 133939, tostring(brokers["Better Tracking"].icon))
Advance(3)
Check("no swap before the interval", #trackingCalls == 1, #trackingCalls .. " calls")
Advance(1)
Check("a swap once it is due turns on minerals", #trackingCalls == 2 and LastCall().index == 2 and ActiveSpell().name == "Find Minerals",
  #trackingCalls .. " calls")
Advance(4)
Check("and alternates back to herbs", #trackingCalls == 3 and LastCall().index == 1, #trackingCalls .. " calls")
local turnedOff = false
for _, call in ipairs(trackingCalls) do turnedOff = turnedOff or not call.on end
Check("the swap never turns tracking off", not turnedOff)
Check("the tooltip says it is swapping", TooltipText()[3] == "Swapping herbs and minerals.", tooltipLines[3])
cooldownActive = true
Check("the global cooldown a swap spent is normal running, not a wait", TooltipText()[3] == "Swapping herbs and minerals.",
  tooltipLines[3])
cooldownActive = false
Check("timed swaps that take are never counted as dropped", Said("did not take") == 0)

ns.db.swapInterval = 2
local beforeFast = #trackingCalls
Advance(10)
Check("Swap Every 2 Seconds swaps twice as often", #trackingCalls - beforeFast == 5, (#trackingCalls - beforeFast) .. " swaps")
ns.db.swapInterval = 4

-- Each guard holds the swap with its own reason, and the swap carries on once the guard clears.
local savedActive
local guards = {
  { "a missing gathering spell", function(on) tracking[2].spellID = on and 99999 or 2580 end, "needs Find Herbs and Find Minerals" },
  { "another tracking", function(on)
      if on then savedActive = ActiveSpell().name end
      SetActive(on and "Find Fish" or savedActive)
    end, "another tracking is on" },
  { "combat lockdown", function(on) inCombat = on end, "in combat" },
  { "combat before lockdown", function(on) player.combat = on end, "in combat" },
  { "death", function(on) player.dead = on end, "dead or a ghost" },
  { "a flight", function(on) player.taxi = on end, "on a flight" },
  { "an instance", function(on) player.instance = on end, "in an instance" },
  { "resting", function(on) player.resting = on end, "resting in a town or inn" },
  { "standing still", function(on) player.speed = on and 0 or 7 end, "standing still" },
  { "a secret speed", function(on) player.speed = on and SECRET or 7 end, "standing still" },
  { "a cast", function(on) player.casting = on and "Hearthstone" or nil end, "casting" },
  { "a secret cast", function(on) player.casting = on and SECRET or nil end, "casting" },
  { "a channel", function(on) player.channeling = on and "First Aid" or nil end, "casting" },
  { "looting", function(on) LootFrame.shown = on end, "looting" },
  { "an attackable target", function(on) target.attackable = on end, "an enemy is targeted or under the cursor" },
  { "an attackable unit under the cursor", function(on) underCursor.attackable = on end,
    "an enemy is targeted or under the cursor" },
  { "a cooldown", function(on) cooldownActive = on end, "on cooldown" },
}
for _, guard in ipairs(guards) do
  local label, set, reason = guard[1], guard[2], guard[3]
  set(true)
  local before = #trackingCalls
  Advance(5)
  local held, said = #trackingCalls == before, ns.SwapWaitReason()
  set(false)
  Advance(5)
  Check(label .. " holds the swap with its reason and releases it", held and said == reason and #trackingCalls > before,
    tostring(said) .. ", " .. (#trackingCalls - before) .. " swaps")
end

target.attackable, target.dead = true, true
local beforeDead = #trackingCalls
Advance(5)
Check("a dead enemy target does not hold the swap", #trackingCalls > beforeDead)
target.attackable, target.dead = false, false

player.speed = 0
Check("the tooltip names why the swap waits", TooltipText()[3] == "Swap waits: standing still.", tooltipLines[3])
player.speed = 7

SlashCmdList.BETTERTRACKING("swap")
Check("/tra swap turns it off with one line", not ns.db.swap and LiveTickers() == 0
  and chat[#chat] == "[Better Tracking]: Herb and ore swap off.", chat[#chat])
tracking[2].spellID = 99999
ClickLauncher("MiddleButton")
Check("a middle click turns it on and says when a spell is missing", ns.db.swap and LiveTickers() == 1
  and chat[#chat] == "[Better Tracking]: Herb and ore swap needs Find Herbs and Find Minerals.", chat[#chat])
tracking[2].spellID = 2580
ClickLauncher("MiddleButton")
Check("a second middle click turns it off", not ns.db.swap and LiveTickers() == 0)

print("swapped-in nodes")
SetActive("Find Herbs")
ns.ResetSeen()
alerts = {}
Advance(6)
Check("the herb already on screen is recorded silently", #alerts == 0 and ns.SeenCount() == 1, ns.SeenCount() .. " remembered")
ClickLauncher("MiddleButton")
Advance(2)
Check("an ore node revealed by a swap pings", ActiveSpell().name == "Find Minerals" and #alerts == 1
  and ns.lastAlertName == "Copper Vein", #alerts .. " alerts, last " .. tostring(ns.lastAlertName))
local swapsBefore = #trackingCalls
Advance(20)
Check("node memory keeps both quiet on every later swap", #trackingCalls - swapsBefore >= 4 and #alerts == 1,
  (#trackingCalls - swapsBefore) .. " swaps, " .. #alerts .. " alerts")

cooldownActive = true
world[#world + 1] = { name = "Mageroyal", x = 10, y = -30, kind = "herb" }
SetActive("Find Herbs")
Fire("MINIMAP_UPDATE_ZOOM")
Advance(2)
Check("a zoom change with the swap on still reprimes silently", #alerts == 1 and ns.SeenCount() == 3,
  #alerts .. " alerts, " .. ns.SeenCount() .. " remembered")
cooldownActive = false

ClickLauncher("MiddleButton")
world[#world + 1] = { name = "Tin Vein", x = -20, y = -30, kind = "ore" }
Advance(5)
SetActive("Find Minerals")
Fire("MINIMAP_UPDATE_TRACKING")
Advance(2)
Check("a manual tracking change with the swap off reprimes silently", #alerts == 1 and ns.SeenCount() == 4,
  #alerts .. " alerts, " .. ns.SeenCount() .. " remembered")

ClickLauncher("MiddleButton")
blipDelay = 0.2
world[#world + 1] = { name = "Earthroot", x = 12, y = 6, kind = "herb" }
world[#world + 1] = { name = "Silver Vein", x = -8, y = -12, kind = "ore" }
local alertsBefore = #alerts
Advance(9)
Check("swapped-in blips that arrive late still ping", #alerts == alertsBefore + 2, (#alerts - alertsBefore) .. " alerts")
blipDelay = 0
ClickLauncher("MiddleButton")

print("blocked swaps")
ClickLauncher("MiddleButton")
Fire("ADDON_ACTION_BLOCKED", "BetterTracking", "CastSpellByName()")
Advance(5)
Check("a block outside the swap changes nothing", LiveTickers() == 1 and Said("Blizzard blocked") == 0)
blockTimed, blockedAs = true, "OtherAddon"
Advance(5)
Check("a block naming another addon changes nothing", LiveTickers() == 1 and Said("Blizzard blocked") == 0)
blockedAs = "BetterTracking"
Advance(5)
Check("a blocked timed swap moves the swap onto movement keys with one line", LiveTickers() == 0
  and Said("Blizzard blocked timed swaps, so the swap now runs on your movement keys.") == 1, LiveTickers() .. " tickers")
local blockedCalls = #trackingCalls
Advance(10)
Check("the ticker no longer swaps", #trackingCalls == blockedCalls, (#trackingCalls - blockedCalls) .. " calls")

local function Press(name)
  hardwareInput = true
  _G[name]()
  hardwareInput = false
end

Check("the tooltip says the swap runs on movement keys", TooltipText()[3] == "Swapping herbs and minerals on your movement keys.",
  tooltipLines[3])
player.speed = 0
Press("TurnLeftStart")
Check("turning in place does not swap", #trackingCalls == blockedCalls)
local activeBefore = ActiveSpell().name
Press("MoveForwardStart")
player.speed = 7
Check("a movement key runs the due swap from a standstill", #trackingCalls == blockedCalls + 1 and ActiveSpell().name ~= activeBefore)
Press("JumpOrAscendStart")
Check("a second input inside the interval does not", #trackingCalls == blockedCalls + 1)
Advance(12)
Press("TurnOrActionStart")
Check("one swap per input, however long it waited", #trackingCalls == blockedCalls + 2, (#trackingCalls - blockedCalls) .. " calls")
Advance(5)
player.speed = 0
Press("CameraOrSelectOrMoveStart")
Check("an input keeps every guard", #trackingCalls == blockedCalls + 2)
player.speed = 7

Advance(5)
underCursor.attackable = true
Press("TurnOrActionStart")
Check("a click on an enemy does not swap before it targets", #trackingCalls == blockedCalls + 2)
underCursor.attackable = false

blockAll, blockEvent = true, "ADDON_ACTION_FORBIDDEN"
Press("StrafeLeftStart")
Advance(5)
Press("StrafeRightStart")
Check("a block on movement keys too stops the swap with one line", #trackingCalls == blockedCalls + 3
  and Said("Blizzard blocks the swap on movement keys too") == 1, (#trackingCalls - blockedCalls) .. " calls")
Check("a forbidden block says to choose Ignore", chat[#chat]:find("Choose Ignore in Blizzard's warning.", 1, true) ~= nil, chat[#chat])
Check("and says so in the tooltip", TooltipText()[3] == "Swap waits: Blizzard blocks it until you type /reload.", tooltipLines[3])
Check("the timed block line came once, without the Ignore hint", Said("Blizzard blocked timed swaps") == 1
  and Said("Ignore") == 1)
SlashCmdList.BETTERTRACKING("swap")
SlashCmdList.BETTERTRACKING("swap")
Check("turning it on again says it stays off", chat[#chat]
  == "[Better Tracking]: Herb and ore swap stays off until you type /reload, because Blizzard blocks it.", chat[#chat])
blockEvent = "ADDON_ACTION_BLOCKED"
blockTimed, blockAll = false, false
ns.db.swap = false

print("without gathermate2")
loaded.GatherMate2, _G.LibStub, hooks = nil, nil, {}
ns.db.space = false
local hintsBefore = Said(HINT)
local bare = LoadAddon()
Check("a later load prints no second hint", Said(HINT) == hintsBefore, (Said(HINT) - hintsBefore) .. " new hints")
bare.db.space = "center"
Check("the GatherMate2 source stays detached", not bare.gatherMateReady and hooks.addMiniPin == nil)
Check("it offers no node types", #bare.GatherMateTypes() == 0)
Check("the panel still builds", BuildPanel())
Check("without an empty node types row", Row("Node Types") == nil and Setting("mutedTypes") == nil)
Check("the GatherMate2 row is greyed", not Row("Also Ping at Spots GatherMate2 Remembers"):IsEnabled())
Check("and its tooltip says why", Tooltip("Also Ping at Spots GatherMate2 Remembers"):find("Needs GatherMate2", 1, true) ~= nil)
Check("the minimap rows stay live", Row("Alert on Minimap Nodes"):IsEnabled() and Row("Gathering Nodes Only"):IsEnabled())

print("dropped timed swaps")
dropTimed = true
SetActive("Find Herbs")
bare.ToggleSwap()
local dropCalls = #trackingCalls
Advance(3)
Check("one dropped swap is not yet a block", LiveTickers() == 1 and #trackingCalls == dropCalls + 1
  and Said("did not take") == 0, LiveTickers() .. " tickers")
Advance(4)
Check("a second dropped swap moves the swap onto movement keys with one line", LiveTickers() == 0
  and Said("Timed swaps did not take, so the swap now runs on your movement keys.") == 1, LiveTickers() .. " tickers")
Advance(2)
Press("MoveForwardStart")
Check("and a key press then swaps", ActiveSpell().name == "Find Minerals", ActiveSpell().name)
dropTimed = false
bare.db.swap = false

print("timed swaps behind a lagging tracking mirror")
_G.LibStub = nil
local lagged = LoadAddon()
local droppedBefore = Said("did not take")
lagMirror = true
SetActive("Find Herbs")
lagged.ToggleSwap()
local lagCalls = #trackingCalls
Advance(9)
Check("a cast that succeeds counts as taken while the mirror lags", #trackingCalls > lagCalls + 1
  and Said("did not take") == droppedBefore and not lagged.SwapRunsOnInput(), (#trackingCalls - lagCalls) .. " swaps")
lagMirror = false
lagged.db.swap = false
lagged.ApplySwap()

print("losing the calibrated space")
Minimap.UpdateMouseoverAtPoint = function() error("bad argument") end
local saidFailure = Said("The minimap stopped answering")
bare.Probe(10, 0)
bare.Probe(20, 0)
Check("a failing calibrated space says so once", Said("The minimap stopped answering") == saidFailure + 1)
Check("and the status line says alerts are off", bare.StatusText() == "Minimap alerts are off until you type /reload.", bare.StatusText())

print("slash commands")
Check("status raises no error", pcall(SlashCmdList.BETTERTRACKING, "status"))
Check("types raises no error", pcall(SlashCmdList.BETTERTRACKING, "types"))
Check("calibrate raises no error", pcall(SlashCmdList.BETTERTRACKING, "calibrate"))
Check("/bettertracking is the long command", SLASH_BETTERTRACKING1 == "/bettertracking" and SLASH_BETTERTRACKING2 == "/tra")

print(failures == 0 and "\nall checks passed" or ("\n" .. failures .. " failing checks"))
os.exit(failures == 0 and 0 or 1)
