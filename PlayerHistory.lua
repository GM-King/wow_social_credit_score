local addon, S = ...
local limit, rowHeight, visibleRows = 100, 60, 7
local width, height, rowWidth = 720, 560, 666
local media = "Interface\\AddOns\\" .. addon .. "\\Media\\"
local units, refreshQueued = {}
local window, minimapButton, tab
local roster, entries, offsets = {}, {}, {Recent = 0, Reviewed = 0, Guilds = 0}

local function recent()
    local history = S.db.recentPlayers
    history[S.me.key] = history[S.me.key] or {}
    return history[S.me.key]
end

local function record(key, name, interaction)
    if not key or S.db.alts[key] then return end
    local rows = recent()
    for i, row in ipairs(rows) do
        if row.key == key then
            table.remove(rows, i)
            break
        end
    end
    table.insert(rows, 1, {key = key, name = name, interaction = interaction, time = S.Now()})
    if #rows > limit then table.remove(rows, limit + 1) end
end

local function reviewed()
    local rows = {}
    for subject, author in pairs(S.db.authored) do
        local review = author == S.me.key and (S.db.reviews[subject] or {})[author]
        if review and not review.deleted and not S.db.alts[subject] then
            rows[#rows + 1] = review
        end
    end
    table.sort(rows, function(a, b)
        if a.revision == b.revision then return a.subject < b.subject end
        return a.revision > b.revision
    end)
    return rows
end

local function guilds()
    local totals, rows = {}, {}
    if not S.realm then return rows end
    for key, profile in pairs(S.db.profiles) do
        local name = profile.guild
        if profile.guildRealm == S.realm and type(name) == "string" and name ~= "" then
            local _, _, score = S.RatingSummary(key)
            if score then
                local guildKey = name:lower()
                local guild = totals[guildKey] or {name = name, total = 0, count = 0}
                guild.name = name < guild.name and name or guild.name
                guild.total, guild.count = guild.total + score, guild.count + 1
                totals[guildKey] = guild
            end
        end
    end
    for _, guild in pairs(totals) do
        if guild.count >= 5 then
            guild.average = guild.total / guild.count
            rows[#rows + 1] = guild
        end
    end
    table.sort(rows, function(a, b)
        if a.average ~= b.average then return a.average > b.average end
        return a.name:lower() < b.name:lower()
    end)
    return rows
end

local tabEntries = {Recent = recent, Reviewed = reviewed, Guilds = guilds}
local emptyText = {Recent = "No recent players", Reviewed = "No reviews written",
    Guilds = "No known guilds with five scored members on this server"}

local function elapsed(stamp)
    local age = math.max(0, S.Now() - stamp)
    if age < 60 then return "Just now" end
    if age < 3600 then return ("%dm ago"):format(math.floor(age / 60)) end
    if age < 86400 then return ("%dh ago"):format(math.floor(age / 3600)) end
    return ("%dd ago"):format(math.floor(age / 86400))
end

local function updateUnits()
    units = {}
    local function remember(unit)
        local player = S.Unit(unit, true)
        if player then units[player.key] = unit end
    end
    local raid = S.Call(IsInRaid)
    for i = 1, S.Call(raid and GetNumGroupMembers or GetNumSubgroupMembers) or 0 do
        remember((raid and "raid" or "party") .. i)
    end
    remember("focus")
    remember("target")
end

local function paintRow(button, entry, index)
    button.background:SetColorTexture(.15, .095, .084, index % 2 == 0 and 1 or .64)
    local guild = tab == "Guilds"
    button.rank:SetShown(guild)
    button.portrait:SetShown(not guild)
    button.border:SetShown(not guild)
    button:SetEnabled(not guild)
    if guild then
        button.mark:Hide()
        button.rank:SetText(tostring(index))
        button.name:SetText(entry.name)
        button.metadata:SetText(("%d scored members"):format(entry.count))
        button.detail:SetText("")
        button.score:SetText(("%.2f SCS"):format(entry.average))
        button.tier:SetText("Guild average")
        return
    end
    local key = entry.subject or entry.key
    local profile = S.db.profiles[key]
    local class = profile and profile.class
    local _, _, score, provisional = S.RatingSummary(key)
    local tier = S.Tier(score)
    local unit = units[key]
    local observed = unit and S.Unit(unit, true)
    S.PaintProfilePortrait(button.portrait, observed and observed.key == key and unit, class)
    S.PaintProfileBorder(button.border, tier)
    button.mark:SetShown(S.BlackMarkReviewers(key) ~= nil)
    button.name:SetText(entry.subjectName or entry.name)
    local metadata = {}
    if profile then
        if profile.level then metadata[#metadata + 1] = ("Level %d"):format(profile.level) end
        if class then
            local names = LOCALIZED_CLASS_NAMES_MALE
            metadata[#metadata + 1] = (names and names[class]) or class:sub(1, 1) .. class:sub(2):lower()
        end
        if profile.guild and profile.guild ~= "" then metadata[#metadata + 1] = profile.guild end
    end
    button.metadata:SetText(table.concat(metadata, "  \226\128\162  "))
    button.detail:SetText(tab == "Recent" and (entry.interaction .. "  /  " .. elapsed(entry.time))
        or ("%g / 5 stars  /  %s"):format(entry.stars, elapsed(entry.time)))
    local belowCap = profile and profile.level and profile.level < 60 and S.Viewable(key)
    button.score:SetText(score and ("%.2f SCS"):format(score) or belowCap and "Unlocks at level 60" or "SCS -")
    button.tier:SetText(score and (tier .. (provisional and "  /  Provisional" or "")) or "")
end

local function render(offset)
    if not window then return end
    offsets[tab] = offset
    local first = math.floor(offset / rowHeight)
    for i, button in ipairs(window.rows) do
        local entry = entries[first + i]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -(first + i - 1) * rowHeight)
        button.entry = entry or false
        if entry then paintRow(button, entry, first + i) end
        button:SetShown(entry ~= nil)
    end
end

function S.RefreshPlayerHistory()
    if not window or not window:IsShown() then return end
    if tab ~= "Guilds" then updateUnits() end
    entries = tabEntries[tab]()
    local offset = math.min(offsets[tab], math.max(0, #entries - visibleRows) * rowHeight)
    window.content:SetHeight(math.max(visibleRows, #entries) * rowHeight)
    window.scroll:UpdateScrollChildRect()
    window.scroll:SetVerticalScroll(offset)
    render(offset)
    window.empty:SetText(#entries == 0 and emptyText[tab] or "")
    window.Recent:SetEnabled(tab ~= "Recent")
    window.Reviewed:SetEnabled(tab ~= "Reviewed")
    window.Guilds:SetEnabled(tab ~= "Guilds")
end

function S.QueuePlayerHistoryRefresh()
    if not window or not window:IsShown() or refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        S.RefreshPlayerHistory()
    end)
end

for _, event in ipairs({"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_PORTRAIT_UPDATE",
    "PLAYER_REGEN_ENABLED"}) do
    S.On(event, S.QueuePlayerHistoryRefresh)
end

function S.SetPlayerHistoryStatus(message)
    if window then window.status:SetText(message or "") end
end

local function scanGroup()
    if not S.me then return end
    local previous, current, changed = roster, {}, false
    local raid = S.Call(IsInRaid)
    local count = S.Call(raid and GetNumGroupMembers or GetNumSubgroupMembers) or 0
    for i = 1, count do
        local player = S.Unit((raid and "raid" or "party") .. i, true)
        if player and not S.db.alts[player.key] then
            current[player.key] = true
            if player.faction == S.faction and S.Readable(player.level) and player.level and player.level > 0 then
                local known = S.db.profiles[player.key]
                if not known or known.level ~= player.level or known.faction ~= player.faction
                    or (player.guild ~= nil and (known.guild ~= player.guild or known.guildRealm ~= player.guildRealm)) then
                    S.Remember(player)
                end
            end
            if not previous[player.key] then
                record(player.key, player.name, "Group")
                changed = true
            end
        end
    end
    roster = current
    if changed then S.RefreshPlayerHistory() else S.QueuePlayerHistoryRefresh() end
end

local function whisper(_, name)
    if not S.me then return end
    local key, display = S.Identity(name)
    if key and not S.db.alts[key] then
        record(key, display, "Whisper")
        S.RefreshPlayerHistory()
    end
end

S.On("CHAT_MSG_WHISPER", whisper)
S.On("CHAT_MSG_WHISPER_INFORM", whisper)
S.On("GROUP_ROSTER_UPDATE", scanGroup)
S.On("PLAYER_ENTERING_WORLD", scanGroup)

function S.HidePlayerHistory()
    if window then window:Hide() end
end

local function showHistory()
    window:Show()
    S.RefreshPlayerHistory()
end

local function buildHistory()
    local f = CreateFrame("Frame", "SocialCreditSystemHistory", UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = {left = 4, right = 4, top = 4, bottom = 4}})
    f:SetBackdropColor(.09, .063, .067, .98)
    f:SetBackdropBorderColor(.65, .44, .25)
    table.insert(UISpecialFrames, f:GetName())
    f:SetScript("OnHide", function()
        S.CancelHistoryProfileLookup()
        S.SetPlayerHistoryStatus()
    end)
    f:SetScript("OnShow", function(self)
        self:SetScale(math.min(1, UIParent:GetWidth() / (width + 32), UIParent:GetHeight() / (height + 32)))
    end)

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetPoint("TOPRIGHT", -5, -5)
    header:SetHeight(88)
    header:SetTexture(media .. "GuildHall")
    header:SetVertexColor(.66, .54, .48)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -22)
    title:SetText("Social Credit System")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    for index, name in ipairs({"Recent", "Reviewed", "Guilds"}) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f[name] = button
        button:SetSize(108, 24)
        button:SetPoint("TOPLEFT", 22 + (index - 1) * 111, -57)
        button:SetText(name)
        button:SetScript("OnClick", function()
            tab = name
            S.RefreshPlayerHistory()
        end)
    end

    local scroll = CreateFrame("ScrollFrame", "SocialCreditSystemHistoryScroll", f, "UIPanelScrollFrameTemplate")
    f.scroll = scroll
    scroll:SetPoint("TOPLEFT", 16, -95)
    scroll:SetSize(rowWidth, visibleRows * rowHeight)
    local content = CreateFrame("Frame", nil, scroll)
    f.content = content
    content:SetSize(rowWidth, visibleRows * rowHeight)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function(_, offset) render(offset) end)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("TOP", scroll, "TOP", 0, -25)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("BOTTOMLEFT", 22, 15)
    f.rows = {}

    local function rowText(row, font, point, x, y, textWidth)
        local label = row:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint(point, x, y)
        label:SetWidth(textWidth)
        label:SetJustifyH(point == "RIGHT" and "RIGHT" or "LEFT")
        label:SetMaxLines(1)
        return label
    end
    -- The extra row covers the partial row revealed during smooth scrolling.
    for i = 1, visibleRows + 1 do
        local row = CreateFrame("Button", nil, content)
        f.rows[i] = row
        row:SetSize(rowWidth, rowHeight)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetAllPoints()
        row.portrait = row:CreateTexture(nil, "ARTWORK")
        row.portrait:SetSize(36, 36)
        row.portrait:SetPoint("LEFT", 18, 0)
        row.border = row:CreateTexture(nil, "OVERLAY")
        row.border:SetPoint("CENTER", row.portrait)
        row.border:SetSize(55, 55)
        row.mark = S.CreateBlackMark(row, row.portrait, 15)
        row.rank = rowText(row, "GameFontNormalLarge", "LEFT", 18, 0, 45)
        row.name = rowText(row, "GameFontNormal", "LEFT", 70, 15, 400)
        row.metadata = rowText(row, "GameFontHighlightSmall", "LEFT", 70, 0, 400)
        row.detail = rowText(row, "GameFontDisableSmall", "LEFT", 70, -15, 400)
        row.score = rowText(row, "GameFontHighlight", "RIGHT", -15, 7, 165)
        row.tier = rowText(row, "GameFontNormalSmall", "RIGHT", -15, -10, 165)
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if entry and tab ~= "Guilds" then S.OpenNamedProfile(entry.subjectName or entry.name, showHistory) end
        end)
    end
    return f
end

local function toggleHistory()
    if window and window:IsShown() then window:Hide(); return end
    if not window then
        tab = "Recent"
        window = buildHistory()
    end
    showHistory()
end

local function buildMinimapButton()
    if minimapButton or not Minimap then return end
    local position = S.db.historyMinimap
    local button = CreateFrame("Button", "SocialCreditSystemMinimapButton", Minimap)
    minimapButton = button
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    if type(position.x) == "number" and type(position.y) == "number" then
        button:SetPoint("CENTER", Minimap, "CENTER", position.x, position.y)
    else
        button:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 5, -5)
    end

    local art = button:CreateTexture(nil, "ARTWORK")
    art:SetSize(24, 24)
    art:SetPoint("CENTER", 1, -1)
    art:SetTexture("Interface\\AddOns\\" .. addon .. "\\Media\\MinimapStamp")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(55, 55)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    local dragged
    button:SetScript("OnMouseDown", function() dragged = false end)
    button:SetScript("OnDragStart", function(self)
        dragged = true
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local mx, my = Minimap:GetCenter()
        if not x or not mx then return end
        position.x, position.y = x - mx, y - my
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", position.x, position.y)
    end)
    button:SetScript("OnClick", function()
        if not dragged then toggleHistory() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Social Credit System")
        GameTooltip:AddLine("Click to open player history")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

S.OnActive(function()
    buildMinimapButton()
    scanGroup()
end)

