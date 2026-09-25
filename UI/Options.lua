local _, ns = ...

local NEEDS_GATHERMATE = "Needs GatherMate2 installed and enabled."

local category, layout, categoryID
local settings = {}
local nodeTypes = {}

local function IsOn(key)
  return function() return ns.db[key] end
end

local function IsGatherMateReady()
  return ns.gatherMateReady
end

-- Every control is a proxy over ns.db, so each saved key stays exactly what it was. Blizzard calls a proxy's
-- setter only when the value really changes, so a Defaults click that changes nothing fires no preview and
-- no GatherMate2 refresh. Settings.VarType names are Lua type names, so the default names the type.
local function RegisterSetting(key, name, default, get, set)
  local variable = "TRACKING_ALERT_" .. strupper(key)
  local setting = Settings.RegisterProxySetting(category, variable, type(default), name, default, get, set)
  settings[key] = setting
  return setting
end

local function SavedSetting(key, name, onChange)
  return RegisterSetting(key, name, ns.defaults[key],
    function() return ns.db[key] end,
    function(value)
      ns.db[key] = value
      if onChange then onChange() end
    end)
end

-- The saved value is a channel name, but the question a player answers is yes or no.
local function ChannelSetting()
  return RegisterSetting("channel", "Play while sound effects are muted", ns.defaults.channel == "Master",
    function() return ns.db.channel == "Master" end,
    function(value) ns.db.channel = value and "Master" or "SFX" end)
end

local function AddSlider(setting, minimum, maximum, format, tooltip)
  local options = Settings.CreateSliderOptions(minimum, maximum, 1)
  options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
  return Settings.CreateSlider(category, setting, options, tooltip)
end

local function AddHeader(name, tooltip)
  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, tooltip))
end

local function AddButton(name, text, onClick, tooltip)
  local addSearchTags = true
  layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, addSearchTags))
end

local function FormatSeconds(value)
  return SECOND_ONELETTER_ABBR:format(value)
end

local function SoundOptions()
  local container = Settings.CreateControlTextContainer()
  for _, sound in ipairs(ns.sounds) do container:Add(sound.id, sound.name) end
  return container:GetData()
end

local function PreviewThickness()
  ns.ApplyThickness()
  ns.Flash()
end

local function BuildAlertSection()
  AddHeader("Alert", "Shared by both sources.")

  local sound = Settings.CreateCheckbox(category, SavedSetting("sound", "Play a sound"), "Plays a sound on each alert.")
  local soundPicker = Settings.CreateDropdown(category, SavedSetting("soundId", "Sound", ns.PlayAlertSound),
    SoundOptions, "One of six game sounds. Picking one plays it.")
  soundPicker:SetParentInitializer(sound, IsOn("sound"))
  local channel = Settings.CreateCheckbox(category, ChannelSetting(),
    "Plays on the Master channel, so the alert comes through with sound effects turned off.")
  channel:SetParentInitializer(sound, IsOn("sound"))

  local flash = Settings.CreateCheckbox(category, SavedSetting("flash", "Flash the minimap edge"),
    "Flashes a ring around the minimap: gold for a minimap node, the circle's own colour for GatherMate2. Leave the sound off for a silent alert.")
  local thickness = AddSlider(SavedSetting("flashThickness", "Flash thickness", PreviewThickness), 1, 10, nil,
    "From a hairline at 1 to bold at 10.")
  thickness:SetParentInitializer(flash, IsOn("flash"))

  AddSlider(SavedSetting("cooldown", "Cooldown"), 1, 30, FormatSeconds,
    "Shortest gap between two alerts. A node noticed during the cooldown stays silent, so a cluster is one alert.")
  AddButton("Preview", "Test", ns.PreviewAlert, "Plays the alert sound and flashes the minimap edge.")
end

local function CalibrateText()
  return ns.db.space and "Recalibrate" or "Calibrate"
end

