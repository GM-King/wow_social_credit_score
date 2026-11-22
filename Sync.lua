local _, S = ...
local prefix = "SocialCredit2"
local peers, queue, fragments, pending = {}, {}, {}, {}
local requests, cursors, incoming, served = {}, {}, {}, {}
local messageID, timer, head, tail = 0, nil, 1, 0
local nextHello = 0
local maxPeers, maxQueue = 64, 256
local channelName
local groupRequests, groupCooldowns, lookups = {}, {}, {}
local lookupTimer
local talentPublish

local function blocked()
    return InCombatLockdown() or IsInInstance()
        or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown())
end

local function pump()
    timer = nil
    if head > tail then head, tail = 1, 0; return end
    if blocked() then timer = C_Timer.NewTimer(2, pump); return end
    local item = queue[head]
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, item.body, item.route, item.address)
    local codes = Enum and Enum.SendAddonMessageResult
    local throttled = ok and codes and S.Readable(result)
        and (result == codes.AddonMessageThrottle or (codes.ChannelThrottle and result == codes.ChannelThrottle))
    if throttled and item.attempts < 3 then
        item.attempts = item.attempts + 1
        timer = C_Timer.NewTimer(item.attempts, pump)
        return
    end
    queue[head], head = nil, head + 1
    timer = C_Timer.NewTimer(0.16, pump)
end

