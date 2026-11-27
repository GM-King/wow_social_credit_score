local _, S = ...
local stats, run, fight
local observed, pending, meterContext, baselineReady = {}, {}, nil, false
local closing, instanceRetry
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
    if not stats then return end
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
    local name, kind, difficulty, _, capacity, _, _, map, groupSize = S.Call(GetInstanceInfo)
    if kind ~= "party" and kind ~= "raid" and kind ~= "pvp" then
        if kind and not S.Call(IsInInstance) then return nil, kind end
        return
    end
    if type(map) ~= "number" or map <= 0 or type(difficulty) ~= "number" then return end
    if not capacity or capacity <= 0 then capacity = groupSize end
    if not capacity or capacity <= 0 then return end
    return ("%s:%d:%d"):format(kind, map, difficulty), kind, capacity, map, name
end

-- Forever's Master Spelunker objectives, keyed by DungeonEncounter ID.
local dungeonObjectives = {
    [437] = 129,  -- Razorfen Downs: Amnennar
    [554] = 70,   -- Uldaman: Archaedas
    [600] = 209,  -- Zul'Farrak: Chief Ukorz
    [429] = 349,  -- Maraudon: Princess Theradras
    [3409] = 2994, -- Alcaz Prison: Blazeroar
    [493] = 109,  -- Sunken Temple: Shade of Eranikus
    [245] = 230,  -- Blackrock Depths: Emperor Dagran Thaurissan
    [3334] = 2974, -- Blackmaw Hold: Varrox Bleakhoof
    [275] = 229,  -- Lower Blackrock Spire: Overlord Wyrmthalak
    [280] = 229,  -- Upper Blackrock Spire: General Drakkisath
    [463] = 289,  -- Scholomance: Darkmaster Gandling
    [478] = 329,  -- Stratholme Live: Balnazzar
    [484] = 329,  -- Stratholme Dead: Baron Rivendare
    [346] = 429,  -- Dire Maul East: Alzzin
    [349] = 429,  -- Dire Maul West: Immol'thar
    [368] = 429,  -- Dire Maul North: King Gordok
    [3502] = 3001, -- Shaper's Terrace: Nanaya
}
local mappedDungeons, multiWing = {}, {[229] = true, [329] = true, [429] = true}
for _, map in pairs(dungeonObjectives) do mappedDungeons[map] = true end

local function dungeonSize(encounter)
    return encounter == 280 and 10 or 5
end

local function dungeonVisit(kind, map)
    return kind == "party" or (kind == "raid" and map == 229)
end

local function raidLock()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local name, _, difficulty, _, _, _, _, map = S.Call(GetInstanceInfo)
    for i = 1, S.Call(GetNumSavedInstances) or 0 do
        local ok, saved, id, _, mode, locked, extended, high, raid, _, _, bosses, killed, _, savedMap =
            pcall(GetSavedInstanceInfo, i)
        if ok and S.Readable(saved) and S.Readable(id) and S.Readable(mode) and S.Readable(locked)
            and S.Readable(extended) and S.Readable(high) and S.Readable(raid)
            and saved == name and mode == difficulty and raid and (locked or extended) and type(id) == "number"
            and id > 0 and S.Readable(savedMap) and (not savedMap or savedMap == 0 or savedMap == map) then
            return tostring(high or 0) .. ":" .. tostring(id),
                S.Readable(bosses) and S.Readable(killed) and type(bosses) == "number" and bosses > 0 and bosses == killed
        end
    end
end

local function mergeRateRows(target, source)
    if not source then return target end
    target = target or {}
    for key, values in pairs(source) do
        local total = target[key] or {0, 0, 0, 0, 0, 0}
        for i = 1, 6 do total[i] = total[i] + values[i] end
        target[key] = total
    end
    return target
end

