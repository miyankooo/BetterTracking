local _, ns = ...

local categoryID

local function AddCheckbox(category, key, label, tooltip)
  local variable = "TRACKING_ALERT_" .. strupper(key)
  local setting = Settings.RegisterAddOnSetting(category, variable, key, ns.db,
    Settings.VarType.Boolean, label, ns.defaults[key])

  Settings.CreateCheckbox(category, setting, tooltip)
  return setting
end

local function AddSlider(category, key, label, minimum, maximum, step, tooltip)
  local variable = "TRACKING_ALERT_" .. strupper(key)
  local setting = Settings.RegisterAddOnSetting(category, variable, key, ns.db,
    Settings.VarType.Number, label, ns.defaults[key])

  local options = Settings.CreateSliderOptions(minimum, maximum, step)
  options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
  Settings.CreateSlider(category, setting, options, tooltip)
  return setting
end

local function RegisterPanel()
  local category = Settings.RegisterVerticalLayoutCategory("Tracking Alert")

  AddCheckbox(category, "enabled", "Enabled",
    "Scan the minimap and ping when a new tracked blip appears.")

  AddCheckbox(category, "requireMovement", "Only while moving",
    "A blip can only cross the minimap edge while you move, so standing still skips the scan entirely.")

  AddCheckbox(category, "objectsOnly", "Gathering nodes only",
    "Ping only for blips whose tooltip is a world object. Turn off to ping for every blip, including townsfolk and other players.")

  AddCheckbox(category, "vignettes", "Also ping for vignettes",
    "Alert on rares and treasures that report themselves through the vignette system.")

  AddSlider(category, "cooldown", "Alert cooldown", 0.25, 5, 0.25,
    "Shortest gap between two pings, in seconds.")

  -- The scan interval and probe budget trade latency against work per frame, so they are exposed
  -- rather than hidden: a low-end machine can halve the budget and still catch every node.
  AddSlider(category, "discInterval", "Full sweep interval", 1, 20, 1,
    "How often the whole minimap is swept, in seconds. Catches nodes that spawn inside the radius rather than crossing the edge.")

  AddSlider(category, "probeBudget", "Probes per frame", 2, 24, 1,
    "How many points are tested each frame. Lower is cheaper and slower to react.")

  Settings.RegisterAddOnCategory(category)
  categoryID = category:GetID()
end

EventUtil.ContinueOnPlayerLogin(RegisterPanel)

local function SpaceLabel()
  if not ns.db.space then return "not calibrated" end

  for _, space in ipairs(ns.spaces) do
    if space.key == ns.db.space then return space.label end
  end
  return ns.db.space
end

local function ReportTypes()
  local names = {}
  for value in pairs(ns.observedTypes) do
    if value == "untyped" then
      tinsert(names, "untyped")
    else
      tinsert(names, (Enum.TooltipDataType and tostring(value)) or tostring(value))
    end
  end

  if #names == 0 then
    ns.Print("no blip tooltips seen yet.")
  else
    table.sort(names)
    ns.Print("tooltip types seen on blips: " .. table.concat(names, ", ") .. ".")
  end
end

SLASH_TRACKINGALERT1, SLASH_TRACKINGALERT2 = "/trackingalert", "/tra"
function SlashCmdList.TRACKINGALERT(input)
  local command = strlower(strtrim(input or ""))

  if command == "calibrate" then
    local ok, detail = ns.CalibrateFromCursor()
    if not ok then ns.Print("calibration failed: " .. detail) end

  elseif command == "status" then
    ns.Print(("%s, coordinate space %s, %d nodes remembered."):format(
      ns.db.enabled and "enabled" or "disabled", SpaceLabel(), ns.SeenCount()))

  elseif command == "types" then
    ReportTypes()

  elseif command == "reset" then
    ns.ResetSeen()
    ns.Print("forgot every remembered node.")

  elseif command == "recalibrate" then
    ns.db.space = false
    ns.Print("coordinate space cleared, hover a blip near the minimap edge to redetect it.")

  elseif command == "test" then
    PlaySound(ns.db.sound or SOUNDKIT.MAP_PING, ns.db.channel)

  elseif categoryID then
    Settings.OpenToCategory(categoryID)
  end
end
