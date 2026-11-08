local _, ns = ...

-- A dependent row, one that only applies while the row above it is on, indents its label by the settings list's
-- own indent (Blizzard_SettingControls.lua:1, 359) and greys out while its parent is off.
local CHILD_INDENT = 15

-- Every control starts at one left edge, the row's CENTER -40. The dropdown is 220 wide (Blizzard_SettingControls.lua
-- :839), the slider 250 wide and 3 up, as Blizzard's slider row (:715).
local CONTROL_X = -40
local DROPDOWN_WIDTH = 220
local SLIDER_WIDTH, SLIDER_Y = 250, 3

local NEEDS_GATHERMATE = "Needs GatherMate2 installed and enabled."
local TIP_TEXT = "Turn on Swap Herbs and Minerals to see herb and ore nodes on the minimap at once."

local INTRO = "Swaps Find Herbs and Find Minerals while you move, so the minimap shows both, and pings once for "
  .. "each new node, rare or treasure that shows up on it. Each swap costs a global cooldown.\n\n"
  .. "Minimap alerts start once a tracking spell is on and you hover a blip near the minimap edge. The tracking "
  .. "menu, the minimap and its blips stay the game's own."

-- Every row with its saved key, control and refresh, in page order. Defaults restores exactly these keys, so the
-- calibration, the pause and the minimap button position stay as they are.
local rows = {}
local swapCheckbox, showSwapTip, retireSwapTip

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
local function CreateText(parent, fontObject, layer)
  local text = parent:CreateFontString(nil, layer or "ARTWORK")
  text:SetFontObject(fontObject or GameFontHighlight)
  text:SetJustifyH("LEFT")
  return text
end

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
local function AttachTooltip(frame, fill, anchor)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Blizzard's menu dropdown, filled with SetupMenu. Its art hangs 8 px past each side, so the caller indents it by 8.
local function CreateDropdown(parent, width, name)
  local dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
  dropdown:SetWidth(width or 160)
  return dropdown
end

-- The slider Blizzard's own settings use. Its Init takes a step count, not a step size.
local function CreateSlider(parent, width, name)
  local slider = CreateFrame("Frame", name, parent, "MinimalSliderWithSteppersTemplate")
  slider:SetWidth(width)
  return slider
end

-- The addon's page in Blizzard's Settings window, as its own canvas, copying the settings list's look
-- (Blizzard_SettingsList.xml:14-30, Blizzard_SettingControls.xml, Blizzard_SettingControls.lua). Never a settings
-- list: a pick in a list dropdown runs addon code in Blizzard's pooled controls and taints its settings until /reload.
-- The 2026-10-21 stress test saw exactly that as nameplate errors naming this addon.
local ROW_HEIGHT, ROW_SPACING, LABEL_X, INTRO_Y, INTRO_GAP = 26, 9, 37, -64, 16
local categoryID

local function BuildPanel(introText, restoreDefaults)
  local panel = CreateFrame("Frame")
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
  title:SetJustifyH("LEFT")
  title:SetPoint("TOPLEFT", 7, -22)
  title:SetText(ns.title)
  local divider = panel:CreateTexture(nil, "ARTWORK")
  divider:SetAtlas("Options_HorizontalDivider", true)
  divider:SetPoint("TOP", 0, -50)
  local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  defaults:SetSize(96, 22)
  defaults:SetPoint("TOPRIGHT", -36, -16)
  defaults:SetText(SETTINGS_DEFAULTS)
  defaults:SetScript("OnClick", restoreDefaults)
  panel.intro = CreateText(panel, GameFontHighlight)
  panel.intro:SetPoint("TOPLEFT", LABEL_X, INTRO_Y)
  panel.intro:SetPoint("TOPRIGHT", -LABEL_X, INTRO_Y)
  panel.intro:SetText(introText)
  return panel
end

-- One row below the intro, its label in GameFontNormal from x 37 to the row's centre less 85. A checkbox
-- (SettingsCheckboxTemplate) goes at the row's CENTER -80, a WowStyle1DropdownTemplate 220 wide at CENTER -48.
-- Within one page, controls share one left edge.
local function AddRow(panel, index, label, fillTooltip)
  local y = -INTRO_GAP - (index - 1) * (ROW_HEIGHT + ROW_SPACING)
  local row = CreateFrame("Frame", nil, panel)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", panel.intro, "BOTTOMLEFT", -LABEL_X, y)
  row:SetPoint("TOPRIGHT", panel.intro, "BOTTOMRIGHT", LABEL_X, y)
  row:EnableMouse(true)
  AttachTooltip(row, fillTooltip)
  local text = CreateText(row, GameFontNormal)
  text:SetPoint("LEFT", LABEL_X, 0)
  text:SetPoint("RIGHT", row, "CENTER", -85, 0)
  text:SetText(label)
  row.label = text
  return row
