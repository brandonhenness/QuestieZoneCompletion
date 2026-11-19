local addonName, ns = ...
local frame = CreateFrame("Frame")
local pending, layoutPending, initialized, startupRetries = false, false, false, 0
local warned = {}

function ns:Print(message)
    print("|cffffd100Questie Zone Completion:|r " .. tostring(message))
end

local function warnOnce(message)
    if not warned[message] then
        warned[message] = true
        ns:Print(message)
    end
end

function ns:Refresh()
    local snapshot = self.Adapter:Snapshot()
    self.progress = self.ZoneProgress.Calculate(snapshot, self.settings.progressMode)
    self.UI:Render(self.progress)
    if snapshot.status == "unavailable" then warnOnce(snapshot.message) end
    -- Bounded startup recovery for temporarily unavailable initialization; public on-ready
    -- handles arbitrarily long valid startups without a permanent polling loop.
    if snapshot.status == "waiting" and startupRetries < 5 then
        startupRetries = startupRetries + 1
        C_Timer.After(2, function() self:RequestRefresh() end)
    end
end

function ns:RequestLayoutRefresh()
    if not initialized or layoutPending then return end
    layoutPending = true
    -- Tracker formatting/resize notifications only repaint our widget, not the quest index.
    C_Timer.After(0.1, function()
        layoutPending = false
        ns.UI:ApplySettings()
    end)
end

local function observeTracker()
    if ns.Adapter.ObserveTrackerLayout then
        ns.Adapter:ObserveTrackerLayout(function() ns:RequestLayoutRefresh() end)
    end
end

local function connect()
    local ok, message = ns.Adapter:Connect(function()
        observeTracker()
        ns:RequestRefresh()
    end, function() ns:RequestRefresh() end)
    if not ok then warnOnce(message) end
    observeTracker()
end

function ns:RequestRefresh()
    if not initialized or pending then return end
    pending = true
    -- Fixed-window coalescing cannot starve under a continuous stream of quest events.
    C_Timer.After(0.35, function()
        pending = false
        ns:Refresh()
    end)
end

local events = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "PLAYER_LEVEL_UP", "UPDATE_FACTION", "SKILL_LINES_CHANGED", "SPELLS_CHANGED",
    "PLAYER_REGEN_ENABLED",
}

frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == addonName and not initialized then
            QuestieZoneCompletionDB = ns.Config.Initialize(QuestieZoneCompletionDB)
            ns.settings = QuestieZoneCompletionDB
            initialized = true
            ns.UI:Create()
            ns.UI:ApplySettings()
            local registered, message = ns.Config.RegisterSettings()
            if not registered then warnOnce(message) end
            SLASH_QUESTIEZONECOMPLETION1 = "/qzc"
            SlashCmdList.QUESTIEZONECOMPLETION = function(message) ns.Config.HandleCommand(message) end
            for _, gameEvent in ipairs(events) do frame:RegisterEvent(gameEvent) end
            connect()
            ns:RequestRefresh()
        elseif initialized and (name == "Questie" or name == "QuestieDB") then
            connect()
            ns:RequestRefresh()
        end
    elseif initialized then
        ns:RequestRefresh()
        if event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            -- Forever can deliver turn-in events late. A second bounded read lets
            -- Questie's asynchronously maintained eligibility settle.
            if not ns.settlePending then
                ns.settlePending = true
                C_Timer.After(2, function()
                    ns.settlePending = false
                    ns:RequestRefresh()
                end)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            connect()
        end
    end
end)
frame:RegisterEvent("ADDON_LOADED")
