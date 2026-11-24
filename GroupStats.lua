local _, S = ...
local cache = {}
local brackets = {[5] = true, [10] = true, [20] = true, [40] = true}
local function blank() return {0, 0, 0, 0, 0, 0} end

function S.ClearGroupStatsCache()
    cache = {}
end

function S.GroupRoster(remember)
    local roster, units = {}, {}
    if not S.me then return roster, units end
    local raid = S.Call(IsInRaid)
    local count = raid and S.Call(GetNumGroupMembers) or (not raid and S.Call(GetNumSubgroupMembers))
    for i = 1, math.min(count or 0, raid and 40 or 4) do
        local unit = (raid and "raid" or "party") .. i
        local profile = S.Unit(unit)
        if profile and profile.level == 60 and profile.class and not S.db.alts[profile.key] then
            if remember then
                S.Remember(profile)
                S.db.groupSeen[profile.key] = profile
            end
            local guid = S.Call(UnitGUID, unit)
            if type(guid) == "string" and guid:match("^Player%-")
                and S.Call(UnitIsConnected, unit) ~= false
                and (S.Call(UnitInRange, unit) == true or S.Call(UnitIsVisible, unit) == true) then
                roster[guid] = profile.key
                units[guid] = unit
            end
        end
    end
    return roster, units
end

local function scan()
    if S.Eligible(S.me and S.me.key) then S.GroupRoster(true) end
end
S.OnLevel60(scan)
S.On("GROUP_ROSTER_UPDATE", scan)
S.On("PLAYER_ENTERING_WORLD", scan)

S.OnActive(function()
    local backup = SocialCreditBackup and SocialCreditBackup.groupClears
    for subject, witnesses in pairs(backup or {}) do
        if not S.db.alts[subject] then
            local current = S.db.groupClears[subject] or {}
            S.db.groupClears[subject] = current
            for witness, rows in pairs(witnesses) do
                current[witness] = current[witness] or {}
                for id, row in pairs(rows) do
                    local saved = current[witness][id]
                    if not saved or saved.revision < row.revision then
                        current[witness][id] = S.Copy(row)
                    end
                end
            end
        end
    end
    for key in pairs(S.db.alts) do
        S.db.groupSeen[key], S.db.groupClears[key] = nil, nil
    end
end)

local function records(subject, witness)
    local all = S.db.groupClears
    all[subject] = all[subject] or {}
    all[subject][witness] = all[subject][witness] or {}
    return all[subject][witness]
end

local function store(subject, witness, id, row)
    local rows = records(subject, witness)
    local old = rows[id]
    if old and old.revision >= row.revision then return end
    rows[id] = row
    S.InvalidateScores()
    if S.Refresh and S.openSubject == subject then S.Refresh(subject) end
    return true
end

function S.SaveGroupClear(run, participants, stamp)
    local size = run.capacity
    local _, map, difficulty = run.key:match("^(%a+):(%d+):(%d+)$")
    if not map or not brackets[size] or (run.kind == "party") ~= (size == 5) then return end
    run.groupClear = {participants = participants, stamp = stamp, size = size, map = map .. ":" .. difficulty,
        token = run.lock or tostring(stamp)}
    for _, subject in pairs(participants) do S.UpdateGroupClear(run, subject) end
end

function S.UpdateGroupClear(run, subject)
    local clear = run.groupClear
    if not clear or S.db.alts[subject] then return end
    local present = false
    for _, key in pairs(clear.participants) do
        if key == subject then present = true; break end
    end
    if not present then return end
    local id = clear.map .. ":" .. clear.token
    local old = records(subject, S.me.key)[id]
    local row = S.Copy(clear)
    row.participants = nil
    row.rates = S.Copy(run.groupRates and run.groupRates[subject] or blank())
    row.revision = old and old.revision + 1 or 1
    store(subject, S.me.key, id, row)
    S.SaveBuildClear(run, subject, run.groupBuildRates and run.groupBuildRates[subject])
end

