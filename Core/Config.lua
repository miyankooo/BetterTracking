local addonName, ns = ...

ns.addonName = addonName

-- Defaults are tuned for gathering: only GameObject tooltips, only while moving, and a cooldown long
-- enough that riding into a cluster of nodes is one ping rather than a burst.
ns.defaults = {
  enabled = true,

  -- False resolves to SOUNDKIT.MAP_PING at play time, which is the sound the stock minimap already
  -- uses for a ping. A number here overrides it with any other sound kit id.
  sound = false,
  channel = "Master",
  cooldown = 0.75,
  requireMovement = true,
  objectsOnly = true,
  allowUntyped = true,
  vignettes = true,
  ringPoints = 64,
  discSpacing = 8,
  discInterval = 5,
  probeBudget = 8,

  -- False means the coordinate space of the engine hit test is still unknown, which is the one thing
  -- this addon cannot settle without a blip to test against. Scanner stays idle until it is set.
  space = false,
}

ns.db = {}

function ns.Print(message)
  print("|cff7FD4FFTracking Alert|r " .. message)
end

local function LoadSettings()
  TrackingAlertDB = TrackingAlertDB or {}
  for key, value in pairs(ns.defaults) do
    if TrackingAlertDB[key] == nil then
      TrackingAlertDB[key] = value
    end
  end
  ns.db = TrackingAlertDB
end

local configFrame = CreateFrame("Frame")
configFrame:RegisterEvent("ADDON_LOADED")
configFrame:SetScript("OnEvent", function(self, _, loadedAddon)
  if loadedAddon == addonName then
    LoadSettings()
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
