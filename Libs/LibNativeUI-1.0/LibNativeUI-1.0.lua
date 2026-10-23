-- LibNativeUI-1.0: a native UI design system for WoW Forever addons. Style tokens on a 4px grid, font
-- roles at 12 and 16 px on Blizzard's own font objects, and window, dialog, control and launcher builders
-- made only from Blizzard templates. Every addon embeds an identical copy; LibStub keeps the highest MINOR.
local MAJOR, MINOR = "LibNativeUI-1.0", 3
local UI = LibStub:NewLibrary(MAJOR, MINOR)
if not UI then return end

-- Every size, gap, padding, offset and width an addon chooses is a multiple of this grid.
UI.GRID = 4

-- Spacing roles. tight: label to control, hint under a field. gap: between related controls, heading to
-- body. padding: inside an inset. section: between sections. dialog and dialogTop: a dialog's side and
-- bottom padding, and its content top below the 28px of header art.
UI.Space = {
    tight = 4,
    gap = 8,
    padding = 16,
    section = 24,
    dialog = 20,
    dialogTop = 40,
}

-- Component slots on the grid. Blizzard templates keep their native heights centred inside a slot.
UI.Size = {
    row = 24,
    heading = 16,
    icon = 16,
    button = 128,
    dropdown = 160,
    input = 160,
}

-- Geometry Blizzard's templates fix themselves. These are the only values allowed off the grid.
UI.Native = {
    -- MagicButtonTemplate in a ButtonFrameTemplate bar (Mainline/SharedUIPanelTemplates.xml:750).
    buttonHeight = 22,

    -- InputBoxTemplate art height and its left cap outside the box (Shared/InputBox/InputBoxTemplates.xml:47-49).
    inputHeight = 20,
    inputArt = 5,

    -- WowStyle1DropdownTemplate art reaches 8px past each side (Blizzard_Menu/Mainline/MenuTemplates.xml:9-10).
    dropdownArt = 8,

    -- WowStyle1DropdownTemplate height (Blizzard_Menu/Mainline/MenuTemplates.xml:4).
    dropdownHeight = 25,

    -- MinimalSliderWithSteppersTemplate height (Shared/Slider/MinimalSlider.xml:35).
    sliderHeight = 40,

    -- ButtonFrameTemplate's TitleContainer starts here, so attic text lines up with the title
    -- (Mainline/SharedUIPanelTemplates.xml:603).
    titleLeft = 58,

    -- MinimalScrollBar width (Shared/Scroll/MinimalScrollBar.xml:16).
    scrollBarWidth = 8,
}

-- UIPanelCloseButton sits 2px in from a DialogBorderTemplate corner (Blizzard_Channels/Mainline/CreateChannelPopup.xml:72).
local DIALOG_CLOSE_INSET = 2

-- UIPanelButtonTemplate pads its text by 40px when it fits to it (SecureUIPanelTemplates.xml:42).
local BUTTON_TEXT_PADDING = 40

-- Fit-to-text buttons never get narrower than this, so short labels like "Add" keep a usable target.
local BUTTON_MIN_WIDTH = 64

-- Font roles on Blizzard's font objects: title 16, the rest 12. Title is only for a dialog's subject line.
UI.Font = {
    title = GameFontNormalLarge,
    heading = GameFontNormal,
    body = GameFontHighlight,
    muted = GameFontDisable,
}

-- Colour roles on Blizzard's colour objects, so text matches the game's own UI.
UI.Color = {
    heading = NORMAL_FONT_COLOR,
    body = HIGHLIGHT_FONT_COLOR,
    muted = GRAY_FONT_COLOR,
    good = GREEN_FONT_COLOR,
    bad = RED_FONT_COLOR,
    warn = WARNING_FONT_COLOR,
    prefix = YELLOW_FONT_COLOR,
}

-- Tool windows sit above the game UI and below Blizzard's popups and menus.
UI.Strata = {
    window = "HIGH",
    dialog = "DIALOG",
}

-- Rounds a length up to the next grid step, for sizes derived from text or content.
function UI.Snap(length)
    return math.ceil(length / UI.GRID) * UI.GRID
end

-- Space a ScrollFrameTemplate needs on its right: Forever hangs MinimalScrollBar off the frame's edge.
function UI.ScrollGutter()
    return UI.Snap(SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT + UI.Native.scrollBarWidth + UI.Space.gap)
end

-- One chat line in the shared voice: the yellow "[Addon Name]:" prefix, then the message.
function UI.Print(title, message)
    print(UI.Color.prefix:WrapTextInColorCode("[" .. title .. "]:") .. " " .. message)
end

