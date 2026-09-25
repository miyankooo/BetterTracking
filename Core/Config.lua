local addonName, ns = ...

ns.addonName = addonName
ns.title = "Tracking Alert"

-- Defaults are tuned for gathering: a sound that comes through muted effects, a cooldown long enough that
-- riding into a cluster of nodes is one ping, and only GameObject blips while moving.
ns.defaults = {
  -- Alert output, shared by both sources.
  sound = true,
  soundId = SOUNDKIT.MAP_PING,
  channel = "Master",
  flash = true,
  flashThickness = 4,
  cooldown = 3,

  -- Minimap blip source.
  blips = true,
  requireMovement = true,
  objectsOnly = true,
  vignettes = true,
  discInterval = 5,
  probeBudget = 8,

  -- False means the coordinate space of the engine hit test is still unknown, which is the one thing
  -- this addon cannot settle without a blip to test against. The blip source stays idle until it is set.
  space = false,

  -- GatherMate2 source, plus the GatherMate2 minimap tweaks that came with it.
  gatherMate = true,
  hideIcons = false,
  mergeCircles = true,
  circleSize = 1,
  mutedTypes = {},
}

ns.db = {}

local loadedCallbacks = {}

-- Everything that reads settings at startup waits on this one hook, so it always runs after the load
-- and in the order the files registered.
function ns.OnSettingsLoaded(callback)
  loadedCallbacks[#loadedCallbacks + 1] = callback
end

function ns.Print(message)
  print("|cff7FD4FF" .. ns.title .. "|r " .. message)
end

-- 1.0.0 saved another shape: `enabled` switched the blip scan, and `sound` was false for the default ping or
-- a sound kit id, never "off", so read as-is an upgrade goes silent. Only 1.0.0 wrote `enabled`, so it marks
-- such a save and dropping it makes this run once. Cooldown snaps onto the new whole-second slider.
local function MigrateLegacy(saved)
  if saved.enabled == nil then return end

  saved.blips = saved.enabled
  if type(saved.sound) == "number" then saved.soundId = saved.sound end
  saved.sound = true
  if saved.cooldown then saved.cooldown = math.max(1, math.floor(saved.cooldown + 0.5)) end

  saved.enabled, saved.allowUntyped, saved.ringPoints, saved.discSpacing = nil, nil, nil, nil
end

-- Table defaults are copied, so a saved table never aliases the defaults it was filled from.
local function LoadSettings()
  TrackingAlertDB = TrackingAlertDB or {}
  MigrateLegacy(TrackingAlertDB)
  for key, value in pairs(ns.defaults) do
    if TrackingAlertDB[key] == nil then
      TrackingAlertDB[key] = type(value) == "table" and CopyTable(value) or value
    end
  end
  ns.db = TrackingAlertDB
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
  LoadSettings()
  for _, callback in ipairs(loadedCallbacks) do callback() end
end)