end

local function RegisterPanel(panel)
  local category = Settings.RegisterCanvasLayoutCategory(panel, ns.title)
  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
end

-- Opening in combat waits for combat to end, since the settings panel's open path has restrictions.
local waitingForCombat = false
function ns.OpenSettings()
  if not categoryID then return end
  if InCombatLockdown() then
    ns.Print("Opens after combat.")
    if not waitingForCombat then
      waitingForCombat = true
      EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", function()
        waitingForCombat = false
        ns.OpenSettings()
      end)
    end
    return
  end
  Settings.OpenToCategory(categoryID)
end

-- Blizzard's yellow help tip, as an own HelpTipTemplate frame on its target, never HelpTip:Show, whose shared pool
-- would carry addon taint into the tips Blizzard shows later. It shows each time the target shows until the player
-- closes it or uses the feature, then never again on the account, and hides with its target without being marked.
-- Init leaves acknowledged set and only Blizzard's pool resets a tip (Blizzard_SharedXML/HelpTip.lua:419-431, 495,
-- 687), so Reset runs before every Init, or a tip closed once and brought back by /tra intro would count as seen
-- when it merely hides with its target.
local function AttachTip(target, text, targetPoint, relativeRegion)
  local tip
  local info = {
    text = text,
    buttonStyle = HelpTip.ButtonStyle.Close,
    targetPoint = targetPoint,
    onAcknowledgeCallback = function() ns.db.tipSeen = true end,
  }
  local function ShowTip()
    if ns.db.tipSeen or (tip and tip:IsShown()) then return end
    if not tip then
      tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
      tip.width = HelpTip.width
      tip:SetWidth(tip.width)
    end
    tip:Reset()
    tip:Init(target, info, relativeRegion or target)
    tip:Show()
  end
  target:HookScript("OnShow", ShowTip)
  if target:IsVisible() then ShowTip() end

  -- The player used the feature: the tip goes for good, shown or not.
  local function Retire()
    if tip and tip.info then tip:Acknowledge() else ns.db.tipSeen = true end
  end
  return ShowTip, Retire
end

local function HelpTooltip(label, help, errorText)
  return function(tooltip)
    GameTooltip_SetTitle(tooltip, label)
    GameTooltip_AddNormalLine(tooltip, help)
    local reason = errorText and errorText()
    if reason then GameTooltip_AddErrorLine(tooltip, reason) end
  end
end