local function aggregate(subject, owner)
    local rows = {}
    local cutoff = owner and (owner.level60Since or owner.ratesSince or owner.stamp)
    for witness, reports in pairs(S.db.groupClears[subject] or {}) do
        for _, row in pairs(reports) do
            if not cutoff or row.stamp < cutoff - 60 then
                rows[#rows + 1] = {witness = witness, row = row}
            end
        end
    end
    if #rows == 0 then return owner end
    table.sort(rows, function(a, b)
        if a.row.stamp ~= b.row.stamp then return a.row.stamp < b.row.stamp end
        return a.witness < b.witness
    end)
    local stats = {}
    for key, value in pairs(owner or {}) do stats[key] = value end
    stats.runs, stats.rates, stats.groupRuns = S.Copy(stats.runs or {}), S.Copy(stats.rates or {}), {}
    local latest, clears = {}, {}
    for _, item in ipairs(rows) do
        local row = item.row
        local key = row.map .. ":" .. row.size .. ":" .. (row.size == 5 and "dungeon" or row.token)
        local clear = latest[key]
        if not clear or (row.size == 5 and row.stamp - clear.stamp > 60) then
            clear = {size = row.size, stamp = row.stamp, best = {}}
            clears[#clears + 1], latest[key] = clear, clear
        end
        for _, offset in ipairs({1, 4}) do
            local best = clear.best[offset]
            local duration, samples = row.rates[offset + 1], row.rates[offset + 2]
            local old = best and best.row.rates
            if not old or duration > old[offset + 1] or (duration == old[offset + 1]
                and (samples > old[offset + 2] or (samples == old[offset + 2] and item.witness < best.witness))) then
                clear.best[offset] = item
            end
        end
    end
    for _, clear in ipairs(clears) do
        local size = clear.size
        stats.groupRuns[size] = (stats.groupRuns[size] or 0) + 1
        stats.runs[size] = (stats.runs[size] or 0) + 1
        local row = stats.rates[size] or blank()
        for _, offset in ipairs({1, 4}) do
            local rate = clear.best[offset].row.rates
            for i = offset, offset + 2 do row[i] = row[i] + rate[i] end
        end
        stats.rates[size] = row
    end
    if stats.groupRuns[5] then stats.dungeons = (stats.dungeons or 0) + stats.groupRuns[5] end
    return stats
end

function S.ProfileStats(subject)
    local owner = S.db.stats[subject]
    if S.db.alts[subject] or not S.db.groupClears[subject] then return owner end
    if not cache[subject] then cache[subject] = aggregate(subject, owner) or false end
    return cache[subject] or nil
end

function S.GroupReports(subject, cursor)
    local profile = S.db.groupSeen[subject]
    if not profile or not S.Eligible(subject) then return end
    local rows = (S.db.groupClears[subject] or {})[S.me.key] or {}
    local ids = {}
    for id in pairs(rows) do if id > cursor then ids[#ids + 1] = id end end
    table.sort(ids)
    return profile, ids, rows
end

local function fields(payload)
    local values = {}
    for value in (payload .. "~"):gmatch("(.-)~") do values[#values + 1] = value end
    return values
end

function S.ImportGroupProfile(subject, payload)
    local f = fields(payload)
    if #f ~= 4 or S.Identity(f[1]) ~= subject or not f[2]:match("^[A-Z]+$")
        or #f[2] > 24 or f[3] ~= S.faction or #f[4] > 120 or f[4]:find("[|%c]") then return end
    local known = S.db.profiles[subject]
    if known and (not S.Eligible(subject) or known.class ~= f[2]) then return end
    if not known or known.guild == nil then
        S.Remember({key = subject, name = f[1], class = f[2], faction = f[3], level = 60,
            guild = f[4] ~= "?" and f[4] or nil})
    end
    if S.Refresh then S.Refresh(S.openSubject) end
    if S.OpenDiscoveredProfile then S.OpenDiscoveredProfile(subject) end
    return true
end

function S.ImportGroupClear(subject, witness, payload)
    local f = fields(payload)
    if #f ~= 11 or not S.Eligible(subject) or S.db.alts[subject] or subject == witness then return end
    local map, token = f[1], f[2]
    local size, stamp, revision = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not map:match("^%d+:%d+$") or #map > 24 or not brackets[size]
        or not stamp or stamp % 1 ~= 0 or stamp < 1 or stamp > S.Now() + 60
        or not revision or revision % 1 ~= 0 or revision < 1 or revision > 1000000 then return end
    if size == 5 then
        if token ~= tostring(stamp) then return end
    elseif #token > 32 or not token:match("^%d+:%d+$") then return end
    local row = {map = map, token = token, size = size, stamp = stamp, revision = revision, rates = {}}
    for i = 1, 6 do
        local n = tonumber(f[i + 5])
        if not n or n ~= n or n < 0 or n > 1e14 or (i % 3 == 0 and n % 1 ~= 0) then return end
        row.rates[i] = n
    end
    for _, offset in ipairs({1, 4}) do
        local weighted, seconds, samples = unpack(row.rates, offset, offset + 2)
        if seconds > 604800 or samples > 10000 or (seconds == 0) ~= (samples == 0)
            or weighted > seconds * 1e8 then return end
    end
    return store(subject, witness, map .. ":" .. token, row)
end
