local _, ns = ...

local UI = {}
ns.UI = UI

local DASH = "\226\128\148"
local frame, lastProgress
local suppressClickUntil, dragging, ignoredDrag = 0, false, false
local tooltipKind
local colors = {
    completed = {0.25, 0.72, 0.40},
    inProgress = {0.96, 0.72, 0.22},
    available = {0.40, 0.49, 0.59},
    missingRequirements = {0.63, 0.31, 0.32},
}

local function integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == value and math.floor(value) or 0
end

local function font(parent, template, point, x, y)
    local result = parent:CreateFontString(nil, "OVERLAY", template)
    result:SetPoint(point, x, y)
    result:SetJustifyH("LEFT")
    return result
end

local function refreshControls()
    if ns.Config and ns.Config.RefreshControls then ns.Config.RefreshControls() end
end

local function applyStyle()
    if dragging then return end
    local style = ns.Adapter.GetTrackerStyle and ns.Adapter:GetTrackerStyle() or {}
    style = style or {}
    local headerFont = style.headerFont or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local bodyFont = style.font or headerFont
    local headerSize = math.max(6, math.min(32, style.headerFontSize or 12))
    local bodySize = math.max(6, math.min(32, style.fontSize or 10))
    local width = math.max(180, style.width or 284)
    local left = math.min(width / 4, math.max(0, style.leftInset or 14))
    local right = math.min(width / 4, math.max(0, style.rightInset or 30))
    -- Questie's header uses a 6px icon inset, independently of body margins.
    local headerLeft = 6
    local innerWidth = math.max(80, width - left - right)
    local headerHeight = headerSize + 4
    local zoneY = headerHeight + 2
    local countY = zoneY + bodySize + 3
    local barY = countY + bodySize + 4
    frame.layout = {innerWidth = innerWidth, bodySize = bodySize}
    frame:SetSize(width, ns.settings.collapsed and headerHeight or barY + 8)
    frame.header:ClearAllPoints()
    frame.header:SetPoint("TOPLEFT", frame.settingsButton, "TOPRIGHT", 2, 0)
    frame.header:SetSize(math.max(30, width - headerLeft - headerSize - 2 - right), headerHeight)
    frame.header.label:SetFont(headerFont, headerSize, style.headerOutline or style.outline or "")
    frame.header.label:SetWidth(frame.header:GetWidth())
    frame.settingsButton:ClearAllPoints()
    frame.settingsButton:SetPoint("TOPLEFT", headerLeft, 0)
    frame.settingsButton:SetSize(headerSize, headerSize)
    frame.settingsButton.glyph:SetFont(headerFont, headerSize, style.headerOutline or style.outline or "")
    local icon = ns.Adapter.GetTrackerIcon and ns.Adapter:GetTrackerIcon()
    frame.settingsButton.texture:SetShown(icon ~= nil)
    frame.settingsButton.glyph:SetShown(icon == nil)
    if icon ~= nil then frame.settingsButton.texture:SetTexture(icon) end
    frame.title:SetFont(bodyFont, bodySize, style.outline or "")
    frame.count:SetFont(bodyFont, bodySize, style.outline or "")
    frame.percent:SetFont(bodyFont, bodySize, style.outline or "")
    local headerColor, textColor = style.headerColor or {1, 0.82, 0}, style.textColor or {1, 1, 1}
    frame.header.label:SetTextColor(headerColor[1], headerColor[2], headerColor[3])
    frame.settingsButton.glyph:SetTextColor(headerColor[1], headerColor[2], headerColor[3])
    frame.title:SetTextColor(textColor[1], textColor[2], textColor[3])
    frame.count:SetTextColor(textColor[1], textColor[2], textColor[3])
    frame.percent:SetTextColor(textColor[1], textColor[2], textColor[3])
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOPLEFT", left, -zoneY)
    frame.title:SetWidth(innerWidth)
    frame.title:SetHeight(bodySize + 2)
    frame.count:ClearAllPoints()
    frame.count:SetPoint("TOPLEFT", left, -countY)
    frame.count:SetHeight(bodySize + 2)
    frame.percent:ClearAllPoints()
    frame.percent:SetPoint("TOPRIGHT", -right, -countY)
    frame.percent:SetHeight(bodySize + 2)
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", left, -barY)
    frame.bar:SetSize(innerWidth, 5)
    if style.backdropEnabled or style.borderEnabled then
        frame:SetBackdrop({
            bgFile = style.backdropEnabled and "Interface\\Buttons\\WHITE8X8" or nil,
            edgeFile = style.borderEnabled and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
            tile = true, edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        local bg, border = style.backdropColor or {0, 0, 0, 1}, style.borderColor or {1, 1, 1, 1}
        frame:SetBackdropColor(bg[1], bg[2], bg[3], style.backdropEnabled and (bg[4] or 1) * ns.settings.opacity or 0)
        frame:SetBackdropBorderColor(border[1], border[2], border[3], style.borderEnabled and (border[4] or 1) or 0)
    else
        frame:SetBackdrop(nil)
    end
end

local function savePosition()
    local x, y = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if x and y and parentX and parentY then
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        ns.settings.x, ns.settings.y = x * ratio - parentX, y * ratio - parentY
    end
end

local function anchorStandalone()
    if frame:GetParent() ~= UIParent then frame:SetParent(UIParent) end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local limitX = math.max(0, (UIParent:GetWidth() - frame:GetWidth() * ratio) / 2)
    local limitY = math.max(0, (UIParent:GetHeight() - frame:GetHeight() * ratio) / 2)
    ns.settings.x = math.max(-limitX, math.min(limitX, ns.settings.x))
    ns.settings.y = math.max(-limitY, math.min(limitY, ns.settings.y))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", ns.settings.x / ratio, ns.settings.y / ratio)
    UI.attached = false
end

local function updateAnchor()
    if dragging then return end
    local anchor
    if ns.settings.attachToTracker and ns.Adapter.GetTrackerAnchor then
        anchor = ns.Adapter:GetTrackerAnchor()
    end
    if anchor then
        -- Parenting only our frame inherits the tracker's visibility, alpha and scale.
        -- Relative anchoring follows movement without touching Questie's scripts or state.
        if frame:GetParent() ~= anchor then frame:SetParent(anchor) end
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
        UI.attached = true
    else
        anchorStandalone()
    end
end

local function hasProgress(progress)
    return progress.status == "ready" and type(progress.percent) == "number"
        and progress.percent >= 0 and progress.percent <= 100
        and integer(progress.unknown) == 0 and integer(progress.total) > 0
end

local function showTooltip(owner, kind)
    owner, kind = owner or frame, kind or "progress"
    tooltipKind = kind
    local progress = lastProgress or {}
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
    if kind == "settings" then
        GameTooltip:SetText("Open settings", 1, 0.82, 0)
    elseif kind == "header" then
        GameTooltip:SetText("Zone Completion", 1, 0.82, 0)
        GameTooltip:AddLine(ns.settings.collapsed and "Click to expand." or "Click to minimize.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Ctrl-drag to move.", 0.65, 0.85, 1)
    else
        GameTooltip:SetText(progress.zoneName or "Questie Zone Completion", 1, 0.82, 0)
        if progress.completed ~= nil and progress.status ~= "waiting" and progress.status ~= "unavailable" then
            for _, entry in ipairs({
                {"completed", "Completed"}, {"inProgress", "In progress"},
                {"available", "Available"}, {"missingRequirements", "Missing requirements"},
            }) do
                local key, label = entry[1], entry[2]
                local color = colors[key]
                GameTooltip:AddLine(string.format("%s: %d", label, integer(progress[key])),
                    math.min(1, color[1] + 0.22), math.min(1, color[2] + 0.22), math.min(1, color[3] + 0.22))
            end
            GameTooltip:AddLine(progress.mode == "available" and "Available quests; missing requirements excluded." or "All zone quests.",
                0.8, 0.8, 0.8)
        end
        if progress.status ~= "ready" and progress.message and progress.message ~= "" then
            GameTooltip:AddLine(progress.message, 1, 0.8, 0.35, true)
        end
        GameTooltip:AddLine("Click: Quests by Zone.", 0.65, 0.85, 1)
    end
    GameTooltip:Show()
end

local function measuredWidth(label)
    if label.GetUnboundedStringWidth then return label:GetUnboundedStringWidth() end
    if label.GetStringWidth then return label:GetStringWidth() end
end

local function updateCount(progress, ready)
    local percent = ready and string.format("%d%%", math.floor(progress.percent)) or DASH
    frame.percent:SetText(percent)
    local layout = frame.layout or {innerWidth = 240, bodySize = 10}
    local percentWidth = measuredWidth(frame.percent) or layout.bodySize * 3
    percentWidth = math.min(layout.innerWidth, math.max(1, percentWidth))
    frame.percent:SetWidth(percentWidth)
    local availableWidth = math.max(1, layout.innerWidth - percentWidth - 8)
    frame.count:SetWidth(availableWidth)
    local full, compact
    if ready then
        compact = string.format("%d / %d", integer(progress.completed), integer(progress.total))
        full = compact .. " completed"
    else
        local hasCount = progress.completed ~= nil and progress.status ~= "waiting" and progress.status ~= "unavailable"
        compact = hasCount and string.format("%d / %s", integer(progress.completed), DASH) or DASH
        full = compact
    end
    frame.count:SetText(full)
    local naturalWidth = measuredWidth(frame.count)
    if naturalWidth == nil or naturalWidth > availableWidth then frame.count:SetText(compact) end
end

local function stopDrag(reapply)
    local kind = dragging
    if not kind then return end
    dragging = false
    if kind == "tracker" then
        local ok, reason = ns.Adapter:StopTrackerDrag()
        if not ok then ns:Print(reason or "Questie's tracker could not finish moving.") end
    else
        frame:StopMovingOrSizing()
        savePosition()
    end
    suppressClickUntil = GetTime() + 0.2
    if reapply ~= false then UI:ApplySettings() end
end

local function drawSegments(progress, ready)
    local offset, total = 0, integer(progress.total)
    local width = frame.bar:GetWidth()
    for _, key in ipairs({"completed", "inProgress", "available", "missingRequirements"}) do
        local segment = frame.bar.segments[key]
        local count = integer(progress[key])
        if key == "missingRequirements" and progress.mode == "available" then count = 0 end
        local segmentWidth = ready and math.min(width - offset, width * count / total) or 0
        segment:ClearAllPoints()
        segment:SetPoint("LEFT", frame.bar, "LEFT", offset, 0)
        segment:SetWidth(math.max(0, segmentWidth))
        segment:SetShown(segmentWidth > 0)
        offset = offset + segmentWidth
    end
end

function UI:Create()
    if frame then return end
    frame = CreateFrame("Button", "QuestieZoneCompletionWidget", UIParent, "BackdropTemplate")
    self.frame = frame
    frame:SetSize(284, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame.header = CreateFrame("Button", nil, frame)
    frame.header.label = font(frame.header, "GameFontNormal", "TOPLEFT", 0, 0)
    frame.header.label:SetWordWrap(false)
    frame.settingsButton = CreateFrame("Button", nil, frame)
    frame.settingsButton.texture = frame.settingsButton:CreateTexture(nil, "ARTWORK")
    frame.settingsButton.texture:SetAllPoints()
    frame.settingsButton.glyph = font(frame.settingsButton, "GameFontNormal", "CENTER", 0, 0)
    frame.settingsButton.glyph:SetText("?")
    frame.title = font(frame, "GameFontHighlightSmall", "TOPLEFT", 14, -20)
    frame.title:SetWordWrap(false)
    frame.count = font(frame, "GameFontHighlightSmall", "TOPLEFT", 14, -35)
    frame.count:SetWordWrap(false)
    frame.percent = font(frame, "GameFontHighlightSmall", "TOPRIGHT", -30, -35)
    frame.percent:SetWordWrap(false)
    frame.bar = CreateFrame("Frame", nil, frame)
    frame.bar:SetSize(240, 5)
    frame.bar.segments = {}
    local track = frame.bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.12, 0.12, 0.13, 0.65)
    for _, key in ipairs({"completed", "inProgress", "available", "missingRequirements"}) do
        local color = colors[key]
        local segment = frame.bar:CreateTexture(nil, "ARTWORK")
        segment:SetColorTexture(color[1], color[2], color[3], 1)
        segment:SetHeight(5)
        frame.bar.segments[key] = segment
    end

    local function clickAllowed()
        return GetTime() >= suppressClickUntil and not IsControlKeyDown()
    end
    local function startDrag()
        if not IsControlKeyDown() then ignoredDrag = true; return end
        ignoredDrag = false
        GameTooltip:Hide()
        if InCombatLockdown() then
            ignoredDrag = true
            ns:Print("Move the tracker after combat.")
            return
        end
        if UI.attached then
            if type(ns.Adapter.StartTrackerDrag) ~= "function" or type(ns.Adapter.StopTrackerDrag) ~= "function" then
                ignoredDrag = true
                ns:Print("Questie's tracker movement is unavailable. Update both addons.")
                return
            end
            local ok, reason = ns.Adapter:StartTrackerDrag()
            if not ok then
                ignoredDrag = true
                ns:Print(reason or "Questie's tracker cannot move right now.")
                return
            end
            dragging = "tracker"
        else
            dragging = "widget"
            frame:StartMoving()
        end
        suppressClickUntil = math.huge
    end
    local function endDrag()
        if ignoredDrag then
            ignoredDrag = false
            suppressClickUntil = GetTime() + 0.2
            return
        end
        stopDrag()
    end
    for _, region in ipairs({frame, frame.header, frame.settingsButton}) do
        region:EnableMouse(true)
        region:RegisterForDrag("LeftButton")
        region:RegisterForClicks("LeftButtonUp")
        region:SetScript("OnDragStart", startDrag)
        region:SetScript("OnDragStop", endDrag)
        local kind = region == frame and "progress" or (region == frame.header and "header" or "settings")
        region:SetScript("OnEnter", function(self)
            if UI.attached and ns.Adapter.SetTrackerHover then ns.Adapter:SetTrackerHover(true) end
            UI:Render(lastProgress)
            showTooltip(self or region, kind)
        end)
        region:SetScript("OnLeave", function()
            if UI.attached and ns.Adapter.SetTrackerHover then ns.Adapter:SetTrackerHover(false) end
            tooltipKind = nil
            GameTooltip:Hide()
        end)
    end
    frame:SetScript("OnClick", function()
        if not clickAllowed() then return end
        if InCombatLockdown() then
            ns:Print("Open Questie Journey after combat.")
            return
        end
        local ok, reason = ns.Adapter:OpenJourney()
        if not ok then ns:Print(reason or "Questie Journey is unavailable.") end
    end)
    frame.header:SetScript("OnClick", function()
        if not clickAllowed() or InCombatLockdown() then return end
        ns.Config.ToggleCollapsed()
    end)
    frame.settingsButton:SetScript("OnClick", function()
        if clickAllowed() then ns.Config.Open() end
    end)
    frame:SetScript("OnHide", function()
        if UI.attached and ns.Adapter.SetTrackerHover then ns.Adapter:SetTrackerHover(false) end
        stopDrag(false)
    end)
    self:ApplySettings()
end

function UI:ApplySettings()
    if not frame then return end
    frame:SetScale(ns.settings.scale)
    refreshControls()
    self:Render(lastProgress)
end

function UI:Render(progress)
    lastProgress = progress or lastProgress or {status = "waiting", message = "Waiting for Questie"}
    if not frame then return end
    progress = lastProgress
    applyStyle()
    updateAnchor()
    frame.title:SetText(progress.zoneName or "Questie Zone Completion")
    local ready = hasProgress(progress)
    updateCount(progress, ready)
    drawSegments(progress, ready)
    frame.header.label:SetText(ns.settings.collapsed and "Zone Completion +" or "Zone Completion")
    local expanded = not ns.settings.collapsed
    frame.title:SetShown(expanded)
    frame.count:SetShown(expanded)
    frame.percent:SetShown(expanded)
    frame.bar:SetShown(expanded)
    local hideComplete = ns.settings.hideComplete and ready and integer(progress.completed) == integer(progress.total)
    frame:SetShown(ns.settings.visible and not hideComplete)
    local owner = GameTooltip:GetOwner()
    if tooltipKind and (owner == frame or owner == frame.header or owner == frame.settingsButton) then
        showTooltip(owner, tooltipKind)
    end
end