-- A settings row has no status line, so the live calibration state leads the tooltip, which is built on
-- every hover.
local function CalibrationTooltip()
  local label = ns.SpaceLabel()
  local status = label and ("Calibrated to " .. label .. ".") or "Not calibrated yet."
  return status .. "\n\nHover a tracked blip near the minimap edge for a second and the addon works out how to"
    .. " read the minimap. The button forgets the result, so the next hover detects it again."
end

-- The cursor is on this panel, not on a blip, so the button can only clear the old result and leave the
-- detection to the next hover. The row reads its text once when shown, so the click updates it.
local function OnCalibrate(button)
  ns.Recalibrate()
  button:SetText(CalibrateText())
end

local function NodesTooltip()
  return ("Forgets every node the minimap source remembers, %d right now, so each alerts again the next time it"
    .. " comes into range."):format(ns.SeenCount())
end

local function ForgetNodes()
  ns.ResetSeen()
  ns.Print("forgot every remembered node.")
end

local function BuildBlipSection()
  AddHeader("Minimap nodes", "Pings when a tracked blip, such as Find Herbs or Find Minerals, first appears on the minimap.")

  local blips = Settings.CreateCheckbox(category, SavedSetting("blips", "Alert on minimap nodes"),
    "Scans the minimap for tracked blips and pings when a new one appears.")

  -- The sweep interval and probe budget trade latency against work per frame, so a low-end machine can
  -- halve the budget and still catch every node.
  local children = {
    Settings.CreateCheckbox(category, SavedSetting("requireMovement", "Only while moving"),
      "A blip can only cross the minimap edge while you move, so standing still skips the scan entirely."),
    Settings.CreateCheckbox(category, SavedSetting("objectsOnly", "Gathering nodes only"),
      "Ping only for blips whose tooltip is a world object. Turn off to ping for every blip, including townsfolk and other players."),
    Settings.CreateCheckbox(category, SavedSetting("vignettes", "Also alert on vignettes"),
      "Alert on rares and treasures that report themselves through the vignette system."),
    AddSlider(SavedSetting("discInterval", "Full sweep"), 1, 20, FormatSeconds,
      "How often the whole minimap is swept. Catches nodes that spawn inside the radius rather than crossing the edge."),
    AddSlider(SavedSetting("probeBudget", "Probes per frame"), 2, 24, nil,
      "How many points are tested each frame. Lower is cheaper and slower to react."),
  }
  for _, child in ipairs(children) do child:SetParentInitializer(blips, IsOn("blips")) end

  AddButton("Calibration", CalibrateText, OnCalibrate, CalibrationTooltip)
  AddButton("Remembered nodes", "Reset", ForgetNodes, NodesTooltip)
end

-- Blizzard's settings dropdown stores a multi-select as a bitmask with one bit per option, so the saved set
-- of muted types is shown as a mask over GatherMate2's own type list.
local function TypeBit(index)
  return bit.lshift(1, index - 1)
end

local function TypeMask()
  local mask = 0
  for index, nodeType in ipairs(nodeTypes) do
    if not ns.db.mutedTypes[nodeType] then mask = bit.bor(mask, TypeBit(index)) end
  end
  return mask
end

-- Rebuilt from scratch, so a type that GatherMate2 no longer has does not stay muted forever.
local function SetTypeMask(mask)
  wipe(ns.db.mutedTypes)
  for index, nodeType in ipairs(nodeTypes) do
    if bit.band(mask, TypeBit(index)) == 0 then ns.db.mutedTypes[nodeType] = true end
  end
end

local function TypeOptions()
  local container = Settings.CreateControlTextContainer()
  for index, nodeType in ipairs(nodeTypes) do container:AddCheckbox(index, nodeType) end
  return container:GetData()
end

-- Nil falls back to Blizzard's own list of the ticked names.
local function TypeSelectionText(selections)
  if #selections == 0 then return NONE end
  if #selections == #nodeTypes then return ALL end
end

