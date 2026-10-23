local _, ns = ...

local NEEDS_GATHERMATE = "Needs GatherMate2 installed and enabled."

local category, layout, categoryID
local nodeTypes = {}

local function IsOn(key)
  return function() return ns.db[key] end
end

local function IsGatherMateReady()
  return ns.gatherMateReady
end

-- Every control is a proxy over ns.db, so each saved key stays exactly what it was. Blizzard calls a proxy's
-- setter only when the value really changes, so a Defaults click that changes nothing plays no sound
-- preview. Settings.VarType names are Lua type names, so the default names the type.
local function RegisterSetting(key, name, default, get, set)
  local variable = "BETTER_TRACKING_" .. strupper(key)
  return Settings.RegisterProxySetting(category, variable, type(default), name, default, get, set)
end

local function SavedSetting(key, name, onChange)
  return RegisterSetting(key, name, ns.defaults[key],
    function() return ns.db[key] end,
    function(value)
      ns.db[key] = value
      if onChange then onChange() end
    end)
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

local function BuildAlertSection()
  AddHeader("Alert", "Shared by both sources.")

  local sound = Settings.CreateCheckbox(category, SavedSetting("sound", "Play a Sound"),
    "Plays a sound on each alert, on the Master channel, so it comes through with sound effects turned off.")
  local soundPicker = Settings.CreateDropdown(category, SavedSetting("soundId", "Sound", ns.PlayAlertSound),
    SoundOptions, "One of six game sounds. Picking one plays it.")
  soundPicker:SetParentInitializer(sound, IsOn("sound"))

  Settings.CreateCheckbox(category, SavedSetting("flash", "Flash the Minimap Edge"),
    "Flashes a ring around the minimap: gold for a minimap node, the circle's own colour for GatherMate2. Leave the sound off for a silent alert.")

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
  local status = ns.db.space and "Minimap alerts are ready." or "Not calibrated yet."
  return status .. "\n\nHover a tracked blip near the minimap edge for a second and the addon works out how to"
    .. " read the minimap. The button forgets the result, so the next hover detects it again."
end

-- The cursor is on this panel, not on a blip, so the button can only clear the old result and leave the
-- detection to the next hover. With nothing to clear it says how to start. The row reads its text once
-- when shown, so the click updates it.
local function OnCalibrate(button)
  if ns.db.space then
    ns.Recalibrate()
  else
    ns.Print(ns.HOVER_HINT)
  end
  button:SetText(CalibrateText())
end

local function NodesTooltip()
  return ("Forgets every node both sources remember, %d right now, so each alerts again the next time it"
    .. " comes into range."):format(ns.SeenCount() + ns.GatherMateSeenCount())
end

local function ForgetNodes()
  ns.ResetSeen()
  ns.ResetGatherMateSeen()
  ns.Print("Forgot every remembered node.")
end

local function BuildBlipSection()
  AddHeader("Minimap Nodes", "Pings when a tracked blip, such as Find Herbs or Find Minerals, first appears on the minimap.")

  local blips = Settings.CreateCheckbox(category, SavedSetting("blips", "Alert on Minimap Nodes"),
    "Scans the minimap for tracked blips while you move and pings when a new one appears.")

  local children = {
    Settings.CreateCheckbox(category, SavedSetting("objectsOnly", "Gathering Nodes Only"),
      "Skips blips that the game marks as a unit, such as townsfolk and other players. Turn off to ping for every blip."),
    Settings.CreateCheckbox(category, SavedSetting("vignettes", "Rares and Treasures"),
      "Pings when a rare or treasure shows on the minimap."),
  }
  for _, child in ipairs(children) do child:SetParentInitializer(blips, IsOn("blips")) end

  AddButton("Calibration", CalibrateText, OnCalibrate, CalibrationTooltip)
  AddButton("Remembered Nodes", RESET, ForgetNodes, NodesTooltip)
end

local function IntervalOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add(2, "2 Seconds")
  container:Add(4, "4 Seconds")
  return container:GetData()
