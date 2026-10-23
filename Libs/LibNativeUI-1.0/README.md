# LibNativeUI-1.0

A native UI design system for WoW Forever 1.60.x addons, shared by the miyanko addons. Every addon with a window, a dialog or a minimap button builds it from this library, so the addons look native to the game and recognisably come from one developer.

## Rules

- Native first. Every component is a Blizzard template, mixin, font object or colour object. Build a custom piece only when Blizzard has none, and style it from native parts.
- 4 px grid. Every size, gap, padding, offset, row height and width an addon chooses is a multiple of 4. Use the `UI.Space` and `UI.Size` tokens, or `UI.Snap()` for sizes derived from content.
- Native geometry is not spacing. Offsets and sizes a template fixes itself, such as the 22 px bar button or InputBoxTemplate's left cap, are listed in `UI.Native`. They are the only values off the grid. The content box is on the grid, and a frame's outer size is content plus native chrome.
- Two text sizes. Text uses only the `UI.Font` roles: 12 px for everything, 16 px for a dialog's subject line. Never the 10, 11, 13, 14 or 18 px objects, and never `SetFont`.
- Blizzard colours. Colours come from `UI.Color` or another Blizzard colour object. Never write a literal `|cffRRGGBB`.
- Title Case for window titles, buttons, section headings, setting names and menu entries, as Blizzard does ("Auto Loot", "Clear List"). Use a Blizzard global string where an exact one exists: `ADD`, `REMOVE`, `SEARCH`, `CLEAR_ALL`, `NONE`.
- Sentence case for tooltips, helper lines and chat. Sentences end with a period.

## Embedding

Each addon carries an identical copy under `Libs/LibNativeUI-1.0/`. It needs only LibStub:

```
Libs\LibStub\LibStub.lua
Libs\LibNativeUI-1.0\LibNativeUI-1.0.lua
```

`UI.CreateLauncher` also needs CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0, loaded before the library:

```
Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
Libs\LibDataBroker-1.1\LibDataBroker-1.1.lua
Libs\LibDBIcon-1.0\LibDBIcon-1.0.lua
Libs\LibNativeUI-1.0\LibNativeUI-1.0.lua
```

Get it with `local UI = LibStub("LibNativeUI-1.0")`.

## Tokens

| Token | Value | Use |
|---|---|---|
| `UI.GRID` | 4 | the grid unit. `UI.Snap()` rounds up to it. |
| `UI.Space.tight` | 4 | label to control, hint under a field |
| `UI.Space.gap` | 8 | between related controls, heading to body |
| `UI.Space.padding` | 16 | inside an inset, to its content |
| `UI.Space.section` | 24 | between sections, in windows and dialogs |
| `UI.Space.dialog` | 20 | dialog side and bottom padding |
| `UI.Space.dialogTop` | 40 | dialog content top, below 28 px of header art |
| `UI.Size.row` | 24 | a list row, checkbox, remove button or content button |
| `UI.Size.heading` | 16 | one section heading line |
| `UI.Size.icon` | 16 | inline icons |
| `UI.Size.button` | 128 | default bar button width |
| `UI.Size.dropdown` | 160 | default dropdown width |
| `UI.Size.input` | 160 | default edit and search box width |
| `UI.ScrollGutter()` | 24 | right margin a scroll frame leaves for its bar: offset 6, bar 8 and gap 8, snapped |

An editable row (an edit box with its buttons) has a pitch of 32: a 24 px row plus an 8 px gap.

| Native token | Value | Blizzard source |
|---|---|---|
| `UI.Native.buttonHeight` | 22 | MagicButtonTemplate in a window's button bar, `Mainline/SharedUIPanelTemplates.xml:750` |
| `UI.Native.inputHeight` | 20 | InputBoxTemplate art, `Shared/InputBox/InputBoxTemplates.xml:47` |
| `UI.Native.inputArt` | 5 | InputBoxTemplate's left cap outside the box, `InputBoxTemplates.xml:49` |
| `UI.Native.dropdownArt` | 8 | WowStyle1DropdownTemplate art past each side, `Blizzard_Menu/Mainline/MenuTemplates.xml:9-10` |
| `UI.Native.dropdownHeight` | 25 | WowStyle1DropdownTemplate, `MenuTemplates.xml:4` |
| `UI.Native.sliderHeight` | 40 | MinimalSliderWithSteppersTemplate, `Shared/Slider/MinimalSlider.xml:35` |
| `UI.Native.titleLeft` | 58 | where the title starts, for attic text, `SharedUIPanelTemplates.xml:603` |
| `UI.Native.scrollBarWidth` | 8 | MinimalScrollBar, `Shared/Scroll/MinimalScrollBar.xml:16` |