-- Without GatherMate2 there are no types to list, so the row is left out instead of shown empty.
local function AddTypePicker(parent)
  nodeTypes = ns.GatherMateTypes()
  if #nodeTypes == 0 then return end

  local allTypes = TypeBit(#nodeTypes + 1) - 1
  local setting = RegisterSetting("mutedTypes", "Node types", allTypes, TypeMask, SetTypeMask)
  local picker = Settings.CreateDropdown(category, setting, TypeOptions, "Which GatherMate2 node types alert. All do by default.")
  picker.getSelectionTextFunc = TypeSelectionText
  picker:SetParentInitializer(parent, IsOn("gatherMate"))
end

local function GatherMateTooltip(text)
  if ns.gatherMateReady then return text end
  return text .. "\n\n" .. RED_FONT_COLOR:WrapTextInColorCode(NEEDS_GATHERMATE)
end

-- GatherMate2 attaches on its own ADDON_LOADED, before login, so readiness is settled by the time this
-- runs. Its rows stay visible but greyed without it, so the source can be found.
local function BuildGatherMateSection()
  local summary = "Pings when GatherMate2 turns a nearby node into a tracking circle."
  AddHeader("GatherMate2", ns.gatherMateReady and summary or NEEDS_GATHERMATE)

  local circles = Settings.CreateCheckbox(category, SavedSetting("gatherMate", "Alert on GatherMate2 circles"),
    GatherMateTooltip(summary))
  AddTypePicker(circles)

  local rows = {
    circles,
    Settings.CreateCheckbox(category, SavedSetting("hideIcons", "Hide node icons", ns.RefreshGatherMate),
      GatherMateTooltip("Hides GatherMate2's far node icons. Tracking circles for nearby nodes stay, so the alert keeps working.")),
    Settings.CreateCheckbox(category, SavedSetting("mergeCircles", "Merge stacked circles into one", ns.RefreshGatherMate),
      GatherMateTooltip("Overlapping circles show as one. A cluster of mixed node types turns gold.")),
    AddSlider(SavedSetting("circleSize", "Circle size", ns.RefreshGatherMate), 1, 10, nil,
      GatherMateTooltip("GatherMate2's own circle size at 1, larger above.")),
  }
  for _, row in ipairs(rows) do row:AddModifyPredicate(IsGatherMateReady) end
end

-- The calibration is not a registered setting, so the panel's Defaults button leaves it alone. It is a
-- fact about the client, not a preference.
local function Register()
  category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
  BuildAlertSection()
  BuildBlipSection()
  BuildGatherMateSection()
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
end

EventUtil.ContinueOnPlayerLogin(Register)

function ns.OpenOptions()
  if categoryID then Settings.OpenToCategory(categoryID) end
end

-- A change made outside the panel, such as the compartment toggle, reaches a control on screen only once
-- its setting is told to read the saved value again.
function ns.RefreshOptions(...)
  for index = 1, select("#", ...) do
    local setting = settings[select(index, ...)]
    if setting then setting:NotifyUpdate() end
  end
end

local function ReportTypes()
  local names = {}
  for value in pairs(ns.observedTypes) do
    names[#names + 1] = tostring(value)
  end

  if #names == 0 then
    ns.Print("no blip tooltips seen yet.")
  else
    table.sort(names)
    ns.Print("tooltip types seen on blips: " .. table.concat(names, ", ") .. ".")
  end
end

SLASH_TRACKINGALERT1, SLASH_TRACKINGALERT2 = "/trackingalert", "/tra"
function SlashCmdList.TRACKINGALERT(input)
  local command = strlower(strtrim(input or ""))

  if command == "calibrate" then
    local ok, detail = ns.CalibrateFromCursor()
    if not ok then ns.Print("calibration failed: " .. detail) end

  elseif command == "status" then
    ns.Print(("alerts %s, coordinate space %s, %d nodes remembered, GatherMate2 %s."):format(
      ns.AlertsOn() and "on" or "off", ns.SpaceLabel() or "not calibrated", ns.SeenCount(),
      ns.gatherMateReady and "attached" or "not attached"))

  elseif command == "types" then
    ReportTypes()

  elseif command == "reset" then
    ForgetNodes()

  elseif command == "recalibrate" then
    ns.Recalibrate()

  elseif command == "test" then
    ns.PreviewAlert()

  else
    ns.OpenOptions()
  end
end