local function send(body, route, address)
    local chunks, offset = {}, 1
    while offset <= #body do
        local last = math.min(offset + 199, #body)
        local nextByte = body:byte(last + 1)
        while nextByte and nextByte >= 128 and nextByte <= 191 do
            last = last - 1
            nextByte = body:byte(last + 1)
        end
        chunks[#chunks + 1] = body:sub(offset, last)
        offset = last + 1
    end
    local parts = #chunks
    if parts > 8 or tail - head + parts > maxQueue then return end
    messageID = (messageID + 1) % 1000000
    for i, chunk in ipairs(chunks) do
        local packet = ("%d:%d:%d:%s"):format(messageID, i, parts, chunk)
        tail = tail + 1
        queue[tail] = {body = packet, route = route, address = address, attempts = 0}
    end
    if not timer then timer = C_Timer.NewTimer(0, pump) end
    return true
end

local function whisper(key, body, excluded)
    if key == excluded or S.db.alts[key] then return end
    local peer = peers[key]
    local address = peer and peer.address
    if not address then
        local _, _, target = S.Identity(S.db.names[key])
        address = target
    end
    if address then return send(body, "WHISPER", address) end
end

local function reviewPayload(record)
    return table.concat({record.subject, record.subjectName, record.author, record.name,
        record.revision, record.time, record.deleted and "-" or record.stars, record.text or ""}, "~")
end

local function deliver(key, record, relayed)
    if not record.level60 then return end
    return whisper(key, (relayed and "W~" or "R~") .. reviewPayload(record), record.subject)
end

local function guildMember(key)
    local _, guildmates = S.ReviewRelationships()
    return IsInGuild() and guildmates[key]
end

local function deliverGuildReview(key, subject)
    local record = (S.db.reviews[subject] or {})[S.me.key]
    local profile = S.db.profiles[subject]
    if not record or not record.level60 or not S.Eligible(subject)
        or not profile.class or not profile.class:match("^[A-Z]+$") then return end
    local acks = S.db.deliveries[S.Fingerprint(record)]
    if acks and acks[key] then return end
    return whisper(key, "B~" .. profile.class .. "~" .. reviewPayload(record), subject)
end

local function catchUpGuild(key)
    local sent = 0
    for subject in pairs(S.db.zeroSubjects) do
        if sent == 2 or tail - head >= 48 then break end
        if deliverGuildReview(key, subject) then sent = sent + 1 end
    end
end

local function backupToPeer(key, cap)
    if S.db.alts[key] then return end
    for subject, author in pairs(S.db.authored) do
        local record = (S.db.reviews[subject] or {})[author]
        if author == S.me.key and record and record.level60 and subject ~= key then
            -- Only acknowledged direct copies count toward the replication target.
            local acks = S.db.deliveries[S.Fingerprint(record)] or {}
            local count = 0
            for _ in pairs(acks) do count = count + 1 end
            local retractions = S.db.reviewRetractions[subject]
            if not acks[key] and (count < 3 or (retractions and retractions[key]))
                and deliver(key, record, false) then
                cap = cap - 1
                if cap == 0 then return end
            end
        end
    end
end

function S.Publish(record)
    local subject = record.subject
    local retractions = S.db.reviewRetractions[subject] or {}
    local beginning = subject .. "~" .. record.author .. "~"
    for fingerprint in pairs(S.db.deliveries) do
        if fingerprint:sub(1, #beginning) == beginning then
            if record.deleted then
                for peer in pairs(S.db.deliveries[fingerprint]) do retractions[peer] = true end
            end
            S.db.deliveries[fingerprint] = nil
        end
    end
    if next(retractions) then S.db.reviewRetractions[subject] = retractions end
    if S.db.zeroSubjects[record.subject] then
        for key, peer in pairs(peers) do
            if tail - head >= 48 then break end
            if peer.guildSync and GetTime() - peer.guildSync < 130 and guildMember(key) then
                deliverGuildReview(key, record.subject)
            end
        end
    end
    local count = 0
    for _, retry in ipairs({true, false}) do
        for key in pairs(peers) do
            if (retractions[key] == true) == retry and deliver(key, record, false) then count = count + 1 end
            if count == 3 then return end
        end
    end
end

local function introduction(kind)
    local profile = S.db.profiles[S.me.key]
    local guild = profile.guild
    if guild and (#guild > 120 or guild:find("[~|%c]")) then guild = nil end
    return table.concat({kind, S.faction, "60", profile.class or "", guild == nil and "?" or guild}, "~")
end

local function hello()
    if blocked() or GetTime() < nextHello then return end
    nextHello = GetTime() + 15
    local greeting = introduction("H")
    local talent = S.ExportTalentContext(S.me.key, true)
    local function advertise(route, address)
        send(greeting, route, address)
        if talent then send("F~" .. talent, route, address) end
    end
    if IsInGuild() then
        advertise("GUILD")
        send("Z~", "GUILD")
    end
    if IsInRaid() then advertise("RAID")
    elseif IsInGroup() then advertise("PARTY") end
    local channel = channelName and S.Call(GetChannelName, channelName)
    if type(channel) == "number" and channel > 0 then advertise("CHANNEL", tostring(channel)) end
end

function S.PublishTalentContext()
    if talentPublish then return end
    talentPublish = C_Timer.NewTimer(5, function()
        talentPublish = nil
        nextHello = 0
        hello()
    end)
end

local function request(key, subject, cursor)
    if whisper(key, table.concat({"Q", subject, cursor or ""}, "~")) then
        requests[key .. "~" .. subject] = GetTime() + 180
    end
end

local function requestGroup(peer, subject, cursor)
    if whisper(peer, table.concat({"X", subject, cursor or ""}, "~")) then
        groupRequests[peer .. "~" .. subject] = GetTime() + 180
        return true
    end
end

local function fresh(key, subject)
    local requestKey = key .. "~" .. subject
    if (cursors[requestKey] or 0) > GetTime() then return end
    if not peers[key] then whisper(key, introduction("H")) end
    request(key, subject)
    cursors[requestKey] = GetTime() + 30
    if key == subject and (groupCooldowns[requestKey] or 0) <= GetTime() and requestGroup(key, subject) then
        groupCooldowns[requestKey] = GetTime() + 180
    end
end

local function flushLookups()
    lookupTimer = nil
    local now, sent = GetTime(), 0
    for subject, lookup in pairs(lookups) do
        if lookup.expires <= now then lookups[subject] = nil end
    end
    if not next(lookups) then return end
    if blocked() then
        lookupTimer = C_Timer.NewTimer(5, flushLookups)
        return
    end
    for _, priority in ipairs({true, false}) do
        for subject, lookup in pairs(lookups) do
            if lookup.priority == priority and not S.db.alts[subject] then
                for peer in pairs(peers) do
                    if sent == 4 or lookup.sent == (priority and 8 or 4) then break end
                    local key = peer .. "~" .. subject
                    if peer ~= subject and (groupCooldowns[key] or 0) <= now
                        and requestGroup(peer, subject) then
                        groupCooldowns[key] = now + 180
                        sent, lookup.sent = sent + 1, lookup.sent + 1
                    end
                end
            end
        end
    end
    lookupTimer = C_Timer.NewTimer(sent == 4 and 1 or 5, flushLookups)
end

function S.LookupGroupProfile(subject, priority)
    if not S.me or not subject or S.db.alts[subject] then return end
    if not lookups[subject] then
        local count = 0
        for _ in pairs(lookups) do count = count + 1 end
        if count >= 128 and not priority then return end
        lookups[subject] = {expires = GetTime() + 90, sent = 0, priority = false}
    end
    if priority then lookups[subject].priority = true end
    if not lookupTimer then lookupTimer = C_Timer.NewTimer(.25, flushLookups) end
    return true
end

function S.FindProfile(name)
    local key, _, address = S.Identity(name)
    if not key or S.db.alts[key] then return end
    S.LookupGroupProfile(key, true)
    local requestKey = "profile~" .. key
    if (cursors[requestKey] or 0) <= GetTime()
        and send(introduction("H"), "WHISPER", address) then
        cursors[requestKey] = GetTime() + 30
    end
end

function S.Query(subject)
    if not S.Eligible(subject) or S.db.alts[subject] then return end
    hello()
    S.LookupGroupProfile(subject, true)
    fresh(subject, subject)
    local candidates = {}
    for key in pairs(peers) do if key ~= subject then table.insert(candidates, key) end end
    table.sort(candidates, function(a, b)
        local first, second = peers[a].queried or 0, peers[b].queried or 0
        if first == second then return a < b end
        return first < second
    end)
    for index = 1, math.min(8, #candidates) do
        local key = candidates[index]
        fresh(key, subject)
        peers[key].queried = GetTime()
    end
end

local function answerGroup(peer, subject, cursor)
    if peer == subject or S.db.alts[subject] then return end
    local profile, ids, rows = S.GroupReports(subject, cursor)
    if not profile then return end
    local buildRows = S.BuildReports(subject)
    local guild = profile.guild
    if not guild or #guild > 120 or guild:find("[~|%c]") then guild = "?" end
    if not whisper(peer, table.concat({"M", subject, profile.name, profile.class, profile.faction, guild}, "~")) then return end
    local talent = S.ExportTalentContext(subject, false)
    if talent and cursor == "" then whisper(peer, "D~" .. subject .. "~" .. talent) end
    for i = 1, math.min(#ids, 6) do
        local row = rows[ids[i]]
        local values = {"T", subject, row.map, row.token, row.size, row.stamp, row.revision}
        for _, n in ipairs(row.rates) do values[#values + 1] = ("%.6f"):format(n) end
        if not whisper(peer, table.concat(values, "~")) then return end
        local typed = buildRows and buildRows[ids[i]]
        if typed and not whisper(peer, "U~" .. subject .. "~" .. S.ExportBuildClear(typed)) then return end
    end
    if #ids > 6 then whisper(peer, "V~" .. subject .. "~" .. ids[6]) end
end

local function answerOwnerCombat(peer, subject, cursor)
    local rows = S.BuildReports(subject)
    local ids = {}
    for id in pairs(rows or {}) do
        if id > cursor then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for i = 1, math.min(#ids, 6) do
        if not whisper(peer, "U~" .. subject .. "~" .. S.ExportBuildClear(rows[ids[i]])) then return end
    end
    if #ids > 6 then whisper(peer, "V~" .. subject .. "~" .. ids[6]) end
end

local function answer(key, subject, cursor)
    if key == subject then return end
    if subject == S.me.key then
        local stats = S.ExportStats(true)
        if stats and whisper(key, "J~" .. stats) then
            whisper(key, "G~" .. S.ExportReviewsGiven())
            whisper(key, "K~" .. S.ExportNeedGreed())
            local talent = S.ExportTalentContext(subject, true)
            if talent then whisper(key, "F~" .. talent) end
        end
        return
    end
    if S.db.alts[subject] then return end
    local rows = S.db.reviews[subject] or {}
    local authors = {}
    for author, record in pairs(rows) do
        if record.level60 and record.direct and author > cursor then table.insert(authors, author) end
    end
    table.sort(authors)
    local last
    for i = 1, math.min(#authors, 8) do
        if not deliver(key, rows[authors[i]], authors[i] ~= S.me.key) then return end
        last = authors[i]
    end
    whisper(key, "E~" .. subject .. "~" .. (#authors > 8 and last or ""))
end

local function review(kind, body, key, class)
    local subject, subjectName, author, name, revision, stamp, stars, comment =
        body:match("^([^~]+)~([^~]+)~([^~]+)~([^~]+)~(%d+)~(%d+)~([^~]+)~(.*)$")
    local deleted = stars == "-" and comment == ""
    if not stars or not (deleted or stars:match("^%d$") or stars:match("^%d%.5$")) then return end
    local record = {subject = subject, subjectName = subjectName, author = author, name = name,
        revision = tonumber(revision), time = tonumber(stamp), stars = tonumber(stars), text = comment, level60 = true}
    if deleted then record.deleted, record.text = true, nil end
    if not S.ValidRecord(record) or S.db.alts[subject] or key == subject then return end
    if kind == "R" then
        if author ~= key then return end
        local accepted = S.Merge(record, true)
        if accepted and accepted.revision == record.revision then
            if class and not S.db.profiles[subject] then
                S.Remember({key = subject, name = subjectName, class = class, faction = S.faction, level = 60})
                if S.OpenDiscoveredProfile then S.OpenDiscoveredProfile(subject) end
            end
            whisper(key, "A~" .. subject .. "~" .. revision, subject)
        end
    elseif author ~= key and (requests[key .. "~" .. subject] or 0) >= GetTime() then
        local fingerprint = S.Fingerprint(record)
        local candidate = pending[fingerprint]
        if not candidate then
            candidate = {key = key}
            pending[fingerprint] = candidate
            C_Timer.After(180, function()
                if pending[fingerprint] == candidate then pending[fingerprint] = nil end
            end)
        elseif candidate.key ~= key then
            pending[fingerprint] = nil
            S.Merge(record, false)
        end
    end
end

local function receive(body, route, key, address)
    local kind, data = body:match("^([A-Z])~(.*)$")
    if kind == "H" or kind == "I" then
        local faction, class, guild = data:match("^([^~]+)~60~([A-Z]+)~([^~]*)$")
        if faction ~= S.faction or not class or #class > 24 or #guild > 120 or guild:find("[|%c]") then return end
        local target = S.Unit("target")
        if target and target.key == key and target.level and target.level > 0 and target.level ~= 60 then return end
        local _, display = S.Identity(address)
        S.Remember({key = key, level = 60, class = class, faction = faction,
            name = display, guild = guild ~= "?" and guild or nil})
        local new = not peers[key]
        if new then
            local count, oldest = 0, key
            for other, peer in pairs(peers) do
                count = count + 1
                if oldest == key or peer.seen < peers[oldest].seen then oldest = other end
            end
            if count >= maxPeers then peers[oldest] = nil end
        end
        peers[key] = peers[key] or {}
        peers[key].address, peers[key].seen = address, GetTime()
        if S.OpenDiscoveredProfile then S.OpenDiscoveredProfile(key) end
        if kind == "H" and (new or route == "WHISPER") then whisper(key, introduction("I")) end
        if new then fresh(key, key) end
        if S.Refresh then S.Refresh(S.openSubject) end
        backupToPeer(key, 3)
        if new and S.openSubject then fresh(key, S.openSubject) end
        return
    end
    if kind == "Z" and data == "" and route == "GUILD" and peers[key] and guildMember(key) then
        peers[key].guildSync = GetTime()
        local requestKey = "guild~" .. key
        if (served[requestKey] or 0) <= GetTime() then
            served[requestKey] = GetTime() + 12
            catchUpGuild(key)
        end
        return
    end
    if kind == "F" and peers[key] then S.ImportTalentContext(key, data, true); return end
    if route ~= "WHISPER" or not peers[key] then return end
    if kind == "B" and guildMember(key) then
        local class, record = data:match("^([A-Z]+)~(.*)$")
        if class and #class <= 24 then review("R", record, key, class) end
        return
    end
    if kind == "X" or kind == "M" or kind == "T" or kind == "V" or kind == "U" or kind == "D" then
        local subject, value = data:match("^([^~]+)~(.*)$")
        if not subject or S.Identity(subject) ~= subject
            or (S.db.alts[subject] and (kind ~= "X" or subject ~= S.me.key)) then return end
        if subject == key and kind ~= "U" and kind ~= "V" then return end
        local requestKey = key .. "~" .. subject
        local cursor = #value <= 64 and value:match("^%d+:%d+:[%d:]+$")
        if kind == "X" and (value == "" or cursor) then
            local servedKey = "X~" .. requestKey .. "~" .. value
            if (served[servedKey] or 0) > GetTime() then return end
            served[servedKey] = GetTime() + 10
            if subject == S.me.key then answerOwnerCombat(key, subject, value)
            else answerGroup(key, subject, value) end
        elseif (groupRequests[requestKey] or -1) >= GetTime() then
            if kind == "M" then S.ImportGroupProfile(subject, value)
            elseif kind == "T" then S.ImportGroupClear(subject, key, value)
            elseif kind == "D" then S.ImportTalentContext(subject, value, false)
            elseif kind == "U" then S.ImportBuildClear(subject, key, value)
            elseif kind == "V" and cursor then requestGroup(key, subject, value) end
        end
        return
    end
    if kind == "R" or kind == "W" then review(kind, data, key); return end
    if kind == "G" or kind == "J" or kind == "K" then
        local import = kind == "J" and S.ImportStats or kind == "K" and S.ImportNeedGreed or S.ImportReviewsGiven
        if (requests[key .. "~" .. key] or 0) >= GetTime() and import(key, data, kind == "J") then
            S.db.synced[key] = S.Now()
            S.Refresh(S.openSubject)
        end
        return
    end
    local subject, value = data:match("^([^~]+)~([^~]*)$")
    if not subject or S.Identity(subject) ~= subject then return end
    if kind == "Q" and (#value == 0 or S.Identity(value) == value) then
        local requestKey = key .. "~" .. subject .. "~" .. value
        if served[requestKey] and served[requestKey] > GetTime() then return end
        served[requestKey] = GetTime() + 10
        answer(key, subject, value)
    elseif kind == "E" and (requests[key .. "~" .. subject] or 0) >= GetTime()
        and not S.db.alts[subject] then
        S.db.synced[subject] = S.Now()
        S.Refresh(subject)
        if value ~= "" and S.Identity(value) == value then request(key, subject, value) end
    elseif kind == "A" and key ~= subject then
        local record = (S.db.reviews[subject] or {})[S.me.key]
        if record and record.revision == tonumber(value) then
            local fingerprint = S.Fingerprint(record)
            S.db.deliveries[fingerprint] = S.db.deliveries[fingerprint] or {}
            S.db.deliveries[fingerprint][key] = true
            local retractions = S.db.reviewRetractions[subject]
            if retractions then retractions[key] = nil end
        end
    end
end

S.On("CHAT_MSG_ADDON", function(tag, packet, route, sender)
    if not S.me or not S.Readable(tag) or tag ~= prefix or not S.Readable(packet)
        or not S.Readable(route) or blocked() then return end
    local key, _, address = S.Identity(sender)
    if not key or S.db.alts[key] or type(packet) ~= "string" or #packet > 220 then return end
    local now = GetTime()
    local rate = incoming[key]
    if not rate or now - rate.start >= 10 then
        rate = {start = now, count = 0}
        incoming[key] = rate
        C_Timer.After(10, function() if incoming[key] == rate then incoming[key] = nil end end)
    end
    if rate.count >= 80 then return end
    rate.count = rate.count + 1
    local id, index, size, part = packet:match("^(%d+):(%d):(%d):(.*)$")
    index, size = tonumber(index), tonumber(size)
    if not id or #id > 6 or index < 1 or index > size or size > 8 then return end
    if size == 1 then receive(part, route, key, address); return end
    if route ~= "WHISPER" or not peers[key] then return end
    local fragmentKey = key .. ":" .. id
    local assembly = fragments[fragmentKey]
    if not assembly then
        assembly = {size = size, count = 0, parts = {}}
        fragments[fragmentKey] = assembly
        C_Timer.After(25, function()
            if fragments[fragmentKey] == assembly then fragments[fragmentKey] = nil end
        end)
    end
    if size ~= assembly.size or assembly.parts[index] then return end
    assembly.parts[index] = part
    assembly.count = assembly.count + 1
    if assembly.count == size then
        fragments[fragmentKey] = nil
        receive(table.concat(assembly.parts), route, key, address)
    end
end)

S.OnActive(function()
    if not S.me or not C_ChatInfo then return end
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    channelName = "SocialCredit" .. S.faction
    local function discover()
        if blocked() then return end
        if JoinTemporaryChannel and S.Call(GetChannelName, channelName) == 0 then
            S.Call(JoinTemporaryChannel, channelName)
        end
        hello()
        local recent = {}
        for key, peer in pairs(peers) do
            backupToPeer(key, 2)
            recent[#recent + 1] = key
        end
        table.sort(recent, function(a, b) return (peers[a].statsAt or 0) < (peers[b].statsAt or 0) end)
        for i = 1, math.min(4, #recent) do
            local key = recent[i]
            fresh(key, key)
            peers[key].statsAt = GetTime()
        end
        if S.openSubject then S.Query(S.openSubject) end
        for key, expires in pairs(requests) do if expires < GetTime() then requests[key] = nil end end
        for key, expires in pairs(cursors) do if expires < GetTime() then cursors[key] = nil end end
        for key, expires in pairs(served) do if expires < GetTime() then served[key] = nil end end
        for key, expires in pairs(groupRequests) do if expires < GetTime() then groupRequests[key] = nil end end
        for key, expires in pairs(groupCooldowns) do if expires < GetTime() then groupCooldowns[key] = nil end end
    end
    C_Timer.After(3, discover)
    C_Timer.NewTicker(60, discover)
end)

S.On("GROUP_ROSTER_UPDATE", function() if S.me then hello() end end)
S.On("PLAYER_GUILD_UPDATE", function(unit)
    if S.me and S.Readable(unit) and (not unit or unit == "player") then
        nextHello = 0
        hello()
    end
end)
S.On("PLAYER_REGEN_ENABLED", function() if S.me then hello() end end)
S.On("PLAYER_ENTERING_WORLD", function()
    if S.me then
        hello()
        if S.openSubject then S.Query(S.openSubject) end
    end
end)

S.On("PLAYER_GUILD_UPDATE", function()
    if not S.me then return end
    local profile = S.Unit("player", true)
    if profile then
        profile.level = 60
        S.Remember(profile)
        nextHello = 0
        hello()
    end
end)
