return function(test, equal)
    local function withUI(callback)
        local names = {"CreateFrame", "UIParent", "GameTooltip", "GetTime", "InCombatLockdown", "IsShiftKeyDown", "IsControlKeyDown"}
        local old = {}
        for _, name in ipairs(names) do old[name] = _G[name] end
        local now, combat, shift, ctrl = 20, false, false, false
        local function object(parent)
            local item = {scripts = {}, shown = true, scale = 1, width = 1920, height = 1080, parent = parent}
            function item:SetSize(w, h) self.width, self.height = w, h end
            function item:SetWidth(w) self.width = w end
            function item:SetHeight(h) self.height = h end
            function item:GetWidth() return self.width end
            function item:GetHeight() return self.height end
            function item:SetScale(value) self.scale = value end
            function item:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
            function item:GetCenter() return self.centerX or 960, self.centerY or 540 end
            function item:SetParent(value) self.parent = value end
            function item:GetParent() return self.parent end
            function item:SetPoint(...) self.point = {...} end
            function item:ClearAllPoints() self.point = nil end
            function item:SetAllPoints() end
            function item:SetText(text) self.text = text end
            function item:SetTextColor(...) self.color = {...} end
            function item:SetFont(...) self.font = {...} end
            function item:SetJustifyH() end
            function item:SetWordWrap(value) self.wordWrap = value end
            function item:GetUnboundedStringWidth() return #(self.text or "") * ((self.font and self.font[2]) or 12) * 0.6 end
            function item:SetFrameStrata() end
            function item:SetMovable() end
            function item:SetClampedToScreen() end
            function item:EnableMouse() end
            function item:RegisterForDrag() end
            function item:RegisterForClicks() end
            function item:SetBackdrop(value) self.backdrop = value end
            function item:SetBackdropColor(...) self.backdropColor = {...} end
            function item:SetBackdropBorderColor(...) self.borderColor = {...} end
            function item:SetScript(name, script) self.scripts[name] = script end
            function item:CreateFontString() return object(self) end
            function item:CreateTexture() return object(self) end
            function item:SetColorTexture(...) self.color = {...} end
            function item:SetTexture(value) self.texturePath = value end
            function item:SetShown(value) self.shown = value end
            function item:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
            function item:Hide() self.shown = false end
            function item:Show() self.shown = true end
            function item:StartMoving() self.moving = true end
            function item:StopMovingOrSizing() self.moving = false end
            return item
        end
        _G.CreateFrame = function(_, _, parent) return object(parent) end
        _G.UIParent = object()
        _G.GameTooltip = object()
        function GameTooltip:GetOwner() return self.owner end
        function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
        function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
        _G.GetTime = function() return now end
        _G.InCombatLockdown = function() return combat end
        _G.IsShiftKeyDown = function() return shift end
        _G.IsControlKeyDown = function() return ctrl end
        local ns = {messages = {}, opens = 0, settingsOpens = 0, trackerStarts = 0, trackerStops = 0}
        function ns:Print(message) self.messages[#self.messages + 1] = message end
        local style = {width = 304, leftInset = 14, rightInset = 30, headerFont = "QuestieHeader.ttf",
            font = "QuestieBody.ttf", headerFontSize = 14, fontSize = 12, outline = "OUTLINE", headerOutline = "THICKOUTLINE",
            headerColor = {1, 0.82, 0}, textColor = {0.9, 0.9, 0.9}, backdropEnabled = false, borderEnabled = false}
        ns.Adapter = {
            OpenJourney = function() ns.opens = ns.opens + 1; return true end,
            GetTrackerStyle = function() return style end,
            GetTrackerIcon = function() return ns.icon end,
            StartTrackerDrag = function()
                ns.trackerStarts = ns.trackerStarts + 1
                if ns.dragFailure then return false, "Tracker cannot move." end
                ns.movingTracker = ns.Adapter:GetTrackerAnchor()
                ns.movingTracker:StartMoving()
                return true
            end,
            StopTrackerDrag = function()
                ns.trackerStops = ns.trackerStops + 1
                ns.movingTracker:StopMovingOrSizing()
                return true
            end,
        }
        assert(loadfile("Config.lua"))("QuestieZoneCompletion", ns)
        ns.settings = ns.Config.Initialize()
        ns.Config.Open = function() ns.settingsOpens = ns.settingsOpens + 1 end
        assert(loadfile("UI.lua"))("QuestieZoneCompletion", ns)
        ns.UI:Create()
        local ok, reason = pcall(callback, ns, {
            combat = function(value) combat = value end,
            shift = function(value) shift = value end,
            ctrl = function(value) ctrl = value end,
            time = function(value) now = value end,
            object = object,
            style = style,
        })
        for _, name in ipairs(names) do _G[name] = old[name] end
        if not ok then error(reason, 0) end
    end

    local function progress(mode)
        return {status = "ready", mode = mode or "total", zoneName = "The Barrens", completed = 15,
            inProgress = 22, available = 13, missingRequirements = 50, total = mode == "available" and 50 or 100,
            percent = mode == "available" and 30 or 15, unknown = 0, breadcrumbs = 4,
            excluded = 10, repeatable = 8, alternatives = 0, unobtainable = 2}
    end

    test("widget displays four progress segments with no on-screen legend", function()
        withUI(function(ns)
            ns.UI:Render(progress())
            local frame = ns.UI.frame
            equal(frame.count.text, "15 / 100 completed")
            equal(frame.percent.text, "15%")
            equal(frame.legend, nil)
            equal(frame.bar.segments.completed.width, 39)
            equal(frame.bar.segments.inProgress.width, 57.2)
            equal(frame.bar.segments.available.width, 33.8)
            equal(frame.bar.segments.missingRequirements.width, 130)
            equal(frame.unlocked, nil)
            equal(frame.scripts.OnUpdate, nil)
        end)
    end)

    test("short tooltip provides colored counts while available mode excludes missing from the bar", function()
        withUI(function(ns)
            ns.UI:Render(progress("available"))
            local frame = ns.UI.frame
            equal(frame.count.text, "15 / 50 completed")
            equal(frame.percent.text, "30%")
            equal(frame.bar.segments.missingRequirements.shown, false)
            equal(frame.legend, nil)
            equal(frame.bar.segments.completed.width, 78)
            frame.scripts.OnEnter()
            local tooltip = table.concat(GameTooltip.lines, "\n")
            equal(tooltip:find("Missing requirements: 50", 1, true) ~= nil, true)
            equal(tooltip:find("missing requirements excluded", 1, true) ~= nil, true)
            equal(tooltip:find("unobtainable", 1, true), nil)
            equal(tooltip:find("breadcrumb", 1, true), nil)
            equal(tooltip:find("Ctrl-drag", 1, true), nil)
            equal(#GameTooltip.lines, 6)
            equal(tooltip:find("coverage", 1, true), nil)
        end)
    end)

    test("unknown empty and dependency states show no fabricated percentage or hiding", function()
        withUI(function(ns)
            ns.settings.hideComplete = true
            local data = progress()
            data.status, data.unknown = "incomplete", 1
            ns.UI:Render(data)
            equal(ns.UI.frame.percent.text, "\226\128\148")
            equal(ns.UI.frame.bar.segments.completed.shown, false)
            equal(ns.UI.frame.shown, true)
            ns.UI:Render({status = "waiting", completed = 0, total = 0})
            equal(ns.UI.frame.count.text, "\226\128\148")
            ns.UI:Render({status = "ready", completed = 0, total = 0, percent = 100})
            equal(ns.UI.frame.percent.text, "\226\128\148")
            equal(ns.UI.frame.shown, true)
        end)
    end)

    test("hide complete respects selected denominator and never rounds unfinished data to 100", function()
        withUI(function(ns)
            ns.settings.hideComplete = true
            local data = progress("available")
            data.completed, data.inProgress, data.available, data.percent = 50, 0, 0, 100
            ns.UI:Render(data)
            equal(ns.UI.frame.shown, false)
            data.completed, data.available, data.percent = 49, 1, 99.9
            ns.UI:Render(data)
            equal(ns.UI.frame.shown, true)
            equal(ns.UI.frame.percent.text, "99%")
        end)
    end)

    test("widget click blocks combat and Ctrl clicks and reports failed Journey navigation", function()
        withUI(function(ns, control)
            ns.UI.frame.scripts.OnClick()
            equal(ns.opens, 1)
            control.ctrl(true)
            ns.UI.frame.scripts.OnClick()
            equal(ns.opens, 1)
            control.ctrl(false)
            control.combat(true)
            ns.UI.frame.scripts.OnClick()
            equal(ns.opens, 1)
            equal(ns.messages[1], "Open Questie Journey after combat.")
            control.combat(false)
            ns.Adapter.OpenJourney = function() return false, "Journey changed." end
            ns.UI.frame.scripts.OnClick()
            equal(ns.messages[2], "Journey changed.")
        end)
    end)

    test("ordinary and Shift dragging cannot move widget and Ctrl-drag saves scaled position", function()
        withUI(function(ns, control)
            local frame = ns.UI.frame
            ns.settings.scale = 1.5
            ns.UI:ApplySettings()
            frame.scripts.OnDragStart(frame)
            equal(frame.moving, nil)
            frame.scripts.OnDragStop(frame)
            frame.scripts.OnClick()
            equal(ns.opens, 0)
            control.shift(true)
            frame.scripts.OnDragStart(frame)
            equal(frame.moving, nil)
            frame.scripts.OnDragStop(frame)
            control.shift(false)
            frame.centerX, frame.centerY = 800, 400
            control.ctrl(true)
            frame.scripts.OnDragStart(frame)
            equal(frame.moving, true)
            frame.scripts.OnDragStop(frame)
            equal(frame.moving, false)
            equal(ns.settings.x, 240)
            equal(ns.settings.y, 60)
            equal(frame.point[4], 160)
            equal(frame.point[5], 40)
            control.ctrl(false)
            frame.scripts.OnClick()
            equal(ns.opens, 0)
            control.time(21)
            frame.scripts.OnClick()
            equal(ns.opens, 1)
        end)
    end)

    test("attachment inherits tracker motion visibility and scale without modifying scripts", function()
        withUI(function(ns, control)
            local tracker = control.object(UIParent)
            ns.Adapter.GetTrackerAnchor = function() return tracker end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            local frame = ns.UI.frame
            equal(ns.UI.attached, true)
            equal(frame:GetParent(), tracker)
            equal(frame.point[1], "BOTTOMLEFT")
            equal(frame.point[2], tracker)
            equal(frame.point[3], "TOPLEFT")
            tracker.scale = 1.3
            equal(frame:GetEffectiveScale(), 1.3)
            tracker:Hide()
            equal(frame:IsVisible(), false)
            tracker:Show()
            equal(frame:IsVisible(), true)
            equal(next(tracker.scripts), nil)
            equal(tracker.point, nil)
        end)
    end)

    test("attached Ctrl-drag moves Questie without detaching or changing standalone position", function()
        withUI(function(ns, control)
            local tracker = control.object(UIParent)
            tracker.scale = 2
            ns.Adapter.GetTrackerAnchor = function() return tracker end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            local frame = ns.UI.frame
            frame.centerX, frame.centerY = 800, 400
            local oldX, oldY = ns.settings.x, ns.settings.y
            control.ctrl(true)
            frame.scripts.OnDragStart(frame)
            equal(ns.settings.attachToTracker, true)
            equal(ns.UI.attached, true)
            equal(frame:GetParent(), tracker)
            equal(ns.settings.x, oldX)
            equal(ns.settings.y, oldY)
            equal(tracker.moving, true)
            equal(frame.moving, nil)
            equal(ns.trackerStarts, 1)
            frame.point = {"moving"}
            ns.UI:Render(progress())
            equal(frame.point[1], "moving")
            control.ctrl(false)
            frame.scripts.OnDragStop(frame)
            equal(ns.trackerStops, 1)
            equal(tracker.moving, false)
            equal(ns.settings.attachToTracker, true)
            equal(ns.settings.x, oldX)
            equal(ns.settings.y, oldY)
        end)
    end)

    test("widget copies Questie typography, width and transparent default instead of a separate card", function()
        withUI(function(ns, control)
            local frame = ns.UI.frame
            ns.UI:Render(progress())
            equal(frame:GetWidth(), 304)
            equal(frame:GetHeight(), 59)
            equal(frame.header.label.font[1], "QuestieHeader.ttf")
            equal(frame.header.label.font[2], 14)
            equal(frame.header.label.font[3], "THICKOUTLINE")
            equal(frame.title.font[1], "QuestieBody.ttf")
            equal(frame.count.font[1], "QuestieBody.ttf")
            equal(frame.count.font[2], 12)
            equal(frame.count.font[3], "OUTLINE")
            equal(frame.header.label.color[2], 0.82)
            equal(frame.count.color[1], 0.9)
            equal(frame.title.point[2], 14)
            equal(frame.percent.point[2], -30)
            equal(frame.backdrop, nil)
            control.style.width = 360
            control.style.backdropEnabled, control.style.borderEnabled = true, true
            control.style.backdropColor, control.style.borderColor = {0.2, 0.3, 0.4, 0.6}, {1, 1, 1, 0.8}
            ns.settings.opacity = 0.5
            ns.UI:Render(progress())
            equal(frame:GetWidth(), 360)
            equal(frame.bar:GetWidth(), 316)
            equal(frame.backdrop.bgFile, "Interface\\Buttons\\WHITE8X8")
            equal(frame.backdrop.edgeSize, 16)
            equal(frame.backdropColor[1], 0.2)
            equal(frame.backdropColor[4], 0.3)
            equal(frame.borderColor[4], 0.8)
            control.style.width = 25
            ns.UI:Render(progress())
            equal(frame:GetWidth(), 180)
            equal(frame.bar.point[2] + frame.bar:GetWidth() <= frame:GetWidth(), true)
        end)
    end)

    test("failed attached movement and combat do not detach or begin an independent drag", function()
        withUI(function(ns, control)
            local tracker = control.object(UIParent)
            ns.Adapter.GetTrackerAnchor = function() return tracker end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            local frame = ns.UI.frame
            control.ctrl(true)
            ns.dragFailure = true
            frame.scripts.OnDragStart(frame)
            equal(ns.messages[1], "Tracker cannot move.")
            equal(frame.moving, nil)
            equal(ns.settings.attachToTracker, true)
            frame.scripts.OnDragStop(frame)
            equal(ns.trackerStops, 0)
            control.combat(true)
            frame.scripts.OnDragStart(frame)
            equal(ns.messages[2], "Move the tracker after combat.")
            equal(ns.trackerStarts, 1)
            equal(ns.settings.attachToTracker, true)
        end)
    end)

    test("hiding a dragged section finishes the delegated tracker movement", function()
        withUI(function(ns, control)
            local tracker = control.object(UIParent)
            ns.Adapter.GetTrackerAnchor = function() return tracker end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            control.ctrl(true)
            ns.UI.frame.scripts.OnDragStart(ns.UI.frame)
            ns.UI.frame.scripts.OnHide()
            equal(ns.trackerStops, 1)
            equal(tracker.moving, false)
            ns.UI.frame.scripts.OnDragStop(ns.UI.frame)
            equal(ns.trackerStops, 1)
        end)
    end)

    test("narrow tracker drops completed and keeps count and percent on one line", function()
        withUI(function(ns, control)
            local data = progress("available")
            data.completed, data.total, data.percent = 17, 52, 100 * 17 / 52
            control.style.width = 180
            ns.UI:Render(data)
            local frame = ns.UI.frame
            equal(frame.count.text, "17 / 52")
            equal(frame.percent.text, "32%")
            equal(frame.count.wordWrap, false)
            equal(frame.percent.wordWrap, false)
            equal(frame.count:GetHeight(), 14)
            equal(frame.percent:GetHeight(), 14)
            equal(frame.count:GetWidth() + frame.percent:GetWidth() + 8, frame.layout.innerWidth)
            control.style.width = 350
            ns.UI:Render(data)
            equal(frame.count.text, "17 / 52 completed")
            -- A large font changes measured width even without another resize.
            control.style.fontSize = 26
            ns.UI:Render(data)
            equal(frame.count.text, "17 / 52")
            equal(frame.count:GetHeight(), 28)
        end)
    end)

    test("header minimizes only the body and preserves collapse through layout refreshes", function()
        withUI(function(ns)
            ns.UI:Render(progress())
            local frame = ns.UI.frame
            equal(frame.header.label.text, "Zone Completion")
            frame.header.scripts.OnClick()
            equal(ns.settings.collapsed, true)
            equal(frame.header.label.text, "Zone Completion +")
            equal(frame:GetHeight(), 18)
            equal(frame.shown, true)
            equal(frame.header.shown, true)
            equal(frame.settingsButton.shown, true)
            equal(frame.title.shown, false)
            equal(frame.count.shown, false)
            equal(frame.percent.shown, false)
            equal(frame.bar.shown, false)
            ns.UI:Render(progress("available"))
            equal(frame.bar.shown, false)
            equal(ns.settings.collapsed, true)
            equal(ns.opens, 0)
            frame.header.scripts.OnClick()
            equal(ns.settings.collapsed, false)
            equal(frame.bar.shown, true)
            equal(frame.title.shown, true)
            equal(frame:GetHeight(), 59)
        end)
    end)

    test("question mark opens only settings and preserves tiny child tooltips", function()
        withUI(function(ns)
            local frame = ns.UI.frame
            ns.UI:Render(progress())
            equal(frame.settingsButton.glyph.text, "?")
            equal(frame.settingsButton.glyph.shown, true)
            ns.icon = "Interface/AddOns/Questie/Icons/complete.blp"
            ns.UI:Render(progress())
            equal(frame.settingsButton.texture.texturePath, ns.icon)
            equal(frame.settingsButton.texture.shown, true)
            equal(frame.settingsButton.glyph.shown, false)
            frame.settingsButton.scripts.OnClick()
            equal(ns.settingsOpens, 1)
            equal(ns.opens, 0)
            equal(ns.settings.collapsed, false)
            frame.settingsButton.scripts.OnEnter(frame.settingsButton)
            equal(GameTooltip.text, "Open settings")
            equal(#GameTooltip.lines, 0)
            ns.UI:Render(progress("available"))
            equal(GameTooltip.text, "Open settings")
            equal(#GameTooltip.lines, 0)
            frame.header.scripts.OnEnter(frame.header)
            equal(GameTooltip.text, "Zone Completion")
            equal(#GameTooltip.lines, 2)
        end)
    end)

    test("header and settings share attached Ctrl-drag without accidental click actions", function()
        withUI(function(ns, control)
            local tracker = control.object(UIParent)
            ns.Adapter.GetTrackerAnchor = function() return tracker end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            local frame = ns.UI.frame
            control.ctrl(true)
            frame.header.scripts.OnDragStart(frame.header)
            equal(tracker.moving, true)
            equal(frame.header.moving, nil)
            control.ctrl(false)
            frame.header.scripts.OnDragStop(frame.header)
            frame.header.scripts.OnClick()
            equal(ns.settings.collapsed, false)
            equal(ns.settings.attachToTracker, true)
            equal(ns.trackerStops, 1)
            control.time(21)
            control.ctrl(true)
            frame.settingsButton.scripts.OnDragStart(frame.settingsButton)
            equal(tracker.moving, true)
            equal(frame.settingsButton.moving, nil)
            control.ctrl(false)
            frame.settingsButton.scripts.OnDragStop(frame.settingsButton)
            frame.settingsButton.scripts.OnClick()
            equal(ns.settingsOpens, 0)
            equal(ns.opens, 0)
            equal(ns.trackerStops, 2)
        end)
    end)

    test("header control clicks do not change collapse or settings during a Ctrl gesture", function()
        withUI(function(ns, control)
            local frame = ns.UI.frame
            control.ctrl(true)
            frame.header.scripts.OnClick()
            frame.settingsButton.scripts.OnClick()
            equal(ns.settings.collapsed, false)
            equal(ns.settingsOpens, 0)
            control.ctrl(false)
            control.combat(true)
            frame.header.scripts.OnClick()
            equal(ns.settings.collapsed, false)
        end)
    end)

    test("missing tracker uses standalone position without losing attachment preference", function()
        withUI(function(ns)
            ns.Adapter.GetTrackerAnchor = function() return nil end
            ns.settings.attachToTracker = true
            ns.UI:ApplySettings()
            equal(ns.UI.frame:GetParent(), UIParent)
            equal(ns.settings.attachToTracker, true)
            equal(ns.UI.attached, false)
        end)
    end)
end
