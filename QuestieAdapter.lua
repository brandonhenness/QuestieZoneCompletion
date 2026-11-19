local _, ns = ...
local Adapter = {}
ns.Adapter = Adapter

local function failure(status, message, zoneName)
    return { status = status, message = message, zoneName = zoneName }
end

local function import(name)
    -- ImportModule creates absent modules in some revisions. Inspect the registry first.
    local loader = QuestieLoader
    if type(loader) ~= "table" or type(loader.ImportModule) ~= "function"
        or type(loader._modules) ~= "table" or type(loader._modules[name]) ~= "table" then
        error("Questie module unavailable: " .. name)
    end
    return loader:ImportModule(name)
end

function Adapter:Connect(onReady, onUpdate)
    if not Questie or not LibQuestieDB then
        return false, "Install and enable compatible Forever versions of Questie and QuestieDB."
    end
    local api = Questie.API
    if type(api) ~= "table" or type(api.RegisterOnReady) ~= "function"
        or type(api.RegisterForQuestUpdates) ~= "function"
        or type(LibQuestieDB.RequireContract) ~= "function" then
        return false, "Questie integration is outdated. Update Questie and QuestieDB, then reload."
    end
    local ok, supported = pcall(LibQuestieDB.RequireContract, 4)
    if not ok or not supported then
        return false, "QuestieDB contract 4 is required. Update QuestieDB, then reload."
    end
    if self.boundAPI == api then
        return true
    end
    -- Public callbacks have no unregister operation. Never append duplicate listeners.
    local registered, err = pcall(function()
        if not self.updateBound then
            api.RegisterForQuestUpdates(onUpdate)
            self.updateBound = true
        end
        api.RegisterOnReady(onReady)
    end)
    if not registered then
        self.lastError = tostring(err)
        return false, "Questie's callback interface changed. Update both addons and reload."
    end
    self.boundAPI = api
    return true
end

