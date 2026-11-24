local addon, S = ...
S.events = {}
local events = CreateFrame("Frame")

function S.Readable(value)
    return not issecretvalue or not issecretvalue(value)
end

function S.Call(fn, ...)
    if not fn then return end
    local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...)
    if ok and S.Readable(a) and S.Readable(b) and S.Readable(c)
        and S.Readable(d) and S.Readable(e) and S.Readable(f)
        and S.Readable(g) and S.Readable(h) and S.Readable(i) then
        return a, b, c, d, e, f, g, h, i
    end
end

function S.On(event, fn)
    if not S.events[event] then
        if not pcall(events.RegisterEvent, events, event) then return end
        S.events[event] = {}
    end
    table.insert(S.events[event], fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    for _, handler in ipairs(S.events[event]) do handler(...) end
end)

function S.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = S.Copy(entry) end
    return copy
end

function S.Identity(name)
    if not S.Readable(name) or type(name) ~= "string" or #name > 110
        or name:find("[%c|~%d]") then return end
    name = name:match("^%s*(.-)%s*$")
    local realm = S.Call(GetNormalizedRealmName)
    local base, suffix = name:match("^(.-)%-([^%-]+)$")
    if realm and base and suffix:lower() == realm:lower() then name = base end
    local first, last = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if not first then return end
    return (first .. "-" .. last):lower(), first .. " " .. last, first .. "-" .. last
end

function S.Unit(unit, anyFaction)
    if not S.Call(UnitIsPlayer, unit) then return end
    local faction = S.Call(UnitFactionGroup, unit)
    if not faction or (not anyFaction and faction ~= S.faction) then return end
    local name, second = S.Call(UnitFullName, unit)
    local normalName, normalSecond = S.Call(UnitName, unit)
    local key, display, address
    if type(name) == "string" and type(second) == "string" and second ~= "" then
        key, display, address = S.Identity(name .. "-" .. second)
    end
    if not key then key, display, address = S.Identity(name) end
    if not key and type(normalName) == "string" and type(normalSecond) == "string" and normalSecond ~= "" then
        key, display, address = S.Identity(normalName .. "-" .. normalSecond)
    end
    if not key then key, display, address = S.Identity(normalName) end
    if key then
        local _, class = S.Call(UnitClass, unit)
        local guild = S.Call(GetGuildInfo, unit)
        if not guild and S.Call(UnitIsInMyGuild, unit) then guild = S.Call(GetGuildInfo, "player") end
        if not guild and S.Call(IsInGuild) == false and unit == "player" then guild = "" end
        if not guild and S.Call(UnitIsInGuild, unit) == false then guild = "" end
        return {key = key, name = display, address = address, level = S.Call(UnitLevel, unit),
            class = class, faction = faction, guild = guild}
    end
end

function S.ValidText(text)
    if type(text) ~= "string" or #text > 960 or text:find("[%c|]") then return false end
    local offset, count = 1, 0
    while offset <= #text do
        local lead = text:byte(offset)
        local width = lead < 128 and 1 or lead >= 194 and lead <= 223 and 2
            or lead >= 224 and lead <= 239 and 3 or lead >= 240 and lead <= 244 and 4
        if not width or offset + width - 1 > #text then return false end
        for index = offset + 1, offset + width - 1 do
            local byte = text:byte(index)
            if byte < 128 or byte > 191 then return false end
        end
        local second = text:byte(offset + 1)
        if (lead == 224 and second < 160) or (lead == 237 and second >= 160)
            or (lead == 240 and second < 144) or (lead == 244 and second >= 144) then return false end
        offset, count = offset + width, count + 1
        if count > 240 then return false end
    end
    return true, count
end

function S.Now()
    return GetServerTime()
end

local function validReviewContent(record)
    if record.deleted == true then return record.stars == nil and record.text == nil end
    return record.deleted == nil and type(record.stars) == "number" and record.stars >= 0 and record.stars <= 5
        and (record.stars * 2) % 1 == 0 and S.ValidText(record.text)
end

