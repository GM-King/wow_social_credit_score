local _, S = ...
local requested, nextQuery
local recent = {}
local resultPatterns = {}

local function classToken(class, label)
    if S.Readable(class) and type(class) == "string" and class:match("^[A-Z]+$") then return class end
    if not S.Readable(label) or type(label) ~= "string" then return end
    local best, token = 0
    local function find(names)
        for id, name in pairs(names or {}) do
            if #name > best and (label == name or label:sub(-#name - 1) == " " .. name) then
                best, token = #name, id
            end
        end
    end
    find(LOCALIZED_CLASS_NAMES_MALE)
    find(LOCALIZED_CLASS_NAMES_FEMALE)
    return token
end

local function profileFor(name, level, guild, class, label)
    local key, display = S.Identity(name)
    if not key or S.db.alts[key] or not S.Readable(level) or type(level) ~= "number"
        or level % 1 ~= 0 or level < 1 or level > 60 then return end
    local old = S.db.profiles[key]
    if old and (old.faction ~= S.faction or (old.level and old.level > level)) then return end
    if not S.Readable(guild) or type(guild) ~= "string" or guild:find("[%c|]") then guild = nil end
    return {key = key, name = display, level = level, faction = S.faction,
        class = classToken(class, label), guild = guild}
end

function S.FindWhoProfile(key)
    local old = S.db.profiles[key]
    if S.db.alts[key] or (old and old.faction ~= S.faction) then return end
    local list = C_FriendList
    if list then
        for index = 1, S.Call(list.GetNumWhoResults) or 0 do
            local row = S.Call(list.GetWhoInfo, index)
            if type(row) == "table" and S.Identity(row.fullName) == key then
                local profile = profileFor(row.fullName, row.level, row.fullGuildName, row.filename, row.classStr)
                if profile then return profile end
            end
        end
    end
    local entry = recent[key]
    if entry and entry.profile.faction == S.faction and entry.expires >= GetTime()
        and (not old or not old.level or entry.profile.level >= old.level) then return S.Copy(entry.profile) end
end

local function apply(profile)
    if not profile then return end
    S.Remember(profile)
    if S.OpenDiscoveredProfile then S.OpenDiscoveredProfile(profile.key) end
end

S.On("WHO_LIST_UPDATE", function()
    if S.me and requested then apply(S.FindWhoProfile(requested)) end
end)

