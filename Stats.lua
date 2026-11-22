local _, S = ...
local stats, run, fight
local observed, pending, meterContext, baselineReady = {}, {}, nil, false
local meter = C_DamageMeter
local sizes = {5, 10, 20, 40}
local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}
local slotWeights = {
    HEAD = 1, NECK = .5625, SHOULDER = .75, CHEST = 1, ROBE = 1, WAIST = .75,
    LEGS = 1, FEET = .75, WRIST = .5625, HAND = .75, FINGER = .5625, TRINKET = .5625,
    CLOAK = .5625, WEAPON = 1, WEAPONMAINHAND = 1, WEAPONOFFHAND = 1, HOLDABLE = 1,
    SHIELD = 1, ["2HWEAPON"] = 2, RANGED = .3164, RANGEDRIGHT = .3164, THROWN = .3164, RELIC = .3164,
}

-- Classic GearScore coefficients from the GearScoreLite lineage; see README.
local function scoreItem(quality, level, equip)
    local weight = slotWeights[equip:match("^INVTYPE_(.+)$")]
    if not weight then return 0 end
    local modifier = 1
    if quality == 5 then quality, modifier = 4, 1.3
    elseif quality <= 1 then quality, modifier = 2, .005
    elseif quality == 7 then quality, level = 3, 187.05 end
    local offset, divisor
    if quality == 4 then
        if level < 100 then offset, divisor = .25, 1.6275
        elseif level < 168 then offset, divisor = 26, 1.2
        else offset, divisor = 91.45, .65 end
    elseif quality == 3 then
        if level < 148 then offset, divisor = .75, 1.8
        else offset, divisor = 81.375, .8125 end
    elseif quality == 2 then
        if level < 138 then offset, divisor = 8, 2
        else offset, divisor = 73, 1 end
    else return 0 end
    return math.max(0, math.floor((level - offset) / divisor * weight * 1.8618 * modifier))
end

local gearQueued
local function scanEquipment()
    gearQueued = nil
    if not stats or InCombatLockdown() then return end
    local total, incomplete = 0, false
    local _, class = S.Call(UnitClass, "player")
    local ranged = S.Call(GetInventoryItemID, "player", 18)
    local offhand = S.Call(GetInventoryItemID, "player", 17)
    for _, slot in ipairs(slots) do
        local id = S.Call(GetInventoryItemID, "player", slot)
        if id then
            local link = S.Call(GetInventoryItemLink, "player", slot)
            local _, _, quality, level, _, _, _, _, equip =
                S.Call((C_Item and C_Item.GetItemInfo) or GetItemInfo, link or id)
            if type(quality) == "number" and type(level) == "number" and type(equip) == "string" then
                local score = scoreItem(quality, level, equip)
                if slot == 16 or slot == 17 then
                    if class == "HUNTER" and ranged then score = score * .3164 end
                    if equip == "INVTYPE_2HWEAPON" and offhand then score = score * .5 end
                end
                total = total + score
            else
                incomplete = true
                if not link and C_Item then S.Call(C_Item.RequestLoadItemDataByID, id) end
            end
        end
    end
    if not incomplete then stats.gear = math.max(stats.gear or 0, math.floor(total)) end
end

local function queueGear()
    if gearQueued then return end
    gearQueued = true
    C_Timer.After(.25, scanEquipment)
end

