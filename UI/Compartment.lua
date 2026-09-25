local _, ns = ...

-- The addon compartment under the minimap is the native launcher, so no minimap button library is
-- needed. The toc names these three globals, and the compartment calls them with the addon name first.
function TrackingAlert_OnClick(_, mouseButton)
  if mouseButton == "RightButton" then
    ns.ToggleAlerts()
    ns.RefreshOptions("sound", "flash")
  else
    ns.OpenOptions()
  end
end

function TrackingAlert_OnEnter(_, menuButton)
  GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
  GameTooltip_SetTitle(GameTooltip, ns.title)
  GameTooltip_AddHighlightLine(GameTooltip, ns.AlertsOn() and "Alerts are on." or "Alerts are off.")
  GameTooltip_AddInstructionLine(GameTooltip, "Left-click opens the settings.")
  GameTooltip_AddInstructionLine(GameTooltip, "Right-click turns alerts on or off.")
  GameTooltip:Show()
end

function TrackingAlert_OnLeave()
  GameTooltip:Hide()
end