local function decodeResult(message, format)
    if type(format) ~= "string" then return end
    -- Global strings can reorder placeholders in localized clients.
    local compiled = resultPatterns[format]
    if not compiled then
        local parts, fields, offset = {"^"}, {}, 1
        local function literal(value) return (value:gsub("(%W)", "%%%1")) end
        while true do
            local first, last, position, kind = format:find("%%([%d$]*)([sd])", offset)
            if not first then break end
            parts[#parts + 1] = literal(format:sub(offset, first - 1))
            parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
            fields[#fields + 1] = tonumber(position:match("^([0-9]+)%$$")) or #fields + 1
            offset = last + 1
        end
        parts[#parts + 1] = literal(format:sub(offset)) .. "$"
        compiled = {pattern = table.concat(parts), fields = fields}
        resultPatterns[format] = compiled
    end
    local captures = {message:match(compiled.pattern)}
    if #captures < 2 then return end
    local values = {}
    for i, field in ipairs(compiled.fields) do values[field] = captures[i] end
    return values
end

S.On("CHAT_MSG_SYSTEM", function(message)
    if not S.me or not S.Readable(message) or type(message) ~= "string" then return end
    local values = decodeResult(message, WHO_LIST_GUILD_FORMAT)
    local guild = values and values[5]
    values = values or decodeResult(message, WHO_LIST_FORMAT)
    if not values or not values[1] or not values[2] then return end
    local name = values[1]:match("|Hplayer:([^:|]+)") or values[1]
    local profile = profileFor(name, tonumber(values[2]), guild or "", nil, values[4])
    if not profile then return end
    local now = GetTime()
    for key, entry in pairs(recent) do if entry.expires < now then recent[key] = nil end end
    recent[profile.key] = {profile = profile, expires = now + 90}
    if profile.key == requested then apply(S.Copy(profile)) end
end)

function S.RequestWhoProfile(key, name)
    requested = key
    local send = C_FriendList and C_FriendList.SendWho
    if not send or (nextQuery or 0) > GetTime() or name:find('["\\]') then return false end
    nextQuery = GetTime() + 10
    -- SendWho requires a hardware event. This is called directly by the profile action.
    return pcall(send, 'n-"' .. name .. '"')
end



local whoScrollBox, whoClick
local hookedRows = setmetatable({}, {__mode = "k"})

local function rowProfile(row)
    if not S.me then return end
    local data = S.Call(row.GetElementData, row)
    local index = data
    if type(data) == "table" then
        index = S.Readable(data.whoIndex) and data.whoIndex or nil
        if index == nil then index = data.index end
        local info = S.Readable(data.info) and type(data.info) == "table" and data.info or data
        local profile = profileFor(info.fullName, info.level, info.fullGuildName, info.filename, info.classStr)
        if profile then return profile end
        local key = S.Identity(info.fullName)
        if key then return S.FindWhoProfile(key) end
    end
    -- Stock Who rows show the character name even if the element carries only an index.
    local label = row.Name
    local text = label and S.Call(label.GetText, label)
    if type(text) == "string" then
        local key = S.Identity((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        if key then return S.FindWhoProfile(key) end
    end
    if index == nil then index = row.whoIndex end
    if not S.Readable(index) or type(index) ~= "number" or not C_FriendList then return end
    local info = S.Call(C_FriendList.GetWhoInfo, index)
    if type(info) == "table" then
        return profileFor(info.fullName, info.level, info.fullGuildName, info.filename, info.classStr)
    end
end

local function addProfileAction(root, profile)
    root:CreateButton("Open SCS", function()
        S.Remember(profile)
        S.OpenNamedProfile(profile.name)
    end)
end

local function attachWhoRow(row)
    if not row or not row.HookScript or hookedRows[row] then return end
    hookedRows[row] = true
    row:HookScript("OnMouseDown", function(self, button)
        if button ~= "RightButton" then return end
        local profile = rowProfile(self)
        whoClick = profile and {row = self, profile = profile}
    end)
    row:HookScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local click = whoClick
        if not click or click.row ~= self then return end
        -- Let a Blizzard unit menu created by this click get the action first.
        C_Timer.After(0, function()
            if whoClick ~= click then return end
            whoClick = nil
            if click.added or not MenuUtil or not MenuUtil.CreateContextMenu then return end
            local current = rowProfile(self)
            if current and current.key == click.profile.key then
                MenuUtil.CreateContextMenu(self, function(_, root) addProfileAction(root, current) end)
            end
        end)
    end)
end

local function attachWhoList()
    local scrollBox = LFGWhoListFrame and LFGWhoListFrame.ScrollBox
    if not scrollBox or scrollBox == whoScrollBox or not ScrollUtil or not ScrollUtil.AddInitializedFrameCallback then return end
    whoScrollBox = scrollBox
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, row) attachWhoRow(row) end, S)
    if scrollBox.ForEachFrame then scrollBox:ForEachFrame(attachWhoRow) end
end

S.On("PLAYER_LOGIN", function()
    attachWhoList()
    if not Menu or not Menu.ModifyMenu then return end
    for _, tag in ipairs({"MENU_UNIT_FRIEND", "MENU_UNIT_FRIEND_OFFLINE", "MENU_UNIT_WHO"}) do
        Menu.ModifyMenu(tag, function(_, root, context)
            local click = whoClick
            if not click or click.added or not context or context.chatFrame
                or S.Identity(context.name) ~= click.profile.key then return end
            click.added = true
            root:CreateDivider()
            addProfileAction(root, click.profile)
        end)
    end
end)

S.On("ADDON_LOADED", function(name)
    if name == "Blizzard_GroupFinder_VanillaStyle" then attachWhoList() end
end)
S.On("WHO_LIST_UPDATE", attachWhoList)