-- A left-aligned font string in one of the font roles.
function UI.CreateText(parent, role, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(UI.Font[role or "body"])
    text:SetJustifyH("LEFT")
    return text
end

-- A content button one row tall. Without a width it fits its label the way the template's own
-- FitToText does, then snaps to 8 so neighbouring buttons share widths.
function UI.CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    if not width then
        local fitted = math.ceil((button:GetTextWidth() + BUTTON_TEXT_PADDING) / 8) * 8
        width = math.max(BUTTON_MIN_WIDTH, fitted)
    end
    button:SetSize(width, UI.Size.row)
    return button
end

-- The label's width joins the hit rect, so a click on the text toggles the box like a native option.
local function setCheckboxLabel(checkbox, label)
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(UI.Space.tight + checkbox.Text:GetStringWidth()), 0, 0)
end

-- CheckboxWithLabelTemplate: the minimal checkbox art Blizzard's Settings use, at the 24px AddonList
-- uses it (Blizzard_AddOnList/AddonList.xml:73-74). Change the label later through checkbox:SetLabel.
function UI.CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "CheckboxWithLabelTemplate")
    checkbox:SetSize(UI.Size.row, UI.Size.row)
    checkbox.Text:SetFontObject(UI.Font.body)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", UI.Space.tight, 0)
    checkbox.SetLabel = setCheckboxLabel
    setCheckboxLabel(checkbox, label or "")
    return checkbox
end

-- InputBoxTemplate draws its left cap UI.Native.inputArt px outside the box, so callers indent the box
-- by that much to line the art up with the column.
function UI.CreateEditBox(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width or UI.Size.input, UI.Native.inputHeight)
    box:SetAutoFocus(false)
    box:SetFontObject(UI.Font.body)
    return box
end

-- SearchBoxTemplate types and hints in 10px fonts; both move to the 12px roles. The hint keeps the grey the
-- template gives it (InputBoxTemplates.xml, InputBoxInstructionsTemplate), so its colour is read before the
-- font object changes and put back after.
function UI.CreateSearchBox(parent, width, name)
    local box = CreateFrame("EditBox", name, parent, "SearchBoxTemplate")
    box:SetSize(width or UI.Size.input, UI.Native.inputHeight)
    box:SetAutoFocus(false)
    box:SetFontObject(UI.Font.body)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(UI.Font.muted)
    box.Instructions:SetTextColor(r, g, b)
    return box
end

-- A DropdownButton on Blizzard's menu dropdown; callers fill it with SetupMenu. Its art hangs
-- UI.Native.dropdownArt px past each side, so callers indent it by that much.
function UI.CreateDropdown(parent, width, name)
    local dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width or UI.Size.dropdown)
    return dropdown
end

-- Blizzard's "Filter" button (Blizzard_Menu/Mainline/MenuTemplates.xml:66), as on the Who list. The
-- template sizes itself to its text; the width is fixed here, on the grid, so later text never moves it.
-- Callers set SetDefaultCallback and SetIsDefaultCallback before SetupMenu; the template then shows its
-- own reset button whenever the filters differ from the defaults.
function UI.CreateFilterDropdown(parent, width)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1FilterDropdownTemplate")
    dropdown.resizeToText = false
    dropdown:SetWidth(width or UI.Snap(dropdown:GetWidth()))
    return dropdown
end

-- The slider Blizzard's own settings use. Its Init takes a step count, not a step size.
function UI.CreateSlider(parent, width, name)
    local slider = CreateFrame("Frame", name, parent, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(width)
    return slider
end

-- The close button Blizzard uses for one row of a list, sized to the row.
function UI.CreateRemoveButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
    button:SetSize(UI.Size.row, UI.Size.row)
    return button
end

function UI.CreateInset(parent)
    return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

local function setBodyHeight(section, height)
    section.body:SetHeight(height)
    section:SetHeight(UI.Size.heading + UI.Space.gap + height)
end

-- A titled block: a gold heading with its body one gap below. Callers fill section.body and report its
-- height through section:SetBodyHeight.
function UI.CreateSection(parent, title)
    local section = CreateFrame("Frame", nil, parent)
    section.heading = UI.CreateText(section, "heading")
    section.heading:SetHeight(UI.Size.heading)
    section.heading:SetPoint("TOPLEFT")
    section.heading:SetPoint("TOPRIGHT")
    section.heading:SetText(title)

    section.body = CreateFrame("Frame", nil, section)
    section.body:SetPoint("TOPLEFT", section.heading, "BOTTOMLEFT", 0, -UI.Space.gap)
    section.body:SetPoint("TOPRIGHT", section.heading, "BOTTOMRIGHT", 0, -UI.Space.gap)
    section.SetBodyHeight = setBodyHeight
    setBodyHeight(section, 0)
    return section
end

-- Chains a frame below another at the same width, one section break apart unless a gap is given.
function UI.StackBelow(frame, above, gap)
    local offset = -(gap or UI.Space.section)
    frame:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, offset)
    frame:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, offset)
