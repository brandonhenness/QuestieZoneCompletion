return function(test, equal)
    local function fresh(saved)
        local ns = {messages = {}, refreshes = 0, applications = 0, opens = 0}
        function ns:Print(message) self.messages[#self.messages + 1] = message end
        function ns:RequestRefresh() self.refreshes = self.refreshes + 1 end
        ns.UI = {ApplySettings = function() ns.applications = ns.applications + 1 end}
        ns.Adapter = {OpenJourney = function() ns.opens = ns.opens + 1; return true end}
        assert(loadfile("Config.lua"))("QuestieZoneCompletion", ns)
        ns.settings = ns.Config.Initialize(saved)
        return ns
    end

    local function withNative(callback)
        local oldSettings, oldSlider, oldButton, oldCombat = Settings, MinimalSliderWithSteppersMixin,
            CreateSettingsButtonInitializer, InCombatLockdown
        local native = {registered = 0, categories = 0, proxies = {}, controls = {}, opened = {}, initializers = {}, notices = 0}
        Settings = {VarType = {Boolean = "boolean", String = "string", Number = "number"}}
        function Settings.RegisterVerticalLayoutCategory(name)
            native.categories = native.categories + 1
            native.name = name
            return {GetID = function() return 1042 end}, {
                AddInitializer = function(_, value) native.initializers[#native.initializers + 1] = value end,
            }
        end
        function Settings.RegisterAddOnCategory() native.registered = native.registered + 1 end
        function Settings.RegisterProxySetting(_, variable, kind, title, default, getter, setter)
            equal(type(default), kind)
            local setting = {kind = kind, title = title, default = default, get = getter, set = setter}
            function setting:NotifyUpdate() native.notices = native.notices + 1 end
            native.proxies[variable] = setting
            return setting
        end
        for _, kind in ipairs({"Checkbox", "Dropdown", "Slider"}) do
            Settings["Create" .. kind] = function(_, setting, options, tooltip)
                native.controls[#native.controls + 1] = {kind = kind, setting = setting, options = options, tooltip = tooltip}
            end
        end
        function Settings.CreateSliderOptions(minimum, maximum, step)
            return {minimum = minimum, maximum = maximum, step = step, SetLabelFormatter = function() end}
        end
        function Settings.CreateControlTextContainer()
            local container = {values = {}}
            function container:Add(value, title, tooltip)
                self.values[#self.values + 1] = {value = value, title = title, tooltip = tooltip}
            end
            function container:GetData() return self.values end
            return container
        end
        function Settings.OpenToCategory(id) native.opened[#native.opened + 1] = id end
        CreateSettingsButtonInitializer = function(name, text, click, tooltip, searchable)
            return {name = name, text = text, click = click, tooltip = tooltip, searchable = searchable}
        end
        MinimalSliderWithSteppersMixin = {Label = {Right = 2}}
        InCombatLockdown = function() return false end
        local ok, err = pcall(callback, native)
        Settings, MinimalSliderWithSteppersMixin, CreateSettingsButtonInitializer, InCombatLockdown =
            oldSettings, oldSlider, oldButton, oldCombat
        if not ok then error(err) end
    end

    test("settings migrate old scope and lock preferences while preserving display choices", function()
        local saved = {schemaVersion = 1, visible = false, locked = false, knownScope = false,
            hideComplete = true, scale = 1.4, opacity = 0.5, x = 25, y = 60}
        local ns = fresh(saved)
        equal(ns.settings.schemaVersion, 3)
        equal(ns.settings.collapsed, false)
        equal(ns.settings.progressMode, "available")
        equal(ns.settings.attachToTracker, true)
        equal(ns.settings.knownScope, nil)
        equal(ns.settings.locked, nil)
        equal(ns.settings.visible, false)
        equal(ns.settings.hideComplete, true)
        equal(ns.settings.scale, 1.4)
        equal(ns.settings.opacity, 0.5)
        equal(ns.settings.x, 25)
        equal(ns.settings.y, 60)
        equal(saved.knownScope, false)
        equal(saved.schemaVersion, 1)
    end)

    test("minimized state persists and toggling only repaints the current settings", function()
        local ns = fresh({schemaVersion = 3, collapsed = true, x = 35, progressMode = "available"})
        local settings = ns.settings
        equal(settings.collapsed, true)
        ns.Config.ToggleCollapsed()
        equal(settings.collapsed, false)
        equal(ns.settings, settings)
        equal(settings.x, 35)
        equal(settings.progressMode, "available")
        equal(ns.applications, 1)
        equal(ns.refreshes, 0)
        ns.Config.ToggleCollapsed()
        equal(settings.collapsed, true)
        ns.Config.Reset()
        equal(settings.collapsed, false)
    end)

    test("settings sanitize corrupt saves and accept only valid progress modes", function()
        local ns = fresh({scale = math.huge, opacity = 0 / 0, x = 20000, y = -20000,
            visible = 0, attachToTracker = true, progressMode = "available"})
        equal(ns.settings.scale, 1)
        equal(ns.settings.opacity, 0.85)
        equal(ns.settings.x, 10000)
        equal(ns.settings.y, -10000)
        equal(ns.settings.visible, true)
        equal(ns.settings.attachToTracker, true)
        equal(ns.settings.progressMode, "available")
        ns = fresh("invalid")
        equal(ns.settings.visible, true)
        equal(ns.settings.progressMode, "available")
        equal(fresh({progressMode = "unknown"}).settings.progressMode, "available")
        ns = fresh({progressMode = "total", attachToTracker = false})
        equal(ns.settings.progressMode, "total")
        equal(ns.settings.attachToTracker, false)
    end)

    test("reset preserves the SavedVariables reference and restores progress and position defaults", function()
        local ns = fresh({visible = false, scale = 1.8, progressMode = "total", attachToTracker = false, x = 20})
        local saved = ns.settings
        ns.settings.legacy = true
        ns.Config.Reset()
        equal(ns.settings, saved)
        equal(saved.visible, true)
        equal(saved.scale, 1)
        equal(saved.progressMode, "available")
        equal(saved.attachToTracker, true)
        equal(saved.x, -300)
        equal(saved.legacy, nil)
        equal(ns.applications, 1)
        equal(ns.refreshes, 1)
    end)

    test("slash controls expose progress basis and tracker attachment without lock or scope settings", function()
        local ns = fresh()
        local command = ns.Config.HandleCommand
        command("  HIDE  ")
        equal(ns.settings.visible, false)
        command("")
        equal(ns.settings.visible, true)
        command("scale 1.25")
        equal(ns.settings.scale, 1.25)
        command("opacity 0")
        equal(ns.settings.opacity, 0)
        command("mode available")
        equal(ns.settings.progressMode, "available")
        command("complete on")
        equal(ns.settings.hideComplete, true)
        command("attach on")
        equal(ns.settings.attachToTracker, true)
        command("mode total")
        equal(ns.settings.progressMode, "total")
        equal(ns.refreshes, 8)
        equal(ns.applications, 8)
    end)

    test("invalid slash values and retired commands do not mutate settings", function()
        local ns = fresh()
        for _, message in ipairs({"scale bad", "scale 2", "opacity -1", "mode maybe", "complete", "attach", "lock", "scope on"}) do
            ns.Config.HandleCommand(message)
        end
        equal(ns.settings.scale, 1)
        equal(ns.settings.opacity, 0.85)
        equal(ns.settings.progressMode, "available")
        equal(ns.settings.hideComplete, false)
        equal(ns.settings.attachToTracker, true)
        equal(ns.settings.locked, nil)
        equal(ns.settings.knownScope, nil)
        equal(ns.applications, 0)
        equal(ns.refreshes, 0)
    end)

    test("open command surfaces Journey failures and refresh requests a read", function()
        local ns = fresh()
        ns.Adapter.OpenJourney = function() return false, "Wait for Questie." end
        ns.Config.HandleCommand("open")
        equal(ns.messages[1], "Wait for Questie.")
        ns.Config.HandleCommand("refresh")
        equal(ns.refreshes, 1)
    end)

    test("native Settings register one generated AddOns category and no custom window", function()
        withNative(function(native)
            local ns = fresh()
            equal(ns.Config.RegisterSettings(), true)
            equal(ns.Config.RegisterSettings(), true)
            equal(native.categories, 1)
            equal(native.registered, 1)
            equal(native.name, "Questie Zone Completion")
            equal(#native.controls, 6)
            equal(#native.initializers, 2)
            equal(ns.Config.ToggleWindow, nil)
            equal(native.proxies.QuestieZoneCompletion_locked, nil)
            equal(native.proxies.QuestieZoneCompletion_knownScope, nil)
            local dropdown = native.controls[4]
            equal(dropdown.kind, "Dropdown")
            local options = dropdown.options()
            equal(options[1].value, "total")
            equal(options[2].value, "available")
        end)
    end)

    test("native proxy setters persist and apply changes and getters follow external changes", function()
        withNative(function(native)
            local ns = fresh()
            ns.Config.RegisterSettings()
            native.proxies.QuestieZoneCompletion_progressMode.set("available")
            equal(ns.settings.progressMode, "available")
            native.proxies.QuestieZoneCompletion_attachToTracker.set(true)
            equal(ns.settings.attachToTracker, true)
            native.proxies.QuestieZoneCompletion_scale.set(1.5)
            equal(ns.settings.scale, 1.5)
            equal(ns.refreshes, 3)
            equal(ns.applications, 3)
            ns.settings.visible = false
            equal(native.proxies.QuestieZoneCompletion_visible.get(), false)
            ns.Config.RefreshControls()
            equal(native.notices > 0, true)
            native.initializers[1].click()
            equal(ns.settings.visible, true)
            equal(ns.settings.progressMode, "available")
            equal(ns.settings.attachToTracker, true)
            native.initializers[2].click()
            equal(ns.refreshes, 5)
        end)
    end)

    test("config command opens the native category and refuses opening it during combat", function()
        withNative(function(native)
            local ns = fresh()
            ns.Config.HandleCommand("config")
            equal(#native.opened, 1)
            equal(native.opened[1], 1042)
            InCombatLockdown = function() return true end
            equal(ns.Config.Open(), false)
            equal(#native.opened, 1)
            equal(ns.messages[1], "Open AddOns settings after combat.")
        end)
    end)

    test("unavailable native Settings degrade to clear guidance without creating a custom window", function()
        withNative(function()
            local ns = fresh()
            Settings = nil
            equal(ns.Config.RegisterSettings(), false)
            equal(ns.Config.Open(), false)
            equal(#ns.messages, 1)
            equal(string.find(ns.messages[1], "AddOns settings", 1, true) ~= nil, true)
        end)
    end)
end