local function snapshot()
    local zoneName = GetRealZoneText() or "Unknown zone"
    if not Questie or not LibQuestieDB then
        return failure("unavailable", "Questie and QuestieDB are required.", zoneName)
    end
    if type(LibQuestieDB.RequireContract) ~= "function" or not LibQuestieDB.RequireContract(4) then
        return failure("unavailable", "Update QuestieDB to a version supporting contract 4.", zoneName)
    end
    if not Questie.API or not Questie.API.isReady then
        return failure("waiting", "Waiting for Questie to finish initializing.", zoneName)
    end
    if not C_QuestLog or type(C_QuestLog.IsQuestFlaggedCompleted) ~= "function"
        or type(C_QuestLog.IsOnQuest) ~= "function" then
        return failure("unavailable", "The Forever character quest APIs are unavailable.", zoneName)
    end
    local journey, db = import("QuestieJourney"), import("QuestieDB")
    local player, zones = import("QuestiePlayer"), import("ZoneDB")
    if type(journey.zoneMap) ~= "table" or type(journey.private) ~= "table"
        or type(journey.private.questsByZone) ~= "table"
        or type(journey.private.questsByZone.CategorizeQuests) ~= "function"
        or type(db.QuestPointers) ~= "table" or type(db.QueryQuestSingle) ~= "function"
        or type(db.IsRepeatable) ~= "function" or type(db.IsDoableVerbose) ~= "function"
        or type(db.IsDailyQuest) ~= "function" or type(db.IsWeeklyQuest) ~= "function"
        or type(db.IsMonthlyQuest) ~= "function"
        or type(db.DoableStates) ~= "table" then
        error("Journey classification contract changed")
    end
    local zoneId = player:GetCurrentZoneId()
    if not zoneId then
        return failure("incomplete", "The current zone could not be resolved.", zoneName)
    end
    -- Journey groups subzones and alternative dungeon areas under their parent area.
    zoneId = zones:GetParentZoneId(zoneId) or zoneId
    local quests = journey.zoneMap[zoneId]
    if type(quests) ~= "table" or not next(quests) then
        return failure("incomplete", "Questie has no known quest group for this zone.", zoneName)
    end
    local tree = journey.private.questsByZone:CategorizeQuests(quests)
    if type(tree) ~= "table" then error("Journey returned no categories") end
    local categories, present = {}, {}
    for _, group in ipairs(tree) do
        local key = group.value
        if key ~= "a" and key ~= "c" and key ~= "p" and key ~= "r" and key ~= "u"
            and key ~= "b" and key ~= "h" then
            error("Unknown Journey category")
        end
        if present[key] or type(group.children) ~= "table" then error("Malformed Journey category") end
        present[key] = true
        for _, child in ipairs(group.children) do
            local id = child.value
            if type(id) ~= "number" or not quests[id] then error("Unexpected Journey quest") end
            categories[id] = categories[id] or {}
            categories[id][key] = true
        end
    end
    for _, key in ipairs({ "a", "c", "p", "r", "u", "b" }) do
        if not present[key] then error("Missing Journey category") end
    end
    local result = { status = "ready", zoneName = zoneName, zoneId = zoneId, quests = {} }
    for id in pairs(quests) do
        local record = { id = id }
        result.quests[#result.quests + 1] = record
        local group = categories[id] or {}
        record.breadcrumb = group.b == true
        local primaryCount = 0
        for _, key in ipairs({ "a", "c", "p", "r", "u" }) do
            if group[key] then primaryCount = primaryCount + 1 end
        end
        local name = db.QuestPointers[id] and db.QueryQuestSingle(id, "name")
        if primaryCount > 1 or type(name) ~= "string" or name == "" then
            record.unknown = true
        else
            local repeatable = db.IsRepeatable(id)
            local daily, weekly, monthly = db.IsDailyQuest(id), db.IsWeeklyQuest(id), db.IsMonthlyQuest(id)
            if type(repeatable) ~= "boolean" or type(daily) ~= "boolean"
                or type(weekly) ~= "boolean" or type(monthly) ~= "boolean" then
                record.unknown = true
            elseif repeatable or daily or weekly or monthly then
                record.repeatable = true
            elseif group.a or group.c or group.p then
                local completed = C_QuestLog.IsQuestFlaggedCompleted(id)
                local inProgress = C_QuestLog.IsOnQuest(id)
                if type(completed) ~= "boolean" or type(inProgress) ~= "boolean" then
                    record.unknown = true
                elseif group.c and not completed and not inProgress then
                    -- Journey marks exclusive alternatives and some child quests completed.
                    record.alternative = true
                else
                    record.eligible, record.completed = true, completed
                    record.inProgress = not completed and inProgress
                    record.missingRequirements = group.p == true and not completed and not inProgress
                end
            elseif group.u then
                record.eligible, record.unobtainable = false, true
            elseif group.r then
                record.unknown = true -- A non-repeatable in the repeatable group is contradictory.
            else
                local _, _, reason = db.IsDoableVerbose(id, false, true, false)
                local states = db.DoableStates
                if reason ~= nil and (reason == states.WRONG_RACE or reason == states.WRONG_CLASS
                    or reason == states.BLACKLISTED) then
                    record.eligible = false
                else
                    record.unknown = true
                end
            end
        end
    end
    return result
end

function Adapter:Snapshot()
    local ok, result = pcall(snapshot)
    if ok then return result end
    self.lastError = tostring(result)
    return failure("unavailable", "Questie data could not be read. Update both addons, then /qzc refresh.")
end

-- TrackerBaseFrame owns the unprotected Questie tracker frame in the inspected
-- revision. Return an existing frame only; never create or reposition Questie UI.
function Adapter:GetTrackerAnchor()
    local ok, anchor = pcall(function()
        if not Questie or not Questie.API or not Questie.API.isReady
            or not Questie.db or not Questie.db.profile or not Questie.db.profile.trackerEnabled then
            return nil
        end
        local tracker, base = import("QuestieTracker"), import("TrackerBaseFrame")
        local frame = base.baseFrame
        if tracker.started and base.IsInitialized and frame
            and type(frame.GetEffectiveScale) == "function" and type(frame.IsShown) == "function"
            and type(frame.GetObjectType) == "function" and frame:GetObjectType() == "Frame" then
            return frame
        end
    end)
    if not ok then
        self.trackerError = tostring(anchor)
        return nil
    end
    return anchor
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function color(r, g, b, a)
    if not finite(r) or not finite(g) or not finite(b) then return nil end
    local result = { math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b)) }
    if finite(a) then result[4] = math.max(0, math.min(1, a)) end
    return result
end

