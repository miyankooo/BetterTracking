local addonName, ns = ...

-- Both sources remember a node this long after they last saw it, so walking away and back stays quiet.
ns.REMEMBER_FOR = 180
ns.GOLD = { 1, 0.82, 0 }

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

-- The texture is a 4x4 atlas of ten rings from hairline to bold, because the client cannot draw a ring
-- at runtime. The thickness setting picks a cell.
function ns.ApplyThickness()
  local index = ns.db.flashThickness - 1
  local column, row = index % 4, math.floor(index / 4)
  ring:SetTexCoord(column * 0.25, (column + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
end

function ns.Flash(r, g, b)
  if not r then r, g, b = unpack(ns.GOLD) end
  ring:SetVertexColor(r, g, b)
  flash:Show()
  fade:Restart()
end

function ns.PlayAlertSound()
  PlaySound(ns.db.soundId, ns.db.channel, true)
end

function ns.AlertsOn()
  return ns.db.sound or ns.db.flash
end

-- Sources check this before they record a node, so a node reached while muted, on a flight path or in a
-- fight still alerts once an alert is possible again.
function ns.CanAlert()
  return ns.AlertsOn() and not UnitOnTaxi("player") and not InCombatLockdown()
end

-- Sources record a node before calling this, so a node swallowed by the cooldown or the zoning window
-- stays remembered and never alerts late.
function ns.Alert(r, g, b)
  local now = GetTime()
  if now < quietUntil or now - lastAlert < ns.db.cooldown then return end

  lastAlert = now
  if ns.db.sound then ns.PlayAlertSound() end
  if ns.db.flash then ns.Flash(r, g, b) end
end

function ns.PreviewAlert()
  ns.PlayAlertSound()
  ns.Flash()
end

-- The right-click toggle turns both outputs on or off together, so one click always means one state.
function ns.ToggleAlerts()
  local turnOn = not ns.AlertsOn()
  ns.db.sound, ns.db.flash = turnOn, turnOn
  PlaySound(turnOn and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

ns.OnSettingsLoaded(ns.ApplyThickness)

-- Zoning repopulates every node at once, so stay quiet for a moment instead of pinging for all of them.
local zoning = CreateFrame("Frame")
zoning:RegisterEvent("PLAYER_ENTERING_WORLD")
zoning:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoning:SetScript("OnEvent", function()
  quietUntil = GetTime() + ZONING_QUIET
end)
