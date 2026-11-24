local _, S = ...
local ownConfig, ownTree, ownName
local inspected, lastAttempt = {}, {}
local pending, requested, inspectionTimer
local liveRoles = {}
local INSPECT_AGE = 150

local function timestamp()
    return S.Now() * 1000 + math.floor(GetTime() % 1 * 1000)
end

local function validTree(id)
    return type(id) == "number" and id % 1 == 0 and id >= 1 and id <= 1000000
end

local function field(value, name)
    if S.Readable(value) and type(value) == "table" and S.Readable(value[name]) then return value[name] end
end

local function dominant(config)
    local api = C_Traits
    if not api or not config then return end
    local info = S.Call(api.GetConfigInfo, config)
    local trees = field(info, "treeIDs")
    if type(trees) ~= "table" then return end
    local best, name, most, tied
    for _, tree in ipairs(trees) do
        if not S.Readable(tree) or not validTree(tree) then return end
        local displays = S.Call(api.GetGroupDisplayInfoByTreeID, tree)
        if type(displays) ~= "table" or #displays == 0 then return end
        local ids, labels, seen = {}, {}, {}
        for _, display in ipairs(displays) do
            local id = field(display, "groupID")
            if not validTree(id) or labels[id] then return end
            ids[#ids + 1], labels[id] = id, field(display, "displayName") or ""
        end
        local groups = S.Call(api.GetGroupCurrencyInfo, config, ids)
        if type(groups) ~= "table" or #groups ~= #ids then return end
        for _, group in ipairs(groups) do
            local id = field(group, "traitNodeGroupID")
            local currencies = field(group, "currencyInfos")
            local spent = type(currencies) == "table" and field(currencies[1], "spent")
            if not validTree(id) or not labels[id] or seen[id] or type(spent) ~= "number"
                or spent % 1 ~= 0 or spent < 0 then return end
            seen[id] = true
            if not most or spent > most then
                best, name, most, tied = id, labels[id], spent, false
            elseif spent == most then tied = true end
        end
    end
    if most and most > 0 and not tied then return best, name end
    if most then return 0 end
end

local function context(key)
    local rows = S.db.talentContexts
    rows[key] = rows[key] or {roles = {}}
    return rows[key]
end

local function changed(key)
    S.InvalidateScores()
    if S.openSubject == key and S.Refresh then S.Refresh(key) end
end

local function mergeRole(data, tree, role, stamp)
    local old = data.roles[tree]
    if role and (not old or stamp > old.stamp) then
        data.roles[tree] = {role = role, stamp = stamp}
        return not old or old.role ~= role
    end
end

local function observe(key, tree, name, stamp, source, role, roleStamp)
    local data = context(key)
    local old = data[source]
    local updated = false
    if not old or stamp > old.stamp then
        data[source] = {tree = tree, name = name, stamp = stamp}
        updated = not old or old.tree ~= tree or old.name ~= name
    end
    if validTree(tree) and mergeRole(data, tree, role, roleStamp) then updated = true end
    if updated then changed(key) end
    return true
end

local function newest(data)
    local owner, witness = data.owner, data.witness
    if not owner or (witness and witness.stamp > owner.stamp) then return witness end
    return owner
end

local function assignedRole(unit)
    if S.Call(GetPartyAssignment, "maintank", unit) then return "T" end
    local role = S.Call(UnitGroupRolesAssigned, unit)
    if role == "TANK" then return "T" end
    if role == "DAMAGER" or role == "HEALER" then return "N" end
end

local function activeConfig()
    local api = C_SpecializationInfo
    local group = api and S.Call(api.GetActiveSpecGroup)
    return group and S.Call(api.GetCombatConfigIDForSpecGroup, group)
        or C_ClassTalents and S.Call(C_ClassTalents.GetActiveConfigID)
end

local function refreshOwner()
    if not S.Eligible(S.me and S.me.key) then return end
    local config = activeConfig()
    local staged = config and C_Traits and S.Call(C_Traits.ConfigHasStagedChanges, config)
    if staged == false or (config and C_Traits and not C_Traits.ConfigHasStagedChanges) then
        local tree, name = dominant(config)
        if tree ~= nil then
            ownTree, ownName = tree, name
        elseif ownConfig == config then
            return
        else
            ownTree, ownName = nil, nil
        end
    elseif not config then
        -- A temporarily unreadable config does not invalidate the last confirmed build.
        return
    elseif ownConfig ~= config then
        ownTree, ownName = nil, nil
    end
    ownConfig = config
    local data = context(S.me.key)
    local previous = data.owner
    local tree, stamp = ownTree or 0, timestamp()
    if previous then stamp = math.max(stamp, previous.stamp + 1) end
    observe(S.me.key, tree, ownName, stamp, "owner")
    if (not previous or previous.tree ~= tree) and S.PublishTalentContext then S.PublishTalentContext() end
end

function S.CurrentBuild(key)
    local data = key and S.db.talentContexts[key]
    local current = data and newest(data)
    if not current or not validTree(current.tree) then return end
    local tree = current.tree
    local last = data.roles[tree]
    local live = liveRoles[key]
    return tree, current.name ~= "" and current.name or nil, live or (last and last.role), not live and last ~= nil
end

function S.CaptureBuild(unit, key)
    local tree
    if unit == "player" then
        if ownConfig == activeConfig() then tree = ownTree end
    else
        local guid = S.Call(UnitGUID, unit)
        local record = guid and inspected[guid]
        local data = S.db.talentContexts[key]
        local owner = data and data.owner
        if record and record.key == key and GetTime() <= record.expires then
            tree = record.tree
            if owner and owner.stamp >= record.stamp then tree = owner.tree end
        elseif owner and timestamp() - owner.stamp <= INSPECT_AGE * 1000 then
            tree = owner.tree
        end
    end
    local role = assignedRole(unit)
    if not validTree(tree) or not role then return end
    local stamp = timestamp()
    if mergeRole(context(key), tree, role, stamp) then
        changed(key)
        if key == S.me.key and S.PublishTalentContext then S.PublishTalentContext() end
    end
    return tree .. ":" .. role, stamp
end

local function unitMap()
    local _, units = S.GroupRoster(false)
    return units or {}
end

local function updateRoles()
    if not S.Eligible(S.me and S.me.key) then return end
    local roles = {}
    local function add(unit, key)
        local role = assignedRole(unit)
        if not role then return end
        roles[key] = role
        S.CaptureBuild(unit, key)
    end
    local grouped = S.Call(IsInGroup) or (S.Call(GetNumSubgroupMembers) or 0) > 0 or S.Call(IsInRaid)
    if grouped then add("player", S.me.key) end
    for _, unit in pairs(unitMap()) do
        local id = S.Unit(unit)
        if id then add(unit, id.key) end
    end
    local previous = liveRoles
    liveRoles = roles
    for key, role in pairs(previous) do
        if role ~= roles[key] then changed(key) end
    end
    for key in pairs(roles) do
        if not previous[key] then changed(key) end
    end
end

local function inspectBusy()
    return (InspectFrame and InspectFrame:IsShown())
        or (PlayerSpellsFrame and PlayerSpellsFrame.IsInspecting and PlayerSpellsFrame:IsInspecting())
end

local function inspectNext()
    if not S.Eligible(S.me and S.me.key) or not NotifyInspect or not CanInspect or inspectBusy() then return end
    local now = GetTime()
    if pending and now < pending.untilTime then return end
    pending = nil
    local nextGUID, nextUnit, earliest
    for guid, unit in pairs(unitMap()) do
        local attempted = lastAttempt[guid] or -math.huge
        if now - attempted >= 90 and (not earliest or attempted < earliest)
            and S.Call(CanInspect, unit) and S.Call(UnitGUID, unit) == guid then
            nextGUID, nextUnit, earliest = guid, unit, attempted
        end
    end
    if not nextGUID then return end
    local id = S.Unit(nextUnit)
    if not id then return end
    lastAttempt[nextGUID] = now
    pending = {guid = nextGUID, key = id.key, untilTime = now + 7}
    requested = true
    S.Call(NotifyInspect, nextUnit)
    requested = nil
end

S.On("INSPECT_READY", function(guid)
    if not pending or not S.Readable(guid) or guid ~= pending.guid then return end
    local entry = pending
    pending = nil
    if GetTime() >= entry.untilTime or inspectBusy() then return end
    local unit = unitMap()[guid]
    local id = unit and S.Unit(unit)
    if not id or id.key ~= entry.key or S.Call(UnitGUID, unit) ~= guid then return end
    local config = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    local tree, name = dominant(config)
    if tree == nil then return end
    local stamp = timestamp()
    inspected[guid] = {key = id.key, tree = tree, stamp = stamp, expires = GetTime() + INSPECT_AGE}
    observe(id.key, tree, name, stamp, "witness")
    updateRoles()
end)

local function refresh()
    refreshOwner()
    updateRoles()
end

for _, event in ipairs({"ACTIVE_COMBAT_CONFIG_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED"}) do
    S.On(event, refresh)
end
S.On("GROUP_ROSTER_UPDATE", function()
    local units = unitMap()
    for guid in pairs(lastAttempt) do
        if not units[guid] then inspected[guid], lastAttempt[guid] = nil, nil end
    end
    updateRoles()
end)
S.On("PLAYER_ROLES_ASSIGNED", updateRoles)
S.On("ROLE_CHANGED_INFORM", updateRoles)
S.On("PARTY_ASSIGNMENT_UPDATE", updateRoles)
S.OnLevel60(function()
    if NotifyInspect and hooksecurefunc then
        hooksecurefunc("NotifyInspect", function() if not requested then pending = nil end end)
    end
    refresh()
    if not inspectionTimer then inspectionTimer = C_Timer.NewTicker(3, inspectNext) end
end)

function S.ExportTalentContext(key, owner)
    local data = S.db.talentContexts[key]
    local info = data and data[owner and "owner" or "witness"]
    if not info then return end
    local name = info.name or ""
    if #name > 64 or name:find("[~|%c]") then name = "" end
    local last = data.roles[info.tree]
    return table.concat({"1", info.tree, info.stamp, name, last and last.role or "",
        last and last.stamp or 0}, "~")
end

function S.ImportTalentContext(key, payload, owner)
    if not S.Eligible(key) or S.db.alts[key] then return end
    local tree, stamp, name, role, roleStamp = payload:match("^1~(%d+)~(%d+)~([^~]*)~([TN]?)~(%d+)$")
    tree, stamp, roleStamp = tonumber(tree), tonumber(stamp), tonumber(roleStamp)
    if not stamp or stamp < 1 or stamp > timestamp() + 60000 or roleStamp > timestamp() + 60000
        or (tree ~= 0 and not validTree(tree)) or #name > 64 or name:find("[|%c]")
        or (role ~= "" and (tree == 0 or roleStamp < 1)) then return end
    return observe(key, tree, name, stamp, owner and "owner" or "witness",
        role ~= "" and role or nil, roleStamp)
end