function Adapter:GetTrackerStyle()
    local ok, style = pcall(function()
        if not Questie or not Questie.API or not Questie.API.isReady
            or not Questie.db or type(Questie.db.profile) ~= "table" then return nil end
        local profile = Questie.db.profile
        local result = {
            leftInset = 14, rightInset = 30,
            headerFontSize = finite(profile.trackerFontSizeHeader) and profile.trackerFontSizeHeader > 0
                and profile.trackerFontSizeHeader <= 64 and profile.trackerFontSizeHeader or 12,
            fontSize = finite(profile.trackerFontSizeObjective) and profile.trackerFontSizeObjective > 0
                and profile.trackerFontSizeObjective <= 64 and profile.trackerFontSizeObjective or 10,
            outline = type(profile.trackerFontOutline) == "string" and profile.trackerFontOutline or "",
            headerColor = { 1, 0.82, 0 }, textColor = { 1, 1, 1 },
            backdropEnabled = profile.trackerBackdropEnabled == true,
            borderEnabled = profile.trackerBackdropEnabled == true and profile.trackerBorderEnabled == true,
            backdropColor = { 0, 0, 0, 0 }, borderColor = { 1, 1, 1, 0 },
        }
        local backdrop = profile.trackerBackdropColor
        if type(backdrop) == "table" then
            result.backdropColor = color(backdrop.r, backdrop.g, backdrop.b, backdrop.a) or result.backdropColor
            result.borderColor[4] = result.backdropColor[4] or 0
        end
        if type(Questie.ColorizeRGB) == "function" then
            result.headerColor = color(Questie:ColorizeRGB("gold")) or result.headerColor
            result.textColor = color(Questie:ColorizeRGB("white")) or result.textColor
        end
        -- Read rendered typography first so custom font files and actual header flags match.
        local modules = QuestieLoader and QuestieLoader._modules
        local header = type(modules) == "table" and modules.TrackerHeaderFrame
        local label = header and header.headerFrame and header.headerFrame.trackedQuests
            and header.headerFrame.trackedQuests.label
        if label and type(label.GetFont) == "function" then
            local path, size, flags = label:GetFont()
            if type(path) == "string" and path ~= "" then result.headerFont = path end
            if finite(size) and size > 0 and size <= 64 then result.headerFontSize = size end
            if type(flags) == "string" then result.headerOutline = flags end
        end
        if label and type(label.GetTextColor) == "function" then
            result.headerColor = color(label:GetTextColor()) or result.headerColor
        end
        -- Questie already loads LibSharedMedia; access that registered library without bundling it.
        if LibStub then
            local found, media = pcall(function() return LibStub("LibSharedMedia-3.0", true) end)
            if found and media and type(media.Fetch) == "function" then
                local fetched, path = pcall(media.Fetch, media, "font", profile.trackerFontObjective, true)
                if fetched and type(path) == "string" and path ~= "" then result.font = path end
                if not result.headerFont then
                    fetched, path = pcall(media.Fetch, media, "font", profile.trackerFontHeader, true)
                    if fetched and type(path) == "string" and path ~= "" then result.headerFont = path end
                end
            end
        end
        result.font = result.font or result.headerFont
        result.headerOutline = result.headerOutline or result.outline
        local layout = type(modules) == "table" and modules.TrackerLayout
        if layout then
            if finite(layout.MARGIN_LEFT) and layout.MARGIN_LEFT >= 0 and layout.MARGIN_LEFT <= 256 then
                result.leftInset = layout.MARGIN_LEFT
            end
            if finite(layout.MARGIN_RIGHT) and layout.MARGIN_RIGHT >= 0 and layout.MARGIN_RIGHT <= 256 then
                result.rightInset = layout.MARGIN_RIGHT
            end
        end
        local anchor = self:GetTrackerAnchor()
        if anchor then
            if type(anchor.GetWidth) == "function" then
                local width = anchor:GetWidth()
                if finite(width) and width > 0 and width <= 4096 then result.width = width end
            end
            if type(anchor.GetBackdropColor) == "function" then
                result.backdropColor = color(anchor:GetBackdropColor()) or result.backdropColor
            end
            if type(anchor.GetBackdropBorderColor) == "function" then
                result.borderColor = color(anchor:GetBackdropBorderColor()) or result.borderColor
            end
        end
        if not result.backdropEnabled then result.backdropColor[4] = 0 end
        if not result.borderEnabled then result.borderColor[4] = 0 end
        return result
    end)
    if not ok then self.trackerError = tostring(style); return nil end
    return style
end

-- Use the same handlers Questie installs on its header and quest rows. In particular,
-- OnDragStop queues Questie's own position persistence; do not write TrackerLocation here.
function Adapter:StartTrackerDrag()
    if self.trackerDrag then return false, "Questie's tracker is already moving." end
    if InCombatLockdown() then return false, "Move Questie's tracker after combat." end
    if type(IsControlKeyDown) ~= "function" or not IsControlKeyDown() then
        return false, "Hold Ctrl to move Questie's tracker."
    end
    local frame = self:GetTrackerAnchor()
    if not frame then return false, "Questie's tracker is unavailable." end
    local loaded, base = pcall(import, "TrackerBaseFrame")
    if not loaded or type(base.OnDragStart) ~= "function" or type(base.OnDragStop) ~= "function" then
        return false, "Questie's tracker movement interface changed. Update both addons."
    end
    if base.isMoving ~= false or base.isSizing == true then
        return false, "Questie's tracker is already moving or resizing."
    end
    local stop = base.OnDragStop
    local ok, started = pcall(base.OnDragStart, frame, "LeftButton")
    if not ok or started ~= true or base.isMoving ~= true or base.baseFrame ~= frame then
        -- A changed handler may fail after beginning movement. Clean up only our attempt.
        if base.baseFrame == frame and base.isMoving == true then pcall(stop, frame, "LeftButton") end
        if not ok then self.trackerError = tostring(started) end
        return false, "Questie could not start moving. Release Shift/Alt and close chat, then Ctrl-drag."
    end
    self.trackerDrag = { frame = frame, module = base, stop = stop }
    return true
