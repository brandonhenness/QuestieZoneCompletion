return function(test, equal)
    -- Controlled upstream contracts, not a second implementation of Questie's rules.
    -- Category labels deliberately carry no usable English counts.
    local function fresh()
        local ns = {}
        assert(loadfile("ZoneProgress.lua"))("QuestieZoneCompletion", ns)
        assert(loadfile("QuestieAdapter.lua"))("QuestieZoneCompletion", ns)
        local fixture = {
            ns = ns, records = {}, completed = {}, active = {}, quests = {}, imports = 0,
            zone = 12, parent = {}, readyRegistrations = 0, updateRegistrations = 0,
            readyCalls = 0, updateCalls = 0, toggles = 0, shown = false, tabSelections = {},
        }
        local tree, byCategory = {}, {}
        for _, category in ipairs({"b", "a", "r", "c", "p", "u", "h"}) do
            local group = {value = category, text = "localized label [garbage]", children = {}}
            tree[#tree + 1], byCategory[category] = group, group
        end
        fixture.tree, fixture.byCategory = tree, byCategory
        local states = {WRONG_RACE = 1, WRONG_CLASS = 2, BLACKLISTED = 3, AVAILABLE = 4,
            EXCLUSIVE_BREADCRUMB = 5}
        local db = {QuestPointers = {}, DoableStates = states}
        fixture.db = db
        db.QueryQuestSingle = function(id, key)
            local record = fixture.records[id]
            if key == "name" then return record and record.name end
            error("Unexpected field query: " .. tostring(key))
        end
        db.IsRepeatable = function(id) return fixture.records[id].repeatable == true end
        db.IsDailyQuest = function(id) return fixture.records[id].daily == true end
        db.IsWeeklyQuest = function(id) return fixture.records[id].weekly == true end
        db.IsMonthlyQuest = function(id) return fixture.records[id].monthly == true end
        db.IsDoableVerbose = function(id)
            return "localized explanation", false, fixture.records[id].reason
        end
        db.IsComplete = function() error("Objective readiness cannot prove historical completion") end
        local journey = {zoneMap = {[12] = fixture.quests}, private = {questsByZone = {}}}
        fixture.journey = journey
        function journey.private.questsByZone:CategorizeQuests(quests)
            equal(quests, fixture.quests)
            return fixture.tree
        end
        function journey:IsShown() return fixture.shown end
        function journey:ToggleJourneyWindow()
            fixture.toggles = fixture.toggles + 1
            fixture.shown = not fixture.shown
        end
        journey.tabGroup = {
            tablist = {{value = "journey"}, {value = "zone"}, {value = "faction"}},
            localstatus = {selected = "journey"},
            SelectTab = function(self, value)
                equal(fixture.shown, true, "SelectTab runs after Journey is opened")
                fixture.tabSelections[#fixture.tabSelections + 1] = value
                self.localstatus.selected = value
                -- This models the existing Questie OnGroupSelected callback.
                journey.private.lastOpenWindow = value
            end,
        }
        local modules = {
            QuestieJourney = journey, QuestieDB = db,
            QuestiePlayer = {GetCurrentZoneId = function() return fixture.zone end},
            ZoneDB = {GetParentZoneId = function(_, id) return fixture.parent[id] end},
        }
        fixture.modules = modules
        QuestieLoader = {_modules = modules, ImportModule = function(_, name)
            fixture.imports = fixture.imports + 1
            return modules[name]
        end}
        Questie = {API = {isReady = true}, db = {char = {complete = {}}},
            icons = {complete = "Interface\\Addons\\Questie\\Icons\\complete.blp"}}
        Questie.API.RegisterOnReady = function(callback)
            fixture.readyRegistrations = fixture.readyRegistrations + 1
            if Questie.API.isReady then callback() else fixture.onReady = callback end
        end
        Questie.API.RegisterForQuestUpdates = function(callback)
            fixture.updateRegistrations = fixture.updateRegistrations + 1
            fixture.onUpdate = callback
        end
        LibQuestieDB = {RequireContract = function(required)
            equal(required, 4)
            return fixture.contract ~= false
        end}
        GetRealZoneText = function() return "Elwynn Forest" end
        C_QuestLog = {
            IsOnQuest = function(id)
                if fixture.nilActive then return nil end
                return fixture.active[id] == true
            end,
            IsQuestFlaggedCompleted = function(id)
                if fixture.nilCompletion then return nil end
                if fixture.completionError then error("Completion data temporarily inaccessible") end
                return fixture.completed[id] == true
            end,
            IsQuestFlaggedCompletedOnAccount = function() error("Account completion is outside scope") end,
        }
        InCombatLockdown = function() return fixture.combat == true end
        IsControlKeyDown = function() return fixture.control ~= false end
        LibStub, hooksecurefunc = nil, nil
        function fixture:tracker()
            local frame = {
                GetObjectType = function() return "Frame" end,
                IsShown = function() return true end,
                GetEffectiveScale = function() return 1 end,
                GetWidth = function() return 320 end,
                GetBackdropColor = function() return 0.1, 0.2, 0.3, 0.6 end,
                GetBackdropBorderColor = function() return 1, 1, 1, 0.6 end,
            }
            local base = {IsInitialized = true, baseFrame = frame, isMoving = false, isSizing = false}
            self.dragStarts, self.dragStops = 0, 0
            base.OnDragStart = function(received, button)
                equal(received, frame)
                equal(button, "LeftButton")
                self.dragStarts = self.dragStarts + 1
                if self.rejectStart then return nil end
                base.isMoving, frame.isMoving = true, true
                return true
            end
            base.OnDragStop = function(received, button)
                equal(received, frame)
                equal(button, "LeftButton")
                self.dragStops = self.dragStops + 1
                base.isMoving, frame.isMoving = false, false
                self.nativePositionSaved = true
            end
            self.modules.QuestieTracker = {started = true, Update = function() end,
                UpdateFormatting = function() end, UpdateWidth = function() end}
            base.Update = function() end
            self.modules.TrackerBaseFrame = base
            Questie.db.profile = {trackerEnabled = true, trackerLocked = true}
            return frame, base
        end
        function fixture:add(id, categories, record)
            record = record or {}
            if record.name == nil then record.name = "Quest " .. id end
            self.records[id], self.quests[id], db.QuestPointers[id] = record, true, true
            for category in string.gmatch(categories or "", ".") do
                local group = assert(self.byCategory[category], "Unknown fixture category")
                group.children[#group.children + 1] = {value = id}
            end
            return self
        end
        function fixture:progress(mode)
            return ns.ZoneProgress.Calculate(ns.Adapter:Snapshot(), mode)
        end
        function fixture:connect()
            return ns.Adapter:Connect(function() self.readyCalls = self.readyCalls + 1 end,
                function() self.updateCalls = self.updateCalls + 1 end)
        end
        return fixture
    end

    test("adapter counts character-confirmed completions and future requirements", function()
        local f = fresh()
        f:add(101, "a"):add(102, "c"):add(103, "p"):add(104, "u")
        f.completed[102] = true
        local progress = f:progress()
        equal(progress.status, "ready")
        equal(progress.completed, 1)
        equal(progress.total, 3)
        equal(progress.excluded, 1)
        equal(progress.missingRequirements, 1)
        equal(progress.percent, 100 / 3)
        equal(progress.mode, "total")
    end)

    test("active objective-ready quest and saved Questie history do not imply turn-in", function()
        local f = fresh()
        f:add(101, "a")
        Questie.db.char.complete[101] = true
        local progress = f:progress()
        equal(progress.completed, 0)
        equal(progress.total, 1)
        equal(progress.percent, 0)
    end)

    test("Journey exclusive and virtual completions are excluded without character flags", function()
        local f = fresh()
        f:add(101, "c"):add(102, "a")
        local progress = f:progress()
        equal(progress.completed, 0)
        equal(progress.total, 1)
        equal(progress.alternatives, 1)
        equal(progress.excluded, 1)
    end)

    test("breadcrumb and hidden overlays never duplicate the denominator", function()
        local f = fresh()
        f:add(101, "abh"):add(102, "cbh")
        f.completed[102] = true
        local progress = f:progress()
        equal(progress.total, 2)
        equal(progress.completed, 1)
        equal(progress.percent, 50)
        equal(#f.quests, 0) -- The source is an ID set, never rewritten as an array.
        equal(f.quests[101], true)
        equal(#f.byCategory.b.children, 2)
    end)

    test("repeatables and daily weekly monthly resets are excluded independently", function()
        local f = fresh()
        f:add(101, "r", {repeatable = true}):add(102, "c", {daily = true})
        f:add(103, "a", {weekly = true}):add(104, "p", {monthly = true}):add(105, "a")
        f.completed[102] = true
        local progress = f:progress()
        equal(progress.status, "ready")
        equal(progress.total, 1)
        equal(progress.completed, 0)
        equal(progress.repeatable, 4)
        equal(progress.excluded, 4)
    end)

    test("missing pointers and names prevent a scoped percentage", function()
        local f = fresh()
        f:add(101, "a"):add(102, "a"):add(103, "a")
        f.db.QuestPointers[102] = nil
        f.records[103].name = nil
        local progress = f:progress()
        equal(progress.status, "incomplete")
        equal(progress.total, 1)
        equal(progress.unknown, 2)
        equal(progress.percent, nil)
    end)

    test("unclassified and overlay-only entries stay unknown", function()
        local f = fresh()
        f:add(101, "a"):add(102, "b"):add(103, "h", {reason = f.db.DoableStates.EXCLUSIVE_BREADCRUMB})
        local progress = f:progress()
        equal(progress.status, "incomplete")
        equal(progress.unknown, 2)
        equal(progress.total, 1)
        equal(progress.percent, nil)
    end)

    test("verified race class and blacklist omissions are accounted exclusions", function()
        local f = fresh()
        local states = f.db.DoableStates
        f:add(101, "a"):add(102, "", {reason = states.WRONG_RACE})
        f:add(103, "", {reason = states.WRONG_CLASS}):add(104, "", {reason = states.BLACKLISTED})
        local progress = f:progress()
        equal(progress.status, "ready")
        equal(progress.excluded, 3)
        equal(progress.unknown, 0)
        equal(progress.total, 1)
    end)

    test("unrecognized or absent reason never masquerades as an exclusion", function()
        local f = fresh()
        f:add(101, "a"):add(102, "", {reason = 9876}):add(103, "")
        local progress = f:progress()
        equal(progress.status, "incomplete")
        equal(progress.unknown, 2)
        equal(progress.percent, nil)
    end)

    test("null current map and absent zone group do not imply completion", function()
        local f = fresh()
        f:add(101, "a")
        f.zone = nil
        local progress = f:progress()
        equal(progress.status, "incomplete")
        equal(progress.total, nil)
        equal(progress.percent, nil)
        f.zone = 999
        equal(f:progress().status, "incomplete")
    end)

    test("subzone maps through Questie's parent to the existing Journey set", function()
        local f = fresh()
        f:add(101, "a")
        f.zone, f.parent[123] = 123, 12
        local snapshot = f.ns.Adapter:Snapshot()
        equal(snapshot.status, "ready")
        equal(snapshot.zoneId, 12)
        equal(f:progress().total, 1)
    end)

    test("empty and wholly excluded groups never report 100 percent", function()
        local f = fresh()
        equal(f:progress().status, "incomplete")
        f:add(101, "u")
        local progress = f:progress()
        equal(progress.status, "incomplete")
        equal(progress.percent, nil)
        equal(progress.total, 0)
    end)

    test("default mode shows progress without an opt-in setting", function()
        local f = fresh()
        f:add(101, "c")
        f.completed[101] = true
        local progress = f:progress()
        equal(progress.status, "ready")
        equal(progress.completed, 1)
        equal(progress.total, 1)
        equal(progress.percent, 100)
        equal(progress.message, nil)
    end)

    test("nonboolean completion data and completion errors degrade safely", function()
        local f = fresh()
        f:add(101, "a")
        f.nilCompletion = true
        equal(f:progress().status, "incomplete")
        equal(f:progress().unknown, 1)
        f.nilCompletion, f.completionError = false, true
        equal(f:progress().status, "unavailable")
        equal(type(f.ns.Adapter.lastError), "string")
    end)

    test("new malformed or missing Journey categories disable exact counts", function()
        local mutations = {
            function(f) f.tree[1].value = "new-category" end,
            function(f) f.tree[2].children = false end,
            function(f) table.remove(f.tree, 3) end,
            function(f) f.tree = nil end,
            function(f) f.byCategory.a.children[1].value = 999 end,
        }
        for _, mutate in ipairs(mutations) do
            local f = fresh()
            f:add(101, "a")
            mutate(f)
            equal(f:progress().status, "unavailable")
        end
    end)

    test("contradictory primary categories cannot establish a precise total", function()
        local f = fresh()
        f:add(101, "au")
        local progress = f:progress()
        assert(progress.status == "incomplete" or progress.status == "unavailable")
        equal(progress.percent, nil)
    end)

    test("missing internal module fails without importing or creating that module", function()
        local f = fresh()
        f:add(101, "a")
        f.modules.QuestieJourney = nil
        equal(f:progress().status, "unavailable")
        equal(f.modules.QuestieJourney, nil)
        equal(f.imports, 0)
    end)

    test("changed internal API and reset flag contracts fail safely", function()
        local f = fresh()
        f:add(101, "a")
        f.db.IsDoableVerbose = nil
        equal(f:progress().status, "unavailable")
        f = fresh()
        f:add(101, "a")
        f.db.IsDailyQuest = function() return nil end
        equal(f:progress().status, "incomplete")
        equal(f:progress().unknown, 1)
    end)

    test("active quests split Journey available without being added twice", function()
        local f = fresh()
        f:add(101, "ab"):add(102, "a"):add(103, "c"):add(104, "p"):add(105, "u")
        f.completed[103], f.active[101], f.active[9999] = true, true, true
        local progress = f:progress()
        equal(progress.zoneTotal, 4)
        equal(progress.completed, 1)
        equal(progress.inProgress, 1)
        equal(progress.available, 1)
        equal(progress.missingRequirements, 1)
        equal(progress.breadcrumbs, 1)
        equal(progress.unobtainable, 1)
        equal(progress.percent, 25)
        progress = f:progress("available")
        equal(progress.total, 3)
        equal(progress.percent, 100 / 3)
    end)

    test("confirmed completion wins when a quest briefly remains in the log", function()
        local f = fresh()
        f:add(101, "a")
        f.completed[101], f.active[101] = true, true
        local progress = f:progress()
        equal(progress.completed, 1)
        equal(progress.inProgress, 0)
        equal(progress.available, 0)
    end)

    test("inaccessible quest-log membership cannot fabricate segment counts", function()
        local f = fresh()
        f:add(101, "a")
        f.nilActive = true
        equal(f:progress().status, "incomplete")
        equal(f:progress().unknown, 1)
        C_QuestLog.IsOnQuest = nil
        equal(f:progress().status, "unavailable")
    end)

    test("tracker attachment returns only the initialized enabled Questie frame", function()
        local f = fresh()
        local anchor = {
            GetObjectType = function() return "Frame" end,
            IsShown = function() return true end,
            GetEffectiveScale = function() return 1 end,
        }
        Questie.db.profile = {trackerEnabled = true}
        f.modules.QuestieTracker = {started = true}
        f.modules.TrackerBaseFrame = {IsInitialized = true, baseFrame = anchor}
        equal(f.ns.Adapter:GetTrackerAnchor(), anchor)
        Questie.db.profile.trackerEnabled = false
        equal(f.ns.Adapter:GetTrackerAnchor(), nil)
        Questie.db.profile.trackerEnabled = true
        f.modules.QuestieTracker.started = false
        equal(f.ns.Adapter:GetTrackerAnchor(), nil)
        f.modules.QuestieTracker.started = true
        f.modules.TrackerBaseFrame.baseFrame = {}
        equal(f.ns.Adapter:GetTrackerAnchor(), nil)
        f.modules.TrackerBaseFrame = nil
        equal(f.ns.Adapter:GetTrackerAnchor(), nil)
        equal(f.modules.TrackerBaseFrame, nil)
    end)

    test("attached Ctrl-drag delegates movement and persistence to Questie's own handlers", function()
        local f = fresh()
        local frame, base = f:tracker()
        local saved = {"original"}
        Questie.db.profile.TrackerLocation = saved
        equal(f.ns.Adapter:StartTrackerDrag(), true)
        equal(base.isMoving, true)
        equal(f.dragStarts, 1)
        equal(Questie.db.profile.TrackerLocation, saved)
        equal(f.ns.Adapter:StopTrackerDrag(), true)
        equal(base.isMoving, false)
        equal(frame.isMoving, false)
        equal(f.dragStops, 1)
        equal(f.nativePositionSaved, true)
        equal(Questie.db.profile.TrackerLocation, saved) -- Only the native handler may persist it.
        equal(f.ns.Adapter:StopTrackerDrag(), true)
        equal(f.dragStops, 1)
    end)

    test("tracker movement rejects missing Ctrl combat rejected starts and unrelated drags", function()
        local f = fresh()
        local _, base = f:tracker()
        f.control = false
        equal(f.ns.Adapter:StartTrackerDrag(), false)
        equal(f.dragStarts, 0)
        f.control, f.combat = true, true
        equal(f.ns.Adapter:StartTrackerDrag(), false)
        equal(f.dragStarts, 0)
        f.combat, f.rejectStart = false, true
        equal(f.ns.Adapter:StartTrackerDrag(), false)
        equal(f.dragStarts, 1)
        equal(f.ns.Adapter.trackerDrag, nil)
        equal(f.dragStops, 0)
        f.rejectStart, base.isMoving = false, true
        equal(f.ns.Adapter:StartTrackerDrag(), false)
        equal(f.dragStops, 0)
        equal(base.isMoving, true)
    end)

    test("tracker stop uses captured handler despite modifier combat readiness or module changes", function()
        local f = fresh()
        local _, base = f:tracker()
        equal(f.ns.Adapter:StartTrackerDrag(), true)
        base.OnDragStop = function() error("Replacement handler must not run") end
        f.modules.TrackerBaseFrame = {}
        Questie.API.isReady = false
        f.combat, f.control = true, false
        equal(f.ns.Adapter:StopTrackerDrag(), true)
        equal(f.dragStops, 1)
        equal(base.isMoving, false)
    end)

    test("Questie may finish a Ctrl drag first without a second save on mouse release", function()
        local f = fresh()
        local frame, base = f:tracker()
        equal(f.ns.Adapter:StartTrackerDrag(), true)
        base.OnDragStop(frame, "LeftButton")
        equal(f.dragStops, 1)
        equal(f.ns.Adapter:StopTrackerDrag(), true)
        equal(f.ns.Adapter.trackerDrag, nil)
        equal(f.dragStops, 1)
    end)

    test("tracker start errors clean up only movement started by that attempt", function()
        local f = fresh()
        local frame, base = f:tracker()
        base.OnDragStart = function()
            base.isMoving, frame.isMoving = true, true
            error("Native handler failed after beginning")
        end
        equal(f.ns.Adapter:StartTrackerDrag(), false)
        equal(f.dragStops, 1)
        equal(base.isMoving, false)
        equal(f.ns.Adapter.trackerDrag, nil)
    end)

    test("tracker styling copies rendered font colors size and current background settings", function()
        local f = fresh()
        f:tracker()
        local profile = Questie.db.profile
        profile.trackerBackdropEnabled, profile.trackerBorderEnabled = true, true
        profile.trackerFontSizeHeader, profile.trackerFontSizeObjective = 14, 11
        profile.trackerFontObjective, profile.trackerFontOutline = "Custom body", "OUTLINE"
        local label = {
            GetFont = function() return "Fonts/CustomHeader.ttf", 16, "THICKOUTLINE" end,
            GetTextColor = function() return 0.9, 0.8, 0.1 end,
        }
        f.modules.TrackerHeaderFrame = {headerFrame = {trackedQuests = {label = label}}}
        f.modules.TrackerLayout = {MARGIN_LEFT = 18, MARGIN_RIGHT = 28}
        LibStub = function(name, silent)
            equal(name, "LibSharedMedia-3.0")
            equal(silent, true)
            return {Fetch = function(_, kind, name)
                equal(kind, "font")
                equal(name, "Custom body")
                return "Fonts/CustomBody.ttf"
            end}
        end
        local style = f.ns.Adapter:GetTrackerStyle()
        equal(style.width, 320)
        equal(style.leftInset, 18)
        equal(style.rightInset, 28)
        equal(style.headerFont, "Fonts/CustomHeader.ttf")
        equal(style.headerFontSize, 16)
        equal(style.headerOutline, "THICKOUTLINE")
        equal(style.font, "Fonts/CustomBody.ttf")
        equal(style.fontSize, 11)
        equal(style.outline, "OUTLINE")
        equal(style.headerColor[1], 0.9)
        equal(style.backdropColor[4], 0.6)
        equal(style.borderColor[4], 0.6)
        style.headerColor[1] = 0
        equal(f.ns.Adapter:GetTrackerStyle().headerColor[1], 0.9)
        profile.trackerBackdropEnabled = false
        style = f.ns.Adapter:GetTrackerStyle()
        equal(style.backdropEnabled, false)
        equal(style.backdropColor[4], 0)
        equal(style.borderColor[4], 0)
    end)

    test("layout observers register once and never propagate a callback failure into Questie", function()
        local f = fresh()
        local frame = f:tracker()
        frame.SetBackdropColor = function() end
        frame.SetBackdropBorderColor = function() end
        local hooks, calls = {}, 0
        hooksecurefunc = function(object, key, callback)
            hooks[#hooks + 1] = {object, key, callback}
        end
        equal(f.ns.Adapter:ObserveTrackerLayout(function() calls = calls + 1 end), true)
        equal(#hooks, 6)
        equal(f.ns.Adapter:ObserveTrackerLayout(function() error("Duplicate listener") end), true)
        equal(#hooks, 6)
        hooks[1][3]()
        equal(calls, 1)
        equal(hooks[5][1], frame)
        equal(hooks[5][2], "SetBackdropColor")
        hooks[5][3]()
        equal(calls, 2)
        f = fresh()
        f:tracker()
        hooks = {}
        hooksecurefunc = function(object, key, callback) hooks[#hooks + 1] = callback end
        equal(f.ns.Adapter:ObserveTrackerLayout(function() error("Layout temporarily unavailable") end), true)
        equal(pcall(hooks[1]), true)
        equal(type(f.ns.Adapter.trackerError), "string")
    end)

    test("tracker hover delegates to the existing Questie fader without changing settings", function()
        local f = fresh()
        f:tracker()
        local entered, left = 0, 0
        f.modules.TrackerFadeTicker = {
            Unfade = function() entered = entered + 1 end,
            Fade = function() left = left + 1 end,
        }
        f.ns.Adapter:SetTrackerHover(true)
        f.ns.Adapter:SetTrackerHover(false)
        equal(entered, 1)
        equal(left, 1)
        Questie.db.profile.trackerEnabled = false
        f.ns.Adapter:SetTrackerHover(true)
        equal(entered, 1)
    end)

    test("public callbacks bind once and already-ready registration is synchronous", function()
        local f = fresh()
        equal(f:connect(), true)
        equal(f.readyCalls, 1)
        equal(f:connect(), true)
        equal(f.readyRegistrations, 1)
        equal(f.updateRegistrations, 1)
        f.onUpdate(101, 2, "QUEST_UPDATED")
        equal(f.updateCalls, 1)
    end)

    test("not-ready startup waits for public readiness without reading Journey", function()
        local f = fresh()
        Questie.API.isReady = false
        equal(f:connect(), true)
        equal(f.readyCalls, 0)
        equal(f.ns.Adapter:Snapshot().status, "waiting")
        equal(f.imports, 0)
        Questie.API.isReady = true
        f.onReady()
        equal(f.readyCalls, 1)
    end)

    test("missing dependencies changed public APIs and unsupported contracts report failure", function()
        local f = fresh()
        Questie = nil
        equal(f:connect(), false)
        equal(f.ns.Adapter:Snapshot().status, "unavailable")
        f = fresh()
        Questie.API.RegisterForQuestUpdates = nil
        equal(f:connect(), false)
        f = fresh()
        f.contract = false
        equal(f:connect(), false)
        equal(f.ns.Adapter:Snapshot().status, "unavailable")
        equal(f.readyRegistrations, 0)
        equal(f.updateRegistrations, 0)
    end)

    test("throwing database contract or callback registration does not escape", function()
        local f = fresh()
        LibQuestieDB.RequireContract = function() error("Provider unavailable") end
        equal(f:connect(), false)
        equal(f.ns.Adapter:Snapshot().status, "unavailable")
        f = fresh()
        Questie.API.RegisterForQuestUpdates = function() error("Changed callback contract") end
        equal(f:connect(), false)
        equal(type(f.ns.Adapter.lastError), "string")
    end)

    test("Journey opens once and selects Quests by Zone without overwriting its zone selection", function()
        local f = fresh()
        f.journey.private.lastZoneSelection = {2, 12, "a\001101"}
        local selection = f.journey.private.lastZoneSelection
        equal(f.ns.Adapter:OpenJourney(), true)
        equal(f.ns.Adapter:OpenJourney(), true)
        equal(f.toggles, 1)
        equal(f.shown, true)
        equal(#f.tabSelections, 2)
        equal(f.tabSelections[1], "zone")
        equal(f.journey.tabGroup.localstatus.selected, "zone")
        equal(f.journey.private.lastOpenWindow, "zone")
        equal(f.journey.private.lastZoneSelection, selection)
        equal(selection[3], "a\001101")
    end)

    test("already-open Journey always switches back to Quests by Zone without closing", function()
        local f = fresh()
        f.shown = true
        f.journey.tabGroup.localstatus.selected = "faction"
        f.journey.private.lastOpenWindow = "faction"
        equal(f.ns.Adapter:OpenJourney(), true)
        equal(f.journey.tabGroup.localstatus.selected, "zone")
        f.journey.tabGroup.localstatus.selected = "journey"
        equal(f.ns.Adapter:OpenJourney(), true)
        equal(f.journey.tabGroup.localstatus.selected, "zone")
        equal(f.toggles, 0)
        equal(f.shown, true)
    end)

    test("missing disabled or changed zone-tab interfaces do not open an unrelated Journey view", function()
        for _, mutate in ipairs({
            function(f) f.journey.tabGroup = nil end,
            function(f) f.journey.tabGroup.SelectTab = nil end,
            function(f) f.journey.tabGroup.tablist = nil end,
            function(f) f.journey.tabGroup.tablist = {{value = "journey"}} end,
            function(f) f.journey.tabGroup.tablist[2].disabled = true end,
        }) do
            local f = fresh()
            mutate(f)
            equal(f.ns.Adapter:OpenJourney(), false)
            equal(f.toggles, 0)
            equal(f.shown, false)
            equal(#f.tabSelections, 0)
        end
    end)

    test("zone navigation reports blocked opening failed selection and callback errors", function()
        local f = fresh()
        f.journey.ToggleJourneyWindow = function() end
        equal(f.ns.Adapter:OpenJourney(), false)
        equal(#f.tabSelections, 0)
        f = fresh()
        f.journey.tabGroup.SelectTab = function() end
        equal(f.ns.Adapter:OpenJourney(), false)
        f = fresh()
        f.journey.tabGroup.SelectTab = function() error("Changed zone callback") end
        equal(f.ns.Adapter:OpenJourney(), false)
        equal(type(f.ns.Adapter.lastError), "string")
    end)

    test("tracker question-mark icon reuses Questie's own validated texture without assets", function()
        local f = fresh()
        equal(f.ns.Adapter:GetTrackerIcon(), "Interface\\Addons\\Questie\\Icons\\complete.blp")
        Questie.icons.complete = 123456
        equal(f.ns.Adapter:GetTrackerIcon(), 123456)
        for _, invalid in ipairs({"", "   ", 0, -1, 1.5, math.huge, {}, false}) do
            Questie.icons.complete = invalid
            equal(f.ns.Adapter:GetTrackerIcon(), nil)
        end
        Questie.icons = nil
        equal(f.ns.Adapter:GetTrackerIcon(), nil)
        Questie = nil
        equal(f.ns.Adapter:GetTrackerIcon(), nil)
    end)

    test("Journey navigation refuses combat and unavailable initialization", function()
        local f = fresh()
        f.combat = true
        equal(f.ns.Adapter:OpenJourney(), false)
        equal(f.toggles, 0)
        equal(f.imports, 0)
        f.combat = false
        Questie.API.isReady = false
        equal(f.ns.Adapter:OpenJourney(), false)
        equal(f.toggles, 0)
        Questie.API.isReady = true
        f.journey.ToggleJourneyWindow = function() error("Upstream UI changed") end
        equal(f.ns.Adapter:OpenJourney(), false)
        equal(type(f.ns.Adapter.lastError), "string")
    end)
end
