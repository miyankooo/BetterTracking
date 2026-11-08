local _, ns = ...

-- Matches the toc IconTexture. Blizzard's own pet bar uses the same path (Shared/PetActionBar.lua).
local ICON = "Interface\\Icons\\inv_10_dungeonjewelry_explorer_trinket_1compass_color1"

local setMinimapShown

-- One line that says whether a ping can come at all, and if not, what the player has to do.
function ns.StatusText()
  if ns.db.paused then return "Alerts are paused." end
  if not ns.AlertsOn() then return "Alerts are off." end
  if ns.db.blips and not ns.db.space then return ns.HOVER_HINT end
  if ns.db.blips and ns.readFailed then return "Minimap alerts are off until you type /reload." end
  return "Alerts are on."
end

function ns.SwapStatusText()
  if not ns.db.swap then return "Swap is off." end

  -- Each swap spends a global cooldown, so a cooldown is normal running, not a wait.
  local reason = ns.SwapWaitReason()
  if reason and reason ~= ns.SWAP_COOLDOWN then return "Swap waits: " .. reason .. "." end
  if ns.SwapRunsOnInput() then return "Swapping herbs and minerals on your movement keys." end
  return "Swapping herbs and minerals."
end

-- The last alert's name tells a real node from a false ping, which the sound alone cannot.
local function FillTooltip(tooltip)
  GameTooltip_AddHighlightLine(tooltip, ns.StatusText())
  GameTooltip_AddHighlightLine(tooltip, ns.SwapStatusText())
  if ns.lastAlertName then GameTooltip_AddHighlightLine(tooltip, "Last alert: " .. ns.lastAlertName .. ".") end
  GameTooltip_AddInstructionLine(tooltip, "Left-click to open the settings.")
  GameTooltip_AddInstructionLine(tooltip, "Middle-click to turn the herb and ore swap on or off.")
  GameTooltip_AddInstructionLine(tooltip, ns.db.paused and "Right-click to resume alerts." or "Right-click to pause alerts.")
end

-- Right-click toggles the pause, never the sound or flash settings.
local function OnClick(button)
  if button == "MiddleButton" then
    ns.ToggleSwap()
  elseif button == "RightButton" then
    ns.TogglePause()
  else
    ns.OpenSettings()
  end
end

-- One launcher for the minimap button and the Addon Compartment: LibDBIcon draws the button and adds the
-- compartment entry through AddonCompartmentFrame, so both share the click and the tooltip. Such an addon has no
-- AddonCompartmentFunc toc keys. LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 load first.
local function CreateLauncher(icon, db, onClick, fillTooltip)
  local LDBIcon = LibStub("LibDBIcon-1.0")
  if not LDBIcon:IsRegistered(ns.title) then
    local object = LibStub("LibDataBroker-1.1"):NewDataObject(ns.title, {
      type = "launcher",
      text = ns.title,
      icon = icon,
      OnClick = function(_, button) onClick(button) end,
      OnTooltipShow = function(tooltip)
        GameTooltip_SetTitle(tooltip, ns.title)
        fillTooltip(tooltip)
      end,
    })
    LDBIcon:Register(ns.title, object, db)
    LDBIcon:AddButtonToCompartment(ns.title)
  end
  -- Shows or hides only the minimap button and remembers it in db.hide; the addon menu entry stays.
  return function(shown)
    db.hide = not shown
    if shown then LDBIcon:Show(ns.title) else LDBIcon:Hide(ns.title) end
  end
end

-- The button shows what is tracked right now, so it visibly alternates while the swap runs. Login and
-- /reload go through the zoning hook, so a tracking that is already on shows before any change.
local function UpdateIcon()
  local _, active = ns.ReadTracking()
  LibStub("LibDataBroker-1.1"):GetDataObjectByName(ns.title).icon = active and active.texture or ICON
end

-- The minimap button and the addon menu entry share this click and tooltip. The minimap position lives in
-- the account-wide db, so every character shares it.
ns.OnSettingsLoaded(function()
  setMinimapShown = CreateLauncher(ICON, ns.db.minimap, OnClick, FillTooltip)

  local events = CreateFrame("Frame")
  events:SetScript("OnEvent", UpdateIcon)
  events:RegisterEvent("MINIMAP_UPDATE_TRACKING")
  events:RegisterEvent("SPELLS_CHANGED")
end)

ns.OnZoning(UpdateIcon)

-- Flips only the minimap button; the addon menu entry always stays. A button that comes back shows itself, so only
-- hiding it prints, with the way back.
function ns.ToggleMinimap()
  local show = ns.db.minimap.hide
  setMinimapShown(show)
  if not show then ns.Print("Minimap button hidden. Type /tra minimap to show it again.") end
end
