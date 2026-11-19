return function(test, equal)
    local function withCore(callback, options)
        options = options or {}
        local names = {"CreateFrame", "C_Timer", "QuestieZoneCompletionDB", "SlashCmdList",
            "SLASH_QUESTIEZONECOMPLETION1", "print"}
        local old = {}
        for _, name in ipairs(names) do old[name] = _G[name] end
        local state = {
            time = 0, timers = {}, timerSequence = 0, timerCalls = {}, events = {}, messages = {},
            snapshots = 0, connects = 0, registrations = 0, initialized = 0, created = 0, applied = 0,
            rendered = 0, nativeRegistrations = 0, layoutObservers = 0, status = options.status or "ready",
        }
        function state:Advance(target)
            local executed = 0
            while true do
                local nextIndex, nextTimer
                for index, timer in ipairs(self.timers) do
                    if timer.at <= target and (not nextTimer or timer.at < nextTimer.at
                        or (timer.at == nextTimer.at and timer.sequence < nextTimer.sequence)) then
                        nextIndex, nextTimer = index, timer
                    end
                end
                if not nextTimer then break end
                table.remove(self.timers, nextIndex)
                self.time = nextTimer.at
                nextTimer.callback()
                executed = executed + 1
                if executed > 1000 then error("Timer loop did not become idle") end
            end
            self.time = target
        end
        function state:Pending(delay)
            local count = 0
            for _, timer in ipairs(self.timers) do
                if not delay or timer.delay == delay then count = count + 1 end
            end
            return count
        end
        local frame = {}
        function frame:SetScript(name, script) self[name] = script end
        function frame:RegisterEvent(name) state.events[name] = true end
        function state:Event(name, argument) frame.OnEvent(frame, name, argument) end
        _G.CreateFrame = function() return frame end
        _G.C_Timer = {After = function(delay, task)
            state.timerSequence = state.timerSequence + 1
            state.timerCalls[delay] = (state.timerCalls[delay] or 0) + 1
            state.timers[#state.timers + 1] = {
                delay = delay, at = state.time + delay, callback = task, sequence = state.timerSequence,
            }
        end}
        _G.print = function(message) state.messages[#state.messages + 1] = message end
        _G.QuestieZoneCompletionDB = options.saved
        _G.SlashCmdList = {}
        local ns = {}
        ns.Config = {
            Initialize = function(saved)
                state.initialized = state.initialized + 1
                state.savedInput = saved
                return {visible = true, progressMode = options.progressMode or "total"}
            end,
            HandleCommand = function(message) state.command = message end,
            RegisterSettings = function()
                state.nativeRegistrations = state.nativeRegistrations + 1
                return true
            end,
        }
        ns.UI = {
            Create = function() state.created = state.created + 1 end,
            ApplySettings = function() state.applied = state.applied + 1 end,
            Render = function(_, progress)
                state.rendered = state.rendered + 1
                state.lastRendered = progress
            end,
        }
        ns.Adapter = {
            ObserveTrackerLayout = function(_, callback)
                if not state.onTrackerLayout then
                    state.layoutObservers = state.layoutObservers + 1
                    state.onTrackerLayout = callback
                end
                return true
            end,
            Connect = function(_, onReady, onUpdate)
                state.connects = state.connects + 1
                if options.connectFailure then return false, "Dependency unavailable." end
                -- Like the real adapter, repeated attempts reuse its one callback registration.
                if state.registrations == 0 then
                    state.registrations = 1
                    state.onReady, state.onUpdate = onReady, onUpdate
                end
                return true
            end,
            Snapshot = function()
                state.snapshots = state.snapshots + 1
                return {status = state.status, message = "Dependency unavailable."}
            end,
        }
        ns.ZoneProgress = {Calculate = function(snapshot, mode)
            state.calculatedMode = mode
            return {status = snapshot.status, marker = state.snapshots}
        end}
        assert(loadfile("Core.lua"))("QuestieZoneCompletion", ns)
        local ok, reason = pcall(callback, ns, state)
        for _, name in ipairs(names) do _G[name] = old[name] end
        if not ok then error(reason, 0) end
    end

    test("core initializes SavedVariables and slash routing once at its own load event", function()
        local saved = {scale = 1.25}
        withCore(function(ns, state)
            ns:RequestRefresh()
            state:Event("ADDON_LOADED", "UnrelatedAddon")
            equal(state.initialized, 0)
            equal(state:Pending(), 0)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            equal(state.initialized, 1)
            equal(state.savedInput, saved)
            equal(ns.settings, QuestieZoneCompletionDB)
            equal(ns.settings.progressMode, "available")
            equal(state.created, 1)
            equal(state.applied, 1)
            equal(state.nativeRegistrations, 1)
            equal(SLASH_QUESTIEZONECOMPLETION1, "/qzc")
            SlashCmdList.QUESTIEZONECOMPLETION("mode total")
            equal(state.command, "mode total")
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            equal(state.initialized, 1)
            equal(state.nativeRegistrations, 1)
            state:Advance(0.35)
            equal(state.calculatedMode, "available")
            equal(ns.progress, state.lastRendered)
        end, {saved = saved, progressMode = "available"})
    end)

    test("core coalesces event bursts without extending the fixed refresh deadline", function()
        withCore(function(ns, state)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            for _ = 1, 50 do
                state:Event("ZONE_CHANGED")
                ns:RequestRefresh()
                state.onUpdate()
            end
            equal(state:Pending(0.35), 1)
            equal(state.snapshots, 0)
            state:Advance(0.34)
            state:Event("ZONE_CHANGED_NEW_AREA")
            state:Advance(0.35)
            equal(state.snapshots, 1)
            equal(state:Pending(), 0)
            state:Event("QUEST_ACCEPTED", 123)
            state:Advance(0.70)
            equal(state.snapshots, 2)
            state:Advance(100)
            equal(state.snapshots, 2)
            equal(state:Pending(), 0)
        end)
    end)

    test("tracker formatting bursts repaint the widget without rescanning quest data", function()
        withCore(function(ns, state)
            ns:RequestLayoutRefresh()
            equal(state:Pending(), 0)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            state:Advance(0.35)
            equal(state.snapshots, 1)
            equal(state.applied, 1)
            for _ = 1, 100 do state.onTrackerLayout() end
            equal(state:Pending(0.1), 1)
            state:Advance(0.44)
            equal(state.applied, 1)
            state:Advance(0.45)
            equal(state.applied, 2)
            equal(state.snapshots, 1)
            state:Advance(100)
            equal(state:Pending(), 0)
            equal(state.snapshots, 1)
            state:Event("PLAYER_ENTERING_WORLD")
            equal(state.layoutObservers, 1)
        end)
    end)

    test("core reconnects on dependency and world events without duplicating initialization", function()
        withCore(function(_, state)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            state:Event("PLAYER_ENTERING_WORLD")
            state:Event("ADDON_LOADED", "QuestieDB")
            state:Event("ADDON_LOADED", "Questie")
            state:Event("PLAYER_ENTERING_WORLD")
            equal(state.connects, 5)
            equal(state.registrations, 1)
            equal(state.initialized, 1)
            equal(state.created, 1)
            state:Advance(0.35)
            state.onReady()
            state.onUpdate()
            equal(state:Pending(0.35), 1)
            state:Advance(0.70)
            equal(state.snapshots, 2)
        end)
    end)

    test("core bounds startup retries and public readiness resumes an idle addon", function()
        withCore(function(_, state)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            state:Advance(100)
            equal(state.timerCalls[2], 5)
            equal(state.snapshots, 6)
            equal(state:Pending(), 0)
            state.status = "ready"
            state.onReady()
            state:Advance(100.35)
            equal(state.snapshots, 7)
            equal(state.lastRendered.status, "ready")
            equal(state:Pending(), 0)
        end, {status = "waiting"})
    end)

    test("core schedules one bounded eligibility settle pass for turn-in bursts", function()
        withCore(function(ns, state)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            state:Advance(0.35)
            for _ = 1, 30 do
                state:Event("QUEST_REMOVED", 123)
                state:Event("QUEST_TURNED_IN", 123)
            end
            equal(state:Pending(0.35), 1)
            equal(state:Pending(2), 1)
            equal(ns.settlePending, true)
            state:Advance(10)
            equal(state.snapshots, 3)
            equal(state.timerCalls[2], 1)
            equal(ns.settlePending, false)
            equal(state:Pending(), 0)
            state:Event("QUEST_TURNED_IN", 456)
            equal(state:Pending(2), 1)
        end)
    end)

    test("core deduplicates warnings and relies on callbacks instead of idle scans", function()
        withCore(function(_, state)
            state:Event("ADDON_LOADED", "QuestieZoneCompletion")
            equal(state.events.QUEST_LOG_UPDATE, nil)
            equal(state.events.ZONE_CHANGED, true)
            equal(state.events.QUEST_ACCEPTED, true)
            equal(state.events.QUEST_TURNED_IN, true)
            equal(state.events.PLAYER_LEVEL_UP, true)
            equal(state.events.SKILL_LINES_CHANGED, true)
            equal(state.events.UPDATE_FACTION, true)
            state:Advance(0.35)
            state:Event("PLAYER_ENTERING_WORLD")
            state:Advance(0.70)
            equal(#state.messages, 1)
            state:Advance(100)
            equal(state.snapshots, 2)
            equal(state:Pending(), 0)
        end, {status = "unavailable", connectFailure = true})
    end)
end