end

function Adapter:StopTrackerDrag()
    local drag = self.trackerDrag
    if not drag then return true end
    if drag.module.isMoving ~= true then
        -- Questie's modifier handler may finish first when Ctrl is released.
        self.trackerDrag = nil
        return true
    end
    -- Use the captured stop function even if the module registry or Ctrl state changes.
    -- Questie's stop path also deliberately works when combat begins during a drag.
    local ok, err = pcall(drag.stop, drag.frame, "LeftButton")
    if ok and drag.module.isMoving ~= true then
        self.trackerDrag = nil
        return true
    end
    self.trackerError = not ok and tostring(err) or "Questie's movement handler did not finish."
    return false, "Questie could not finish moving its tracker. Release the mouse and reload if it remains stuck."
end

function Adapter:ObserveTrackerLayout(callback)
    if type(callback) ~= "function" or type(hooksecurefunc) ~= "function" then return false end
    local anchor = self:GetTrackerAnchor()
    if not anchor then return false end
    local ok, tracker, base = pcall(function() return import("QuestieTracker"), import("TrackerBaseFrame") end)
    if not ok then self.trackerError = tostring(tracker); return false end
    self.layoutHooks = self.layoutHooks or {}
    local targets = {
        { tracker, "Update" }, { tracker, "UpdateFormatting" }, { tracker, "UpdateWidth" }, { base, "Update" },
        -- Existing Questie hover fading updates these methods. Resample its current
        -- colors through the coalesced layout callback; never run our own fade ticker.
        { anchor, "SetBackdropColor" }, { anchor, "SetBackdropBorderColor" },
    }
    for _, entry in ipairs(targets) do
        local object, name = entry[1], entry[2]
        self.layoutHooks[object] = self.layoutHooks[object] or {}
        if type(object[name]) == "function" and not self.layoutHooks[object][name] then
            local hooked, err = pcall(hooksecurefunc, object, name, function()
                local called, callbackError = pcall(callback)
                if not called then self.trackerError = tostring(callbackError) end
            end)
            if not hooked then self.trackerError = tostring(err); return false end
            self.layoutHooks[object][name] = true
        end
    end
    return true
end

function Adapter:SetTrackerHover(inside)
    if not self:GetTrackerAnchor() then return end
    local ok, err = pcall(function()
        local fade = import("TrackerFadeTicker")
        local handler = inside and fade.Unfade or fade.Fade
        if type(handler) == "function" then handler() end
    end)
    if not ok then self.trackerError = tostring(err) end
end

function Adapter:GetTrackerIcon()
    local icon = type(Questie) == "table" and type(Questie.icons) == "table" and Questie.icons.complete
    if type(icon) == "string" and string.find(icon, "%S") then return icon end
    if finite(icon) and icon > 0 and icon % 1 == 0 then return icon end
end

function Adapter:OpenJourney()
    if InCombatLockdown() then return false, "Open Questie's Journey after combat." end
    local ok, message = pcall(function()
        if not Questie or not Questie.API or not Questie.API.isReady then
            return "Questie is not ready yet."
        end
        local journey = import("QuestieJourney")
        local tabs = journey.tabGroup
        if type(journey.IsShown) ~= "function" or type(journey.ToggleJourneyWindow) ~= "function"
            or type(tabs) ~= "table" or type(tabs.SelectTab) ~= "function" or type(tabs.tablist) ~= "table" then
            return "Questie's Journey interface changed. Update both addons."
        end
        -- AceGUI SelectTab records even unknown values without firing the selection
        -- callback. Verify the actual tab exists before opening a different view.
        local hasZoneTab = false
        for _, tab in ipairs(tabs.tablist) do
            if type(tab) == "table" and tab.value == "zone" and not tab.disabled then hasZoneTab = true end
        end
        if not hasZoneTab then return "Questie's Quests by Zone tab is unavailable. Update both addons." end
        if not journey:IsShown() then journey:ToggleJourneyWindow() end
        if not journey:IsShown() then return "Questie's Journey is not ready yet." end
        -- The verified tab callback rebuilds Quests by Zone and remembers that view.
        -- Select after opening because ToggleJourneyWindow first restores the old tab.
        tabs:SelectTab("zone")
        local status = tabs.status or tabs.localstatus
        if type(status) ~= "table" or status.selected ~= "zone" then
            return "Questie's Quests by Zone tab could not be selected. Update both addons."
        end
    end)
    if not ok then
        self.lastError = tostring(message)
        return false, "Questie's Quests by Zone could not be opened. Update both addons."
    end
    return message == nil, message
end