local function professions()
    local result = {}
    if GetProfessions and GetProfessionInfo then
        local indexes = {S.Call(GetProfessions)}
        for _, index in pairs(indexes) do
            local name, _, rank = S.Call(GetProfessionInfo, index)
            if type(name) == "string" and type(rank) == "number" then
                result[#result + 1] = name .. " " .. rank
            end
        end
    end
    if #result == 0 and C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        local professionHeader = PROFESSIONS or "Professions"
        local secondaryHeader = SECONDARY_SKILLS or "Secondary Skills"
        local inProfessions = false
        for i = 1, S.Call(C_SkillInfo.GetNumSkillLines) or 0 do
            local line = S.Call(C_SkillInfo.GetSkillLineInfo, i)
            if line and line.isHeader then
                inProfessions = line.skillName == professionHeader or line.skillName == secondaryHeader
            elseif line and inProfessions and line.skillName and line.skillRank then
                result[#result + 1] = line.skillName .. " " .. line.skillRank
            end
        end
    end
    if #result > 0 then
        table.sort(result)
        stats.professions = table.concat(result, ", ")
    end
end

local function instance()
    local _, kind, difficulty, capacity, _, _, _, map = S.Call(GetInstanceInfo)
    local key = map and table.concat({kind or "none", map, difficulty or 0}, ":")
    return key, kind, capacity, map
end

local function raidLock()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local name, _, difficulty = S.Call(GetInstanceInfo)
    for i = 1, S.Call(GetNumSavedInstances) or 0 do
        local saved, id, _, mode, locked, extended, high, raid, _, _, bosses, killed = GetSavedInstanceInfo(i)
        if S.Readable(saved) and S.Readable(id) and S.Readable(mode) and S.Readable(locked)
            and S.Readable(extended) and S.Readable(high) and S.Readable(raid)
            and saved == name and mode == difficulty and raid and (locked or extended) and id then
            return tostring(high or 0) .. ":" .. tostring(id),
                S.Readable(bosses) and S.Readable(killed) and type(bosses) == "number" and bosses > 0 and bosses == killed
        end
    end
end

local function updateInstance()
    if not stats then return end
    local key, kind, capacity, map = instance()
    local active = kind == "party" or kind == "raid" or kind == "pvp"
    if not active or not map then stats.run, run, fight = nil, nil, nil; return end
    if not stats.run or stats.run.key ~= key then stats.run = {key = key} end
    run = stats.run
    run.kind, run.capacity, run.map = kind, capacity, map
    run.rates = run.rates or {}
    if kind == "raid" then
        local lock = raidLock()
        if lock then
            local saved = stats.raidRuns[lock]
            if saved and (not run.lock or run.lock ~= lock) then
                run = saved
                stats.run = run
            else
                run.lock = lock
                stats.raidRuns[lock] = run
            end
        end
    end
end

local function addRate(row, offset, weighted, seconds, samples)
    row[offset] = row[offset] + weighted
    row[offset + 1] = row[offset + 1] + seconds
    row[offset + 2] = row[offset + 2] + samples
end

local function rateRow(rows, size)
    rows[size] = rows[size] or {0, 0, 0, 0, 0, 0}
    return rows[size]
end

local function complete(kind, participants, stamp)
    if not run or run.kind ~= kind or run.completed or instance() ~= run.key then return end
    local size = run.capacity
    if kind == "raid" and (not run.lock or stats.completedLocks[run.lock]) then return end
    run.completed = true
    if kind ~= "pvp" then
        S.SaveGroupClear(run, participants or S.GroupRoster(true), stamp or S.Now())
        S.SaveBuildClear(run, S.me.key, run.ownerBuildRates)
    end
    if kind ~= "raid" then
        local field = kind == "party" and "dungeons" or "battlegrounds"
        stats[field] = (stats[field] or 0) + 1
    else
        stats.completedLocks[run.lock] = true
    end
    if (kind == "party" and size == 5) or (kind == "raid" and (size == 10 or size == 20 or size == 40)) then
        stats.runs[size] = (stats.runs[size] or 0) + 1
        run.scored = true
        local accumulated = rateRow(stats.rates, size)
        local collected = rateRow(run.rates, size)
        for i = 1, 6 do accumulated[i] = accumulated[i] + collected[i] end
        S.InvalidateScores()
    end
end

local function combatBucket()
    if not run then return end
    if run.kind == "party" and run.capacity == 5 then return 5 end
    local cap = run.capacity
    if run.kind == "raid" and (cap == 10 or cap == 20 or cap == 40) then return cap end
end

local function sessions()
    return meter and S.Call(meter.GetAvailableCombatSessions)
end

local function discover(sample)
    local available = sessions()
    if type(available) ~= "table" then return false end
    for _, entry in ipairs(available) do
        if S.Readable(entry) and S.Readable(entry.sessionID) and type(entry.sessionID) == "number"
            and entry.sessionID > 0 and not observed[entry.sessionID] then
            observed[entry.sessionID] = true
            if sample then sample.ids[entry.sessionID] = true end
        end
    end
    return true
end

local function resetMeter()
    fight, pending = nil, {}
    meterContext = instance()
    baselineReady = discover()
end

local function readMeter(id, kind, visit)
    local session = S.Call(meter.GetCombatSessionFromID, id, kind)
    if type(session) ~= "table" or not S.Readable(session.durationSeconds)
        or not S.Readable(session.combatSources) then return end
    local seconds = session.durationSeconds
    if type(seconds) ~= "number" or seconds <= 0 or seconds >= math.huge
        or type(session.combatSources) ~= "table" then return end
    for _, source in ipairs(session.combatSources) do
        if S.Readable(source) then
            local rate = source.amountPerSecond
            if S.Readable(rate) and type(rate) == "number" and rate >= 0 and rate < math.huge then
                visit(source, rate, seconds)
            end
        end
    end
end

local function addBuildRate(runState, subject, build, offset, rate, seconds)
    if not build then return end
    local rates
    if subject == S.me.key then
        runState.ownerBuildRates = runState.ownerBuildRates or {}
        rates = runState.ownerBuildRates
    else
        runState.groupBuildRates = runState.groupBuildRates or {}
        runState.groupBuildRates[subject] = runState.groupBuildRates[subject] or {}
        rates = runState.groupBuildRates[subject]
    end
    addRate(rateRow(rates, build), offset, rate * seconds, seconds, 1)
    if subject == S.me.key and runState.groupClear then S.SaveBuildClear(runState, subject, rates) end
end

local function finalize()
    if not stats or InCombatLockdown() or instance() ~= meterContext then return end
    local types = Enum and Enum.DamageMeterType
    if not types then return end
    for id, sample in pairs(pending) do
        if GetTime() <= sample.expires then
            local row = rateRow(sample.run.rates, sample.bucket)
            local function include(kind, offset)
                readMeter(id, kind, function(source, rate, seconds)
                    if seconds > sample.duration + 1 then return end
                    local seen = sample.done[offset]
                    if S.Readable(source.isLocalPlayer) and source.isLocalPlayer and not seen.self then
                        addRate(row, offset, rate * seconds, seconds, 1)
                        addBuildRate(sample.run, S.me.key, sample.builds[S.me.key], offset, rate, seconds)
                        if sample.run.scored then
                            addRate(rateRow(stats.rates, sample.bucket), offset, rate * seconds, seconds, 1)
                            S.InvalidateScores()
                        end
                        seen.self = true
                    end
                    local guid = source.sourceGUID
                    if not S.Readable(guid) or type(guid) ~= "string" then return end
                    local subject = sample.roster[guid]
                    if not subject or seen[subject] then return end
                    seen[subject] = true
                    local collected = sample.run.groupRates or {}
                    sample.run.groupRates = collected
                    collected[subject] = collected[subject] or {0, 0, 0, 0, 0, 0}
                    addRate(collected[subject], offset, rate * seconds, seconds, 1)
                    addBuildRate(sample.run, subject, sample.builds[subject], offset, rate, seconds)
                    if sample.run.groupClear then
                        S.UpdateGroupClear(sample.run, subject)
                    end
                end)
            end
            include(types.DamageDone, 1)
            include(types.HealingDone, 4)
        end
        if GetTime() > sample.expires then pending[id] = nil end
    end
end

S.On("PLAYER_REGEN_DISABLED", function()
    if not stats then return end
    local bucket = combatBucket()
    if not bucket or not run or run.completed or instance() ~= meterContext or not baselineReady then
        baselineReady = discover()
        return
    end
    -- IDs first exposed at pull start can only be attributed through meter updates
    -- or the synchronous encounter boundary. Older visible sessions were baselined.
    local roster, units = S.GroupRoster(false)
    local builds = {[S.me.key] = S.CaptureBuild("player", S.me.key)}
    for guid, key in pairs(roster) do builds[key] = S.CaptureBuild(units[guid], key) end
    fight = {bucket = bucket, run = run, started = GetTime(), ids = {}, roster = roster, builds = builds}
end)

S.On("GROUP_ROSTER_UPDATE", function()
    if not fight then return end
    local present = S.GroupRoster(false)
    for guid, key in pairs(fight.roster) do
        if present[guid] ~= key then fight.roster[guid] = nil end
    end
end)

S.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(_, id)
    if not stats or not S.Readable(id) or type(id) ~= "number" or id <= 0 then return end
    local sameContext = instance() == meterContext
    if fight and sameContext and not observed[id] then fight.ids[id] = true end
    observed[id] = true
    if pending[id] and sameContext then C_Timer.After(.1, finalize) end
end)

S.On("PLAYER_REGEN_ENABLED", function()
    if not stats then return end
    local sample = fight
    fight = nil
    if sample and instance() == meterContext then
        discover(sample)
        local now = GetTime()
        local present = S.GroupRoster(true)
        for guid, key in pairs(sample.roster) do
            if present[guid] ~= key then sample.roster[guid] = nil end
        end
        for id in pairs(sample.ids) do
            pending[id] = {bucket = sample.bucket, run = sample.run, duration = now - sample.started,
                expires = now + 120, roster = sample.roster, builds = sample.builds, done = {[1] = {}, [4] = {}}}
        end
    else
        discover()
    end
    if next(pending) then C_Timer.After(.25, finalize) end
    if stats then queueGear() end
end)
S.On("PLAYER_ENTERING_WORLD", function()
    if not stats then return end
    updateInstance()
    resetMeter()
end)
S.On("ZONE_CHANGED_NEW_AREA", function()
    if not stats then return end
    updateInstance()
    if instance() ~= meterContext then resetMeter() end
end)
S.On("DAMAGE_METER_RESET", function()
    if not stats then return end
    observed = {}
    resetMeter()
end)

local loot = C_LootHistory
local waitingForItem = {}
local function recordGearRoll(encounter, key)
    if not stats or not loot or not S.Readable(encounter) or not S.Readable(key)
        or type(encounter) ~= "number" or type(key) ~= "number" then return end
    local drop = S.Call(loot.GetSortedInfoForDrop, encounter, key)
    if type(drop) ~= "table" or not S.Readable(drop.startTime) or type(drop.startTime) ~= "number"
        or not S.Readable(drop.itemHyperlink) or type(drop.itemHyperlink) ~= "string"
        or not S.Readable(drop.rollInfos) or type(drop.rollInfos) ~= "table" then return end
    local rollStates = Enum and Enum.EncounterLootDropRollState
    if not rollStates then return end
    local identity = table.concat({encounter, key, ("%.6f"):format(drop.startTime), drop.itemHyperlink}, "~")
    local rolls = stats.gearRolls
    if rolls.seen[identity] == true then return end
    for _, result in ipairs(drop.rollInfos) do
        if S.Readable(result) and S.Readable(result.isSelf) and result.isSelf then
            local choice, roll = result.state, result.roll
            if not S.Readable(choice) or type(choice) ~= "number" then return end
            local need = choice == rollStates.NeedMainSpec or choice == rollStates.NeedOffSpec
            local greed = choice == rollStates.Greed
            local numeric = S.Readable(roll) and type(roll) == "number"
                and roll >= 1 and roll <= 100 and roll % 1 == 0
            if not (need or greed or (numeric and choice == rollStates.Transmog)) then return end
            if rolls.seen[identity] and not numeric then return end
            local itemID, _, _, equip = S.Call(C_Item and C_Item.GetItemInfoInstant, drop.itemHyperlink)
            if not equip then
                local id = itemID or tonumber(drop.itemHyperlink:match("item:(%d+)"))
                if id and C_Item and C_Item.RequestLoadItemDataByID and not waitingForItem[identity] then
                    waitingForItem[identity] = {id = id, encounter = encounter, key = key}
                    S.Call(C_Item.RequestLoadItemDataByID, id)
                end
                return
            end
            if not slotWeights[equip:match("^INVTYPE_(.+)$")] then return end
            if not rolls.seen[identity] and (need or greed) then
                if need then rolls.need = (rolls.need or 0) + 1
                else rolls.greed = (rolls.greed or 0) + 1 end
                -- Keep the counted choice while waiting for a readable numeric result.
                rolls.seen[identity] = "choice"
            end
            if numeric then
                rolls.seen[identity] = true
                rolls.count, rolls.sum = rolls.count + 1, rolls.sum + roll
            end
            return
        end
    end
end

S.On("LOOT_HISTORY_UPDATE_DROP", recordGearRoll)
S.On("LOOT_HISTORY_UPDATE_ENCOUNTER", function(encounter)
    if not loot or not S.Readable(encounter) or type(encounter) ~= "number" then return end
    local drops = S.Call(loot.GetSortedDropsForEncounter, encounter)
    if type(drops) ~= "table" then return end
    for _, drop in ipairs(drops) do
        if S.Readable(drop) then recordGearRoll(encounter, drop.lootListKey) end
    end
end)

S.On("LFG_COMPLETION_REWARD", function() complete("party") end)
S.On("PVP_MATCH_COMPLETE", function() complete("pvp") end)
local raidCompletion
local function verifyRaid()
    if not raidCompletion or not run or raidCompletion.key ~= run.key
        or GetTime() > raidCompletion.expires or instance() ~= run.key then return end
    local lock, fullClear = raidLock()
    if lock then updateInstance() end
    if lock and fullClear then
        complete("raid", raidCompletion.participants, raidCompletion.stamp)
        raidCompletion = nil
    end
end
S.On("UPDATE_INSTANCE_INFO", verifyRaid)
S.On("ENCOUNTER_END", function(encounterID, _, _, _, successful)
    if not run or not S.Readable(successful) or successful ~= 1
        or not S.Readable(encounterID) then return end
    if run.kind == "raid" then
        raidCompletion = {key = run.key, expires = GetTime() + 10,
            participants = S.GroupRoster(true), stamp = S.Now()}
        S.Call(RequestRaidInfo)
        C_Timer.After(.5, verifyRaid)
        return
    end
    if run.kind ~= "party" then return end
    local uiMap = C_Map and S.Call(C_Map.GetBestMapForUnit, "player")
    local journal = uiMap and S.Call(EJ_GetInstanceForMap, uiMap)
    if not journal or journal == 0 then return end
    local lastGameEncounter
    for index = 1, 40 do
        local name, _, _, _, _, _, gameEncounter = S.Call(EJ_GetEncounterInfoByIndex, index, journal)
        if not name then break end
        lastGameEncounter = gameEncounter
    end
    if lastGameEncounter and lastGameEncounter == encounterID then complete("party") end
end)
S.On("PLAYER_EQUIPMENT_CHANGED", queueGear)
S.On("GET_ITEM_INFO_RECEIVED", function(id)
    if not stats or not S.Readable(id) or not id then return end
    for _, slot in ipairs(slots) do
        if S.Call(GetInventoryItemID, "player", slot) == id then queueGear(); return end
    end
end)
S.On("GET_ITEM_INFO_RECEIVED", function(id, success)
    if not S.Readable(id) or not S.Readable(success) then return end
    for identity, request in pairs(waitingForItem) do
        if request.id == id then
            if success then recordGearRoll(request.encounter, request.key) end
            waitingForItem[identity] = nil
        end
    end
end)
S.On("SKILL_LINES_CHANGED", function() if stats then professions() end end)
S.On("TIME_PLAYED_MSG", function(seconds)
    if not stats or not S.Readable(seconds) or type(seconds) ~= "number" then return end
    stats.played = seconds
end)

S.OnActive(function()
    if not S.me then return end
    stats = S.db.stats[S.me.key] or {rates = {}}
    S.db.stats[S.me.key] = stats
    if not stats.level60Since then
        stats.rates, stats.ratesSince, stats.level60Since = {}, S.Now(), S.Now()
        stats.runs, stats.raidRuns, stats.completedLocks, stats.run = {}, {}, {}, nil
        stats.gearRolls = nil
        stats.dungeons, stats.battlegrounds, stats.gear = nil, nil, nil
    end
    stats.explicitWords = stats.explicitWords or 0
    stats.gearRolls = stats.gearRolls or {sum = 0, count = 0, seen = {}}
    updateInstance()
    resetMeter()
    C_Timer.After(2, function()
        queueGear()
        professions()
        if RequestTimePlayed and not stats.played then S.Call(RequestTimePlayed) end
    end)
end)

local explicit = {}
for word in ("fuck fucked fucking fucks fucker fuckers shit shits shitty shitting bullshit bitch bitches bastard bastards cunt cunts dick dicks asshole assholes motherfucker motherfuckers"):gmatch("%S+") do
    explicit[word] = true
end
local chatLines = {}
local function countWords(message, sender, _, _, _, _, _, _, _, _, id)
    if not stats or not S.Readable(message) or type(message) ~= "string"
        or S.Identity(sender) ~= S.me.key or not S.Readable(id) then return end
    if type(id) == "number" and id > 0 then
        if chatLines[id] then return end
        chatLines[id] = true
        C_Timer.After(60, function() chatLines[id] = nil end)
    end
    message = message:gsub("|H.-|h.-|h", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for word in message:lower():gmatch("[%w_\128-\255]+") do
        if explicit[word] then stats.explicitWords = stats.explicitWords + 1 end
    end
end
for _, channel in ipairs({"SAY", "YELL", "GUILD", "PARTY", "PARTY_LEADER", "RAID",
    "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "CHANNEL"}) do
    S.On("CHAT_MSG_" .. channel, countWords)
end

local function number(value, max)
    if value == "" then return end
    local n = tonumber(value)
    if n and n >= 0 and n <= max and n == math.floor(n) then return n end
end

function S.ExportStats(verified)
    if not stats then return end
    local professionList = stats.professions or ""
    if #professionList > 300 or professionList:find("[~|%c]") then professionList = "" end
    local fields = {S.Now(), stats.dungeons or "", stats.battlegrounds or "", stats.gear or "",
        stats.played or "", professionList}
    for _, size in ipairs(sizes) do
        local row = (verified or (stats.runs[size] or 0) >= 3) and stats.rates[size] or {}
        for i = 1, 6 do
            local fractional = i == 2 or i == 5 or (verified and (i == 1 or i == 4))
            fields[#fields + 1] = row[i] and math.floor(row[i] * (fractional and 100 or 1) + .5) or ""
        end
    end
    if verified then
        fields[#fields + 1] = stats.ratesSince
        fields[#fields + 1] = stats.gearRolls.sum
        fields[#fields + 1] = stats.gearRolls.count
        for _, size in ipairs(sizes) do fields[#fields + 1] = stats.runs[size] or 0 end
        fields[#fields + 1] = stats.explicitWords
        fields[#fields + 1] = stats.level60Since
    end
    return table.concat(fields, "~")
end

function S.ExportReviewsGiven()
    local count = 0
    for subject, author in pairs(S.db.authored) do
        local review = (S.db.reviews[subject] or {})[author]
        if author == S.me.key and review and not review.deleted then count = count + 1 end
    end
    return ("%d~%d"):format(S.Now(), count)
end

function S.ExportNeedGreed()
    local rolls = stats.gearRolls
    return ("%d~%d~%d"):format(S.Now(), rolls.need or 0, rolls.greed or 0)
end

function S.ImportNeedGreed(owner, payload)
    local stamp, need, greed = payload:match("^(%d+)~(%d+)~(%d+)$")
    stamp, need, greed = number(stamp, S.Now() + 300), number(need, 1e10), number(greed, 1e10)
    local snapshot = S.db.stats[owner]
    local old = snapshot and snapshot.needGreed
    if not stamp or not need or not greed or not snapshot or (old and old.stamp > stamp) then return end
    snapshot.needGreed = {stamp = stamp, need = need, greed = greed}
    S.ClearGroupStatsCache()
    return true
end

function S.ImportReviewsGiven(owner, payload)
    local stamp, count = payload:match("^(%d+)~(%d+)$")
    stamp, count = number(stamp, S.Now() + 300), number(count, 1000000)
    local snapshot = S.db.stats[owner]
    if not stamp or not count or not snapshot
        or (snapshot.givenStamp and snapshot.givenStamp > stamp) then return end
    snapshot.reviewsGiven, snapshot.givenStamp = count, stamp
    return true
end

function S.ImportStats(owner, payload, verified)
    local fields = {}
    for field in (payload .. "~"):gmatch("(.-)~") do fields[#fields + 1] = field end
    if #fields ~= (verified and 39 or 30) or #fields[6] > 300 or fields[6]:find("[|%c]") then return end
    local time = number(fields[1], S.Now() + 300)
    local old = S.db.stats[owner]
    if not time or (old and old.stamp and old.stamp > time) then return end
    local snapshot = {stamp = time, rates = {}, dungeons = number(fields[2], 1000000),
        battlegrounds = number(fields[3], 1000000), gear = number(fields[4], 100000),
        played = number(fields[5], 1000000000), professions = fields[6] ~= "" and fields[6] or nil}
    if old then
        snapshot.reviewsGiven, snapshot.givenStamp = old.reviewsGiven, old.givenStamp
        snapshot.needGreed = old.needGreed
    end
    for index, size in ipairs(sizes) do
        local row = {}
        for i = 1, 6 do
            local value = number(fields[6 + (index - 1) * 6 + i], 1e15)
            local fractional = i == 2 or i == 5 or (verified and (i == 1 or i == 4))
            row[i] = value and value / (fractional and 100 or 1) or 0
        end
        snapshot.rates[size] = row
    end
    if verified then
        local since = number(fields[31], time)
        local sum, count = number(fields[32], 1e12), number(fields[33], 1e10)
        if not since or since == 0 or not sum or not count or sum < count or sum > count * 100 then return end
        snapshot.ratesSince, snapshot.rollSum, snapshot.rollCount = since, sum, count
        snapshot.runs = {}
        for index, size in ipairs(sizes) do
            snapshot.runs[size] = number(fields[33 + index], 1000000)
            if not snapshot.runs[size] then return end
            local row = snapshot.rates[size]
            if row[2] == 0 and row[5] == 0 then snapshot.rates[size] = nil end
        end
        snapshot.explicitWords = number(fields[38], 1e12)
        snapshot.level60Since = number(fields[39], time)
        if not snapshot.explicitWords or not snapshot.level60Since then return end
    elseif old and old.ratesSince then
        snapshot.rates, snapshot.ratesSince = old.rates, old.ratesSince
        snapshot.rollSum, snapshot.rollCount = old.rollSum, old.rollCount
        snapshot.runs, snapshot.explicitWords, snapshot.level60Since = old.runs, old.explicitWords, old.level60Since
    end
    S.db.stats[owner] = snapshot
    S.InvalidateScores()
    return true
end