Indent a dropdown by `UI.Native.dropdownArt` and leave the same on its right. Indent an edit box by `UI.Native.inputArt`.

| Font role | Blizzard font object | Size |
|---|---|---|
| `title` | `GameFontNormalLarge` | 16, a dialog's subject line only |
| `heading` | `GameFontNormal` (gold) | 12 |
| `body` | `GameFontHighlight` (white) | 12 |
| `muted` | `GameFontDisable` (grey) | 12 |

| Colour role | Blizzard colour object |
|---|---|
| `heading` | `NORMAL_FONT_COLOR` |
| `body` | `HIGHLIGHT_FONT_COLOR` |
| `muted` | `GRAY_FONT_COLOR` |
| `good` | `GREEN_FONT_COLOR` |
| `bad` | `RED_FONT_COLOR` |
| `warn` | `WARNING_FONT_COLOR` |
| `prefix` | `YELLOW_FONT_COLOR` |

`UI.Strata.window` is `HIGH` for tool windows, and `UI.Strata.dialog` is `DIALOG` for dialogs and popups.

## Tool window

```lua
local function build()
    local window = UI.CreateWindow({
        name = "MyAddonFrame", title = "My Addon", icon = 134400,
        width = 480, height = 400,
        position = MyAddonDB.window,   -- optional: a saved table the window reads and writes
        attic = false,                 -- optional: drop the attic, or pass a height
        buttonBar = false,             -- optional: drop the button bar
    })
    UI.AddBarButton(window, "Primary", onPrimary)   -- bottom-right
    UI.AddBarButton(window, "Secondary", onSecond)  -- chained to its left
    return window
end
ns.TogglePanel = UI.CreateToggle(build)
```

What the window gives you:

- `ButtonFrameTemplate` with the portrait, the title, the inset, the attic and the button bar.
- Strata `HIGH`, toplevel, clamped and movable.
- Escape closes it through `UISpecialFrames`, never `UIPanelWindows`.
- The close button also works in combat, through `onCloseCallback`.
- Content goes into `window.Inset`, padded by `UI.Space.padding`. A second column is `UI.CreateInset(window)`, 8 px to the right.
- The attic holds one line: a status line in `body` from `UI.Native.titleLeft`, or controls such as a search box or a filter dropdown.

## Dialog

A dialog is one short task: copy a link, set a filter, read a guide.

```lua
local dialog = UI.CreateDialog({
    name = "MyAddonDialog", title = "My Addon", width = 448,
    parent = SomeHostFrame,   -- optional, defaults to UIParent
    position = MyAddonDB.dialog,   -- optional
})
local name = dialog:AddText("title", "")
dialog:AddText("body", "Realm", UI.Space.tight)
local box = UI.CreateEditBox(dialog, dialog.contentWidth - UI.Native.inputArt)
dialog:AddField(box, UI.Native.inputHeight, UI.Space.gap, UI.Native.inputArt)
dialog:AddText("muted", "Press CTRL+C to copy and close.", UI.Space.tight)
dialog:AddButton(CLOSE, function() dialog:Hide() end)
dialog:Fit()
```

- Chrome: `DialogBorderTemplate`, `DialogHeaderTemplate` with the title, and `UIPanelCloseButton` 2 px in from the corner. Its click hides the dialog directly, so it works in combat.
- Strata `DIALOG`, toplevel, clamped and movable. Escape closes it. It starts hidden.
- Width is a multiple of 8 from 400 to 480. The content column is `dialog.contentWidth`, the width less 20 on each side.
- `dialog:AddText(role, text, gap)` adds wrapped text in a font role and returns the font string. The gap defaults to a section break. An empty text still reserves one line.
- `dialog:AddSection(heading, body)` adds a gold heading and body text 8 apart, a section break below the previous content. It returns both font strings.
- `dialog:AddField(widget, height, gap, indent)` places any widget the caller sized. The gap defaults to 8. The indent covers native art.
- `dialog:AddButton(label, onClick)` adds a 24 px fit-to-text button in the bottom-right corner. Later buttons chain leftwards 8 apart.
- `dialog:Fit()` sets the height: 40 top, the content, a section break and the button row if there are buttons, 20 bottom, snapped to the grid. Call it after the last add.

## Controls