end

local function BuildSwapSection()
  AddHeader("Herb and Ore Swap", "Alternates Find Herbs and Find Minerals while you move, so both node types show on the minimap.")

  local swap = Settings.CreateCheckbox(category, SavedSetting("swap", "Swap Herbs and Minerals", ns.ApplySwap),
    "Casts Find Herbs and Find Minerals in turn while you move, so the minimap shows both and each new node"
    .. " pings. Each swap costs a global cooldown. It waits in combat, while dead, on a flight, in an instance,"
    .. " in a town or inn, while standing still, casting or looting, while an enemy is targeted or under the"
    .. " cursor and while another tracking is on. Middle-click the minimap button to turn it on or off.")
  local interval = Settings.CreateDropdown(category, SavedSetting("swapInterval", "Swap Every"), IntervalOptions,
    "How long each tracking stays on before the swap.")
  interval:SetParentInitializer(swap, IsOn("swap"))
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
  local setting = RegisterSetting("mutedTypes", "Node Types", allTypes, TypeMask, SetTypeMask)
  local picker = Settings.CreateDropdown(category, setting, TypeOptions, "Which GatherMate2 node types ping. All do by default.")
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
  local summary = "Pings when you come near a spot GatherMate2 has recorded, even if the node is gone."
    .. " Useful for a second profession you are not tracking."
  AddHeader("GatherMate2", ns.gatherMateReady and summary or NEEDS_GATHERMATE)

  local spots = Settings.CreateCheckbox(category,
    SavedSetting("gatherMate", "Also Ping at Spots GatherMate2 Remembers"), GatherMateTooltip(summary))
  spots:AddModifyPredicate(IsGatherMateReady)
  AddTypePicker(spots)
end

-- The calibration is not a registered setting, so the panel's Defaults button leaves it alone. It is a
-- fact about the client, not a preference.
local function Register()
  category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)

  -- The swap leads, because tracking both node types is what most players open the page for.
  BuildSwapSection()
  BuildAlertSection()
  BuildBlipSection()
  BuildGatherMateSection()
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
end

EventUtil.ContinueOnPlayerLogin(Register)

local waitingForCombat = false

function ns.OpenOptions()
  if not categoryID then return end

  -- C_SettingsUtil.OpenSettingsPanel is documented HasRestrictions (SettingsUtilDocumentation.lua:17) without
  -- saying which, most likely combat (UNVERIFIED), so a request made in combat waits for it to end.
  if InCombatLockdown() then
    ns.Print("Opens after combat.")
    if not waitingForCombat then
      waitingForCombat = true
      EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
        waitingForCombat = false
        ns.OpenOptions()
      end)
    end
    return
  end

  Settings.OpenToCategory(categoryID)
end

local function ReportTypes()
  local names = {}
  for value in pairs(ns.observedTypes) do
    names[#names + 1] = tostring(value)
  end

  if #names == 0 then
    ns.Print("No blip tooltips seen yet.")
  else
    table.sort(names)
    ns.Print("Tooltip types seen on blips: " .. table.concat(names, ", ") .. ".")
  end
end

SLASH_BETTERTRACKING1, SLASH_BETTERTRACKING2 = "/bettertracking", "/tra"
function SlashCmdList.BETTERTRACKING(input)
  local command = strlower(strtrim(input or ""))

  if command == "calibrate" then
    ns.CalibrateNow()

  elseif command == "status" then
    ns.Print(("%s %s Minimap reading: %s. Nodes remembered: %d. Last alert: %s. GatherMate2 %s."):format(
      ns.StatusText(), ns.SwapStatusText(), ns.SpaceLabel() or "not calibrated",
      ns.SeenCount() + ns.GatherMateSeenCount(), ns.lastAlertName or NONE,
      ns.gatherMateReady and "attached" or "not attached"))

  elseif command == "swap" then
    ns.ToggleSwap()

  elseif command == "minimap" then
    ns.ToggleMinimap()

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