end

-- A ScrollFrameTemplate with its scroll child. Leave UI.ScrollGutter() free on its right for the bar.
function UI.CreateScroll(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    scroll.content = CreateFrame("Frame", nil, scroll)
    scroll.content:SetSize(1, 1)
    scroll:SetScrollChild(scroll.content)
    return scroll
end

-- Anchors GameTooltip to its owner, lets the caller fill it with Blizzard's line helpers, then shows it.
function UI.ShowTooltip(owner, fill, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    fill(GameTooltip, owner)
    GameTooltip:Show()
end

function UI.AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self) UI.ShowTooltip(self, fill, anchor) end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function restorePosition(frame, position)
    frame:ClearAllPoints()
    if position and position.point then
        frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

local function savePosition(frame, position)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    position.point, position.relPoint, position.x, position.y = point, relPoint, x, y
end

-- Shared by windows and dialogs: toplevel, clamped, dragged with the left button, and closed by Escape
-- through UISpecialFrames, never UIPanelWindows, so it never drives Blizzard's panel layout.
local function makeMovable(frame, name, strata, position)
    frame:SetFrameStrata(strata)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if position then savePosition(self, position) end
    end)
    restorePosition(frame, position)
    frame:Hide()
    tinsert(UISpecialFrames, name)
end

-- A tool window on ButtonFrameTemplate: portrait, title bar, close button, inset, attic and button bar
-- come from the template. spec: name, title, icon, width, height, and optionally position (a saved table
-- it reads and writes), attic (a height, or false to drop it) and buttonBar (false to drop it).
function UI.CreateWindow(spec)
    local frame = CreateFrame("Frame", spec.name, UIParent, "ButtonFrameTemplate")
    frame:SetSize(spec.width, spec.height)
    frame:SetTitle(spec.title)
    frame:SetPortraitToAsset(spec.icon)

    if spec.attic == false then
        ButtonFrameTemplate_HideAttic(frame)
    elseif spec.attic then
        FrameTemplate_SetAtticHeight(frame, spec.attic)
    end
    if spec.buttonBar == false then ButtonFrameTemplate_HideButtonBar(frame) end

    -- The template's close button goes through HideUIPanel, which refuses insecure callers in combat.
    -- UIPanelCloseButton_OnClick asks onCloseCallback first, so the window hides itself instead.
    frame.onCloseCallback = function()
        frame:Hide()
        return false
    end

    makeMovable(frame, spec.name, UI.Strata.window, spec.position)
    return frame
end

-- Places a region in the dialog's content column below everything added so far.
local function placeContent(dialog, region, height, gap, indent)
    if dialog.hasContent then
        dialog.contentHeight = dialog.contentHeight + gap
    end
    dialog.hasContent = true
    region:SetPoint("TOPLEFT", dialog, "TOPLEFT", UI.Space.dialog + (indent or 0), -(UI.Space.dialogTop + dialog.contentHeight))
    dialog.contentHeight = dialog.contentHeight + height
end

-- Wrapped text across the content column. Its height is measured now, and never less than one line,
-- so text the caller fills in later still has its line reserved.
local function addDialogText(dialog, role, text, gap)
    local fontString = UI.CreateText(dialog, role)
    fontString:SetWidth(dialog.contentWidth)
    fontString:SetWordWrap(true)
    fontString:SetText(text or "")
    local _, lineHeight = UI.Font[role or "body"]:GetFont()
    local height = math.ceil(math.max(fontString:GetStringHeight(), lineHeight))
    fontString:SetHeight(height)
    placeContent(dialog, fontString, height, gap or UI.Space.section)
    return fontString
end

-- A gold heading over white body text, one gap apart, one section break below the previous content.
local function addDialogSection(dialog, heading, body)
    local headingText = addDialogText(dialog, "heading", heading)
    return headingText, addDialogText(dialog, "body", body, UI.Space.gap)
end

-- Any widget in the content column; the caller sizes it. indent shifts it right for native art, such as
-- UI.Native.inputArt for an edit box or UI.Native.dropdownArt for a dropdown.
local function addDialogField(dialog, widget, height, gap, indent)
    placeContent(dialog, widget, height, gap or UI.Space.gap, indent)
    return widget
end