- `UI.CreateText(parent, role)`
- `UI.CreateButton(parent, label, width)` is 24 px tall. Without a width it fits its label: at least 64, otherwise the text plus the template's 40 px padding, rounded up to 8.
- `UI.CreateCheckbox(parent, label)` uses `CheckboxWithLabelTemplate`, the minimal art Blizzard's Settings use, at 24 x 24. The label is 12 px `body` text 4 px to its right and is clickable. Change it with `checkbox:SetLabel(text)`, which also resizes the click area.
- `UI.CreateEditBox(parent, width)`
- `UI.CreateSearchBox(parent, width, name)`, with its typed text and hint moved to the 12 px roles
- `UI.CreateDropdown(parent, width, name)`, filled with `SetupMenu`
- `UI.CreateFilterDropdown(parent, width)`, Blizzard's "Filter" button, described below
- `UI.CreateSlider(parent, width, name)`
- `UI.CreateRemoveButton(parent)`

Containers and tooltips:

- `UI.CreateInset(parent)`
- `UI.CreateSection(parent, title)`, which gives `section.body` and `section:SetBodyHeight(h)`
- `UI.StackBelow(frame, above, gap)`
- `UI.CreateScroll(parent, name)`, which gives `scroll.content`
- `UI.ShowTooltip(owner, fill, anchor)` and `UI.AttachTooltip(frame, fill, anchor)`. Fill them with Blizzard's `GameTooltip_*` line helpers.

### Filter dropdown

`UI.CreateFilterDropdown` wraps `WowStyle1FilterDropdownTemplate`, the button Blizzard's Who list uses. Its text is `FILTER` and its menu comes from `SetupMenu`. Its width is fixed on the grid, from the native fit unless you pass one. Set the reset callbacks before `SetupMenu`; the template then shows its own reset button whenever the filters differ from the defaults:

```lua
local filter = UI.CreateFilterDropdown(window)
filter:SetPoint("RIGHT", searchBox, "LEFT", -UI.Space.gap, 0)
filter:SetDefaultCallback(function() resetFilters(); refreshList() end)
filter:SetIsDefaultCallback(function() return filtersAreDefault() end)
filter:SetupMenu(function(_, root)
    root:CreateCheckbox("Show Completed", isCompletedShown, toggleCompleted)
end)
-- after a change made outside the menu
filter:ValidateResetState()
```

## Launcher

There is no Blizzard template for an addon minimap button on Forever, so the button stays on LibDBIcon-1.0. Blizzard's native entry point is the Addon Compartment, and LibDBIcon registers there through `AddonCompartmentFrame:RegisterAddon`, so one launcher covers both:

```lua
local launcher = UI.CreateLauncher({
    title = "My Addon", icon = 134400,
    db = MyAddonDB.minimap,
    onClick = function(button) if button == "LeftButton" then ns.TogglePanel() end end,
    tooltip = function(tooltip) GameTooltip_AddInstructionLine(tooltip, "Left-click to toggle the window.") end,
})

-- /myaddon minimap flips the button: a hidden one shows, a shown one hides
launcher.setShown(MyAddonDB.minimap.hide)
```

- The tooltip title is added for you. Then add an optional one-line status and instruction lines such as "Left-click to toggle the window." and "Right-click to ...".
- `launcher.setShown(shown)` shows or hides only the minimap button and stores the choice in `db.hide`. The addon menu entry stays. Call it with a dot.
- Don't also list the addon in the toc with `## AddonCompartmentFunc`, or it shows twice.

## Opening and closing

- Slash command: `UI.RegisterSlash("MYADDON", { "/myaddon", "/ma" }, handler)`. One long command and one short alias. The bare command opens the window.
- Toggle: the same `ns.TogglePanel` serves the minimap button, the addon menu and the slash command.
- Chat output: `UI.Print("My Addon", "Sentence in sentence case.")` prints the shared yellow `[My Addon]:` prefix.

## Keeping the copies in sync

- Reference copy: `ChatScan/Libs/LibNativeUI-1.0/`. Every other addon carries a byte-identical copy.
- Changing it: edit the reference copy, raise `MINOR`, run `lua Tests/LibNativeUI.lua` from the ChatScan folder, then copy the folder into every addon that embeds it. LibStub always keeps the highest `MINOR` loaded, so mixed versions never break, but the copies should not drift.
- Checking it: from the AddOns folder, run `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua`. It must print one hash.
- A new addon: copy the folder, add the toc lines, and build its window or dialog, launcher and slash command from this library.
