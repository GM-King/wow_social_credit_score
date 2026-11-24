local addon, S = ...
local media = "Interface\\AddOns\\" .. addon .. "\\Media\\BlackMark"
local marks, overlays = {}, {}
local queued, active, refreshBadges

function S.BlackMarkIcon(size)
    return ("|T%s:%d:%d|t"):format(media, size, size)
end

function S.BlackMarkReviewers(key)
    if not S.me or not key or S.db.alts[key] then return end
    local reviews = S.db.reviews[key]
    if not reviews then return end
    if marks[key] == nil then
        local reviewers = {}
        if not S.db.profiles[key] or S.Eligible(key) then
            local _, guildmates = S.ReviewRelationships()
            for author, record in pairs(reviews) do
                if record.stars == 0 and (S.db.alts[author] or guildmates[author]) then
                    reviewers[#reviewers + 1] = author == S.me.key and "Your review"
                        or S.db.alts[author] and ("Your alt · " .. record.name) or record.name
                end
            end
        end
        table.sort(reviewers)
        marks[key] = #reviewers > 0 and reviewers or false
    end
    return marks[key] or nil
end

function S.CreateBlackMark(parent, anchor, size)
    local mark = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    mark:SetTexture(media)
    mark:SetSize(size, size)
    mark:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
    mark:Hide()
    return mark
end

local function updatePortrait(owner, anchor, unit)
    if not owner or not anchor then return end
    local overlay = overlays[anchor]
    if not overlay then
        if InCombatLockdown() and S.Call(owner.IsProtected, owner) ~= false then return end
        overlay = CreateFrame("Frame", nil, UIParent)
        overlay:SetFrameStrata("HIGH")
        overlay:SetSize(18, 18)
        overlay:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
        local texture = overlay:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetTexture(media)
        overlays[anchor] = overlay
        owner:HookScript("OnHide", function() overlay:Hide() end)
        owner:HookScript("OnShow", function() S.QueueBlackMarkPortraits() end)
        if anchor ~= owner and anchor.HookScript then
            anchor:HookScript("OnHide", function() overlay:Hide() end)
            anchor:HookScript("OnShow", function() S.QueueBlackMarkPortraits() end)
        end
    end
    local visible = owner:IsVisible() and anchor:IsVisible()
    local id = visible and S.Readable(unit) and S.Unit(unit)
    overlay:SetShown(id and id.level == 60 and S.BlackMarkReviewers(id.key) ~= nil or false)
end

local function refreshPortraits()
    for _, unit in ipairs({"target", "focus"}) do
        local suffix = unit == "target" and "Target" or "Focus"
        local owner = _G[suffix .. "Frame"]
        local container = owner and owner.TargetFrameContainer
        updatePortrait(owner, container and container.Portrait or owner and (owner.portrait or owner.Portrait), unit)
        local xperl = _G["XPerl_" .. suffix]
        updatePortrait(xperl, xperl and xperl.portraitFrame, unit)
    end
    for index = 1, 4 do
        local unit = "party" .. index
        local owner = PartyFrame and S.Call(PartyFrame.GetPartyMemberFrame, PartyFrame, index)
            or _G["PartyMemberFrame" .. index]
        updatePortrait(owner, owner and (owner.Portrait or owner.portrait), owner and owner.unit or unit)
        local xperl = S.Call(XPerl_Party_GetUnitFrameByUnit, unit)
        updatePortrait(xperl, xperl and xperl.portraitFrame, unit)
    end
end

function S.QueueBlackMarkPortraits()
    if not active or queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = nil
        refreshPortraits()
        if refreshBadges then
            refreshBadges = nil
            if S.openSubject and S.Refresh then S.Refresh(S.openSubject) end
            if S.QueueGroupFinderRefresh then S.QueueGroupFinderRefresh() end
        end
    end)
end

function S.BlackMarksChanged(key)
    if key then marks[key] = nil else marks = {} end
    refreshBadges = true
    S.QueueBlackMarkPortraits()
end

local chatEvents = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true, CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
}
local chatMark = S.BlackMarkIcon(13) .. " "

local function markedSender(event, sender, guid)
    if not S.Readable(event) or not chatEvents[event] then return end
    local playerGUID = S.Readable(guid) and type(guid) == "string" and guid ~= "" and guid
    if playerGUID and not playerGUID:match("^Player%-") then return end
    local key = S.Identity(sender)
    if not key and playerGUID and S.Readable(sender) then
        local _, _, _, _, _, name, realm = S.Call(GetPlayerInfoByGUID, playerGUID)
        key = S.Identity(name)
        if not key and type(name) == "string" and type(realm) == "string" and realm ~= "" then
            key = S.Identity(name .. "-" .. realm)
        end
    end
    return S.BlackMarkReviewers(key)
end

local function markSender(event, decoratedName, _, sender, ...)
    if not S.Readable(decoratedName) or type(decoratedName) ~= "string" or decoratedName == ""
        or decoratedName:find(chatMark, 1, true)
        or not markedSender(event, sender, select(10, ...)) then return end
    return chatMark .. decoratedName
end

local pratAttached
local function attachPrat()
    if not active or pratAttached or not Prat or not Prat.RegisterChatEvent or not Prat.RegisterMessageItem then return end
    pratAttached = {}
    Prat.RegisterMessageItem("SCSBLACKMARK", "pP", "before")
    Prat.RegisterChatEvent(pratAttached, "Prat_PreAddMessage", function(_, message, _, event)
        message.SCSBLACKMARK = nil
        local player = message.PLAYER
        local args = message.ARGS
        if not S.Readable(player) or type(player) ~= "string" or player == "" or player:find(chatMark, 1, true)
            or not S.Readable(args) or type(args) ~= "table" then return end
        if markedSender(event, args[2], args[12]) then message.SCSBLACKMARK = chatMark end
    end)
end

for _, event in ipairs({"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
    "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD"}) do
    S.On(event, S.QueueBlackMarkPortraits)
end
S.On("ADDON_LOADED", function(name)
    if name == "Prat-3.0" then attachPrat()
    elseif name == "Blizzard_UnitFrame" or name == "ZPerl_Target" or name == "ZPerl_Party" then
        S.QueueBlackMarkPortraits()
    end
end)
S.OnActive(function()
    active = true
    if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then ChatFrameUtil.AddSenderNameFilter(markSender) end
    attachPrat()
    S.QueueBlackMarkPortraits()
end)