-- A fit-to-text button in the bottom-right corner; later ones chain leftwards one gap apart.
local function addDialogButton(dialog, label, onClick)
    local button = UI.CreateButton(dialog, label)
    local previous = dialog.buttons[#dialog.buttons]
    if previous then
        button:SetPoint("RIGHT", previous, "LEFT", -UI.Space.gap, 0)
    else
        button:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -UI.Space.dialog, UI.Space.dialog)
    end
    button:SetScript("OnClick", onClick)
    dialog.buttons[#dialog.buttons + 1] = button
    return button
end

-- Height from the header clearance through the content and the button row to the bottom padding.
local function fitDialog(dialog)
    local height = UI.Space.dialogTop + dialog.contentHeight + UI.Space.dialog
    if #dialog.buttons > 0 then
        height = height + UI.Space.section + UI.Size.row
    end
    dialog:SetHeight(UI.Snap(height))
end

-- A dialog in Blizzard's dialog chrome: DialogBorderTemplate, DialogHeaderTemplate with the title and
-- UIPanelCloseButton. spec: name, title, width (a multiple of 8 from 400 to 480), and optionally parent
-- and position (a saved table it reads and writes). Add content top to bottom, then call dialog:Fit().
function UI.CreateDialog(spec)
    local dialog = CreateFrame("Frame", spec.name, spec.parent or UIParent)
    dialog:SetSize(spec.width, UI.Space.dialogTop + UI.Space.dialog)
    dialog.contentWidth = spec.width - 2 * UI.Space.dialog
    dialog.contentHeight = 0
    dialog.buttons = {}

    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
    dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate")
    dialog.Header:Setup(spec.title)

    -- UIPanelCloseButton_OnClick goes through HideUIPanel, which refuses insecure callers in combat.
    dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.CloseButton:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -DIALOG_CLOSE_INSET, -DIALOG_CLOSE_INSET)
    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)

    dialog.AddText = addDialogText
    dialog.AddSection = addDialogSection
    dialog.AddField = addDialogField
    dialog.AddButton = addDialogButton
    dialog.Fit = fitDialog

    makeMovable(dialog, spec.name, UI.Strata.dialog, spec.position)
    return dialog
end

-- A MagicButtonTemplate bar button: the first takes the bottom-right corner, later ones chain leftwards.
-- MagicButton_OnLoad runs after the zero-offset anchor so Blizzard applies its corner and neighbour
-- spacing; the template's own OnLoad ran before a Lua-made button had anchors.
function UI.AddBarButton(window, label, onClick, width)
    local button = CreateFrame("Button", nil, window, "MagicButtonTemplate")
    button:SetWidth(width or UI.Size.button)
    window.barButtons = window.barButtons or {}
    local previous = window.barButtons[#window.barButtons]
    if previous then
        button:SetPoint("RIGHT", previous, "LEFT")
    else
        button:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT")
    end
    MagicButton_OnLoad(button)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    window.barButtons[#window.barButtons + 1] = button
    return button
end

-- Builds the window on first use and flips it after that, so no frame exists until the player asks.
function UI.CreateToggle(build)
    local window
    return function()
        window = window or build()
        window:SetShown(not window:IsShown())
    end
end

-- One launcher for the minimap button and the Addon Compartment. LibDBIcon draws the minimap button and
-- adds the compartment entry through Blizzard's AddonCompartmentFrame, so both share this click handler
-- and this tooltip. spec: title, icon, db (the saved table LibDBIcon keeps its state in), onClick(button)
-- and tooltip(tooltip), which adds the lines under the title. Returns { setShown = function(shown) },
-- which shows or hides only the minimap button and remembers the choice in db.hide.
function UI.CreateLauncher(spec)
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if not LDBIcon:IsRegistered(spec.title) then
        local object = LibStub("LibDataBroker-1.1"):NewDataObject(spec.title, {
            type = "launcher",
            text = spec.title,
            icon = spec.icon,
            OnClick = function(_, button) spec.onClick(button) end,
            OnTooltipShow = function(tooltip)
                GameTooltip_SetTitle(tooltip, spec.title)
                spec.tooltip(tooltip)
            end,
        })
        LDBIcon:Register(spec.title, object, spec.db)
        LDBIcon:AddButtonToCompartment(spec.title)
    end

    return {
        setShown = function(shown)
            spec.db.hide = not shown
            if shown then
                LDBIcon:Show(spec.title)
            else
                LDBIcon:Hide(spec.title)
            end
        end,
    }
end

-- Blizzard reads SLASH_<KEY>1..n and SlashCmdList[KEY].
function UI.RegisterSlash(key, commands, handler)
    for index, command in ipairs(commands) do
        _G["SLASH_" .. key .. index] = command
    end
    SlashCmdList[key] = handler
end