function S.ValidRecord(record)
    if type(record) ~= "table" then return false end
    return S.Identity(record.author) == record.author and record.author ~= nil
        and S.Identity(record.subject) == record.subject and record.subject ~= nil
        and record.author ~= record.subject
        and S.Identity(record.name) == record.author and S.Identity(record.subjectName) == record.subject
        and validReviewContent(record) and type(record.revision) == "number"
        and record.revision % 1 == 0 and record.revision >= 1 and record.revision <= S.Now() + 86400
        and type(record.time) == "number" and record.time > 0 and record.time <= S.Now() + 300
end

function S.Fingerprint(record)
    return table.concat({record.subject, record.author, record.revision, record.time,
        record.deleted and "-" or record.stars, record.text or ""}, "~")
end

function S.Merge(record, direct)
    if not S.ValidRecord(record) or S.db.alts[record.subject] then return end
    if record.stars == 0 and S.db.alts[record.author] then
        S.db.zeroSubjects[record.subject] = true
    end
    local rows = S.db.reviews[record.subject]
    if not rows then rows = {}; S.db.reviews[record.subject] = rows end
    local old = rows[record.author]
    if old and old.revision > record.revision then return end
    if old and old.revision == record.revision then
        local previous, candidate = S.Fingerprint(old), S.Fingerprint(record)
        if previous == candidate then
            old.direct = old.direct or direct == true
            return old
        end
        if (old.direct and not direct) or (old.direct == (direct == true)
            and (old.deleted and not record.deleted or old.deleted == record.deleted and previous < candidate)) then return end
    end
    record = S.Copy(record)
    record.direct = direct == true
    rows[record.author] = record
    if S.BlackMarksChanged then S.BlackMarksChanged(record.subject) end
    if S.InvalidateScores then S.InvalidateScores() end
    S.db.names[record.subject] = record.subjectName
    if S.db.alts[record.author] and not S.db.authored[record.subject] then
        S.db.authored[record.subject] = record.author
    end
    if S.Refresh then S.Refresh(S.openSubject) end
    if S.RefreshPlayerHistory and S.me and record.author == S.me.key then S.RefreshPlayerHistory() end
    return record
end

function S.ReviewAverage(key)
    local count, total = 0, 0
    if not key or S.db.alts[key] then return count end
    for _, record in pairs(S.db.reviews[key] or {}) do
        if not record.deleted then count, total = count + 1, total + record.stars end
    end
    return count, count >= 5 and total / count or nil
end

function S.Reviews(key, filter)
    local list = {}
    if S.db.alts[key] then return list, 0 end
    for _, record in pairs(S.db.reviews[key] or {}) do
        if not record.deleted and (not filter or filter == "Newest" or (filter == "Negative" and record.stars < 3)
            or (filter == "Positive" and record.stars > 3)) then table.insert(list, record) end
    end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        if a.revision ~= b.revision then return a.revision > b.revision end
        return a.author < b.author
    end)
    return list, S.ReviewAverage(key)
end

function S.Tier(score)
    if not score then return "Neutral" end
    if score >= 850 then return "Laurel" end
    if score >= 650 then return "Gold" end
    if score >= 450 then return "Silver" end
    if score >= 250 then return "Bronze" end
    return "Iron"
end

function S.Viewable(key)
    local profile = key and S.db and S.db.profiles[key]
    return profile and profile.faction == S.faction and (profile.level == nil
        or (type(profile.level) == "number" and profile.level >= 1 and profile.level <= 60))
end

function S.Eligible(key)
    local profile = key and S.db and S.db.profiles[key]
    return profile and profile.level == 60 and profile.faction == S.faction
end

function S.Remember(profile)
    local old = S.db.profiles[profile.key]
    if old and profile.guild == nil then profile.guild = old.guild end
    if old and old.faction == profile.faction then
        if profile.level == nil then profile.level = old.level end
        if profile.class == nil then profile.class = old.class end
    end
    S.db.profiles[profile.key] = profile
    S.db.names[profile.key] = profile.name
    if S.BlackMarksChanged and (not old or old.level ~= profile.level or old.faction ~= profile.faction) then
        S.BlackMarksChanged(profile.key)
    end
    if S.InvalidateScores and (not old or old.class ~= profile.class or old.level ~= profile.level
        or old.faction ~= profile.faction) then S.InvalidateScores() end
end

