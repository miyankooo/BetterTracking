local addonName, ns = ...

local ZONING_QUIET = 5
local FLASH_TEXTURE = "Interface\\AddOns\\" .. addonName .. "\\Media\\pulse_ring"

ns.sounds = {
  { name = "Minimap Ping", id = SOUNDKIT.MAP_PING },
  { name = "Whisper", id = SOUNDKIT.TELL_MESSAGE },
  { name = "Raid Warning", id = SOUNDKIT.RAID_WARNING },
  { name = "Ready Check", id = SOUNDKIT.READY_CHECK },
  { name = "Auction Window", id = SOUNDKIT.AUCTION_WINDOW_OPEN },
  { name = "Alarm Clock", id = SOUNDKIT.ALARM_CLOCK_WARNING_1 },
}

local lastAlert, quietUntil = 0, 0

local flash = CreateFrame("Frame", nil, Minimap)
flash:SetAllPoints(Minimap)
flash:SetFrameLevel(Minimap:GetFrameLevel() + 7)
flash:Hide()

local ring = flash:CreateTexture(nil, "OVERLAY")
ring:SetAllPoints(flash)
ring:SetTexture(FLASH_TEXTURE)

-- The texture is a 4x4 atlas of ten rings from hairline to bold, because the client cannot draw a ring at
-- runtime. The fourth cell is a medium ring.
ring:SetTexCoord(0.75, 1, 0, 0.25)

local fade = flash:CreateAnimationGroup()
local fadeIn = fade:CreateAnimation("Alpha")
fadeIn:SetFromAlpha(0)
fadeIn:SetToAlpha(1)
fadeIn:SetDuration(0.1)
fadeIn:SetOrder(1)
local fadeOut = fade:CreateAnimation("Alpha")
fadeOut:SetFromAlpha(1)
fadeOut:SetToAlpha(0)
fadeOut:SetDuration(0.8)
fadeOut:SetOrder(2)
fade:SetScript("OnFinished", function() flash:Hide() end)

function ns.Flash(r, g, b)
  if not r then r, g, b = NORMAL_FONT_COLOR:GetRGB() end
  ring:SetVertexColor(r, g, b)
  flash:Show()
  fade:Restart()
end

-- Master is meant to come through with sound effects muted, which is when a gatherer needs the ping most.
-- UNVERIFIED in game.
function ns.PlayAlertSound()
  PlaySound(ns.db.soundId, "Master", true)
end

function ns.AlertsOn()
  return ns.db.sound or ns.db.flash
end

-- Sources check this before they record a node, so a node reached while paused, muted, dead, on a flight
-- path or in a fight still alerts once an alert is possible again.
function ns.CanAlert()
  return not ns.db.paused and ns.AlertsOn() and not UnitOnTaxi("player") and not InCombatLockdown()
    and not UnitIsDeadOrGhost("player")
end

-- Sources record a node before calling this, so a node swallowed by the cooldown or the zoning window
-- stays remembered and never alerts late. The name is kept so the player can see what pinged.
function ns.Alert(name, r, g, b)
  local now = GetTime()
  if now < quietUntil or now - lastAlert < ns.db.cooldown then return end

  lastAlert = now
  ns.lastAlertName = name
  if ns.db.sound then ns.PlayAlertSound() end
  if ns.db.flash then ns.Flash(r, g, b) end
end

function ns.PreviewAlert()
  ns.PlayAlertSound()
  ns.Flash()
end

-- Pausing is its own flag, so resuming brings back exactly the sound and flash choices the player made.
function ns.TogglePause()
  ns.db.paused = not ns.db.paused
  ns.Print(ns.db.paused and "Alerts paused." or "Alerts resumed.")
end

local zoningCallbacks = {}

-- Both sources forget their nodes on zoning, so one handler owns the event and tells them in the order the
-- files registered.
function ns.OnZoning(callback)
  zoningCallbacks[#zoningCallbacks + 1] = callback
end

-- Zoning repopulates every node at once, so stay quiet for a moment instead of pinging for all of them.
local zoning = CreateFrame("Frame")
zoning:RegisterEvent("PLAYER_ENTERING_WORLD")
zoning:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoning:SetScript("OnEvent", function()
  quietUntil = GetTime() + ZONING_QUIET
  for _, callback in ipairs(zoningCallbacks) do callback() end
end)
