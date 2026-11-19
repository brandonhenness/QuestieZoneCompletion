return function(test, equal)
    local ns = {}
    assert(loadfile("ZoneProgress.lua"))("QuestieZoneCompletion", ns)
    local calculate = ns.ZoneProgress.Calculate

    local function barrens()
        local quests = {}
        for id = 1, 100 do
            quests[#quests + 1] = {
                id = id,
                eligible = true,
                completed = id <= 15,
                inProgress = id >= 16 and id <= 37,
                missingRequirements = id >= 51,
                breadcrumb = id == 1 or id == 16 or id == 38 or id == 51,
            }
        end
        for id = 101, 108 do
            quests[#quests + 1] = {id = id, repeatable = true}
        end
        for id = 109, 110 do
            quests[#quests + 1] = {id = id, eligible = false, unobtainable = true}
        end
        return {status = "ready", zoneName = "The Barrens", quests = quests}
    end

    test("default total mode partitions the Barrens example without double counting active quests", function()
        local result = calculate(barrens())
        equal(result.mode, "total")
        equal(result.status, "ready")
        equal(result.zoneName, "The Barrens")
        equal(result.completed, 15)
        equal(result.inProgress, 22)
        equal(result.available, 13)
        equal(result.missingRequirements, 50)
        equal(result.zoneTotal, 100)
        equal(result.total, 100)
        equal(result.percent, 15)
        equal(result.completed + result.inProgress + result.available + result.missingRequirements, result.total)
        equal(result.repeatable, 8)
        equal(result.unobtainable, 2)
        equal(result.excluded, 10)
        equal(result.breadcrumbs, 4)
        equal(result.unknown, 0)
    end)

    test("available mode removes unmet requirements from the denominator, not active quests", function()
        local result = calculate(barrens(), "available")
        equal(result.mode, "available")
        equal(result.status, "ready")
        equal(result.zoneTotal, 100)
        equal(result.total, 50)
        equal(result.completed, 15)
        equal(result.inProgress, 22)
        equal(result.available, 13)
        equal(result.missingRequirements, 50)
        equal(result.percent, 30)
        equal(result.completed + result.inProgress + result.available, result.total)
    end)

    test("active and objective-ready quests never earn completion credit without the character flag", function()
        local result = calculate({status = "ready", quests = {
            {id = 1, eligible = true, completed = false, inProgress = true},
            {id = 2, eligible = true, completed = false, inProgress = true, missingRequirements = true},
            {id = 3, eligible = true, completed = true, inProgress = true, missingRequirements = true},
        }})
        equal(result.completed, 1)
        equal(result.inProgress, 2)
        equal(result.available, 0)
        equal(result.missingRequirements, 0)
        equal(result.total, 3)
        equal(result.percent, 100 / 3)
    end)

    test("breadcrumb and hidden overlays add neither duplicate totals nor duplicate segments", function()
        local snapshot = barrens()
        snapshot.quests[#snapshot.quests + 1] = snapshot.quests[1]
        snapshot.quests[#snapshot.quests + 1] = snapshot.quests[16]
        snapshot.quests[#snapshot.quests + 1] = snapshot.quests[51]
        local result = calculate(snapshot, "total")
        equal(result.completed, 15)
        equal(result.inProgress, 22)
        equal(result.missingRequirements, 50)
        equal(result.total, 100)
        equal(result.breadcrumbs, 4)
    end)

    test("excluded alternatives, repeatables and unobtainable breadcrumbs never inflate progress", function()
        local result = calculate({status = "ready", quests = {
            {id = 1, eligible = true, completed = true, breadcrumb = true},
            {id = 2, alternative = true, breadcrumb = true},
            {id = 3, repeatable = true, completed = true, inProgress = true, breadcrumb = true},
            {id = 4, eligible = false, unobtainable = true, breadcrumb = true},
        }})
        equal(result.completed, 1)
        equal(result.inProgress, 0)
        equal(result.total, 1)
        equal(result.percent, 100)
        equal(result.excluded, 3)
        equal(result.alternatives, 1)
        equal(result.repeatable, 1)
        equal(result.unobtainable, 1)
        equal(result.breadcrumbs, 1)
    end)

    test("unlocking more quests lowers available-mode percent while total-zone percent stays stable", function()
        local snapshot = {status = "ready", quests = {}}
        for id = 1, 20 do
            snapshot.quests[id] = {id = id, eligible = true, completed = id <= 10, missingRequirements = id > 10}
        end
        equal(calculate(snapshot, "available").percent, 100)
        equal(calculate(snapshot, "total").percent, 50)
        snapshot.quests[11].missingRequirements = false
        local available = calculate(snapshot, "available")
        equal(available.total, 11)
        equal(available.available, 1)
        equal(available.percent, 1000 / 11)
        equal(calculate(snapshot, "total").percent, 50)
    end)

    test("unknown classification suppresses percentages in either denominator mode", function()
        for _, mode in ipairs({"total", "available"}) do
            local result = calculate({status = "ready", quests = {
                {id = 1, eligible = true, completed = true},
                {id = 2, unknown = true, missingRequirements = true},
                {id = 3, eligible = true},
                {id = -1, eligible = true, completed = false},
            }}, mode)
            equal(result.status, "incomplete")
            equal(result.completed, 1)
            equal(result.unknown, 3)
            equal(result.percent, nil)
        end
    end)

    test("invalid quest identifiers cannot create countable entries", function()
        local result = calculate({status = "ready", quests = {
            {id = "1", eligible = true, completed = true},
            {id = 0, eligible = true, completed = true},
            {id = 1.5, eligible = true, completed = true},
            {eligible = true, completed = true},
        }})
        equal(result.completed, 0)
        equal(result.total, 0)
        equal(result.unknown, 4)
        equal(result.status, "incomplete")
    end)

    test("empty and entirely excluded zones never report 100 percent", function()
        for _, mode in ipairs({"total", "available"}) do
            for _, quests in ipairs({{}, {{id = 1, repeatable = true}}, {{id = 2, eligible = false, unobtainable = true}}}) do
                local result = calculate({status = "ready", quests = quests}, mode)
                equal(result.total, 0)
                equal(result.status, "incomplete")
                equal(result.percent, nil)
            end
        end
    end)

    test("only missing requirements cannot establish an available-mode total", function()
        local snapshot = {status = "ready", quests = {{id = 1, eligible = true, completed = false, missingRequirements = true}}}
        local available = calculate(snapshot, "available")
        equal(available.zoneTotal, 1)
        equal(available.total, 0)
        equal(available.percent, nil)
        equal(available.status, "incomplete")
        local total = calculate(snapshot, "total")
        equal(total.status, "ready")
        equal(total.total, 1)
        equal(total.percent, 0)
    end)

    test("unavailable and unresolved snapshots have no invented history or segments", function()
        for _, status in ipairs({"unavailable", "waiting", "incomplete"}) do
            local result = calculate({status = status, message = "No data"}, "total")
            equal(result.status, status)
            equal(result.completed, nil)
            equal(result.inProgress, nil)
            equal(result.available, nil)
            equal(result.missingRequirements, nil)
            equal(result.total, nil)
            equal(result.zoneTotal, nil)
            equal(result.percent, nil)
            equal(result.message, "No data")
        end
    end)
end