local function updateInstance()
    if not stats then return end
    local key, kind, capacity, map, name = instance()
    if not key then
        if kind then stats.run, run, fight = nil, nil, nil end
        return kind ~= nil
    end
    if not stats.run or stats.run.key ~= key then
        stats.run = {key = key, lootSince = S.Call(C_LootHistory and C_LootHistory.GetLootHistoryTime)}
    end
    run = stats.run
    run.kind, run.capacity, run.map, run.name = kind, capacity, map, name
    run.rates = run.rates or {}
    if kind == "raid" and not dungeonVisit(kind, map) then
        local lock = raidLock()
        if lock then
            local saved = stats.raidRuns[lock]
            if saved and (not run.lock or run.lock ~= lock) then
                saved.activeRates = mergeRateRows(saved.activeRates, run.activeRates)
                saved.ownerBuildRates = mergeRateRows(saved.ownerBuildRates, run.ownerBuildRates)
                for subject, builds in pairs(run.groupBuildRates or {}) do
                    saved.groupBuildRates = saved.groupBuildRates or {}
                    saved.groupBuildRates[subject] = mergeRateRows(saved.groupBuildRates[subject], builds)
                end
                if fight and fight.run == run then fight.run = saved end
                if closing and closing.run == run then closing.run = saved end
                for _, sample in pairs(pending) do
                    if sample.run == run then sample.run = saved end
                end
                if meterContext == run then meterContext = saved end
                run = saved
                stats.run = run
            else
                run.lock = lock
                stats.raidRuns[lock] = run
            end
        end
    end
    return true
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

local function complete(kind, participants, stamp, objective)
    if not run or run.completed or instance() ~= run.key then return end
    if kind == "party" then
        if not dungeonVisit(run.kind, run.map) then return end
    elseif run.kind ~= kind then return end
    local size = objective and dungeonSize(objective) or run.capacity
    if kind == "raid" and (not run.lock or stats.completedLocks[run.lock]) then return end
    run.completed = true
    if kind ~= "pvp" then
        S.SaveGroupClear(run, participants or S.GroupRoster(true), stamp or S.Now(), objective, size)
        S.SaveBuildClear(run, S.me.key, run.ownerBuildRates)
    end
    if kind ~= "raid" then
        local field = kind == "party" and "dungeons" or "battlegrounds"
        stats[field] = (stats[field] or 0) + 1
    else
        stats.completedLocks[run.lock] = true
    end
    if (kind == "party" and (size == 5 or size == 10)) or (kind == "raid" and (size == 10 or size == 20 or size == 40)) then
        stats.runs[size] = (stats.runs[size] or 0) + 1
        if run.rates[size] then
            local accumulated = rateRow(stats.rates, size)
            for i = 1, 6 do accumulated[i] = accumulated[i] + run.rates[size][i] end
        end
        S.InvalidateScores()
    end
    if S.Refresh and S.openSubject == S.me.key then S.Refresh(S.me.key) end
end

local function nextWing()
    run = {key = run.key, kind = run.kind, capacity = run.capacity, map = run.map, name = run.name,
        activeRates = run.activeRates, objectives = run.objectives, rates = {}, lootSince = run.lootSince}
    stats.run, meterContext = run, run
end

local function completeObjective(encounter)
    if not run or not S.Readable(encounter) or dungeonObjectives[encounter] ~= run.map
        or not dungeonVisit(run.kind, run.map) or instance() ~= run.key then return end
    run.objectives = run.objectives or {}
    if run.objectives[encounter] or (run.completed and not next(run.objectives)) then return end
    if run.completed then nextWing() end
    run.objectives[encounter] = true
    complete("party", nil, nil, encounter)
end

local function combatBucket()
    if not run then return end
    if dungeonVisit(run.kind, run.map) then
        if run.map == 229 and (S.Call(GetNumGroupMembers) or 0) > 5 then return 10 end
        if run.capacity == 5 or mappedDungeons[run.map] then return 5 end
    end
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
        if S.Readable(entry) and type(entry) == "table" and S.Readable(entry.sessionID) and type(entry.sessionID) == "number"
            and entry.sessionID > 0 and not observed[entry.sessionID] then
            observed[entry.sessionID] = true
            if sample then sample.ids[entry.sessionID] = true end
        end
    end
    return true