-- A greyed row shows its label in grey and refuses input, as Blizzard's rows do while their parent is off
-- (SettingsListElementMixin:DisplayEnabled, Blizzard_SettingControls.lua:309-312).
local function Refresh()
  for _, row in ipairs(rows) do
    row.refresh()
    local enabled = not row.isEnabled or row.isEnabled()
    row.label:SetTextColor((enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
    row.control:SetEnabled(enabled)
  end
end

local function AddControl(row, key, control, refresh, isEnabled, indented)
  row.key, row.control, row.refresh, row.isEnabled = key, control, refresh, isEnabled
  if indented then row.label:SetPoint("LEFT", LABEL_X + CHILD_INDENT, 0) end
  rows[#rows + 1] = row
end

-- The checkbox Blizzard's settings list builds for a checkbox row (SettingsCheckboxControlMixin), on the page's own
-- canvas. Its hover shows the same help in SettingsTooltip, a click on the row's label ticks it, and every tick plays
-- Blizzard's checkbox sound, as the list's row does (Blizzard_SettingControls.lua:617-621, 656-663).
local function AddCheckboxRow(panel, spec)
  local fill = HelpTooltip(spec.label, spec.help, spec.errorText)
  local row = AddRow(panel, #rows + 1, spec.label, fill)
  local checkbox = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
  checkbox:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
  checkbox:Init(ns.db[spec.key], function() fill(SettingsTooltip) end)
  checkbox:RegisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, function(_, checked)
    PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    ns.db[spec.key] = checked
    if spec.onChange then spec.onChange(checked) end
    Refresh()
  end, row)
  row:SetScript("OnMouseUp", function()
    if checkbox:IsEnabled() then checkbox:Click() end
  end)
  AddControl(row, spec.key, checkbox, function() checkbox:SetValue(ns.db[spec.key]) end, spec.isEnabled, spec.indented)
  return checkbox
end

-- The menu is generated again on every show and refresh, so it always reads the saved value.
local function AddDropdownRow(panel, spec)
  local fill = HelpTooltip(spec.label, spec.help)
  local row = AddRow(panel, #rows + 1, spec.label, fill)
  local dropdown = CreateDropdown(row, DROPDOWN_WIDTH)
  dropdown:SetPoint("LEFT", row, "CENTER", CONTROL_X, 0)
  dropdown:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
  end)
  dropdown:HookScript("OnLeave", GameTooltip_Hide)
  if spec.selectionText then dropdown:SetSelectionText(spec.selectionText) end
  dropdown:SetupMenu(spec.setup)
  AddControl(row, spec.key, dropdown, function() dropdown:GenerateMenu() end, spec.isEnabled, spec.indented)
end

-- One radio per choice, the way Blizzard's settings dropdowns offer a single pick.
local function RadioSetup(key, choices, onPick)
  return function(_, rootDescription)
    for _, choice in ipairs(choices) do
      rootDescription:CreateRadio(choice.label,
        function() return ns.db[key] == choice.value end,
        function()
          ns.db[key] = choice.value
          if onPick then onPick() end
        end)
    end
  end
end

local function FormatSeconds(value)
  return SECOND_ONELETTER_ABBR:format(value)
end

local function AddSliderRow(panel, spec)
  local fill = HelpTooltip(spec.label, spec.help)
  local row = AddRow(panel, #rows + 1, spec.label, fill)
  local slider = CreateSlider(row, SLIDER_WIDTH)
  slider:SetPoint("LEFT", row, "CENTER", CONTROL_X, SLIDER_Y)
  slider:Init(ns.db[spec.key], spec.minimum, spec.maximum, spec.maximum - spec.minimum,
    { [MinimalSliderWithSteppersMixin.Label.Right] = spec.format })
  slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    ns.db[spec.key] = value
  end, row)
  -- The bar itself takes the mouse, and its template already sets OnEnter for its hover state.
  slider.Slider:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
  end)
  slider.Slider:HookScript("OnLeave", GameTooltip_Hide)
  AddControl(row, spec.key, slider, function() slider:SetValue(ns.db[spec.key]) end, spec.isEnabled, spec.indented)
end

local function IsOn(key)
  return function() return ns.db[key] end
end

local function BuildSwapRows(panel)
  swapCheckbox = AddCheckboxRow(panel, {
    key = "swap",
    label = "Swap Herbs and Minerals",
    help = "Casts Find Herbs and Find Minerals in turn while you move, so the minimap shows both and each new node"
      .. " pings. Each swap costs a global cooldown. It waits in combat, while dead, on a flight, in an instance,"
      .. " in a town or inn, while standing still, casting or looting, while an enemy is targeted or under the"
      .. " cursor and while another tracking is on. Middle-click the minimap button to turn it on or off.",
    onChange = function(checked)
      ns.ApplySwap()
      if checked then retireSwapTip() end
    end,
  })

  -- The tip points right, where the row has room, at the first thing a new player turns on. A swap that is already
  -- on is the feature in use.
  showSwapTip, retireSwapTip = AttachTip(swapCheckbox, TIP_TEXT, HelpTip.Point.RightEdgeCenter)
  if ns.db.swap then retireSwapTip() end

  AddDropdownRow(panel, {
    key = "swapInterval",
    label = "Swap Every",
    help = "How long each tracking stays on before the swap.",
    setup = RadioSetup("swapInterval", { { value = 2, label = "2 Seconds" }, { value = 4, label = "4 Seconds" } }),
    isEnabled = IsOn("swap"),
    indented = true,
  })
end

local function SoundChoices()
  local choices = {}
  for _, sound in ipairs(ns.sounds) do choices[#choices + 1] = { value = sound.id, label = sound.name } end
  return choices
end

local function BuildAlertRows(panel)
  AddCheckboxRow(panel, {
    key = "sound",
    label = "Play a Sound",
    help = "Plays a sound on each alert, on the Master channel, so it comes through with sound effects turned off.",
  })
  AddDropdownRow(panel, {
    key = "soundId",
    label = "Sound",
    help = "One of six game sounds. Picking one plays it.",
    setup = RadioSetup("soundId", SoundChoices(), ns.PlayAlertSound),
    isEnabled = IsOn("sound"),
    indented = true,
  })
  AddCheckboxRow(panel, {
    key = "flash",
    label = "Flash the Minimap Edge",
    help = "Flashes a ring around the minimap: gold for a minimap node, the circle's own colour for GatherMate2."
      .. " Leave the sound off for a silent alert.",
  })
  AddSliderRow(panel, {
    key = "cooldown",
    label = "Cooldown",
    help = "Shortest gap between two alerts. A node noticed during the cooldown stays silent, so a cluster is one alert.",
    minimum = 1,
    maximum = 30,
    format = FormatSeconds,
  })
end

local function BuildBlipRows(panel)
  AddCheckboxRow(panel, {
    key = "blips",
    label = "Alert on Minimap Nodes",
    help = "Scans the minimap for tracked blips, such as Find Herbs or Find Minerals, while you move and pings when"
      .. " a new one appears.",
  })
  AddCheckboxRow(panel, {
    key = "objectsOnly",
    label = "Gathering Nodes Only",
    help = "Skips blips that the game marks as a unit, such as townsfolk and other players. Turn off to ping for"
      .. " every blip.",
    isEnabled = IsOn("blips"),
    indented = true,
  })
  AddCheckboxRow(panel, {
    key = "vignettes",
    label = "Rares and Treasures",
    help = "Pings when a rare or treasure shows on the minimap.",
    isEnabled = IsOn("blips"),
    indented = true,
  })
end

-- Nil falls back to Blizzard's own list of the ticked names.
local function TypeSelectionText(selections, count)
  if #selections == 0 then return NONE end
  if #selections == count then return ALL end
end

-- GatherMate2 attaches on its own ADDON_LOADED, before login, so readiness is settled by the time this runs. Its
-- row stays visible but greyed without it, so the source can be found. Without GatherMate2 there are no types to
-- list, so the type row is left out instead of shown empty.
local function BuildGatherMateRows(panel)
  AddCheckboxRow(panel, {
    key = "gatherMate",
    label = "Also Ping at Spots GatherMate2 Remembers",
    help = "Pings when you come near a spot GatherMate2 has recorded, even if the node is gone. Useful for a second"
      .. " profession you are not tracking.",
    errorText = function() return not ns.gatherMateReady and NEEDS_GATHERMATE or nil end,
    isEnabled = function() return ns.gatherMateReady end,
  })

  local nodeTypes = ns.GatherMateTypes()
  if #nodeTypes == 0 then return end

  -- A type is saved as muted, so a type GatherMate2 adds later pings until the player unticks it.
  AddDropdownRow(panel, {
    key = "mutedTypes",
    label = "Node Types",
    help = "Which GatherMate2 node types ping. All do by default.",
    setup = function(_, rootDescription)
      for _, nodeType in ipairs(nodeTypes) do
        rootDescription:CreateCheckbox(nodeType,
          function() return not ns.db.mutedTypes[nodeType] end,
          function() ns.db.mutedTypes[nodeType] = not ns.db.mutedTypes[nodeType] or nil end)
      end
    end,
    selectionText = function(selections) return TypeSelectionText(selections, #nodeTypes) end,
    isEnabled = function() return ns.gatherMateReady and ns.db.gatherMate end,
    indented = true,
  })
end

local function RestoreDefaults()
  for _, row in ipairs(rows) do
    local value = ns.defaults[row.key]
    ns.db[row.key] = type(value) == "table" and CopyTable(value) or value
  end
  ns.ApplySwap()
  Refresh()
end

local page

-- The swap leads, because tracking both node types is what most players open the page for. No button rows: test,
-- recalibrate and reset stay on /tra. The page starts hidden, so the Settings window's first show of it fires OnShow
-- down to every control. The window calls OnRefresh on every show (Blizzard_SettingsPanel.lua:7-11), which picks up
-- a swap turned on or off by /tra swap or the minimap button.
EventUtil.ContinueOnPlayerLogin(function()
  page = BuildPanel(INTRO, RestoreDefaults)
  page:Hide()
  BuildSwapRows(page)
  BuildAlertRows(page)
  BuildBlipRows(page)
  BuildGatherMateRows(page)
  page.OnRefresh = Refresh
  Refresh()
  RegisterPanel(page)
end)

-- A page open beside the minimap button follows a swap toggle at once, and a swap turned on by /tra swap or the
-- minimap button is the feature the tip points at in use.
function ns.SwapChanged()
  if ns.db.swap then
    if retireSwapTip then retireSwapTip() else ns.db.tipSeen = true end
  end
  if page and page:IsVisible() then Refresh() end
end

-- /tra intro brings the tip back: now, if the swap row is on screen, else at its next show.
function ns.ReplayTip()
  ns.db.tipSeen = nil
  if swapCheckbox and swapCheckbox:IsVisible() then showSwapTip() end
end

local function ForgetNodes()
  ns.ResetSeen()
  ns.ResetGatherMateSeen()
  ns.Print("Forgot every remembered node.")
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

  elseif command == "probe" then
    ns.ProbeNow()

  elseif command == "reset" then
    ForgetNodes()

  elseif command == "recalibrate" then
    ns.Recalibrate()

  elseif command == "test" then
    ns.PreviewAlert()

  else
    ns.OpenSettings()
  end
end
