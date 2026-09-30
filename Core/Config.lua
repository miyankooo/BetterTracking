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

-- Restricted content can hand values out as secrets, which break comparisons and table keys. issecretvalue
-- is declared SecretArguments "AllowedWhenUntainted", so it may raise for addon code handed a secret, and a
-- raise can only mean secret. It does not take nil, which is never secret.
function ns.IsSecret(value)
  if value == nil then return false end

  local ok, secret = pcall(issecretvalue, value)
  return not ok or secret
end

-- Table defaults are copied, so a saved table never aliases the defaults it was filled from.
local function LoadSettings()
  TrackingAlertDB = TrackingAlertDB or {}
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