end

local function resetMeter()
    fight, closing = nil, nil
    meterContext = run
    baselineReady = discover()
end

local function readMeter(id, kind, visit)
    local session = S.Call(meter.GetCombatSessionFromID, id, kind)
    if not S.Readable(session) or type(session) ~= "table" or not S.Readable(session.durationSeconds)
        or not S.Readable(session.combatSources) then return end
    local seconds = session.durationSeconds
    if type(seconds) ~= "number" or seconds <= 0 or seconds >= math.huge
        or seconds > 86400 or type(session.combatSources) ~= "table" then return end
    for _, source in ipairs(session.combatSources) do
        if S.Readable(source) then
            local rate = source.amountPerSecond
            if S.Readable(rate) and type(rate) == "number" and rate >= 0 and rate <= 1e8 then
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
    if not stats or S.Call(InCombatLockdown) then return end
    local types = Enum and Enum.DamageMeterType
    if not types then return end
    for id, sample in pairs(pending) do
        if GetTime() <= sample.expires then
            sample.run.activeRates = sample.run.activeRates or {}
            local row = rateRow(sample.run.activeRates, sample.bucket)
            local function include(kind, offset)
                readMeter(id, kind, function(source, rate, seconds)
                    if seconds > sample.duration + 1 then return end
                    local seen = sample.done[offset]
                    if S.Readable(source.isLocalPlayer) and source.isLocalPlayer and not seen.self then
                        addRate(row, offset, rate * seconds, seconds, 1)
                        if sample.scoreEligible then
                            addBuildRate(sample.run, S.me.key, sample.builds[S.me.key], offset, rate, seconds)
                        end
                        S.RecordInstanceFight(S.me.key, sample, offset, rate, seconds)
                        seen.self = true
                    end
                    local guid = source.sourceGUID
                    if not S.Readable(guid) or type(guid) ~= "string" then return end
                    local subject = sample.roster[guid]
                    if not subject or seen[subject] then return end
                    seen[subject] = true
                    S.RecordInstanceFight(subject, sample, offset, rate, seconds)
                    if sample.scoreEligible then
                        addBuildRate(sample.run, subject, sample.builds[subject], offset, rate, seconds)
                        if sample.run.groupClear then S.UpdateGroupClear(sample.run, subject) end
                    end
                end)
            end
            include(types.DamageDone, 1)
            include(types.HealingDone, 4)
        end
        if GetTime() > sample.expires then pending[id] = nil end
    end
end

local function refreshRun()
    if S.Refresh and S.openSubject == S.me.key then S.Refresh(S.me.key) end
end

local function refreshInstance(retries)
    if not stats then return end
    if not updateInstance() then
        if not instanceRetry and retries > 0 then
            instanceRetry = C_Timer.After(.25, function()
                instanceRetry = nil
                refreshInstance(retries - 1)
            end) or true
        end
        return
    end
    if run ~= meterContext then resetMeter() end
    refreshRun()
end

function S.ActiveInstance()
    if not run or (run.kind ~= "party" and run.kind ~= "raid") or instance() ~= run.key then return end
    return run.name, run.activeRates and run.activeRates[run.capacity]
end

local function queueSample(sample, id)
    if sample.queued[id] then return end
    sample.queued[id] = true
    pending[id] = {id = ("%d:%d"):format(sample.sequence, id), bucket = sample.bucket, map = sample.map,
        run = sample.run, duration = sample.duration, stamp = sample.stamp, expires = sample.expires,
        roster = sample.roster, builds = sample.builds, scoreEligible = sample.scoreEligible, done = {[1] = {}, [4] = {}}}
end