local function saveReview(subject, stars, body, deleting, expectedRevision)
    if not S.me or not S.Viewable(subject) or S.db.alts[subject] then return end
    local author = S.db.authored[subject]
    if author and author ~= S.me.key then return end
    local old = (S.db.reviews[subject] or {})[S.me.key]
    if deleting and (not old or old.deleted or old.revision ~= expectedRevision) then return end
    local now = S.Now()
    -- Keep the legacy record field for older versions that read the same SavedVariables.
    local record = S.Merge({subject = subject, subjectName = S.db.names[subject],
        author = S.me.key, name = S.me.name, stars = stars, text = body, time = now, level60 = true, deleted = deleting,
        revision = math.max(now, old and old.revision + 1 or 1)}, true)
    if record then S.Publish(record) end
    return record
end

function S.SaveReview(subject, stars, body)
    return saveReview(subject, stars, body)
end

function S.DeleteReview(subject, revision)
    return saveReview(subject, nil, nil, true, revision)
end

local fields = {"alts", "names", "authored", "reviews", "stats", "synced", "deliveries", "profiles",
    "recentPlayers", "historyMinimap", "groupSeen", "groupClears", "zeroSubjects", "talentContexts", "buildClears", "reviewRetractions"}

local function activate(level)
    level = level or S.Call(UnitLevel, "player")
    if S.me or type(level) ~= "number" or level < 1 or level > 60 then return end
    local primary = type(SocialCreditDB) == "table" and SocialCreditDB.version == 1 and SocialCreditDB or {}
    local backup = type(SocialCreditBackup) == "table" and SocialCreditBackup.version == 1 and SocialCreditBackup or {}
    S.db = {version = 1}
    for _, field in ipairs(fields) do
        S.db[field] = type(backup[field]) == "table" and S.Copy(backup[field]) or {}
        if field ~= "reviews" and type(primary[field]) == "table" then
            for key, value in pairs(primary[field]) do S.db[field][key] = value end
        end
    end
    S.db.reviews = {}
    S.faction = S.Call(UnitFactionGroup, "player")
    S.me = S.Unit("player", true)
    if not S.me or not S.faction then
        S.me = nil
        print("Social Credit System: full character identity is unavailable.")
        return
    end
    S.db.alts[S.me.key] = true
    S.me.level = level
    S.Remember(S.me)
    for _, store in ipairs({backup.reviews or {}, primary.reviews or {}}) do
        if type(store) == "table" then
            for _, rows in pairs(store) do
                if type(rows) == "table" then
                    for _, record in pairs(rows) do
                        if S.ValidRecord(record) then S.Merge(record, record.direct) end
                    end
                end
            end
        end
    end
    SocialCreditDB = S.db
    for _, callback in ipairs(S.events.SCS_ACTIVE or {}) do callback() end
end

function S.OnActive(callback)
    S.events.SCS_ACTIVE = S.events.SCS_ACTIVE or {}
    table.insert(S.events.SCS_ACTIVE, callback)
end

local function startLevel60()
    for _, callback in ipairs(S.events.SCS_LEVEL_60 or {}) do callback() end
end

function S.OnLevel60(callback)
    S.events.SCS_LEVEL_60 = S.events.SCS_LEVEL_60 or {}
    table.insert(S.events.SCS_LEVEL_60, callback)
end

S.On("PLAYER_LOGIN", function()
    if S.me then return end
    activate()
    if S.me and S.me.level == 60 then startLevel60() end
end)

S.On("PLAYER_LEVEL_UP", function(level)
    if not S.Readable(level) or type(level) ~= "number" or level < 1 or level > 60 then return end
    local previous = S.me and S.me.level
    if not S.me then
        activate(level)
    else
        -- Replace the profile so Remember can compare it with the previous level.
        local profile = S.Copy(S.me)
        profile.level = level
        S.me = profile
        S.Remember(profile)
    end
    if not S.me then return end
    if level == 60 and previous ~= 60 then startLevel60() end
    if S.AdvertiseLevel then S.AdvertiseLevel() end
    if S.Refresh then S.Refresh(S.openSubject) end
end)

S.On("PLAYER_LOGOUT", function()
    if S.me then SocialCreditBackup = S.Copy(S.db) end
end)
