local _, S = ...
local brackets = {5, 10, 20, 40}
local cache = {}

function S.InvalidateScores()
    cache = {}
    if S.QueuePlayerHistoryRefresh then S.QueuePlayerHistoryRefresh() end
    if S.ClearGroupStatsCache then S.ClearGroupStatsCache() end
    if S.ClearBuildStatsCache then S.ClearBuildStatsCache() end
    if S.QueueGroupFinderRefresh then S.QueueGroupFinderRefresh() end
end

function S.Benchmark(value, population)
    if #population < 5 then return end
    local low, high, sum = math.huge, -math.huge, 0
    for _, point in ipairs(population) do
        low, high, sum = math.min(low, point), math.max(high, point), sum + point
    end
    local mean = sum / #population
    if low == high or value == mean then return 500 end
    if value < mean then return math.max(0, 500 * (value - low) / (mean - low)) end
    return math.min(1000, 500 + 500 * (value - mean) / (high - mean))
end

local function rate(bracket, offset)
    local row = bracket and bracket.clears >= 3 and bracket.rate
    if row and row[offset + 1] > 0 then return row[offset] / row[offset + 1] end
end

local function cohort(class, tree, role)
    local id = table.concat({class, tree or 0, role or ""}, ":")
    if cache[id] then return cache[id] end
    local data = {reviews = {}, combat = {}, count = 0}
    for _, size in ipairs(brackets) do data.combat[size] = {{}, {}} end
    for key, profile in pairs(S.db.profiles) do
        if S.Eligible(key) and profile.class == class then
            data.count = data.count + 1
            local _, stars = S.ReviewAverage(key)
            if stars then table.insert(data.reviews, stars) end
            local build = S.BuildStats(key, tree, role)
            if build then
                for _, size in ipairs(brackets) do
                    for i, offset in ipairs({1, 4}) do
                        local value = rate(build[size], offset)
                        if value then table.insert(data.combat[size][i], value) end
                    end
                end
            end
        end
    end
    cache[id] = data
    return data
end

function S.Composite(key, stars)
    if not stars or not S.Eligible(key) then return end
    local class = S.db.profiles[key].class
    if not class then return end
    local tree, _, role = S.CurrentBuild(key)
    local data = cohort(class, tree, role)
    if not data then return end
    local review = S.Benchmark(stars, data.reviews)
    local sum, matched = 0, 0
    local build = S.BuildStats(key, tree, role)
    for _, size in ipairs(brackets) do
        local best
        for i, offset in ipairs({1, 4}) do
            local value = rate(build and build[size], offset)
            local normalized = value and S.Benchmark(value, data.combat[size][i])
            if normalized then best = best and math.max(best, normalized) or normalized end
        end
        if best then sum, matched = sum + best, matched + 1 end
    end
    local reviewScore = review or (stars < 3 and math.max(0, (stars - .5) * 200) or 500 + (stars - 3) * 250)
    local combat = matched > 0 and sum / matched or 500
    return .75 * reviewScore + .25 * combat, not review or matched == 0,
        data.count, #data.reviews, matched, reviewScore, combat
end

function S.RatingSummary(key)
    if not S.me or not S.Eligible(key) or S.db.alts[key] then return end
    local count, average = S.ReviewAverage(key)
    return count, average, S.Composite(key, average)
end

S.On("PLAYER_REGEN_ENABLED", function()
    if S.openSubject and S.Refresh then S.Refresh(S.openSubject) end
    if S.QueueGroupFinderRefresh then S.QueueGroupFinderRefresh() end
end)