S.On("PLAYER_REGEN_DISABLED", function()
    if not stats then return end
    closing = nil
    refreshInstance(4)
    local bucket = combatBucket()
    if not bucket or instance() ~= run.key then return end
    if run.completed and multiWing[run.map] then nextWing() end
    if not baselineReady then baselineReady = discover() end
    if not baselineReady then return end
    local roster, units = S.GroupRoster(true)
    local builds = {[S.me.key] = S.CaptureBuild("player", S.me.key)}
    for guid, key in pairs(roster) do builds[key] = S.CaptureBuild(units[guid], key) end
    stats.fightSequence = (stats.fightSequence or 0) + 1
    fight = {bucket = bucket, map = run.key:match("^[^:]+:(.+)$"), run = run, started = GetTime(),
        sequence = stats.fightSequence, ids = {}, roster = roster, builds = builds,
        scoreEligible = not run.completed}
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
    if not observed[id] and run and instance() == run.key then
        if fight then fight.ids[id] = true
        elseif closing and GetTime() <= closing.discoverUntil then queueSample(closing, id) end
    end
    observed[id] = true
    if pending[id] then C_Timer.After(.1, finalize) end
end)

S.On("PLAYER_REGEN_ENABLED", function()
    if not stats then return end
    local sample = fight
    fight = nil
    if sample and run and instance() == run.key then
        discover(sample)
        local now = GetTime()
        local present = S.GroupRoster(true)
        for guid, key in pairs(sample.roster) do
            if present[guid] ~= key then sample.roster[guid] = nil end
        end
        sample.stamp, sample.duration, sample.expires = S.Now(), now - sample.started, now + 120
        sample.queued, sample.discoverUntil = {}, now + 3
        closing = sample
        for id in pairs(sample.ids) do queueSample(sample, id) end
        for _, delay in ipairs({.25, 1, 3, 10, 30, 120}) do
            C_Timer.After(delay, function()
                if closing == sample and run and instance() == run.key and GetTime() <= sample.discoverUntil then
                    discover(sample)
                    for id in pairs(sample.ids) do queueSample(sample, id) end
                end
                finalize()
            end)
        end
    else
        discover()
        finalize()
    end
    queueGear()
end)

for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA"}) do
    S.On(event, function() refreshInstance(12) end)
end

S.On("DAMAGE_METER_RESET", function()
    if not stats then return end
    observed, pending = {}, {}
    resetMeter()
end)

local loot = C_LootHistory
local waitingForItem = {}
local function freshBossLoot(encounter, drop)
    if not dungeonObjectives[encounter] or type(drop) ~= "table" or not S.Readable(drop.startTime)
        or type(drop.startTime) ~= "number" then return end
    local now = S.Call(loot.GetLootHistoryTime)
    if type(now) ~= "number" or now < drop.startTime or now - drop.startTime > 15000 then return end
    local previous = stats.dungeonLoot and stats.dungeonLoot[encounter]
    if previous == drop.startTime then return end
    refreshInstance(4)
    if not run or run.map ~= dungeonObjectives[encounter]
        or (run.lootSince and drop.startTime < run.lootSince) then return end
    stats.dungeonLoot = stats.dungeonLoot or {}
    stats.dungeonLoot[encounter] = drop.startTime
    completeObjective(encounter)
end

local function recordGearRoll(encounter, key)
    if not stats or not loot or not S.Readable(encounter) or not S.Readable(key)
        or type(encounter) ~= "number" or type(key) ~= "number" then return end
    local drop = S.Call(loot.GetSortedInfoForDrop, encounter, key)
    freshBossLoot(encounter, drop)
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

