local _, ns = ...

-- Pure counting: the adapter owns upstream interpretation; the UI owns formatting.
local Progress = {}
ns.ZoneProgress = Progress

function Progress.Calculate(snapshot, mode)
    mode = mode == "available" and "available" or "total"
    local result = {
        zoneName = snapshot.zoneName or "Unknown zone",
        status = snapshot.status or "incomplete",
        message = snapshot.message,
        mode = mode,
        completed = 0, total = 0, unknown = 0, excluded = 0,
        inProgress = 0, available = 0, missingRequirements = 0, zoneTotal = 0,
        repeatable = 0, alternatives = 0, unobtainable = 0, breadcrumbs = 0,
    }
    if snapshot.status ~= "ready" then
        result.completed, result.total = nil, nil
        result.inProgress, result.available, result.missingRequirements = nil, nil, nil
        result.zoneTotal = nil
        return result
    end

    local seen = {}
    for _, quest in ipairs(snapshot.quests or {}) do
        local id = quest.id
        if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
            result.unknown = result.unknown + 1
        elseif not seen[id] then
            seen[id] = true
            if quest.unknown then
                result.unknown = result.unknown + 1
            elseif quest.repeatable then
                result.repeatable = result.repeatable + 1
                result.excluded = result.excluded + 1
            elseif quest.alternative then
                result.alternatives = result.alternatives + 1
                result.excluded = result.excluded + 1
            elseif quest.eligible == true and type(quest.completed) == "boolean" then
                result.zoneTotal = result.zoneTotal + 1
                if quest.breadcrumb then result.breadcrumbs = result.breadcrumbs + 1 end
                if quest.completed then
                    result.completed = result.completed + 1
                elseif quest.inProgress == true then
                    result.inProgress = result.inProgress + 1
                elseif quest.missingRequirements then
                    result.missingRequirements = result.missingRequirements + 1
                else
                    result.available = result.available + 1
                end
            elseif quest.eligible == false then
                result.excluded = result.excluded + 1
                if quest.unobtainable then result.unobtainable = result.unobtainable + 1 end
            else
                result.unknown = result.unknown + 1
            end
        end
    end

    result.total = result.zoneTotal
    if mode == "available" then result.total = result.total - result.missingRequirements end
    -- An empty, missing or partly classified group cannot establish zone completion.
    if result.unknown > 0 or result.total == 0 then
        result.status = "incomplete"
        if result.unknown > 0 then
            result.message = "Some Questie entries could not be classified."
        else
            result.message = mode == "available" and "No quests are available in this zone yet."
                or "Questie has no eligible quests for this zone."
        end
    else
        result.status = "ready"
        result.percent = 100 * result.completed / result.total
        result.message = nil
    end
    return result
end
