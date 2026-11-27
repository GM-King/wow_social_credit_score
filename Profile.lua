local addon, S = ...
local media = "Interface\\AddOns\\" .. addon .. "\\Media\\"
local frame, filter = nil, "Newest"
local cream, muted, gold = {1, .94, .85}, {.78, .70, .65}, {1, .77, .43}
local inactive = {.35, .25, .21}
local friendColor, guildColor, reviewEdge = {.48, .91, .83}, {.81, .72, .98}, {.47, .29, .22}
local ownReviewColor = {1, .83, .58}
local width, height, perPage = 812, 566, 3
local page = 1
local pendingProfile
local confirmation = "SOCIAL_CREDIT_CONFIRM_ZERO"
local confirmDelete = "SOCIAL_CREDIT_CONFIRM_DELETE"

local function dismissConfirmation()
    if not StaticPopup_Hide then return end
    StaticPopup_Hide(confirmation)
    StaticPopup_Hide(confirmDelete)
end

function S.CreateAverageStars(parent, x, y, size, spacing)
    local stars = {}
    for i = 1, 5 do
        local empty = parent:CreateTexture(nil, "ARTWORK")
        empty:SetPoint("TOPLEFT", x + (i - 1) * (spacing or size + 2), -y)
        empty:SetSize(size, size)
        empty:SetTexture(media .. "StarEmpty")
        local fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
        fill:SetPoint("LEFT", empty, "LEFT")
        fill:SetSize(size, size)
        fill:SetTexture(media .. "StarFilled")
        stars[i] = {empty = empty, fill = fill}
    end
    return stars
end

function S.PaintAverageStars(stars, average, size)
    for i, star in ipairs(stars) do
        local fraction = math.min(1, math.max(0, (average or 0) - i + 1))
        star.empty:SetShown(average ~= nil and fraction < 1)
        star.fill:SetShown(fraction > 0)
        if fraction > 0 then
            star.fill:SetWidth(size * fraction)
            star.fill:SetTexCoord(0, fraction, 0, 1)
        end
    end
end

function S.AverageCaption(count, average)
    if average then return ("%.2f / 5 · %d reviews"):format(average, count) end
    return ("%d of 5 reviews"):format(count)
end

local function surface(parent, x, y, w, h, r, g, b, layer)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, layer or 0)
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(w, h)
    texture:SetColorTexture(r, g, b, 1)
    return texture
end

local function art(parent, x, y, w, h, file, layer)
    local texture = surface(parent, x, y, w, h, 1, 1, 1, layer)
    texture:SetTexture(media .. file)
    return texture
end

local function previewRating(editor, rating)
    S.PaintAverageStars(editor.icons, rating or 0, 28)
    editor.rating:SetText(rating == 0 and "Zero stars" or rating and ("%.1f / 5"):format(rating) or "")
end

local function label(parent, x, y, w, font, color, value)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    text:SetPoint("TOPLEFT", x, -y)
    text:SetWidth(w)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetTextColor(unpack(color or cream))
    text:SetText(value or "")
    return text
end

local function button(parent, x, y, w, text, fn)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 27)
    b:SetPoint("TOPLEFT", x, -y)
    local bg = surface(b, 0, 0, w, 27, .27, .16, .16)
    local edge = surface(b, 0, 25, w, 2, .49, .32, .24)
    edge:SetDrawLayer("BORDER")
    local caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    caption:SetPoint("CENTER")
    caption:SetTextColor(unpack(cream))
    caption:SetText(text)
    b.caption, b.edge = caption, edge
    b:SetScript("OnEnter", function() bg:SetColorTexture(.39, .23, .20, 1) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(.27, .16, .16, 1) end)
    b:SetScript("OnDisable", function() b:SetAlpha(.45) end)
    b:SetScript("OnEnable", function() b:SetAlpha(1) end)
    b:SetScript("OnClick", fn)
    return b
end

local function combatRate(row)
    local dps = row and row[2] > 0 and ("%.0f DPS (%d)"):format(row[1] / row[2], row[3])
    local hps = row and row[5] > 0 and ("%.0f HPS (%d)"):format(row[4] / row[5], row[6])
    return (dps or "DPS —") .. "  /  " .. (hps or "HPS —")
end