S.On("LFG_COMPLETION_REWARD", function()
    refreshInstance(4)
    local visit = run
    if not visit or visit.objectives then return end
    if mappedDungeons[visit.map] then
        C_Timer.After(2, function()
            if run ~= visit or visit.objectives then return end
            if not multiWing[visit.map] then
                for encounter, map in pairs(dungeonObjectives) do
                    if map == visit.map then completeObjective(encounter); return end
                end
            end
            complete("party")
        end)
    else
        complete("party")
    end
end)
S.On("BOSS_KILL", function(encounter)
    if not S.Readable(encounter) or not dungeonObjectives[encounter] then return end
    refreshInstance(4)
    completeObjective(encounter)
end)
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
    refreshInstance(4)
    if not run or not S.Readable(successful) or successful ~= 1
        or not S.Readable(encounterID) then return end
    if dungeonVisit(run.kind, run.map) and mappedDungeons[run.map] then
        completeObjective(encounterID)
        return
    end
    if run.kind == "raid" then
        raidCompletion = {key = run.key, expires = GetTime() + 10,
            participants = S.GroupRoster(true), stamp = S.Now()}
        S.Call(RequestRaidInfo)
        C_Timer.After(.5, verifyRaid)
        return
    end
    if run.kind ~= "party" then return end
    local journal = S.Call(C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap, run.map)
    if type(journal) ~= "number" or journal <= 0 then return end
    local previous
    if not S.Call(EJ_GetEncounterInfoByIndex, 1, journal) then
        previous = S.Call(EJ_GetCurrentInstance)
        S.Call(EJ_SelectInstance, journal)
    end
    local lastGameEncounter
    for index = 1, 40 do
        local name, _, _, _, _, _, gameEncounter = S.Call(EJ_GetEncounterInfoByIndex, index, journal)
        if not name then break end
        lastGameEncounter = gameEncounter
    end
    if previous and previous > 0 and previous ~= journal then S.Call(EJ_SelectInstance, previous) end
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

local function recoverDungeonClears()
    if stats.dungeonRecovery then return end
    local history = {}
    local backup = type(SocialCreditBackup) == "table" and SocialCreditBackup.version == 1
        and type(SocialCreditBackup.stats) == "table" and SocialCreditBackup.stats[S.me.key] or nil
    for _, source in ipairs({stats, backup}) do
        for identity in pairs(source.gearRolls and source.gearRolls.seen or {}) do
            local encounter, start = tostring(identity):match("^(%d+)~%d+~([%d.]+)~")
            encounter, start = tonumber(encounter), tonumber(start)
            if start and dungeonObjectives[encounter] then
                history[encounter] = history[encounter] or {}
                table.insert(history[encounter], start)
            end
        end
    end
    local total, brackets = 0, {}
    for encounter, starts in pairs(history) do
        table.sort(starts)
        local last, size = nil, dungeonSize(encounter)
        for _, start in ipairs(starts) do
            -- The loot clock is in milliseconds. Several item rolls can come from one kill.
            if not last or start - last > 90000 then
                total, brackets[size], last = total + 1, (brackets[size] or 0) + 1, start
            end
        end
    end
    if total > 0 then stats.dungeons = math.max(stats.dungeons or 0, total) end
    for size, count in pairs(brackets) do stats.runs[size] = math.max(stats.runs[size] or 0, count) end
    stats.dungeonRecovery = true
end

S.OnLevel60(function()
    stats = S.db.stats[S.me.key] or {rates = {}}
    S.db.stats[S.me.key] = stats
    if not stats.level60Since then
        stats.rates, stats.ratesSince, stats.level60Since = {}, S.Now(), S.Now()
        stats.runs, stats.raidRuns, stats.completedLocks, stats.run = {}, {}, {}, nil
        stats.gearRolls = nil
        stats.dungeons, stats.battlegrounds, stats.gear = nil, nil, nil
    end
    stats.rates, stats.runs = stats.rates or {}, stats.runs or {}
    stats.raidRuns, stats.completedLocks = stats.raidRuns or {}, stats.completedLocks or {}
    stats.explicitWords = stats.explicitWords or 0
    stats.gearRolls = stats.gearRolls or {sum = 0, count = 0, seen = {}}
    recoverDungeonClears()
    refreshInstance(12)
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
