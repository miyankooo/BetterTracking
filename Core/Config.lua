local addonName, ns = ...

ns.addonName = addonName
ns.title = "Better Tracking"

-- Defaults are tuned for gathering: a cooldown long enough that riding into a cluster of nodes is one ping,
-- and only gathering blips. The GatherMate2 source is opt-in, because its circles mark remembered spots,
-- which ping even when the node is gone.
ns.defaults = {
  -- Alert output, shared by both sources.
  sound = true,
  soundId = SOUNDKIT.MAP_PING,
  flash = true,
  cooldown = 3,

  -- Minimap blip source.
  blips = true,
  objectsOnly = true,
  vignettes = true,

  -- False means the coordinate space of the engine hit test is still unknown, which is the one thing
  -- this addon cannot settle without a blip to test against. The blip source stays idle until it is set.
  space = false,

  -- GatherMate2 source.
  gatherMate = false,
  mutedTypes = {},

  -- Herb and ore swap, opt-in because it casts spells and each cast costs a global cooldown.
  swap = false,
  swapInterval = 4,

  -- State without a settings control, so the panel's Defaults button leaves it alone.
  paused = false,
  hinted = false,
  minimap = { hide = false },
}

ns.db = {}

local loadedCallbacks = {}

-- Everything that reads settings at startup waits on this one hook, so it always runs after the load
-- and in the order the files registered.
function ns.OnSettingsLoaded(callback)
  loadedCallbacks[#loadedCallbacks + 1] = callback
end

function ns.Print(message)
  print(YELLOW_FONT_COLOR:WrapTextInColorCode("[" .. ns.title .. "]:") .. " " .. message)
end

-- issecretvalue does not take nil (Nilable = false), which is never secret.
local function CheckSecret(value)
  if value == nil then return false end
  return issecretvalue(value)
end

-- Restricted content can hand values out as secrets, which break comparisons and table keys. issecretvalue
-- is declared SecretArguments "AllowedWhenUntainted", and even comparing a secret with nil may raise, so
-- both run under pcall, where a raise can only mean secret.
function ns.IsSecret(value)
  local ok, secret = pcall(CheckSecret, value)
  return not ok or secret
end

-- Speed is secret where unit stats are restricted, and a secret cannot be compared, so an unknown speed
-- counts as standing still.
function ns.IsMoving()
  local speed = GetUnitSpeed("player")
  return not ns.IsSecret(speed) and speed ~= 0
end

-- Table defaults are copied, so a saved table never aliases the defaults it was filled from.
local function LoadSettings()
  BetterTrackingDB = BetterTrackingDB or {}
  for key, value in pairs(ns.defaults) do
    if BetterTrackingDB[key] == nil then
      BetterTrackingDB[key] = type(value) == "table" and CopyTable(value) or value
    end
  end
  ns.db = BetterTrackingDB
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
  LoadSettings()
  for _, callback in ipairs(loadedCallbacks) do callback() end
end)
