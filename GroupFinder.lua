local _, S = ...
local badges = setmetatable({}, {__mode = "k"})
local browse, nativeTooltip, panel, hoveredResult, queued
local starSize = 12

local function listing(resultID)
    if not S.me or not S.Readable(resultID) or type(resultID) ~= "number" then return end
    local info = S.Call(C_LFGList.GetSearchResultInfo, resultID)
    if not info or not S.Readable(info.isDelisted) or info.isDelisted
        or not S.Readable(info.numMembers) or type(info.numMembers) ~= "number" then return end
    return info
end

local function playerSummary(player, fallbackName)
    if player and (not S.Readable(player.level) or (player.level and player.level ~= 60)) then return end
    local name = player and player.name
    if not S.Readable(name) then return end
    local key, display = S.Identity(name or fallbackName)
    if key and (not player or not player.level or player.level == 60) then S.LookupGroupProfile(key) end
    local count, average, score, provisional = S.RatingSummary(key)
    local mark = S.BlackMarkReviewers(key)
    if count ~= nil or mark then return display, count or 0, average, score, provisional, mark ~= nil end
end

local function leader(resultID)
    return S.Call(C_LFGList.GetSearchResultLeaderInfo, resultID)
end

local function scoreText(score, provisional)
    if score then return ("SCS %.2f%s"):format(score, provisional and "*" or "") end
    return "SCS —"
end

local function hideTooltip()
    hoveredResult = nil
    if panel then panel:Hide() end
end

local function updateBadge(row)
    if not row.Name then return end
    local entry = badges[row]
    if not entry then
        entry = {}
        badges[row] = entry
        row:HookScript("OnHide", function()
            if entry.badge then entry.badge:Hide() end
            if hoveredResult == entry.resultID then hideTooltip() end
        end)
    else
        if entry.badge then entry.badge:Hide() end
        if hoveredResult and hoveredResult == entry.resultID
            and (not S.Readable(row.resultID) or row.resultID ~= entry.resultID) then hideTooltip() end
    end
    if not row:IsVisible() then return end
    local resultID = row.resultID
    local info = listing(resultID)
    entry.resultID = info and resultID
    if not info then return end
    local name, _, _, score, provisional, marked = playerSummary(leader(resultID), info.leaderName)
    if not name then return end
    if not entry.badge then
        local badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- The compact top strip sits above Blizzard's name, role and activity fields.
        badge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -9, -2)
        entry.badge = badge
    end
    local badge = entry.badge
    badge:SetText((marked and S.BlackMarkIcon(13) .. " " or "")
        .. (info.numMembers > 1 and "Leader " or "") .. scoreText(score, provisional))
    if score then badge:SetTextColor(1, .82, .54) else badge:SetTextColor(.78, .75, .72) end
    badge:Show()
end

local function makePanel()
    local frame = CreateFrame("Frame", nil, nativeTooltip, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(.10, .07, .07, .98)
    frame:SetBackdropBorderColor(.54, .37, .25)
    frame.rows = {}
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 10, 7)
    frame.footer:SetText("* Provisional · Limited comparison data")
    return frame
end

local function displayRow(index, name, count, average, score, provisional, marked)
    local row = panel.rows[index]
    if not row then
        local y = 8 + (index - 1) * 34
        local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -y)
        local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", 10, -y - 15)
        row = {title = title, value = value, stars = S.CreateAverageStars(panel, 10, y + 14, starSize)}
        panel.rows[index] = row
    end
    row.title:SetText((marked and S.BlackMarkIcon(13) .. " " or "") .. name .. "  ·  " .. scoreText(score, provisional))
    row.title:Show()
    row.value:SetPoint("TOPLEFT", average and 83 or 10, -23 - (index - 1) * 34)
    row.value:SetText(S.AverageCaption(count, average))
    row.value:Show()
    S.PaintAverageStars(row.stars, average, starSize)
    return math.max(row.title:GetStringWidth() + 20,
        row.value:GetStringWidth() + (average and 93 or 20))
end

local function updateTooltip(resultID)
    hideTooltip()
    local info = listing(resultID)
    if not info or not nativeTooltip:IsVisible() then return end
    hoveredResult = resultID
    local used, width, anyProvisional = 0, 235, false
    local function add(name, count, average, score, provisional, marked)
        if not name then return end
        if not panel then panel = makePanel() end
        used = used + 1
        width = math.max(width, displayRow(used, name, count, average, score, provisional, marked))
        anyProvisional = anyProvisional or provisional == true
    end
    local leaderInfo = leader(resultID)
    add(playerSummary(leaderInfo, info.leaderName))
    if info.numMembers > 1 and info.numMembers <= 10 then
        local leaderName = S.Identity(leaderInfo and leaderInfo.name)
            or S.Identity(info.leaderName)
        for index = 1, info.numMembers do
            local member = S.Call(C_LFGList.GetSearchResultPlayerInfo, resultID, index)
            if member and S.Readable(member.isLeader) and not member.isLeader
                and S.Identity(member.name) ~= leaderName then
                add(playerSummary(member))
            end
        end
    end
    if used == 0 then return end
    for index = used + 1, #panel.rows do
        local row = panel.rows[index]
        row.title:Hide()
        row.value:Hide()
        S.PaintAverageStars(row.stars, nil, starSize)
    end
    panel.footer:SetShown(anyProvisional)
    local height = used * 34 + (anyProvisional and 18 or 4)
    panel:SetSize(width, height)
    panel:ClearAllPoints()
    if (nativeTooltip:GetBottom() or 0) >= height + 4 then
        panel:SetPoint("TOPLEFT", nativeTooltip, "BOTTOMLEFT", 0, -4)
    else
        panel:SetPoint("BOTTOMLEFT", nativeTooltip, "TOPLEFT", 0, 4)
    end
    panel:Show()
end

local function refresh()
    if not browse or not browse:IsVisible() then return end
    browse.ScrollBox:ForEachFrame(updateBadge)
    if hoveredResult then updateTooltip(hoveredResult) end
end

function S.QueueGroupFinderRefresh()
    if queued or not browse or not browse:IsVisible() then return end
    queued = true
    C_Timer.After(0, function()
        queued = nil
        refresh()
    end)
end

local function attach()
    if browse or not S.me then return end
    local frame, tooltip = LFGBrowseFrame, LFGBrowseSearchEntryTooltip
    if not frame or not frame.ScrollBox or not frame.ScrollBox.ForEachFrame or not tooltip
        or not LFGBrowseSearchEntry_Update or not LFGBrowseSearchEntryTooltip_UpdateAndShow then return end
    browse, nativeTooltip = frame, tooltip
    hooksecurefunc("LFGBrowseSearchEntry_Update", updateBadge)
    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(_, resultID)
        updateTooltip(resultID)
    end)
    tooltip:HookScript("OnHide", hideTooltip)
    frame:HookScript("OnHide", hideTooltip)
    frame:HookScript("OnShow", S.QueueGroupFinderRefresh)
    S.QueueGroupFinderRefresh()
end

S.On("ADDON_LOADED", function(name)
    if name == "Blizzard_GroupFinder_VanillaStyle" then attach() end
end)
S.OnActive(attach)
