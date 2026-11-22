local _, S = ...
local cache = {}
local sizes = {[5] = true, [10] = true, [20] = true, [40] = true}

function S.ClearBuildStatsCache()
    cache = {}
end

local function rows(subject, witness, create)
    local records = S.db.buildClears
    if create then
        records[subject] = records[subject] or {}
        records[subject][witness] = records[subject][witness] or {}
    end
    return records[subject] and records[subject][witness]
end

local function store(subject, witness, id, record)
    local reports = rows(subject, witness, true)
    local old = reports[id]
    if old and old.revision >= record.revision then return end
    reports[id] = record
    S.InvalidateScores()
    if S.openSubject == subject and S.Refresh then S.Refresh(subject) end
    return true
end

function S.SaveBuildClear(run, subject, cohorts)
    local clear = run.groupClear
    if not clear or not cohorts or not next(cohorts) then return end
    local id = clear.map .. ":" .. clear.token
    local reports = rows(subject, S.me.key)
    local old = reports and reports[id]
    store(subject, S.me.key, id, {map = clear.map, token = clear.token, size = clear.size,
        stamp = clear.stamp, revision = old and old.revision + 1 or 1, cohorts = S.Copy(cohorts)})
end

local function coverage(row)
    local total = 0
    for _, rate in pairs(row.cohorts) do total = total + rate[2] + rate[5] end
    return total
end

local function aggregate(subject)
    local reports = {}
    for witness, byID in pairs(S.db.buildClears[subject] or {}) do
        for _, row in pairs(byID) do
            reports[#reports + 1] = {row = row, witness = witness, seconds = coverage(row)}
        end
    end
    table.sort(reports, function(a, b)
        if a.row.stamp ~= b.row.stamp then return a.row.stamp < b.row.stamp end
        return a.witness < b.witness
    end)
    local current, clears = {}, {}
    for _, report in ipairs(reports) do
        local row = report.row
        local key = row.map .. ":" .. row.size .. ":" .. (row.size == 5 and "dungeon" or row.token)
        local clear = current[key]
        if not clear or (row.size == 5 and (row.stamp - clear.stamp > 60
            or clear.witnesses[report.witness])) then
            clear = {stamp = row.stamp, best = report, witnesses = {}}
            current[key], clears[#clears + 1] = clear, clear
        else
            local best = clear.best
            if report.witness == subject or (best.witness ~= subject and report.seconds > best.seconds) then
                clear.best = report
            end
        end
        clear.witnesses[report.witness] = true
    end
    local builds = {}
    for _, clear in ipairs(clears) do
        local row = clear.best.row
        for build, rate in pairs(row.cohorts) do
            builds[build] = builds[build] or {}
            local bracket = builds[build][row.size] or {clears = 0, rate = {0, 0, 0, 0, 0, 0}}
            builds[build][row.size] = bracket
            bracket.clears = bracket.clears + 1
            for i = 1, 6 do bracket.rate[i] = bracket.rate[i] + rate[i] end
        end
    end
    return builds
end

function S.BuildStats(subject, tree, role)
    if not tree or not role or not S.db.buildClears[subject] then return end
    if not cache[subject] then cache[subject] = aggregate(subject) end
    return cache[subject][tree .. ":" .. role]
end

function S.BuildReports(subject)
    return rows(subject, S.me.key)
end

function S.ExportBuildClear(row)
    local fields = {"1", row.map, row.token, row.size, row.stamp, row.revision}
    for build, rate in pairs(row.cohorts) do
        fields[#fields + 1] = build
        for _, value in ipairs(rate) do fields[#fields + 1] = ("%.6f"):format(value) end
    end
    return table.concat(fields, "~")
end

function S.ImportBuildClear(subject, witness, payload)
    if not S.Eligible(subject) or S.db.alts[subject] then return end
    local fields = {}
    for value in (payload .. "~"):gmatch("(.-)~") do fields[#fields + 1] = value end
    if fields[1] ~= "1" or #fields < 13 or #fields > 62 or (#fields - 6) % 7 ~= 0 then return end
    local map, token = fields[2], fields[3]
    local size, stamp, revision = tonumber(fields[4]), tonumber(fields[5]), tonumber(fields[6])
    if #map > 24 or not map:match("^%d+:%d+$") or not sizes[size]
        or not stamp or stamp % 1 ~= 0 or stamp < 1 or stamp > S.Now() + 60
        or not revision or revision % 1 ~= 0 or revision < 1 or revision > 1000000 then return end
    if size == 5 then
        if token ~= tostring(stamp) then return end
    elseif #token > 32 or not token:match("^%d+:%d+$") then return end
    local cohorts = {}
    for i = 7, #fields, 7 do
        local build = fields[i]
        local tree = tonumber(build:match("^(%d+):[TN]$"))
        if not tree or tree < 1 or tree > 1000000 or cohorts[build] then return end
        local rate = {}
        for j = 1, 6 do
            local n = tonumber(fields[i + j])
            if not n or n ~= n or n < 0 or n > 1e14 or (j % 3 == 0 and n % 1 ~= 0) then return end
            rate[j] = n
        end
        for _, offset in ipairs({1, 4}) do
            local weighted, seconds, samples = unpack(rate, offset, offset + 2)
            if seconds > 604800 or samples > 10000 or (seconds == 0) ~= (samples == 0)
                or weighted > seconds * 1e8 then return end
        end
        if rate[2] + rate[5] == 0 then return end
        cohorts[build] = rate
    end
    return store(subject, witness, map .. ":" .. token, {map = map, token = token,
        size = size, stamp = stamp, revision = revision, cohorts = cohorts})
end

S.OnActive(function()
    local backup = SocialCreditBackup and SocialCreditBackup.buildClears
    for subject, witnesses in pairs(backup or {}) do
        for witness, byID in pairs(witnesses) do
            local current = rows(subject, witness, true)
            for id, row in pairs(byID) do
                if not current[id] or current[id].revision < row.revision then current[id] = S.Copy(row) end
            end
        end
    end
end)
