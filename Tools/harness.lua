-- Offline harness. Run from the addon folder with: lua Tools/harness.lua
-- Stubs enough of the client to drive both sources against a fake world, so the dedup, the queue, the
-- calibration, the GatherMate2 hook, the herb and ore swap, the launcher and the settings panel can be
-- checked without logging in. It proves the logic, never the client behaviour.

-- The harness reports through its own print, while the addon's chat lines land in chat for checking.
local print = print
local chat = {}
_G.print = function(line) chat[#chat + 1] = line end

-- The gold title of every chat line, as the NORMAL_FONT_COLOR stub marks it, then the uncoloured colon.
local PREFIX = "|cnGOLD[Better Tracking]|r: "

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
local UI_SOUNDS = { [SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON] = true, [SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF] = true }
local uiSounds = 0
_G.PlaySound = function(id, channel)
  if UI_SOUNDS[id] then
    uiSounds = uiSounds + 1
    return
  end
  alerts[#alerts + 1] = id
  lastChannel = channel
end
_G.NONE, _G.ALL, _G.RESET, _G.SECOND_ONELETTER_ABBR = "None", "All", "Reset", "%d s"
_G.YES, _G.NO = "Yes", "No"
_G.tContains = function(list, value)
  for _, item in ipairs(list) do
    if item == value then return true end
  end
  return false
end
-- The gold wrap is kept as a marker, so a check can tell the coloured title from the plain message.
_G.NORMAL_FONT_COLOR = {
  GetRGB = function() return 1, 0.82, 0 end,
  WrapTextInColorCode = function(_, text) return "|cnGOLD" .. text .. "|r" end,
}
_G.RED_FONT_COLOR = { WrapTextInColorCode = function(_, text) return text end }
_G.GRAY_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }
_G.SETTINGS_DEFAULTS, _G.SETTINGS = "Defaults", "Settings"
_G.GameFontNormal, _G.GameFontHighlight, _G.GameFontDisable = { "GameFontNormal" }, { "GameFontHighlight" },
  { "GameFontDisable" }
_G.C_AddOns = { GetAddOnMetadata = function(name, field) return name == "BetterTracking" and field == "Title" and "Better Tracking" end }

-- Frames keep their template, parent, children, font strings and scripts, so the settings page can be driven
-- through its own controls and the help tip through its target's OnShow.
local frames = {}
local templates = {}

local function NewFontString()
  local text = setmetatable({ points = {} }, stubMeta)
  function text:SetText(value) self.text = value end
  function text:GetText() return self.text end
  function text:SetFontObject(font) self.font = font end
  function text:SetTextColor(r, g, b) self.color = { r, g, b } end
  function text:SetPoint(point, ...) self.points[point] = { ... } end
  return text
end

_G.CreateFrame = function(_, _, parent, template)
  local frame = setmetatable({ events = {}, scripts = {}, hooks = {}, children = {}, texts = {}, parent = parent,
    template = template, enabled = true, shown = true }, stubMeta)
  function frame:RegisterEvent(event) self.events[event] = true end
  function frame:RegisterUnitEvent(event) self.events[event] = true end
  function frame:UnregisterEvent(event) self.events[event] = nil end
  function frame:SetScript(kind, handler) self.scripts[kind] = handler end
  function frame:HookScript(kind, handler)
    self.hooks[kind] = self.hooks[kind] or {}
    table.insert(self.hooks[kind], handler)
  end
  function frame:CreateFontString()
    local text = NewFontString()
    self.texts[#self.texts + 1] = text
    return text
  end
  function frame:SetText(value) self.text = value end
  function frame:SetEnabled(enabled) self.enabled = enabled and true or false end
  function frame:IsEnabled() return self.enabled end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:IsShown() return self.shown end
  function frame:IsVisible()
    if not self.shown then return false end
    local owner = rawget(self, "parent")
    if type(owner) == "table" and rawget(owner, "children") then return owner:IsVisible() end
    return true
  end
  if type(parent) == "table" and rawget(parent, "children") then parent.children[#parent.children + 1] = frame end
  frames[#frames + 1] = frame
  if templates[template] then templates[template](frame) end
  return frame
end

local function RunScript(frame, kind, ...)
  if frame.scripts[kind] then frame.scripts[kind](frame, ...) end
  for _, hook in ipairs(frame.hooks[kind] or {}) do hook(frame, ...) end
end

-- The client fires OnShow and OnHide down the tree, on every child that is shown itself.
local function ShowTree(frame)
  RunScript(frame, "OnShow")
  for _, child in ipairs(frame.children) do
    if child.shown then ShowTree(child) end
  end
end

local function HideTree(frame)
  RunScript(frame, "OnHide")
  for _, child in ipairs(frame.children) do
    if child.shown then HideTree(child) end
  end
end

-- Blizzard's CallbackRegistryMixin hands each callback its owner first.
local function AddCallbacks(frame)
  frame.callbacks = {}
  function frame:RegisterCallback(event, callback, owner)
    self.callbacks[#self.callbacks + 1] = { event = event, callback = callback, owner = owner }
  end
  function frame:TriggerEvent(event, ...)
    for _, entry in ipairs(self.callbacks) do
      if entry.event == event then entry.callback(entry.owner, ...) end
    end
  end
end

-- SettingsCheckboxMixin:Init wires OnClick to OnValueChanged. A disabled box takes no click.
templates.SettingsCheckboxTemplate = function(checkbox)
  AddCallbacks(checkbox)
  function checkbox:Init(value, tooltip) self.checked, self.tooltip = value, tooltip end
  function checkbox:SetValue(value) self.checked = value end
  function checkbox:Click()
    if not self.enabled then return end
    self.checked = not self.checked
    self:TriggerEvent("OnValueChanged", self.checked)
  end
end

-- The menu runs its generator against a fake root description, and a pick calls the entry's setter, as a click
-- in the open menu does. Text follows DropdownSelectionTextMixin: the selection function first, else the names.
templates.WowStyle1DropdownTemplate = function(dropdown)
  function dropdown:SetupMenu(generator) self.generator = generator end
  function dropdown:SetSelectionText(selectionText) self.selectionText = selectionText end
  function dropdown:GenerateMenu() self.generated = (rawget(self, "generated") or 0) + 1 end
  function dropdown:Entries()
    local entries = {}
    local function Add(kind)
      return function(_, text, isSelected, setSelected)
        entries[#entries + 1] = { kind = kind, text = text, isSelected = isSelected, setSelected = setSelected }
      end
    end
    self.generator(self, { CreateRadio = Add("radio"), CreateCheckbox = Add("checkbox") })
    return entries
  end
  function dropdown:Pick(text)
    for _, entry in ipairs(self:Entries()) do
      if entry.text == text then return entry.setSelected() end
    end
    error("no menu entry " .. text)
  end
  function dropdown:Text()
    local selections, names = {}, {}
    for _, entry in ipairs(self:Entries()) do
      if entry.isSelected() then
        selections[#selections + 1] = entry
        names[#names + 1] = entry.text
      end
    end
    local selectionText = rawget(self, "selectionText")
    return selectionText and selectionText(selections) or table.concat(names, ", ")
  end
end

-- HelpTipTemplateMixin as far as the tip uses it: the frame starts hidden, Init keeps acknowledged and only Reset
-- clears it, and a hide runs Close, which reports a tip still marked acknowledged (HelpTip.lua:405-431, 495, 670-716).
templates.HelpTipTemplate = function(tip)
  -- The addon reads tip.info for whether the tip is up, so a missing info reads nil, never a stub.
  setmetatable(tip, { __index = function(_, key) if key ~= "info" then return Stub() end end })
  tip.shown, tip.acknowledged, tip.inits = false, false, 0
  function tip:Reset() self.info, self.acknowledged = nil, false end
  function tip:Init(_, info) self.info, self.inits = info, self.inits + 1 end
  function tip:Close()
    local info = rawget(self, "info")
    if info then
      self.info = nil
      if self.acknowledged then info.onAcknowledgeCallback() end
    end
    self.shown = false
  end
  function tip:Acknowledge()
    self.acknowledged = true
    self:Close()
  end
  tip:SetScript("OnHide", tip.Close)
end

-- Like Blizzard's, a new value reaches OnValueChanged through the bar's own script.
templates.MinimalSliderWithSteppersTemplate = function(slider)
  AddCallbacks(slider)
  slider.Slider = CreateFrame("Slider", nil, slider)
  function slider:Init(value, minimum, maximum, steps, formatters)
    self.value, self.minimum, self.maximum, self.steps, self.formatters = value, minimum, maximum, steps, formatters
  end
  function slider:SetValue(value)
    if value == self.value then return end
    self.value = value
    self:TriggerEvent("OnValueChanged", value)
  end
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
  softCursor = false,
  SetUsingSoftCursor = function(self, on) self.softCursor = on end,
  -- The engine answers a point only for the soft cursor or under the hardware cursor.
  UpdateMouseoverAtPoint = function(self, x, y)
    if not (self.softCursor or self.mouseIsOver) then
      mouseover = nil
      return
    end
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

-- The real LibStub loads from disk. The launcher's libraries and AceAddon are reduced to the
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
local loginCallbacks = {}
_G.EventUtil = {
  ContinueOnPlayerLogin = function(fn) loginCallbacks[#loginCallbacks + 1] = fn end,
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
_G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
  Event = { OnValueChanged = "OnValueChanged" } }
_G.SettingsCheckboxMixin = { Event = { OnValueChanged = "OnValueChanged" } }
_G.HelpTip = { width = 226, ButtonStyle = { Close = 2 }, Point = { RightEdgeCenter = 8 } }
_G.GameTooltip, _G.SettingsTooltip = Stub(), Stub()

-- Blizzard's link helpers, and the EventRegistry event every addon link click reaches, owner first.
_G.LinkTypes = { AddOn = "addon" }
_G.LinkUtil = {
  FormatLink = function(linkType, text, ...) return "|H" .. table.concat({ linkType, ... }, ":") .. "|h" .. text .. "|h" end,
}
local registry = {}
_G.EventRegistry = {
  RegisterCallback = function(_, event, callback, owner)
    registry[event] = registry[event] or {}
    table.insert(registry[event], { callback = callback, owner = owner })
  end,
}
local function ClickLink(link)
  for _, entry in ipairs(registry.SetItemRef or {}) do entry.callback(entry.owner, link, "[Settings]", "LeftButton") end
end
_G.SlashCmdList = {}

local tooltipLines = {}
local function TooltipLine(_, text) tooltipLines[#tooltipLines + 1] = text end
_G.GameTooltip_SetTitle, _G.GameTooltip_AddHighlightLine, _G.GameTooltip_AddInstructionLine =
  TooltipLine, TooltipLine, TooltipLine
_G.GameTooltip_AddNormalLine, _G.GameTooltip_AddErrorLine = TooltipLine, TooltipLine

-- Blizzard's Settings API for a canvas page. The settings list calls are left out, so a page built as a list
-- fails to load here.
local settingsPage = {}
_G.Settings = {
  RegisterCanvasLayoutCategory = function(frame, name)
    settingsPage.frame, settingsPage.title = frame, name
    return { GetID = function() return 42 end }
  end,
  RegisterAddOnCategory = function() settingsPage.registered = true end,
  OpenToCategory = function(categoryID) settingsPage.opened = categoryID end,
}

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

-- Runs the login callbacks the loaded files registered, once, as PLAYER_LOGIN does.
local function Login()
  local callbacks = loginCallbacks
  loginCallbacks = {}
  for _, callback in ipairs(callbacks) do callback() end
end

local CONTROL_TEMPLATES = { SettingsCheckboxTemplate = true, WowStyle1DropdownTemplate = true,
  MinimalSliderWithSteppersTemplate = true }

-- The rows of the settings page in page order, each with its label and control.
local function PageRows()
  local rows = {}
  for _, frame in ipairs(frames) do
    if frame.parent == settingsPage.frame and frame.texts[1] then
      for _, child in ipairs(frame.children) do
        if CONTROL_TEMPLATES[child.template] then
          rows[#rows + 1] = { frame = frame, label = frame.texts[1], control = child }
        end
      end
    end
  end
  return rows
end

local function Row(label)
  for _, row in ipairs(PageRows()) do
    if row.label.text == label then return row end
  end
end

local function Control(label)
  local row = Row(label)
  return row and row.control
end

-- What a row shows on hover, as one string.
local function RowTooltip(label)
  tooltipLines = {}
  local row = Row(label)
  row.frame.scripts.OnEnter(row.frame)
  return table.concat(tooltipLines, " ")
end

-- Greyed as Blizzard's rows: a grey label and a control that takes no input. A live row's label is gold.
local function IsGreyed(label)
  local row = Row(label)
  return row.label.color[1] == 0.5 and not row.control.enabled
end

local function IsLive(label)
  local row = Row(label)
  return row.label.color[1] == 1 and row.control.enabled
end

-- The Settings window shows the page: OnShow down the tree on its first show, then OnRefresh every time
-- (SettingsPanelMixin:DisplayLayout). Closing the window hides it again.
local function OpenPage()
  local frame = settingsPage.frame
  if not frame.shown then
    frame.shown = true
    ShowTree(frame)
  end
  frame:OnRefresh()
end

local function ClosePage()
  local frame = settingsPage.frame
  if frame.shown then
    HideTree(frame)
    frame.shown = false
  end
end

local function IsIndented(label)
  return Row(label).label.points.LEFT[1] == 37 + 15
end

local function PressDefaults()
  for _, frame in ipairs(frames) do
    if frame.parent == settingsPage.frame and frame.template == "UIPanelButtonTemplate" and frame.text == "Defaults" then
      return frame.scripts.OnClick(frame)
    end
  end
  error("no Defaults button")
end

local ns = LoadAddon()

function Fire(event, ...)
  for _, frame in ipairs(frames) do
    if frame.events[event] and frame.scripts.OnEvent then
      frame.scripts.OnEvent(frame, event, ...)
    end
  end
end

local function Tick(count, step)
  step = step or 1 / 60
  for _ = 1, count do
    clock = clock + step

    -- The engine refreshes minimap mouseover from the real cursor every frame, which is what gives
    -- calibration its ground truth and what overwrites whatever the addon last probed.
    if Minimap.mouseIsOver then
      mouseover = NodeAt(_G.cursorX - 500, _G.cursorY - 400)
    end

    for _, frame in ipairs(frames) do
      if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, step) end
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
local WELCOME = "Pings when a new node, rare or treasure shows up on the minimap"
Check("the first load prints nothing", #chat == 0, chat[1])
Login()
Check("login prints exactly one welcome line", #chat == 1 and Said(WELCOME) == 1, chat[1])
Check("with the gold settings link and the alias", chat[1]:find("Open the |cnGOLD|Haddon:BetterTracking|h[Settings]|h|r or type /tra ",
  1, true) ~= nil, chat[1])
Check("and what minimap pings need", chat[1]:find("hover a blip near the minimap edge.", 1, true) ~= nil, chat[1])
ClickLink("addon:OtherAddon")
local secretGuarded = false
local plainIsSecret = _G.issecretvalue
_G.issecretvalue = function(value)
  secretGuarded = secretGuarded or value == SECRET
  return plainIsSecret(value)
end
ClickLink(SECRET)
_G.issecretvalue = plainIsSecret
Check("another addon's link or a secret one opens nothing", settingsPage.opened == nil)
Check("a secret link is checked before any comparison", secretGuarded)
ClickLink("addon:BetterTracking")
Check("a click on the link opens the settings", settingsPage.opened == 42)
settingsPage.opened = nil

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

print("tracking gate")
local realProbe = Minimap.UpdateMouseoverAtPoint
local probes = 0
Minimap.UpdateMouseoverAtPoint = function(...)
  probes = probes + 1
  return realProbe(...)
end

Fire("MINIMAP_UPDATE_TRACKING")
Tick(300)
Check("without a spell tracking the scan stays idle", probes == 0, probes .. " probes")

-- At login the tracking list can fill in after the zoning read, with no tracking event to follow.
tracking[3].active = true
Tick(60)
Check("a tracking the scan has not read yet keeps it idle", probes == 0, probes .. " probes")
Fire("SPELLS_CHANGED")
Tick(60)
Check("SPELLS_CHANGED reads it, and any spell tracking starts the scan", probes > 0, probes .. " probes")
Check("every probe hands the soft cursor back", Minimap.softCursor == false)

print("scan rate")

-- Probes over ten seconds, past the priming sweep, so both rates hold the same mix of ring and disc.
local function ProbesPerSecond(fps)
  Tick(2 * fps, 1 / fps)
  probes = 0
  Tick(10 * fps, 1 / fps)
  return probes / 10
end

local ringSize, discSize = #ns.RingPoints(), #ns.DiscPoints()
local expected = (ringSize * 4 + discSize) / 5
local slow, fast = ProbesPerSecond(30), ProbesPerSecond(144)
Check("the scan costs the same at 30 and 144 fps", math.abs(slow - fast) <= expected * 0.15, slow .. " vs " .. fast)
Check("the edge ring runs once a second with a full sweep every five", math.abs(fast - expected) <= expected * 0.15,
  fast .. " probes a second, expected " .. expected)
probes = 0
Tick(1, 5)
Check("a hitch never bursts into a whole sweep", probes <= discSize * 0.1 + 1, probes .. " probes")
Minimap.UpdateMouseoverAtPoint = realProbe

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

-- The tip and command checks share their helpers in one block, which keeps the main chunk under Lua's local limit.
do
  print("help tip")
  local function SwapTip()
    for _, frame in ipairs(frames) do
      if frame.template == "HelpTipTemplate" and frame.parent == Control("Swap Herbs and Minerals") then return frame end
    end
  end
  local function TipShown()
    local tip = SwapTip()
    return tip ~= nil and tip.shown and rawget(tip, "info") ~= nil
  end

  Check("no tip before the page shows", SwapTip() == nil)
  OpenPage()
  local tip = SwapTip()
  Check("the first show of the page shows the tip at the swap checkbox", TipShown()
    and tip.info.text == "Turn on Swap Herbs and Minerals to see herb and ore nodes on the minimap at once."
    and tip.info.buttonStyle == HelpTip.ButtonStyle.Close and tip.info.targetPoint == HelpTip.Point.RightEdgeCenter)
  OpenPage()
  ns.ReplayTip()
  Check("a refresh or a replay while it is up does not show it twice", tip.inits == 1, tip.inits)
  ClosePage()
  Check("it hides with the page without being marked", not TipShown() and ns.db.tipSeen == nil)
  OpenPage()
  Check("and shows again at the page's next show", TipShown() and tip.inits == 2)
  tip:Acknowledge()
  Check("its close button retires it for the account", not TipShown() and ns.db.tipSeen == true)
  ClosePage()
  OpenPage()
  Check("so the next show has no tip", not TipShown())

  ns.ReplayTip()
  Check("a replay brings it back at once on the open page", TipShown() and ns.db.tipSeen == nil)
  ClosePage()
  Check("and a tip closed once before still hides unmarked", ns.db.tipSeen == nil)
  OpenPage()
  Control("Swap Herbs and Minerals"):Click()
  Check("turning on the swap is the feature in use and retires it", not TipShown() and ns.db.tipSeen == true)
  Control("Swap Herbs and Minerals"):Click()
  ns.db.tipSeen = nil
  ClosePage()
  SlashCmdList.BETTERTRACKING("swap")
  Check("so does turning it on by command while the page is closed", ns.db.tipSeen == true)
  SlashCmdList.BETTERTRACKING("swap")
  OpenPage()
  Check("and the page shows no tip then", not TipShown())
  ClosePage()

  print("commands")
  local function Command(input)
    local before = #chat
    settingsPage.opened = nil
    SlashCmdList.BETTERTRACKING(input)
    return #chat - before, chat[#chat]
  end

  local lines, line = Command("")
  Check("the bare command opens the settings and says nothing", settingsPage.opened == 42 and lines == 0)
  lines, line = Command("help")
  Check("help prints one line naming every command", lines == 1 and settingsPage.opened == nil
    and line == PREFIX .. "Type /tra for the settings, /tra swap to turn the herb and ore swap on or off, /tra status "
    .. "to see what runs and why the swap waits, /tra test to play the alert, /tra reset to forget every node, /tra "
    .. "minimap to show or hide the minimap button, /tra intro to see the welcome line and the tip again, or /tra help "
    .. "for this list.", line)
  local helpLine = line
  lines, line = Command(" ? ")
  Check("and so does ?", lines == 1 and line == helpLine)
  lines, line = Command("intro")
  Check("intro prints the welcome line again", lines == 1 and line:find(WELCOME, 1, true) ~= nil, line)
  Check("and clears the tip's flag", ns.db.tipSeen == nil)
  OpenPage()
  Check("so the tip shows at the page's next show", TipShown())
  local initsBefore = SwapTip().inits
  Command("intro")
  Check("intro with the page open keeps the one tip", TipShown() and SwapTip().inits == initsBefore,
    SwapTip().inits - initsBefore)
  ClosePage()
  Check("which still hides unmarked", ns.db.tipSeen == nil)
  lines, line = Command("sawp")
  Check("an unknown word prints the hint and opens nothing", lines == 1 and settingsPage.opened == nil
    and line == PREFIX .. "Unknown command. Type /tra help for the list.", line)
  settingsPage.opened = nil
end

print("settings panel")
Check("the canvas page registers at login", settingsPage.registered and settingsPage.title == "Better Tracking")
Check("it starts hidden, so the Settings window's first show reaches every control", not settingsPage.frame.shown)
OpenPage()

-- These keys are state, not preferences, so the page's Defaults button must never reach them.
local STATE_KEYS = { space = true, paused = true, minimap = true }

local bound, labels = {}, {}
for _, row in ipairs(PageRows()) do
  bound[row.frame.key] = true
  labels[#labels + 1] = row.label.text
end
local unbound, stateBound = {}, {}
for key in pairs(ns.defaults) do
  if STATE_KEYS[key] and bound[key] then stateBound[#stateBound + 1] = key end
  if not STATE_KEYS[key] and not bound[key] then unbound[#unbound + 1] = key end
end
table.sort(unbound)
Check("every saved preference has a control", #unbound == 0, table.concat(unbound, ", "))
Check("the state keys have none, so Defaults cannot clear them", #stateBound == 0, table.concat(stateBound, ", "))
Check("the rows run swap, alert, minimap nodes, GatherMate2", table.concat(labels, "|") == "Swap Herbs and Minerals|"
  .. "Swap Every|Play a Sound|Sound|Flash the Minimap Edge|Cooldown|Alert on Minimap Nodes|Gathering Nodes Only|"
  .. "Rares and Treasures|Also Ping at Spots GatherMate2 Remembers|Node Types", table.concat(labels, "|"))

local untipped = {}
for _, row in ipairs(PageRows()) do
  local control = row.control
  local slider = rawget(control, "Slider")
  local controlTip = rawget(control, "tooltip") or control.hooks.OnEnter or (slider and slider.hooks.OnEnter)
  if not (row.frame.scripts.OnEnter and controlTip) then untipped[#untipped + 1] = row.label.text end
end
Check("every row and every control has a tooltip", #untipped == 0, table.concat(untipped, ", "))

Check("the swap interval is a dependent row offering 2 and 4 seconds", IsIndented("Swap Every")
  and #Control("Swap Every"):Entries() == 2 and IsGreyed("Swap Every") and not IsIndented("Swap Herbs and Minerals"))
Check("the swap tooltip names the global cooldown and the middle click",
  RowTooltip("Swap Herbs and Minerals"):find("global cooldown", 1, true)
  and RowTooltip("Swap Herbs and Minerals"):find("Middle-click", 1, true))
local soundsBefore = uiSounds
Control("Swap Herbs and Minerals"):Click()
Check("the swap checkbox starts the ticker", LiveTickers() == 1 and ns.db.swap, LiveTickers())
Check("with Blizzard's checkbox sound", uiSounds == soundsBefore + 1)
Check("and wakes its dependent row", IsLive("Swap Every"))
Control("Swap Every"):Pick("2 Seconds")
Check("a pick in the swap interval saves it", ns.db.swapInterval == 2 and Control("Swap Every"):Text() == "2 Seconds")
Control("Swap Every"):Pick("4 Seconds")
Row("Swap Herbs and Minerals").frame.scripts.OnMouseUp(Row("Swap Herbs and Minerals").frame)
Check("a click on the label stops it again", LiveTickers() == 0 and not ns.db.swap, LiveTickers())

Check("the sound dropdown offers all six sounds", #Control("Sound"):Entries() == #ns.sounds)
alerts = {}
Control("Sound"):Pick("Raid Warning")
Check("picking a sound saves and previews it", ns.db.soundId == SOUNDKIT.RAID_WARNING and alerts[1] == SOUNDKIT.RAID_WARNING
  and Control("Sound"):Text() == "Raid Warning", Control("Sound"):Text())

Control("Play a Sound"):Click()
local greyedOut = IsGreyed("Sound") and not ns.db.sound
Control("Play a Sound"):Click()
Check("the sound picker greys out while the sound is off", greyedOut and IsLive("Sound") and ns.db.sound)
Check("minimap rows depend on their switch", IsIndented("Gathering Nodes Only") and IsIndented("Rares and Treasures")
  and not IsIndented("Alert on Minimap Nodes"))
if not ns.db.blips then Control("Alert on Minimap Nodes"):Click() end
Control("Alert on Minimap Nodes"):Click()
Check("and grey out with it", IsGreyed("Gathering Nodes Only") and IsGreyed("Rares and Treasures"))
Control("Gathering Nodes Only"):Click()
Check("a greyed checkbox takes no click", ns.db.objectsOnly)
Control("Alert on Minimap Nodes"):Click()

local cooldown = Control("Cooldown")
Check("the cooldown reads in seconds from 1 to 30", cooldown.formatters[MinimalSliderWithSteppersMixin.Label.Right](3) == "3 s"
  and cooldown.minimum == 1 and cooldown.maximum == 30 and cooldown.steps == 29)
cooldown:SetValue(10)
Check("moving the slider saves the cooldown", ns.db.cooldown == 10)

local picker = Control("Node Types")
local function Picked() return picker:Text() end
Check("the node types list only GatherMate2's Forever types", picker and #picker:Entries() == 2,
  picker and #picker:Entries())
Check("every type starts ticked", Picked() == "All", Picked())
picker:Pick("Mining")
Check("unticking a type mutes only that one", ns.db.mutedTypes.Mining and not ns.db.mutedTypes["Herb Gathering"])
Check("a partial pick lists the ticked names", Picked() == "Herb Gathering", Picked())
picker:Pick("Herb Gathering")
Check("no pick reads None", Picked() == "None", Picked())
picker:Pick("Herb Gathering")
Check("node types depend on the GatherMate2 switch", IsIndented("Node Types") and IsLive("Node Types"))
Control("Also Ping at Spots GatherMate2 Remembers"):Click()
Check("and grey out with it", IsGreyed("Node Types") and not ns.db.gatherMate)
Control("Also Ping at Spots GatherMate2 Remembers"):Click()

Control("Alert on Minimap Nodes"):Click()
ns.db.paused = true
alerts = {}
PressDefaults()
local drifted = {}
for key, value in pairs(ns.defaults) do
  if type(value) ~= "table" and not STATE_KEYS[key] and ns.db[key] ~= value then drifted[#drifted + 1] = key end
end
table.sort(drifted)
Check("Defaults restore every setting", #drifted == 0 and next(ns.db.mutedTypes) == nil, table.concat(drifted, ", "))
Check("and the controls show them", Control("Alert on Minimap Nodes").checked == ns.defaults.blips
  and cooldown.value == ns.defaults.cooldown and Picked() == "All" and IsGreyed("Node Types"))
Check("Defaults keep the calibration and the pause", ns.db.space == "center" and ns.db.paused, tostring(ns.db.space))
Check("Defaults play nothing", #alerts == 0, #alerts .. " sounds")
ns.db.paused = false

-- A page closed while something else changes reads it again on its next show.
ClosePage()
ns.db.flash = false
OpenPage()
Check("the page reads its values on every show", Control("Flash the Minimap Edge").checked == false)
ns.db.flash = true
OpenPage()

alerts = {}
SlashCmdList.BETTERTRACKING("test")
Check("/tra test plays the alert sound", alerts[1] == ns.db.soundId, tostring(alerts[1]))
SlashCmdList.BETTERTRACKING("recalibrate")
Check("/tra recalibrate clears the space", ns.db.space == false)
ns.db.space = "center"

ns.db.gatherMate = true
ns.ResetSeen()
Tick(600)
local remembered = ns.SeenCount()
SlashCmdList.BETTERTRACKING("probe")
local probeHits, probeWanted = chat[#chat]:match("Probe: (%d+) of %d+ points hit a blip, (%d+) pass the filter")
Check("/tra probe sweeps the minimap and counts the blips", tonumber(probeHits or 0) > 0
  and probeHits == probeWanted and chat[#chat]:find("Tracking on: yes", 1, true) ~= nil, chat[#chat])
Minimap.mouseIsOver = true
SlashCmdList.BETTERTRACKING("probe")
Minimap.mouseIsOver = false
Check("and asks for the cursor off the minimap first", chat[#chat]:find("Move the cursor off the minimap", 1, true) ~= nil, chat[#chat])
clock = clock + 5
hooks.addMiniPin(display, Pin("Mining", 4242, true))
local circles = ns.GatherMateSeenCount()
SlashCmdList.BETTERTRACKING("status")
Check("status counts both sources", chat[#chat]:find("Nodes remembered: " .. (remembered + circles), 1, true) ~= nil, chat[#chat])
SlashCmdList.BETTERTRACKING("reset")
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
settingsPage.opened = nil
Check("a left click in combat waits", not settingsPage.opened and chat[#chat] == PREFIX .. "Opens after combat.", chat[#chat])
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
Check("and opens the category once combat ends", settingsPage.opened == 42)

SlashCmdList.BETTERTRACKING("minimap")
Check("/tra minimap hides the button and says how to bring it back", not icons["Better Tracking"].shown and ns.db.minimap.hide
  and chat[#chat] == PREFIX .. "Minimap button hidden. Type /tra minimap to show it again.", chat[#chat])
SlashCmdList.BETTERTRACKING("minimap")
Check("and shows it again", icons["Better Tracking"].shown and chat[#chat] == PREFIX .. "Minimap button shown.", chat[#chat])

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
SlashCmdList.BETTERTRACKING("swap")
Check("/tra swap turns it on with one line", ns.db.swap and LiveTickers() == 1
  and chat[#chat] == PREFIX .. "Herb and ore swap on.", chat[#chat])
Check("and the open settings page ticks its checkbox", Control("Swap Herbs and Minerals").checked == true)

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
  and chat[#chat] == PREFIX .. "Herb and ore swap off.", chat[#chat])
tracking[2].spellID = 99999
ClickLauncher("MiddleButton")
Check("a middle click turns it on and says when a spell is missing", ns.db.swap and LiveTickers() == 1
  and chat[#chat] == PREFIX .. "Herb and ore swap needs Find Herbs and Find Minerals.", chat[#chat])
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
  == PREFIX .. "Herb and ore swap stays off until you type /reload, because Blizzard blocks it.", chat[#chat])
blockEvent = "ADDON_ACTION_BLOCKED"
blockTimed, blockAll = false, false
ns.db.swap = false

print("without gathermate2")
loaded.GatherMate2, _G.LibStub, hooks = nil, nil, {}
ns.db.space = false
local linesBefore = #chat
local bare = LoadAddon()
bare.db.space = "center"
Check("the GatherMate2 source stays detached", not bare.gatherMateReady and hooks.addMiniPin == nil)
Check("it offers no node types", #bare.GatherMateTypes() == 0)
bare.db.blips = true
Check("the page still builds", pcall(Login))
Check("a later load and login print no welcome", #chat == linesBefore, chat[#chat])
Check("without an empty node types row", Row("Node Types") == nil and Row("Also Ping at Spots GatherMate2 Remembers"))
Check("the GatherMate2 row is greyed", IsGreyed("Also Ping at Spots GatherMate2 Remembers"))
Check("and its tooltip says why", RowTooltip("Also Ping at Spots GatherMate2 Remembers"):find("Needs GatherMate2", 1, true) ~= nil)
Check("the minimap rows stay live", IsLive("Alert on Minimap Nodes") and IsLive("Gathering Nodes Only"))

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

print("native art")
local customArt = {}
for _, path in ipairs(TocFiles()) do
  if not path:find("^Libs/") and io.open(path):read("a"):find("AddOns\\\\", 1, true) then customArt[#customArt + 1] = path end
end
Check("no addon file draws art from its own folder", #customArt == 0, table.concat(customArt, ", "))

print("chat lines")
local unprefixed = {}
for _, line in ipairs(chat) do
  if line:sub(1, #PREFIX) ~= PREFIX then unprefixed[#unprefixed + 1] = line end
end
Check("every chat line starts with the gold title and a plain colon", #chat > 0 and #unprefixed == 0,
  table.concat(unprefixed, " | "))

print(failures == 0 and "\nall checks passed" or ("\n" .. failures .. " failing checks"))
os.exit(failures == 0 and 0 or 1)