local function statsText(subject)
    local stats = S.Eligible(subject) and S.ProfileStats(subject)
    local tree, name, role, lastSeen = S.CurrentBuild(subject)
    local build = S.BuildStats(subject, tree, role)
    local rows, lifetime = {}, {}
    local roleLabel = role == "T" and "Tank" or role == "N" and "Non-tank" or "Role unknown"
    local heading = tree and ((name or ("Tree " .. tree)) .. " · " .. roleLabel
        .. (lastSeen and " (last seen)" or "")) or "Active talent tree unknown"
    local captions = {[5] = "5-player dungeon", [10] = "10-player instance",
        [20] = "20-player raid", [40] = "40-player raid"}
    for _, size in ipairs({5, 10, 20, 40}) do
        local bracket = build and build[size]
        local clears = bracket and bracket.clears or 0
        local active = combatRate(bracket and bracket.rate)
        if tree and role and clears < 3 then active = ("%d of 3 qualifying clears"):format(clears) end
        rows[#rows + 1] = captions[size] .. "\n" .. active
        local lifetimeClears = stats and stats.runs and stats.runs[size] or 0
        local lifetimeRate = stats and stats.rates and stats.rates[size]
        lifetime[#lifetime + 1] = ("Lifetime · %d completed runs\n%s"):format(lifetimeClears,
            combatRate(lifetimeRate))
    end
    local function value(key) return stats and stats[key] and tostring(stats[key]) or "—" end
    local played = stats and stats.played
    local rolls = stats and stats.rollCount
    local rollAverage = rolls and rolls > 0 and ("%.2f (%d rolls)"):format(stats.rollSum / rolls, rolls)
    local choices = stats and stats.needGreed
    local needToGreed = choices and choices.need + choices.greed > 0
        and ("%d:%d"):format(choices.need, choices.greed)
    return rows, {
        "Dungeons completed  " .. value("dungeons"),
        "Battlegrounds completed  " .. value("battlegrounds"),
        "Peak Classic GearScore  " .. value("gear"),
        "Time played  " .. (played and ("%dd %dh %dm"):format(
            math.floor(played / 86400), math.floor(played / 3600) % 24, math.floor(played / 60) % 60) or "—"),
        "Total Reviews Given  " .. value("reviewsGiven"),
        "Average Gear Roll  " .. (rollAverage or "—"),
        "Need-to-Greed  " .. (needToGreed or "—"),
        "Explicit Words  " .. value("explicitWords"),
        "Professions\n" .. (stats and stats.professions or "—"),
    }, stats and stats.stamp and ("Shared " .. date("%d %b %Y %H:%M", stats.stamp))
        or (stats and stats.groupRuns and "Group-observed clears" or "No stats shared"),
        heading, lifetime
end

local function showEditor()
    local subject = S.openSubject
    if not S.Viewable(subject) then return end
    local owner = S.db.authored[subject]
    if owner and owner ~= S.me.key then return end
    local old = (S.db.reviews[subject] or {})[S.me.key]
    if old and old.deleted then old = nil end
    frame.editor.stars = old and old.stars or nil
    frame.editor.body:SetText(old and old.text or "")
    previewRating(frame.editor, frame.editor.stars)
    frame.editor.delete:SetShown(old ~= nil)
    frame.editorShade:Show()
end

local function build()
    local f = CreateFrame("Frame", "SocialCreditSystemProfile", UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", function(self)
        self:SetScale(math.min(1, UIParent:GetWidth() / (width + 32), UIParent:GetHeight() / (height + 32)))
    end)
    f:SetScript("OnHide", function()
        S.openSubject, pendingProfile, f.returnTo = nil, nil, nil
        f.preview, f.lookupStatus = false, false
        f.editorShade:Hide()
        dismissConfirmation()
    end)
    table.insert(UISpecialFrames, f:GetName())
    surface(f, 0, 0, width, height, .09, .063, .067, -2)
    art(f, 0, 4, width, 125, "GuildHall")
    local scrim = surface(f, 0, 4, width, 125, .06, .025, .03, 1)
    scrim:SetAlpha(.38)
    surface(f, 0, 0, width, 3, .70, .43, .28, 2)
    surface(f, 0, 128, width, 1, .58, .36, .26, 2)
    art(f, 20, 144, 250, 375, "StatsSlate")
    surface(f, 286, 144, 506, 375, .16, .094, .085, -1)
    surface(f, 20, 144, 250, 2, .47, .48, .44, 1)
    surface(f, 286, 144, 506, 2, .55, .36, .25, 1)

    label(f, 132, 23, 355, "GameFontNormal", gold, "SOCIAL CREDIT SYSTEM")
    f.name = label(f, 132, 45, 410, "GameFontHighlightHuge", cream)
    f.name:SetMaxLines(1)
    f.blackMark = CreateFrame("Frame", nil, f)
    f.blackMark:SetPoint("LEFT", f.name, "LEFT", 0, 0)
    f.blackMark:SetSize(135, 20)
    f.blackMark:EnableMouseMotion(true)
    label(f.blackMark, 0, 2, 135, "GameFontHighlightSmall", cream, S.BlackMarkIcon(16) .. " Black Mark")
    f.blackMark:SetScript("OnEnter", function(self)
        local reviewers = S.BlackMarkReviewers(S.openSubject)
        if not reviewers or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Black Mark")
        for _, reviewer in ipairs(reviewers) do GameTooltip:AddLine(reviewer, 1, .94, .85) end
        GameTooltip:Show()
    end)
    f.blackMark:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    f.guild = label(f, 132, 72, 420, "GameFontHighlightSmall", muted)
    f.guild:SetMaxLines(1)
    f.score = label(f, 132, 91, 420, "GameFontHighlightLarge", gold)
    f.averageStars = S.CreateAverageStars(f, 132, 111, 13)
    f.reviewMean = label(f, 211, 111, 350, "GameFontHighlightSmall", cream)
    local scoreTip = CreateFrame("Frame", nil, f)
    scoreTip:SetPoint("TOPLEFT", 132, -90)
    scoreTip:SetSize(420, 20)
    scoreTip:EnableMouseMotion(true)
    scoreTip:SetScript("OnEnter", function(self)
        if not f.scoreDetail or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(f.scoreDetail, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scoreTip:SetScript("OnLeave", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    surface(f, 39, 31, 74, 74, .09, .055, .05, 2)
    f.portrait = f:CreateTexture(nil, "ARTWORK")
    f.portrait:SetPoint("TOPLEFT", 39, -31)
    f.portrait:SetSize(74, 74)
    f.blackPortrait = S.CreateBlackMark(f, f.portrait, 24)
    f.border = f:CreateTexture(nil, "OVERLAY")
    f.border:SetPoint("CENTER", f.portrait)
    f.border:SetSize(112, 112)
    f.activeInstance = label(f, 584, 96, 184, "GameFontHighlightSmall", cream)
    f.activeInstance:SetMaxLines(2)
    f.edit = button(f, 584, 63, 184, "Write review", showEditor)
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -3, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.back = button(f, 584, 28, 184, "Back to player history", function()
        local returnTo = f.returnTo
        f:Hide()
        if returnTo then returnTo() end
    end)
    label(f, 38, 161, 210, "GameFontHighlightLarge", cream, "Character stats")
    f.ratesHeading = label(f, 38, 186, 215, "GameFontHighlightSmall", muted)
    f.ratesHeading:SetMaxLines(1)
    f.rates, f.stats = {}, {}
    for i = 1, 4 do
        local y = 204 + (i - 1) * 31
        f.rates[i] = label(f, 38, y, 219)
        local tip = CreateFrame("Frame", nil, f)
        tip:SetPoint("TOPLEFT", 38, -y)
        tip:SetSize(219, 30)
        tip:EnableMouseMotion(true)
        tip:SetScript("OnEnter", function(self)
            if not f.lifetimeRates or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(f.lifetimeRates[i], 1, .94, .85, true)
            GameTooltip:Show()
        end)
        tip:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
    surface(f, 38, 332, 212, 1, .39, .29, .28)
    for i = 1, 9 do f.stats[i] = label(f, 38, 341 + (i - 1) * 15, 215, "GameFontHighlightSmall") end
    f.stats[9]:SetMaxLines(4)

    f.reviewHeading = label(f, 304, 165, 126, "GameFontHighlightLarge", cream, "Reviews")
    f.filters = {}
    for i, choice in ipairs({"Newest", "Negative", "Positive"}) do
        f.filters[choice] = button(f, 507 + (i - 1) * 88, 158, 83, choice, function()
            filter, page = choice, 1
            S.Refresh(S.openSubject)
        end)
    end
    f.rows = {}
    f.empty = label(f, 310, 240, 458, "GameFontHighlightLarge", muted)
    f.empty:SetJustifyH("CENTER")
    for i = 1, perPage do
        local y = 197 + (i - 1) * 91
        local hit = CreateFrame("Frame", nil, f)
        hit:SetPoint("TOPLEFT", 303, -y)
        hit:SetSize(472, 85)
        hit:EnableMouseMotion(true)
        local card = art(hit, 0, 0, 472, 85, "StatsSlate")
        card:SetVertexColor(.80, .72, .71)
        local edge = surface(hit, 0, 0, 3, 85, unpack(reviewEdge))
        edge:SetDrawLayer("BORDER")
        local name = label(hit, 12, 7, 340, "GameFontHighlight", cream)
        name:SetMaxLines(1)
        local stamp = label(hit, 12, 25, 90, "GameFontHighlightSmall", muted)
        local friend = label(hit, 108, 25, 48, "GameFontHighlightSmall", friendColor, "Friend")
        local guildmate = label(hit, 108, 25, 75, "GameFontHighlightSmall", guildColor, "Guildmate")
        local ownReview = label(hit, 108, 25, 115, "GameFontHighlightSmall", ownReviewColor)
        local body = label(hit, 12, 41, 448, "GameFontHighlightSmall", cream)
        body:SetMaxLines(3)
        local icons = S.CreateAverageStars(hit, 371, 8, 16)
        local slot = {card = hit, name = name, stamp = stamp, body = body, icons = icons,
            edge = edge, friend = friend, guildmate = guildmate, ownReview = ownReview,
            zero = label(hit, 371, 26, 94, "GameFontHighlightSmall", cream, "Zero stars")}
        hit:SetScript("OnEnter", function(self)
            if not slot.fullText or slot.fullText == "" or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(slot.fullText, 1, .94, .85, true)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        f.rows[i] = slot
    end
    f.status = label(f, 24, 536, 590, "GameFontHighlightSmall", muted)
    f.page = label(f, 684, 538, 44, "GameFontHighlightSmall", muted)
    f.page:SetJustifyH("CENTER")
    f.previous = button(f, 648, 527, 36, "<", function() page = page - 1; S.Refresh(S.openSubject) end)
    f.next = button(f, 730, 527, 36, ">", function() page = page + 1; S.Refresh(S.openSubject) end)

    local shade = CreateFrame("Frame", nil, f)
    f.editorShade = shade
    shade:SetAllPoints(f)
    shade:SetFrameLevel(f:GetFrameLevel() + 8)
    shade:EnableMouse(true)
    local closeEditorProfile = CreateFrame("Button", nil, shade, "UIPanelCloseButton")
    closeEditorProfile:SetPoint("TOPRIGHT", -3, -4)
    closeEditorProfile:SetScript("OnClick", function() f:Hide() end)
    surface(shade, 0, 0, width, height, 0, 0, 0):SetAlpha(.68)
    local editor = CreateFrame("Frame", nil, shade)
    f.editor = editor
    editor:SetFrameLevel(f:GetFrameLevel() + 10)
    editor:SetSize(494, 255)
    editor:SetPoint("CENTER")
    editor:EnableMouse(true)
    surface(editor, 0, 0, 494, 255, .23, .12, .14)
    surface(editor, 0, 0, 494, 2, .72, .48, .32)
    label(editor, 20, 17, 430, "GameFontHighlightLarge", cream, "Your review")
    local starsX = 162
    art(editor, starsX, 41, 222, 36, "StatsSlate")
    editor.icons = S.CreateAverageStars(editor, starsX + 7, 45, 28, 45)
    editor.rating = label(editor, 397, 54, 77, "GameFontHighlight", gold)
    editor.zero = button(editor, 20, 46, 130, "0 stars · Black Mark", function()
        editor.stars = 0
        previewRating(editor, 0)
    end)
    for half = 1, 10 do
        local rating = half / 2
        local star = math.floor((half - 1) / 2)
        local side = (half - 1) % 2
        local choice = CreateFrame("Button", nil, editor)
        choice:SetSize(21, 36)
        choice:SetPoint("TOPLEFT", starsX + star * 45 + side * 21, -41)
        choice:SetScript("OnEnter", function() previewRating(editor, rating) end)
        choice:SetScript("OnLeave", function() previewRating(editor, editor.stars) end)
        choice:SetScript("OnClick", function()
            editor.stars = rating
            previewRating(editor, rating)
        end)
    end
    label(editor, 20, 84, 435, "GameFontHighlightSmall", muted, "Optional comment, up to 240 characters")
    surface(editor, 20, 106, 454, 77, .10, .065, .073)
    local scroller = CreateFrame("ScrollFrame", nil, editor)
    scroller:SetPoint("TOPLEFT", 26, -111)
    scroller:SetSize(442, 66)
    scroller:EnableMouse(true)
    scroller:SetScript("OnMouseDown", function() editor.body:SetFocus() end)
    local body = CreateFrame("EditBox", nil, scroller)
    editor.body = body
    body:SetMultiLine(true)
    body:SetAutoFocus(false)
    body:SetFontObject(GameFontHighlight)
    body:SetSize(442, 66)
    body:SetTextInsets(4, 4, 3, 3)
    body:SetMaxBytes(960)
    body:SetScript("OnEscapePressed", function() f:Hide() end)
    body:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
        local caret = -y
        local scroll = scroller:GetVerticalScroll()
        if caret < scroll then scroller:SetVerticalScroll(caret)
        elseif caret + lineHeight > scroll + 66 then scroller:SetVerticalScroll(caret + lineHeight - 66) end
    end)
    scroller:SetScrollChild(body)
    editor.message = label(editor, 20, 189, 451, "GameFontHighlightSmall", gold)
    shade:SetScript("OnHide", function()
        dismissConfirmation()
        body:ClearFocus()
        editor.message:SetText("")
    end)
    local function save(subject, stars, comment)
        if S.SaveReview(subject, stars, comment) then shade:Hide()
        else editor.message:SetText("Review could not be saved.") end
    end
    if StaticPopupDialogs then
        StaticPopupDialogs[confirmation] = {
            text = "Apply a Black Mark to %s?\n\nThis zero-star review counts toward their score. You and your current guildmates will see a black mark on this player.",
            button1 = "Apply Black Mark", button2 = "Cancel",
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, draft)
                if not draft or S.openSubject ~= draft.subject or not shade:IsVisible() then return end
                local latest = (S.db.reviews[draft.subject] or {})[S.me.key]
                if (latest and latest.revision) == draft.revision then save(draft.subject, 0, draft.comment)
                else editor.message:SetText("The review changed. Reopen the editor before saving.") end
            end,
        }
        StaticPopupDialogs[confirmDelete] = {
            text = "Delete your review of %s?",
            button1 = "Delete review", button2 = "Cancel",
            timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function(_, draft)
                if not draft or S.openSubject ~= draft.subject or not shade:IsVisible() then return end
                if S.DeleteReview(draft.subject, draft.revision) then shade:Hide()
                else editor.message:SetText("The review changed. Reopen the editor before deleting.") end
            end,
        }
    end
    editor.delete = button(editor, 20, 213, 115, "Delete review", function()
        local subject = S.openSubject
        local old = (S.db.reviews[subject] or {})[S.me.key]
        if not old or old.deleted or S.db.authored[subject] ~= S.me.key then return end
        body:ClearFocus()
        if not StaticPopup_Show or not StaticPopup_Show(confirmDelete, S.db.names[subject], nil,
            {subject = subject, revision = old.revision}) then
            editor.message:SetText("Close the active dialog and try again.")
        end
    end)
    button(editor, 262, 213, 94, "Cancel", function() shade:Hide() end)
    editor.save = button(editor, 363, 213, 111, "Save review", function()
        if not editor.stars then editor.message:SetText("Choose a rating."); return end
        local comment = body:GetText():gsub("[%c]", " "):match("^%s*(.-)%s*$")
        if not S.ValidText(comment) then
            editor.message:SetText("Use up to 240 characters of plain text.")
            return
        end
        local subject = S.openSubject
        local old = (S.db.reviews[subject] or {})[S.me.key]
        if editor.stars == 0 and (not old or old.stars ~= 0) then
            body:ClearFocus()
            if not StaticPopup_Show or not StaticPopup_Show(confirmation, S.db.names[subject], nil,
                {subject = subject, revision = old and old.revision, comment = comment}) then
                editor.message:SetText("Close the active dialog and try again.")
            end
            return
        end
        save(subject, editor.stars, comment)
    end)
    shade:Hide()
    f:Hide()
    return f
end

function S.PaintProfilePortrait(texture, unit, class)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetTexture(media .. "Crest")
    if unit and SetPortraitTexture then
        if pcall(SetPortraitTexture, texture, unit) then
            texture:SetTexCoord(.17, .83, .17, .83)
            return
        end
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        texture:SetTexCoord(unpack(coords))
    end
end

function S.PaintProfileBorder(texture, tier)
    texture:SetTexture(media .. tier)
    local shade = tier == "Neutral" and .57 or 1
    texture:SetVertexColor(shade, shade, shade)
end

function S.Refresh(subject)
    if not S.me or not frame or not subject or subject ~= S.openSubject then return end
    local selfProfile = subject == S.me.key
    if S.db.alts[subject] and not selfProfile then return end
    local verified = S.Viewable(subject)
    if not verified and not frame.preview then frame:Hide(); return end
    local rows, count, average, score, provisional, population, reviewers, brackets, review, combat
    local eligible = S.Eligible(subject)
    if selfProfile then
        rows = {}
    else
        rows = S.Reviews(subject, filter)
        count, average, score, provisional, population, reviewers, brackets, review, combat = S.RatingSummary(subject)
        if not eligible then count = S.ReviewAverage(subject) end
    end
    local tier = S.Tier(score)
    local profile = S.db.profiles[subject] or {}
    local marked = not selfProfile and verified and S.BlackMarkReviewers(subject) ~= nil
    frame.name:SetWidth(marked and 315 or 410)
    frame.blackMark:ClearAllPoints()
    frame.blackMark:SetPoint("LEFT", frame.name, "LEFT", math.min(frame.name:GetStringWidth(), 315) + 8, 0)
    frame.blackMark:SetShown(marked)
    frame.blackPortrait:SetShown(marked)
    frame.guild:SetText(profile.guild == "" and "Unguilded" or profile.guild or "")
    frame.score:SetText(selfProfile and "Your character" or not verified and "Same-faction profile unverified"
        or not profile.level and "Level unknown"
        or not eligible and "SCS unlocks at level 60" or score and ("%.2f SCS  ·  %s%s"):format(score, tier, provisional and "  ·  Provisional" or "")
        or (average and "Class comparison unavailable"
            or "Social Credit Score —"))
    S.PaintAverageStars(frame.averageStars, average, 13)
    frame.reviewMean:SetPoint("TOPLEFT", average and 211 or 132, -111)
    frame.reviewMean:SetText(selfProfile and "" or eligible and S.AverageCaption(count, average)
        or ("%d %s"):format(count, count == 1 and "review" or "reviews"))
    frame.scoreDetail = score and ("%s comparison · %d known characters\n%d qualifying review averages · %d combat brackets\nReviews %.2f × 75%% · Combat %.2f × 25%%%s")
        :format(profile.class, population, reviewers, brackets, review, combat,
            provisional and "\nSparse reviews use the star scale. Unmatched combat uses 500." or "") or nil
    S.PaintProfileBorder(frame.border, tier)
    local owner = S.db.authored[subject]
    local owns = not owner or owner == S.me.key
    frame.edit:SetShown(not selfProfile)
    frame.edit:SetEnabled(not selfProfile and verified and owns)
    local ownRecord = (S.db.reviews[subject] or {})[S.me.key]
    local editing = ownRecord and not ownRecord.deleted
    frame.edit.caption:SetText(not verified and "Review unavailable" or owner and (owns and (editing and "Edit review" or "Write review")
        or "Review slot on " .. (select(2, S.Identity(owner)) or owner))
        or "Write review")
    frame.reviewHeading:SetShown(not selfProfile)
    for choice, b in pairs(frame.filters) do
        b:SetShown(not selfProfile)
        local selected = choice == filter
        b.caption:SetTextColor(unpack(selected and gold or muted))
        local color = selected and gold or inactive
        b.edge:SetColorTexture(color[1], color[2], color[3], 1)
    end
    local pages = math.max(1, math.ceil(#rows / perPage))
    page = math.max(1, math.min(pages, page))
    frame.page:SetText(page .. " / " .. pages)
    frame.page:SetShown(not selfProfile)
    frame.previous:SetShown(not selfProfile)
    frame.next:SetShown(not selfProfile)
    frame.previous:SetEnabled(page > 1)
    frame.next:SetEnabled(page < pages)
    frame.empty:SetText(selfProfile and "Personal combat and character stats" or #rows == 0 and ("No " .. (filter == "Newest" and "" or filter:lower() .. " ") .. "reviews") or "")
    local friends, guildmates = S.ReviewRelationships()
    for i, slot in ipairs(frame.rows) do
        local row = rows[(page - 1) * perPage + i]
        local ownReview = row ~= nil and (row.author == S.me.key or S.db.alts[row.author] == true)
        local friend = row ~= nil and not ownReview and friends[row.author] == true
        local guildmate = row ~= nil and not ownReview and guildmates[row.author] == true
        slot.ownReview:SetShown(ownReview)
        if ownReview then
            slot.ownReview:SetText(row.author == S.me.key and "Your review" or "Your alt's review")
        end
        slot.friend:SetShown(friend)
        slot.guildmate:SetShown(guildmate)
        local color = ownReview and ownReviewColor or friend and friendColor or guildmate and guildColor or reviewEdge
        slot.edge:SetColorTexture(color[1], color[2], color[3], 1)
        slot.edge:SetWidth((ownReview or friend or guildmate) and 3 or 2)
        if guildmate then slot.guildmate:SetPoint("TOPLEFT", friend and 156 or 108, -25) end
        slot.fullText = row and row.text
        slot.card:SetShown(row ~= nil)
        slot.zero:SetShown(row ~= nil and row.stars == 0)
        if row then
            slot.name:SetText(row.name)
            slot.stamp:SetText(date("%d %b %Y", row.time))
            slot.body:SetText(row.text ~= "" and row.text or "Rating only")
            S.PaintAverageStars(slot.icons, row.stars, 16)
        elseif selfProfile then
            slot.name:SetText("")
            slot.stamp:SetText("")
            slot.body:SetText("")
            S.PaintAverageStars(slot.icons, nil, 16)
            if GameTooltip and GameTooltip:IsOwned(slot.card) then GameTooltip:Hide() end
        end
    end
    local instanceName, instanceRates
    if subject == S.me.key then instanceName, instanceRates = S.ActiveInstance() end
    frame.activeInstance:SetText(instanceName and (instanceName .. "\n" ..
        (instanceRates and (instanceRates[3] + instanceRates[6] > 0) and combatRate(instanceRates)
            or "Waiting for meter data")) or "")
    local rates, stats, shared, ratesHeading, lifetime = statsText(subject)
    frame.lifetimeRates = lifetime
    frame.ratesHeading:SetText(ratesHeading)
    for i, line in ipairs(rates) do frame.rates[i]:SetText(line) end
    for i, line in ipairs(stats) do frame.stats[i]:SetText(line) end
    local last = S.db.synced[subject]
    frame.status:SetText(selfProfile and "Counts since tracking began"
        or frame.preview and (frame.lookupStatus or "Checking profile...") or shared .. "  ·  Counts since tracking began  ·  "
        .. (last and "Synced " .. date("%d %b %H:%M", last) or "Local review data"))
end

local function open(key, unit, returnTo, preview)
    if not S.me or (not preview and not S.Viewable(key)) then
        print("Social Credit System: available for known same-faction characters.")
        return
    end
    local selfProfile = key == S.me.key
    if S.db.alts[key] and not selfProfile then print("Social Credit System: your own profiles are private."); return end
    if selfProfile then unit = "player" end
    if not frame then frame = build() end
    pendingProfile = nil
    dismissConfirmation()
    frame.editorShade:Hide()
    if selfProfile and GameTooltip then GameTooltip:Hide() end
    frame.returnTo = returnTo
    frame.preview, frame.lookupStatus = preview or false, false
    frame.back:SetShown(returnTo ~= nil)
    if returnTo and S.HidePlayerHistory then S.HidePlayerHistory() end
    filter, page, S.openSubject = "Newest", 1, key
    frame.name:SetText(S.db.names[key] or preview)
    local id = unit and S.Unit(unit)
    local profile = S.db.profiles[key]
    S.PaintProfilePortrait(frame.portrait, id and id.key == key and unit, profile and profile.class)
    frame:Show()
    S.Refresh(key)
    if not preview and not selfProfile then
        S.RequestReviewGuildRoster()
        S.Query(key)
    end
end

local function inspect(unit)
    local id = S.me and S.Unit(unit)
    if not id then return end
    if not id.level or id.level < 1 or id.level > 60 then id.level = nil end
    S.Remember(id)
    return S.Viewable(id.key) and id or nil
end

local function findUnit(key, preferred)
    local function matches(unit)
        if not S.Readable(unit) or type(unit) ~= "string" then return end
        local id = S.Unit(unit)
        if id and id.key == key then
            inspect(unit)
            return unit
        end
    end
    local unit = matches(preferred) or matches("target") or matches("focus") or matches("mouseover")
    if unit then return unit end
    local raid = S.Call(IsInRaid)
    for index = 1, S.Call(raid and GetNumGroupMembers or GetNumSubgroupMembers) or 0 do
        unit = matches((raid and "raid" or "party") .. index)
        if unit then return unit end
    end
    local plates = C_NamePlate and S.Call(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
        for _, plate in ipairs(plates) do
            if S.Readable(plate) then
                unit = matches(plate.namePlateUnitToken)
                if unit then return unit end
            end
        end
    end
end

local function showLookupStatus(request, message)
    if request.preview and frame and frame.preview and S.openSubject == request.key then
        frame.lookupStatus = message
        S.Refresh(request.key)
    elseif request.returnTo and S.SetPlayerHistoryStatus then
        S.SetPlayerHistoryStatus(message)
    else
        print("Social Credit System: " .. message)
    end
end

function S.ProfileLookupOffline(key)
    if pendingProfile and pendingProfile.key == key and (pendingProfile.preview or pendingProfile.returnTo) then
        local message = pendingProfile.preview and ("Run /who " .. frame.preview .. " to verify this profile.")
            or "Player is offline. Checking synced profiles."
        showLookupStatus(pendingProfile, message)
    end
end

function S.CancelHistoryProfileLookup()
    if pendingProfile and pendingProfile.returnTo then pendingProfile = nil end
end

function S.OpenDiscoveredProfile(subject)
    if not S.Viewable(subject) then return end
    if frame and frame.preview and S.openSubject == subject then
        open(subject, findUnit(subject))
    elseif pendingProfile and subject == pendingProfile.key and GetTime() <= pendingProfile.expires then
        open(subject, nil, pendingProfile.returnTo)
    end
end

function S.OpenNamedProfile(name, returnTo, fromChat, chatUnit)
    pendingProfile = nil
    local key, display = S.Identity(name)
    if not S.me or not key or S.db.alts[key] then open(key, nil, returnTo); return end
    local unit = (fromChat or not S.Viewable(key)) and findUnit(key, chatUnit)
    if not unit and (not S.Viewable(key) or not S.db.profiles[key].level) then
        local who = S.FindWhoProfile(key)
        if who then S.Remember(who) end
    end
    if unit or S.db.profiles[key] then open(key, unit, returnTo); return end
    if fromChat then open(key, nil, returnTo, display) end
    local request = {key = key, expires = GetTime() + 90, returnTo = returnTo, preview = fromChat}
    pendingProfile = request
    local whoRequested = fromChat and S.RequestWhoProfile(key, display)
    if pendingProfile ~= request then return end
    local status = S.FindProfile(name)
    if fromChat then
        local hint = "Run /who " .. display .. " to verify manually."
        showLookupStatus(request, whoRequested and ("Checking /who. " .. hint) or hint)
    else
        showLookupStatus(request, status or "Checking synced profiles.")
    end
    C_Timer.After(90, function()
        if pendingProfile == request then
            pendingProfile = nil
            local message = fromChat and ("Run /who " .. display .. " to verify this profile.")
                or ("Could not verify a same-faction profile for " .. display .. ".")
            showLookupStatus(request, message)
        end
    end)
end

S.On("PLAYER_TARGET_CHANGED", function()
    if not frame or not frame.preview or not S.openSubject then return end
    local id = S.Unit("target")
    if id and id.key == S.openSubject then
        inspect("target")
        open(id.key, "target")
    end
end)

SLASH_SOCIALCREDITSYSTEM1 = "/scs"
SlashCmdList.SOCIALCREDITSYSTEM = function(input)
    pendingProfile = nil
    if S.me and input:lower():match("^%s*self%s*$") then
        open(S.me.key, "player")
    elseif input:match("^%s*$") then
        local id = inspect("target")
        open(id and id.key, "target")
    else S.OpenNamedProfile(input) end
end

S.On("PLAYER_LOGIN", function()
    if not Menu or not Menu.ModifyMenu then return end
    for _, tag in ipairs({"MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE"}) do
        Menu.ModifyMenu(tag, function(_, root, context)
            if not S.me or not context or not context.chatFrame then return end
            local key = S.Identity(context.name)
            if not key or S.db.alts[key] or (S.db.profiles[key] and not S.Viewable(key)) then return end
            local name, unit = context.name, context.unit
            root:CreateDivider()
            root:CreateButton("Open SCS", function() S.OpenNamedProfile(name, nil, true, unit) end)
        end)
    end
    for _, kind in ipairs({"PLAYER", "TARGET", "FOCUS", "PARTY", "RAID_PLAYER", "RAID"}) do
        Menu.ModifyMenu("MENU_UNIT_" .. kind, function(_, root, context)
            local unit = context and context.unit
            local id = unit and inspect(unit)
            if id and not S.db.alts[id.key] then
                root:CreateDivider()
                root:CreateButton("Social Credit", function() open(id.key, unit) end)
            end
        end)
    end
end)
