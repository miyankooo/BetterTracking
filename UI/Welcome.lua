local addonName, ns = ...

-- Blizzard reserves the addon link type for addons and hands every click on one to all of them through one
-- EventRegistry event (Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua:279-281). Gold is the colour of
-- Blizzard's own action links in chat, such as club invites (ItemRef.lua).
local LINK = LinkTypes.AddOn .. ":" .. addonName

local function SurfaceLink(label)
  return NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink(LinkTypes.AddOn, "[" .. label .. "]", addonName))
end

-- What the addon does, where its first step is, and what minimap pings still need from the player, since they
-- cannot start until a blip is hovered once.
function ns.PrintWelcome()
  ns.Print("Pings when a new node, rare or treasure shows up on the minimap, and can swap Find Herbs and Find "
    .. "Minerals as you move. Open the " .. SurfaceLink(SETTINGS) .. " or type /tra to turn on the herb and ore "
    .. "swap. Pings start once you turn on Find Herbs or Find Minerals and hover a blip near the minimap edge.")
end

-- Another addon's link may come from a line kept from restricted content, so it is checked before the comparison.
EventRegistry:RegisterCallback("SetItemRef", function(_, link)
  if ns.CanAccess(link) and link == LINK then ns.OpenSettings() end
end, ns)

-- The account's first load says what the addon does, once, at login: after the client's own load lines, and when
-- the settings page the link opens exists.
EventUtil.ContinueOnPlayerLogin(function()
  if ns.firstRun then ns.PrintWelcome() end
end)
