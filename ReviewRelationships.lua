local _, S = ...
local friends, guildmates
local queued, lastGuildRequest

local function remember(set, name)
    local key = S.Identity(name)
    if key then set[key] = true end
end

local function readFriends()
    local result = {}
    local list = C_FriendList
    if list then
        for index = 1, S.Call(list.GetNumFriends) or 0 do
            local info = S.Call(list.GetFriendInfoByIndex, index)
            if info then remember(result, info.name) end
        end
    end

    local net, project = C_BattleNet, WOW_PROJECT_CAMELOT
    if not net or not project then return result end
    for index = 1, S.Call(BNGetNumFriends) or 0 do
        for account = 1, S.Call(net.GetFriendNumGameAccounts, index) or 0 do
            local info = S.Call(net.GetFriendGameAccountInfo, index, account)
            if info and S.Readable(info.wowProjectID) and info.wowProjectID == project
                and S.Readable(info.isOnline) and info.isOnline
                and S.Readable(info.isInCurrentRegion) and info.isInCurrentRegion then
                local name, realm = info.characterName, info.realmName
                if S.Readable(name) and type(name) == "string" then
                    local base, suffix = name:match("^(.-)%-([^%-]+)$")
                    if suffix and S.Readable(realm) and type(realm) == "string"
                        and suffix:lower():gsub("%s", "") == realm:lower():gsub("%s", "") then
                        name = base
                    end
                    remember(result, name)
                end
            end
        end
    end
    return result
end

local function readGuild()
    local result = {}
    if not S.Call(IsInGuild) then return result end
    local club = C_Club
    local guildID = club and S.Call(club.GetGuildClubId)
    local members = guildID and S.Call(club.GetClubMembers, guildID)
    if type(members) == "table" then
        for _, id in ipairs(members) do
            if S.Readable(id) then
                local info = S.Call(club.GetMemberInfo, guildID, id)
                if info then remember(result, info.name) end
            end
        end
        if next(result) then return result end
    end
    for index = 1, S.Call(GetNumGuildMembers) or 0 do
        remember(result, S.Call(GetGuildRosterInfo, index))
    end
    return result
end

function S.ReviewRelationships()
    if not friends then friends = readFriends() end
    if not guildmates then guildmates = readGuild() end
    return friends, guildmates
end

local function queueRefresh()
    if queued or not S.openSubject then return end
    queued = true
    C_Timer.After(.1, function()
        queued = nil
        if S.openSubject then S.Refresh(S.openSubject) end
    end)
end

function S.RequestReviewGuildRoster()
    if not S.Call(IsInGuild) or (lastGuildRequest and GetTime() - lastGuildRequest < 30) then return end
    lastGuildRequest = GetTime()
    S.Call(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster)
end

for _, event in ipairs({"FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
    "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED",
    "LEGACY_FRIEND_SYSTEM_STATUS_UPDATED", "SOCIAL_UI_SYSTEM_STATUS_UPDATED"}) do
    S.On(event, function()
        friends = nil
        queueRefresh()
    end)
end

local function guildChanged()
    guildmates = nil
    if S.BlackMarksChanged then S.BlackMarksChanged() end
    queueRefresh()
end

S.On("GUILD_ROSTER_UPDATE", guildChanged)
S.On("INITIAL_CLUBS_LOADED", guildChanged)
for _, event in ipairs({"CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED", "CLUB_MEMBER_UPDATED",
    "CLUB_MEMBERS_UPDATED"}) do
    S.On(event, function(id)
        if S.Readable(id) and id and id == S.Call(C_Club and C_Club.GetGuildClubId) then guildChanged() end
    end)
end

S.On("PLAYER_GUILD_UPDATE", function(unit)
    if S.Readable(unit) and unit and unit ~= "player" then return end
    lastGuildRequest = nil
    S.RequestReviewGuildRoster()
    guildChanged()
end)

S.OnActive(S.RequestReviewGuildRoster)
