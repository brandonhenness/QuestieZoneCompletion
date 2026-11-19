local _, ns = ...

local Config = {}
ns.Config = Config

local defaults = {
    schemaVersion = 3,
    visible = true,
    collapsed = false,
    scale = 1,
    opacity = 0.85,
    hideComplete = false,
    progressMode = "available",
    attachToTracker = true,
    x = -300,
    y = 100,
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function bounded(value, fallback, minimum, maximum)
    if not finite(value) then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

function Config.Initialize(saved)
    local source = type(saved) == "table" and saved or {}
    local settings = {}
    for key, value in pairs(defaults) do
        settings[key] = value
        if type(value) == "boolean" and type(source[key]) == "boolean" then
            settings[key] = source[key]
        end
    end
    settings.scale = bounded(source.scale, defaults.scale, 0.6, 1.8)
    settings.opacity = bounded(source.opacity, defaults.opacity, 0, 1)
    settings.x = bounded(source.x, defaults.x, -10000, 10000)
    settings.y = bounded(source.y, defaults.y, -10000, 10000)
    if source.progressMode == "available" or source.progressMode == "total" then
        settings.progressMode = source.progressMode
    end
    -- Version 1's opt-in scope and lock state are deliberately retired. Existing
    -- display preferences and position survive; progress is shown after migration.
    return settings
end

local nativeSettings = {}
local category
local registrationStarted = false
local registrationError
local refreshing = false

function Config.RefreshControls()
    if refreshing then return end
    refreshing = true
    for _, setting in pairs(nativeSettings) do setting:NotifyUpdate() end
    refreshing = false
end

local function apply()
    if ns.UI then ns.UI:ApplySettings() end
    Config.RefreshControls()
end

function Config.Reset()
    for key in pairs(ns.settings) do ns.settings[key] = nil end
    for key, value in pairs(defaults) do ns.settings[key] = value end
    apply()
    ns:RequestRefresh()
end

function Config.ToggleCollapsed()
    ns.settings.collapsed = not ns.settings.collapsed
    apply()
end

local function proxy(key, valueType, title)
    local setting = Settings.RegisterProxySetting(category, "QuestieZoneCompletion_" .. key,
        valueType, title, defaults[key], function() return ns.settings[key] end, function(value)
            if type(value) ~= type(defaults[key]) then return end
            if key == "progressMode" and value ~= "total" and value ~= "available" then return end
            if key == "scale" then value = bounded(value, defaults.scale, 0.6, 1.8) end
            if key == "opacity" then value = bounded(value, defaults.opacity, 0, 1) end
            ns.settings[key] = value
            apply()
            ns:RequestRefresh()
        end)
    nativeSettings[key] = setting
    return setting
end

local function addSlider(key, title, minimum, maximum, step, tooltip, formatter)
    local setting = proxy(key, Settings.VarType.Number, title)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    Settings.CreateSlider(category, setting, options, tooltip)
end

function Config.RegisterSettings()
    if registrationStarted then return category ~= nil and not registrationError, registrationError end
    local required = { "RegisterVerticalLayoutCategory", "RegisterAddOnCategory", "RegisterProxySetting",
        "CreateCheckbox", "CreateSlider", "CreateSliderOptions", "CreateDropdown", "CreateControlTextContainer" }
    if type(Settings) ~= "table" or type(Settings.VarType) ~= "table" then
        return false, "Blizzard's AddOns settings are unavailable in this client."
    end
    for _, name in ipairs(required) do
        if type(Settings[name]) ~= "function" then
            return false, "Blizzard's AddOns settings are unavailable in this client."
        end
    end
    if not MinimalSliderWithSteppersMixin or not MinimalSliderWithSteppersMixin.Label then
        return false, "Blizzard's slider controls are unavailable in this client."
    end
    registrationStarted = true
    local ok, err = pcall(function()
        -- Verified in Forever's Blizzard_Settings_Shared implementation. Blizzard
        -- owns the category, generated controls, layout and Settings search results.
        local layout
        category, layout = Settings.RegisterVerticalLayoutCategory("Questie Zone Completion")
        Settings.CreateCheckbox(category, proxy("visible", Settings.VarType.Boolean, "Show widget"),
            "Show quest progress for your current zone. Hold Ctrl and drag to move it.")
        Settings.CreateCheckbox(category, proxy("attachToTracker", Settings.VarType.Boolean, "Attach above Questie tracker"),
            "Keep the widget above Questie's tracker. Ctrl-drag moves the tracker and widget together. Disable to position it independently.")
        Settings.CreateCheckbox(category, proxy("hideComplete", Settings.VarType.Boolean, "Hide when complete"),
            "Hide when every quest included by the selected progress mode is completed.")

        local mode = proxy("progressMode", Settings.VarType.String, "Progress basis")
        local function modeOptions()
            local options = Settings.CreateControlTextContainer()
            options:Add("total", "All zone quests", "Include completed, in-progress, available and missing-requirement quests.")
            options:Add("available", "Available quests", "Exclude missing-requirement quests. Progress can decrease as new quests unlock.")
            return options:GetData()
        end
        Settings.CreateDropdown(category, mode, modeOptions,
            "Choose the quests represented by the bar. Repeatable and unobtainable quests are excluded in both modes.")
        addSlider("scale", "Widget scale", 0.6, 1.8, 0.05,
            "Adjust the widget's size.", function(value) return string.format("%.2fx", value) end)
        addSlider("opacity", "Background opacity", 0, 1, 0.05,
            "Adjust background opacity when Questie's tracker background is enabled.",
            function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end)
        if type(CreateSettingsButtonInitializer) == "function" then
            layout:AddInitializer(CreateSettingsButtonInitializer("Display defaults", "Reset", Config.Reset,
                "Restore this character's display, progress mode and position defaults.", true))
            layout:AddInitializer(CreateSettingsButtonInitializer("Quest data", "Refresh", function() ns:RequestRefresh() end,
                "Refresh this zone's quest progress from Questie.", true))
        end
        Settings.RegisterAddOnCategory(category)
    end)
    if not ok then
        Config.lastError = tostring(err)
        registrationError = "Questie Zone Completion could not register its AddOns settings. Reload after updating the addon."
        return false, registrationError
    end
    return true
end

function Config.Open()
    if InCombatLockdown() then
        ns:Print("Open AddOns settings after combat.")
        return false
    end
    local ok, message = Config.RegisterSettings()
    if not ok then ns:Print(message); return false end
    if type(Settings.OpenToCategory) ~= "function" then
        ns:Print("Open Options > AddOns > Questie Zone Completion to change settings.")
        return false
    end
    Settings.OpenToCategory(category:GetID())
    return true
end

local function switch(value)
    if value == "on" then return true end
    if value == "off" then return false end
end

function Config.HandleCommand(message)
    local command, argument = string.match(string.lower(message or ""), "^%s*(%S*)%s*(.-)%s*$")
    if command == "config" then
        Config.Open()
        return
    elseif command == "reset" then
        Config.Reset()
        ns:Print("Display settings reset.")
        return
    elseif command == "refresh" then
        ns:RequestRefresh()
        return
    elseif command == "open" then
        local ok, reason = ns.Adapter:OpenJourney()
        if not ok then ns:Print(reason or "Questie Journey is unavailable.") end
        return
    elseif command == "" or command == "toggle" then
        ns.settings.visible = not ns.settings.visible
    elseif command == "show" then
        ns.settings.visible = true
    elseif command == "hide" then
        ns.settings.visible = false
    elseif command == "scale" or command == "opacity" then
        local value = tonumber(argument)
        local minimum = command == "scale" and 0.6 or 0
        local maximum = command == "scale" and 1.8 or 1
        if not finite(value) or value < minimum or value > maximum then
            ns:Print(string.format("Use /qzc %s %.1f to %.1f.", command, minimum, maximum))
            return
        end
        ns.settings[command] = value
    elseif command == "complete" or command == "attach" then
        local value = switch(argument)
        if value == nil then ns:Print("Use /qzc " .. command .. " on or off."); return end
        ns.settings[command == "complete" and "hideComplete" or "attachToTracker"] = value
    elseif command == "mode" then
        if argument ~= "total" and argument ~= "available" then
            ns:Print("Use /qzc mode total or available.")
            return
        end
        ns.settings.progressMode = argument
    else
        ns:Print("/qzc [show | hide | config | reset | refresh | open]")
        ns:Print("/qzc scale 0.6-1.8; opacity 0-1; complete on/off; attach on/off; mode total/available")
        return
    end
    apply()
    ns:RequestRefresh()
end
