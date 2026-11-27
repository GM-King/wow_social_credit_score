"""Offline integration checks. Run with Python 3 and lupa (Lua 5.1)."""
import sys
from pathlib import Path

ADDON = Path(__file__).resolve().parents[1]
local_runtime = ADDON.parent / "PetMaxxing" / ".test-runtime"
if local_runtime.is_dir():
    sys.path.insert(0, str(local_runtime))
from lupa.lua51 import LuaRuntime

MOCK = """
state = {}
serial = 0
clock = 1
timers = {}
outbox = {}
SlashCmdList = {}
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, name, _, data)
    popup = {which = which, name = name, data = data}
    return popup
end
function StaticPopup_Hide(which)
    if popup and popup.which == which then popup = nil end
end
Menu = {ModifyMenu = function(tag, callback)
    local previous = menus[tag]
    menus[tag] = function(...)
        if previous then previous(...) end
        callback(...)
    end
end}
menus = {}
ChatFrameUtil = {AddSenderNameFilter = function(fn) markSender = fn end}
date = os.date
level, targetLevel = 60, 60
function UnitLevel(unit) return unit == "player" and level or targetLevel end
function UnitClass() return "Warrior", "WARRIOR" end
function GetGuildInfo() return "Example Guild" end
function UnitFactionGroup(unit) return unit == "enemy" and "Alliance" or "Horde" end
function UnitIsPlayer(unit) return unit ~= "npc" end
function UnitName(unit)
    if unit == "player" then return character end
    if unit == "target" or unit == "enemy" then return "Test Subject" end
end
UnitFullName = UnitName
function GetTime() return clock end
function GetServerTime() return 1770000000 + math.floor(clock) end
function GetNormalizedRealmName() return "Layer" end
function InCombatLockdown() return false end
function IsInInstance() return false end
function IsInGuild() return true end
function IsInGroup() return false end
function IsInRaid() return false end
Enum = {SendAddonMessageResult = {AddonMessageThrottle = 3}}
Enum.DamageMeterType = {DamageDone = 0, HealingDone = 1}
meterRows, meterList = {}, {}
C_DamageMeter = {
    GetAvailableCombatSessions = function() return meterList end,
    GetCombatSessionFromID = function(id, kind)
        local row = meterRows[id]
        if not row then return end
        return {durationSeconds = row.seconds, combatSources = {
            {isLocalPlayer = false, amountPerSecond = 9999},
            {isLocalPlayer = true, totalAmount = 1, amountPerSecond = row[kind]}}}
    end,
}
function meterSample(id, seconds, damage, healing)
    meterRows[id] = {seconds = seconds, [0] = damage, [1] = healing}
    table.insert(meterList, {sessionID = id})
    emit("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, id)
end
function GetInventoryItemID(_, slot) return slot == 1 and 123 end
C_Item = {GetItemInfo = function() return "Test helm", "test", 4, 65, nil, nil, nil, nil, "INVTYPE_HEAD" end}
C_Item.GetItemInfoInstant = function(link) return 17, nil, nil, link == "item:17" and "INVTYPE_HEAD" or "" end
Enum.EncounterLootDropRollState = {NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, Pass = 5}
lootRows = {}
C_LootHistory = {GetSortedInfoForDrop = function(_, key) return lootRows[key] end}
function lootRoll(key, self, result, choice, link, won)
    lootRows[key] = {startTime = 500, itemHyperlink = link,
        rollInfos = {{isSelf = self, roll = result, state = choice, isWinner = won}}}
    emit("LOOT_HISTORY_UPDATE_DROP", 12, key)
end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(tag, packet, route, to)
        table.insert(outbox, {tag, packet, route, to})
        return 0
    end
}
local function noop() end
local methods = setmetatable({
    SetScript = function(self, script, fn) self[script] = fn end,
    GetName = function(self) return self.name end,
    GetFrameLevel = function() return 5 end,
    GetWidth = function() return 1024 end,
    GetHeight = function() return 768 end,
    GetVerticalScroll = function() return 0 end,
    GetText = function(self) return self.text or "" end,
    SetText = function(self, value) self.text = value end,
    SetPoint = function(self, ...) self.point = {...} end,
    SetColorTexture = function(self, ...) self.color = {...} end,
    SetShown = function(self, value) self.shown = value end,
    SetTexture = function(self, path) self.texture = path end,
    SetTexCoord = function(self, ...) self.uv = {...} end,
    SetScale = function(self, value) self.scale = value end,
    Show = function(self) self.shown = true; if self.OnShow then self:OnShow() end end,
    Hide = function(self) self.shown = false; if self.OnHide then self:OnHide() end end,
    IsVisible = function(self) return self.shown ~= false end,
    IsShown = function(self) return self.shown ~= false end,
    GetCenter = function(self) return rawget(self, "x") or 0, rawget(self, "y") or 0 end,
    SetVerticalScroll = function(self, value)
        self.offset = value
        self:OnVerticalScroll(value)
    end,
    GetStringWidth = function(self) return #(self.text or "") * 6 end,
    GetBottom = function() return 500 end,
    HookScript = function(self, script, fn)
        local previous = rawget(self, script)
        self[script] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end,
}, {__index = function(_, key)
    if key ~= "stars" and key ~= "unit" and key ~= "TargetFrameContainer"
        and key ~= "Portrait" and key ~= "portrait" then return noop end
end})
function CreateFrame(kind, name, parent)
    local f = setmetatable({name = name, kind = kind, children = {}}, {__index = methods})
    if name then _G[name] = f end
    if parent then table.insert(parent.children, f) end
    f.CreateFontString = function(self) return CreateFrame("FontString", nil, self) end
    f.CreateTexture = function(self) return CreateFrame("Texture", nil, self) end
    return f
end
function SetPortraitTexture(texture, unit) texture:SetTexture(unit) end
UIParent = CreateFrame()
Minimap = CreateFrame()
C_Timer = {}
function C_Timer.NewTimer(delay, fn)
    serial = serial + 1
    timers[serial] = {at = clock + delay, fn = fn}
    return {}
end
C_Timer.After = C_Timer.NewTimer
tickers = {}
C_Timer.NewTicker = function(delay, callback) tickers[delay] = callback end
function tick(now)
    clock = now
    local ready = {}
    for id, timer in pairs(timers) do
        if timer.at <= now then ready[#ready+1] = id end
    end
    table.sort(ready)
    for _, id in ipairs(ready) do
        local fn = timers[id].fn
        timers[id] = nil
        fn()
    end
end
function emit(event, ...)
    for _, fn in ipairs(state.events[event] or {}) do fn(...) end
end
"""

class Client:
    def __init__(self, name, level=60, saved=None):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.g = self.lua.globals()
        self.g.character = name
        self.lua.execute(MOCK)
        self.g.level = level
        for file in ("Core.lua", "Score.lua", "GroupStats.lua", "Talents.lua", "CombatBuilds.lua", "Stats.lua", "Sync.lua",
                     "ReviewRelationships.lua", "BlackMarks.lua", "Who.lua", "Profile.lua", "GroupFinder.lua", "PlayerHistory.lua"):
            source = (ADDON / file).read_text(encoding="utf-8")
            self.lua.eval("function(source) assert(loadstring(source))('SocialCreditSystem',state) end")(source)
        if saved:
            self.lua.execute(saved)
        self.g.emit("PLAYER_LOGIN")
        self.s = self.g.state
        if level != 60:
            assert self.s.me.level == level
            assert self.s.db.stats[self.s.me.key] is None
        assert self.s.me
        self.name = self.s.me.key
        self.s.Remember(self.s.Unit("target"))
        self.offset = 1

now = 1

def advance(clients, seconds):
    global now
    for _ in range(seconds * 10):
        now += 0.1
        for client in clients:
            client.g.tick(now)
        for client in clients:
            outbox = client.g.outbox
            while client.offset <= len(outbox):
                msg = outbox[client.offset]
                client.offset += 1
                for recipient in clients:
                    if recipient is client:
                        continue
                    if msg[3] == "GUILD" or (msg[3] == "WHISPER" and msg[4].lower() == recipient.name):
                        if getattr(recipient, "legacy_combat", False) and any(
                            op in msg[2] for op in (":F~", ":D~", ":U~")
                        ):
                            continue
                        if recipient.name == "test-subject":
                            assert not any(op in msg[2] for op in (":R~", ":W~", ":B~", ":E~", ":A~"))
                        recipient.g.emit("CHAT_MSG_ADDON", msg[1], msg[2], msg[3], client.name)

author = Client("First Author")
one = Client("One Witness")
two = Client("Two Witness")
subject = Client("Test Subject")
reader = Client("Profile Reader", 59)
assert author.s.Unit("enemy") is None
assert author.s.Identity("Test Subject")[0] == author.s.Identity("Test-Subject-Layer")[0]
assert author.s.ValidText("⚔" * 240)[0]
assert author.s.ValidText("⚔" * 241) is False
assert author.s.ValidText("|Hitem:123") is False
assert author.s.SaveReview(subject.name, -.5, "") is None
assert subject.s.SaveReview(subject.name, 5, "") is None
subject.s.db.authored["one-witness"] = "account-alt"
subject.s.db.names["one-witness"] = "One Witness"
assert subject.s.SaveReview("one-witness", 5, "") is None

advance([author, one, two, subject], 5)
record = author.s.SaveReview(subject.name, .5, "A long review with delimiters ~ " + "⚔" * 150)
assert record
advance([author, one, two, subject], 5)
assert one.s.Reviews(subject.name)[1] == two.s.Reviews(subject.name)[1] == 1
assert one.s.Reviews(subject.name)[0][1].stars == .5
assert subject.s.Reviews(subject.name)[1] == 0

reader.g.SlashCmdList.SOCIALCREDITSYSTEM("")
advance([reader, one], 6)
assert reader.s.Reviews(subject.name)[1] == 0
# The second firsthand witness appears after the first reply.
two.s.Query(reader.name)
reader.g.emit("CHAT_MSG_ADDON", "SocialCredit2", "800:1:1:H~Horde~60~WARRIOR~", "GUILD", two.name)
advance([reader, one, two], 8)
assert reader.s.Reviews(subject.name)[1] == 1
assert reader.s.Reviews(subject.name, "Negative")[0][1].text == record.text
assert reader.s.Reviews(subject.name, "Negative")[0][1].stars == .5
assert reader.s.Reviews(subject.name)[2] is None

# Amend without the subject online, and discard a stale direct packet.
updated = author.s.SaveReview(subject.name, 5, "")
assert updated.revision > record.revision
advance([author, one, two, reader], 5)
assert one.s.Reviews(subject.name, "Positive")[0][1].stars == 5
assert one.s.Merge(one.lua.table_from(dict(record.items())), True) is None
assert one.s.Reviews(subject.name)[1] == 1

for surname in ("Four", "Five", "Six", "Seven"):
    r = one.lua.table_from(dict(updated.items()))
    r.author, r.name = "other-" + surname.lower(), "Other " + surname
    r.stars = {"Four": 3.5, "Five": 4.5}.get(surname, 4)
    assert one.s.Merge(r, True)
rows, count, mean = one.s.Reviews(subject.name)
assert count == 5 and mean == 4.2 and one.s.Tier(one.s.Composite(subject.name, mean)[0]) == "Gold"
assert [one.s.Tier(score) for score in (0, 250, 450, 650, 850)] == ["Iron", "Bronze", "Silver", "Gold", "Laurel"]
assert [one.s.Benchmark(value, one.lua.table_from([1, 2, 3, 4, 5])) for value in (1, 3, 5)] == [0, 500, 1000]
assert one.s.Benchmark(5, one.lua.table_from([5]*5)) == 500
one.g.emit("PLAYER_LOGOUT")
one.g.SocialCreditDB.reviews = one.lua.table()
one.s.me = None
one.g.emit("PLAYER_LOGIN")
assert one.s.Reviews(subject.name)[1] == 5
assert one.s.db.reviews[subject.name]["other-four"].stars == 3.5
assert one.s.db.reviews[subject.name]["other-five"].stars == 4.5
assert [one.s.Composite(subject.name, stars)[5] for stars in (.5, 3, 5)] == [0, 500, 1000]

# Exercise the displayed profile and editor against real review data.
one.g.SlashCmdList.SOCIALCREDITSYSTEM("")
profile = one.g.SocialCreditSystemProfile
assert [profile.portrait.uv[i] for i in range(1, 5)] == [.17, .83, .17, .83]
one.g.SlashCmdList.SOCIALCREDITSYSTEM("Test Subject")
assert [profile.portrait.uv[i] for i in range(1, 5)] == [0, 1, 0, 1]
one.g.SlashCmdList.SOCIALCREDITSYSTEM("")
assert profile.reviewMean.text.startswith("4.20 ") and profile.guild.text == "Example Guild"
assert abs(profile.averageStars[5].fill.uv[2] - .2) < 1e-8
last_review = one.s.db.reviews[subject.name]["other-seven"]
one.s.db.reviews[subject.name]["other-seven"] = None
one.s.Refresh(subject.name)
assert profile.reviewMean.text == "4 of 5 reviews"
assert profile.averageStars[1].fill.shown is False
assert one.s.Merge(last_review, True)
assert profile.reviewMean.text.startswith("4.20 ")
assert profile.next.OnClick
profile.next.OnClick()
assert profile.page.text == "2 / 2" and profile.rows[3].card.shown is False
profile.filters.Negative.OnClick()
assert profile.empty.text == "No negative reviews"
assert not any(profile.rows[i].card.shown for i in range(1, 4))
profile.filters.Newest.OnClick()

one.lua.execute("""
local profile = SocialCreditSystemProfile
local names = {}
for index, row in ipairs(profile.rows) do names[index] = row.name.text end
local firstName = names[3]:match('^%S+')
local guildNames = {names[1], names[2]}
local inGuild = true
function IsInGuild() return inGuild end
C_Club = {
    GetGuildClubId = function() return 42 end,
    GetClubMembers = function() return {1, 2} end,
    GetMemberInfo = function(_, index) return {name=guildNames[index]} end,
}
C_FriendList = {
    GetNumFriends = function() return 2 end,
    GetFriendInfoByIndex = function(index)
        return {name=index == 1 and names[1] .. '-Layer' or firstName .. ' Different', connected=false}
    end,
}
WOW_PROJECT_CAMELOT = 18
local battleName, project, sameRegion = names[2], 1, true
function BNGetNumFriends() return 1 end
C_BattleNet = {
    GetFriendNumGameAccounts = function() return 2 end,
    GetFriendGameAccountInfo = function(_, account)
        return {wowProjectID=project, isOnline=account == 2, isInCurrentRegion=sameRegion,
            characterName=battleName .. '-Ruleset', realmName='Ruleset'}
    end,
}
local function assertBadges(index, friend, guildmate)
    local row = profile.rows[index]
    assert(row.friend.shown == friend and row.guildmate.shown == guildmate, row.name.text)
    local expected = friend and .48 or guildmate and .81 or .47
    assert(row.edge.color[1] == expected)
end
emit('FRIENDLIST_UPDATE')
emit('GUILD_ROSTER_UPDATE')
tick(clock + .2)
assertBadges(1, true, true)
assertBadges(2, false, true)
assertBadges(3, false, false)
assert(profile.rows[1].guildmate.point[2] == 156)
profile.next:OnClick()
assertBadges(1, false, false)
assertBadges(3, false, false)
profile.previous:OnClick()
project = WOW_PROJECT_CAMELOT
guildNames[2] = nil
emit('CLUB_MEMBER_REMOVED', 42, 2)
emit('BN_FRIEND_INFO_CHANGED')
tick(clock + .2)
assertBadges(2, true, false)
battleName, sameRegion = names[3], false
emit('BN_FRIEND_INFO_CHANGED')
tick(clock + .2)
assertBadges(2, false, false)
assertBadges(3, false, false)
sameRegion = true
inGuild = false
emit('BN_FRIEND_INFO_CHANGED')
emit('PLAYER_GUILD_UPDATE', 'player')
tick(clock + .2)
assertBadges(1, true, false)
assertBadges(3, true, false)
for index, row in ipairs(profile.rows) do assert(row.name.text == names[index]) end
IsInGuild = function() return true end
""")

def check_stars(icons, filled):
    for i in range(1, 6):
        fraction = max(0, min(1, filled - i + 1))
        assert icons[i].empty.shown == (fraction < 1)
        assert icons[i].fill.shown == (fraction > 0)
        if fraction:
            assert icons[i].fill.uv[2] == fraction

for rating in range(1, 6):
    one.g.clock = now + rating
    assert one.s.SaveReview(subject.name, rating, "A long comment " * 16)
    check_stars(profile.rows[1].icons, rating)
one.lua.execute("""
local S = state
local profile = SocialCreditSystemProfile
local friends, guildmates = S.ReviewRelationships()
friends[S.me.key], guildmates[S.me.key] = true, true
local alt = S.Identity(profile.rows[2].name.text)
S.db.alts[alt] = true
S.Refresh(S.openSubject)
assert(profile.rows[1].ownReview.shown and profile.rows[1].ownReview.text == "Your review")
assert(not profile.rows[1].friend.shown and not profile.rows[1].guildmate.shown)
assert(profile.rows[2].ownReview.shown and profile.rows[2].ownReview.text == "Your alt's review")
S.db.alts[alt] = nil
profile.next:OnClick()
assert(not profile.rows[1].ownReview.shown and not profile.rows[2].ownReview.shown)
profile.previous:OnClick()
assert(profile.rows[1].ownReview.shown and not profile.rows[2].ownReview.shown)
""")
assert profile.reviewMean.text.startswith("4.33 ")
profile.edit.OnClick()
check_stars(profile.editor.icons, 5)
editor_buttons = [node for _, node in profile.editor.children.items() if node.kind == "Button"]
assert len(editor_buttons) == 14
assert profile.editor.zero.point[2] < profile.editor.icons[1].empty.point[2]
rating_buttons = editor_buttons[1:11]
for index, choice in enumerate(rating_buttons):
    assert choice.point[2] == 162 + (index // 2) * 45 + (index % 2) * 21
    rating = (index + 1) / 2
    choice.OnEnter()
    check_stars(profile.editor.icons, rating)
    choice.OnLeave()
    check_stars(profile.editor.icons, 5)
    choice.OnClick()
    choice.OnLeave()
    check_stars(profile.editor.icons, rating)
    assert profile.editor.stars == rating
    rating_buttons[9].OnClick()
rating_buttons[6].OnClick()
editor_buttons[-1].OnClick()
assert one.s.Reviews(subject.name)[1] == 6
assert profile.reviewMean.text.startswith("4.08 ")
check_stars(profile.rows[1].icons, 3.5)
profile.edit.OnClick()
assert profile.editor.stars == 3.5
check_stars(profile.editor.icons, 3.5)
editor_buttons[-2].OnClick()
assert one.s.SaveReview(subject.name, 3.25, "") is None
one.lua.execute("""
local S = state
local key = 'filter-target'
for index, rating in ipairs({2.5, 3, 3.5}) do
    local name = 'Review ' .. ({'First','Second','Third'})[index]
    assert(S.Merge({author=S.Identity(name), name=name, subject=key, subjectName='Filter Target',
        stars=rating, revision=index, time=S.Now(), text='', level60=true}, true))
end
local negative = S.Reviews(key, 'Negative')
local positive = S.Reviews(key, 'Positive')
assert(#negative == 1 and negative[1].stars == 2.5)
assert(#positive == 1 and positive[1].stars == 3.5)
assert(#S.Reviews(key, 'Newest') == 3)
""")
one.lua.execute("UIParent.GetWidth = function() return 640 end")
profile.Show(profile)
assert profile.scale < .8
one.g.clock = now

one.lua.execute("""
local zone = 'none'
function GetInstanceInfo() return 'Zone',zone,1,'Normal',5,0,false,zone == 'party' and 36 or 1,5 end
emit('PLAYER_ENTERING_WORLD')
emit('PLAYER_REGEN_DISABLED')
meterSample(6, 20, 999, 999)
emit('PLAYER_REGEN_ENABLED')
zone = 'party'
emit('ZONE_CHANGED_NEW_AREA')
emit('TIME_PLAYED_MSG', 123456)
emit('PLAYER_REGEN_DISABLED')
meterSample(7, 10, 100, 0)
clock = clock + 10
emit('PLAYER_REGEN_ENABLED')
emit('PLAYER_REGEN_DISABLED')
emit('DAMAGE_METER_COMBAT_SESSION_UPDATED', 0, 7)
meterSample(8, 30, 300, nil)
clock = clock + 30
emit('PLAYER_REGEN_ENABLED')
lootRoll(1, true, 20, 0, 'item:17', true)
lootRoll(2, true, 90, 3, 'item:17', false)
lootRoll(3, true, 99, 5, 'item:17', false)
lootRoll(4, true, 99, 3, 'item:18', false)
lootRoll(5, false, 99, 3, 'item:17', false)
emit('CHAT_MSG_SYSTEM', 'One Witness rolls 100 (1-100)')
emit('LOOT_HISTORY_UPDATE_DROP', 12, 1)
""")
now += 40
advance([one], 2)
assert reader.s.ImportStats(one.name, one.s.ExportStats(True), True)
assert reader.s.db.stats[one.name].rates[5] is None
one.lua.execute("""
emit('LFG_COMPLETION_REWARD')
emit('LFG_COMPLETION_REWARD')
local dungeon = GetInstanceInfo
function GetInstanceInfo() return 'World','none',0,"Normal", 0, 0, false,1 end
local world = GetInstanceInfo
for i = 1, 2 do
    GetInstanceInfo = world
    emit('ZONE_CHANGED_NEW_AREA')
    GetInstanceInfo = dungeon
    emit('ZONE_CHANGED_NEW_AREA')
    emit('LFG_COMPLETION_REWARD')
end
GetInstanceInfo = world
emit('ZONE_CHANGED_NEW_AREA')
emit('PLAYER_REGEN_DISABLED')
meterSample(9, 10, 999, 999)
function GetInstanceInfo() return 'Raid','raid',1,"Normal", 20, 0, false,17 end
emit('ZONE_CHANGED_NEW_AREA')
emit('PLAYER_REGEN_ENABLED')
emit('PLAYER_REGEN_DISABLED')
emit('DAMAGE_METER_RESET')
meterSample(10, 10, 999, 999)
emit('PLAYER_REGEN_ENABLED')
emit('CHAT_MSG_GUILD', 'Shit, shit! Shitake.', character, nil,nil,nil,nil,nil,nil,nil,nil,44)
emit('CHAT_MSG_GUILD', 'Shit, shit!', character, nil,nil,nil,nil,nil,nil,nil,nil,44)
emit('CHAT_MSG_WHISPER', 'Shit!', character)
emit('CHAT_MSG_PARTY', 'Shit!', 'Someone Else')
""")
advance([one], 1)
payload = one.s.ExportStats()
assert reader.s.ImportStats(one.name, payload)
snapshot = reader.s.db.stats[one.name]
assert snapshot.dungeons == 3 and snapshot.played == 123456 and snapshot.battlegrounds is None
assert snapshot.gear == 74
assert reader.s.ImportReviewsGiven(one.name, one.s.ExportReviewsGiven())
assert snapshot.reviewsGiven == 1  # Five edits still count as one published review.
assert reader.s.ImportStats(one.name, payload)
assert reader.s.db.stats[one.name].reviewsGiven == 1
assert reader.s.ImportReviewsGiven(one.name, "invalid") is None
one.g.emit("PLAYER_LOGIN")
one.g.emit("LOOT_HISTORY_UPDATE_DROP", 12, 1)
assert reader.s.ImportStats(one.name, one.s.ExportStats(True), True)
snapshot = reader.s.db.stats[one.name]
assert snapshot.ratesSince and snapshot.rollSum / snapshot.rollCount == 55 and snapshot.rollCount == 2
assert snapshot.explicitWords == 2 and snapshot.runs[5] == 3 and snapshot.runs[20] == 0
owner_rates = one.s.ProfileStats(one.name).rates[5]
assert [owner_rates[i] for i in range(1, 7)] == [10000, 40, 2, 0, 10, 1]
assert snapshot.rates[20] is None
assert reader.s.ImportNeedGreed(one.name, one.s.ExportNeedGreed())
assert snapshot.needGreed.need == 1 and snapshot.needGreed.greed == 1
one.lua.execute("""
lootRoll(6, true, nil, 1, 'item:17', true)
emit('LOOT_HISTORY_UPDATE_DROP', 12, 6)
lootRoll(6, true, 40, 1, 'item:17', true)
lootRoll(7, true, 75, 2, 'item:17', true)
""")
assert reader.s.ImportNeedGreed(one.name, one.s.ExportNeedGreed())
assert snapshot.needGreed.need == 2 and snapshot.needGreed.greed == 1
assert reader.s.ImportStats(one.name, one.s.ExportStats(True), True)
snapshot = reader.s.db.stats[one.name]
assert snapshot.needGreed.need == 2 and snapshot.rollCount == 4 and snapshot.rollSum == 225
assert not reader.s.ImportNeedGreed(one.name, f"{snapshot.needGreed.stamp - 1}~99~99")
reader.g.SlashCmdList.SOCIALCREDITSYSTEM("One Witness")
assert reader.g.SocialCreditSystemProfile.stats[7].text == "Need-to-Greed  2:1"

one.lua.execute("""
local lock = 0
local raid = function() return 'Raid','raid',1,"Normal", 20, 0, false,17 end
local world = function() return 'World','none',0,"Normal", 0, 0, false,1 end
function GetNumSavedInstances() return 1 end
function GetSavedInstanceInfo() return 'Raid',lock,3600,1,true,false,0,true,20,'Normal',3,3 end
for i = 1, 3 do
    lock = i
    GetInstanceInfo = world
    emit('ZONE_CHANGED_NEW_AREA')
    GetInstanceInfo = raid
    emit('ZONE_CHANGED_NEW_AREA')
    emit('ENCOUNTER_END', 99, 'Final boss', 1, 12, 1)
    emit('UPDATE_INSTANCE_INFO')
    GetInstanceInfo = world
    emit('ZONE_CHANGED_NEW_AREA')
    GetInstanceInfo = raid
    emit('ZONE_CHANGED_NEW_AREA')
    emit('ENCOUNTER_END', 99, 'Final boss', 1, 12, 1)
    emit('UPDATE_INSTANCE_INFO')
end
assert(state.db.stats[state.me.key].runs[20] == 3)
""")

one.lua.execute("""
local S = state
for i, surname in ipairs({'A', 'B', 'C', 'D', 'E'}) do
    local key = 'bench-' .. surname:lower()
    S.Remember({key=key,name='Bench '..surname,level=60,class='MAGE',faction='Horde'})
    S.db.stats[key] = {runs={[5]=3},rates={[5]={1000 - i * 100,10,1,i * 200,10,1}}}
    local stamp = S.Now()
    assert(S.ImportTalentContext(key, table.concat({1, 42, stamp * 1000, "Frost", "N", stamp * 1000}, "~"), true))
    for clear = 1, 3 do
        local when = stamp - clear * 100
        assert(S.ImportBuildClear(key, key, table.concat({1, "12:1", when, 5, when, 1, "42:N",
            1000 - i * 100, 10, 1, i * 200, 10, 1}, "~")))
    end
    S.db.reviews[key] = {}
    for n = 1, 5 do
        S.db.reviews[key][n] = {stars=i,level60=true,time=1,revision=1,author=tostring(n)}
    end
end
S.Remember({key='other-faction',name='Other Faction',level=60,class='MAGE',faction='Alliance'})
S.InvalidateScores()
local score, provisional, count = S.Composite('bench-e',5)
assert(score == 1000 and not provisional and count == 5)
assert(S.Composite('bench-c',3) == 500)
""")

one.lua.execute("""
local S = state
local row = CreateFrame()
S.db.stats['bench-a'].rates[5][1] = 0
for _, report in pairs(S.db.buildClears['bench-a']['bench-a']) do report.cohorts['42:N'][1] = 0 end
S.InvalidateScores()
row.Name = row:CreateFontString()
local listings = {
    [1] = {leaderName='Bench A', numMembers=1},
    [2] = {leaderName='Bench E', numMembers=3},
    [3] = {leaderName=S.me.name, numMembers=1},
    [4] = {leaderName='Missing Person', numMembers=1},
    [5] = {leaderName='Test Subject', numMembers=1},
}
C_LFGList = {
    GetSearchResultInfo = function(id) return listings[id] end,
    GetSearchResultLeaderInfo = function(id)
        return {name=listings[id].leaderName, level=60}
    end,
    GetSearchResultPlayerInfo = function(_, index)
        return ({ {name='Bench E', isLeader=true, level=60},
            {name='Bench C', level=60}, {name=S.me.name, level=60} })[index]
    end,
}
LFGBrowseFrame = CreateFrame()
LFGBrowseFrame.ScrollBox = {ForEachFrame=function(_, fn) fn(row) end}
LFGBrowseSearchEntryTooltip = CreateFrame()
function LFGBrowseSearchEntry_Update() end
function LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip) tooltip:Show() end
function hooksecurefunc(name, callback)
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        callback(...)
    end
end
local function recycle(id)
    row.resultID = id
    LFGBrowseSearchEntry_Update(row)
end
emit('ADDON_LOADED', 'Blizzard_GroupFinder_VanillaStyle')
recycle(1)
local badge = row.children[2]
assert(badge.shown and badge.text == 'SCS 0.00')
recycle(2)
assert(badge.shown and badge.text == 'Leader SCS 1000.00')
LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 2)
local panel = LFGBrowseSearchEntryTooltip.children[1]
assert(panel.shown and #panel.rows == 2)
assert(panel.rows[2].title.text:match('Bench C'))
assert(panel.rows[2].value.text:match('3.00 / 5'))
SlashCmdList.SOCIALCREDITSYSTEM('Bench E')
local beforeRespec = SocialCreditSystemProfile.score.text
assert(beforeRespec:match('^1000.00 SCS'))
local newStamp = S.Now() * 1000 + 1
assert(S.ImportTalentContext('bench-e', table.concat({1, 43, newStamp, "Fire", "N", newStamp}, "~"), true))
tick(clock)
assert(badge.text == 'Leader SCS 875.00*')
assert(SocialCreditSystemProfile.score.text:match('^875.00 SCS'))
assert(SocialCreditSystemProfile.lifetimeRates[1]:match('50 DPS'))
assert(S.ImportTalentContext('bench-e', table.concat({1, 42, newStamp + 1, "Frost", "", 0}, "~"), true))
tick(clock)
assert(badge.text == 'Leader SCS 1000.00' and SocialCreditSystemProfile.score.text == beforeRespec)
recycle(3)
assert(not badge.shown and not panel.shown)
recycle(4)
assert(not badge.shown)
local key = 'test-subject'
local saved = S.db.reviews[key]
S.db.reviews[key] = {}
recycle(5)
assert(badge.shown and badge.text == 'SCS —')
local eligible = 0
for author, review in pairs(saved) do
    if review.level60 and eligible < 5 then
        eligible = eligible + 1
        S.db.reviews[key][author] = review
    end
end
assert(eligible == 5)
S.InvalidateScores()
tick(clock)
assert(badge.text:match('^SCS %d+%.%d%d%*$'))
local before = badge.text
local _, review = next(S.db.reviews[key])
local amended = S.Copy(review)
amended.revision = amended.revision + 1
amended.stars = amended.stars == 1 and 5 or 1
assert(S.Merge(amended, true))
tick(clock)
assert(badge.text ~= before)
local mark = {stars=0, level60=true, author=S.me.key, name=S.me.name, subject=key,
    subjectName='Test Subject', revision=S.Now(), time=S.Now(), text=''}
assert(S.Merge(mark, true))
tick(clock)
assert(badge.text:find('BlackMark', 1, true))
LFGBrowseSearchEntryTooltip_UpdateAndShow(LFGBrowseSearchEntryTooltip, 5)
assert(panel.rows[1].title.text:find('BlackMark', 1, true))
recycle(2)
assert(not badge.text:find('BlackMark', 1, true))
S.db.alts[key] = true
recycle(5)
assert(not badge.shown)
""")

sizes = {"GuildHall": (1024, 128), "StatsSlate": (256, 512),
         "BlackMark": (32, 32), "MinimapStamp": (64, 64),
         "ReviewParchment": (512, 128), "StarFilled": (64, 64), "StarEmpty": (64, 64)}
for path in (ADDON / "Media").glob("*.tga"):
    data = path.read_bytes()
    w, h = sizes.get(path.stem, (128, 128))
    assert data[2] == 2 and int.from_bytes(data[12:14], "little") == w
    assert int.from_bytes(data[14:16], "little") == h and data[16:18] == bytes([32, 40])
    assert len(data) == 18 + w*h*4
    assert max(data[21::4]) > 240
    if path.stem not in ("GuildHall", "StatsSlate", "ReviewParchment"):
        assert min(data[21::4]) == 0
assert all((ADDON / "Media" / f"{name}.tga").is_file() for name in sizes)

# The grouped subject has no Client and never sends any addon messages.
observers = [Client("Dungeon Scout"), Client("Second Scout"), Client("Group Reader")]
for witness in observers[:2]:
    witness.lua.execute("""
local name = UnitName
function UnitName(unit)
    if unit == 'party1' then return 'Silent Adventurer' end
    if unit == 'party2' then return 'Remote Adventurer' end
    return name(unit)
end
UnitFullName = UnitName
function GetNumSubgroupMembers() return 2 end
function UnitGUID(unit) return 'Player-1-' .. unit end
function UnitInRange(unit) return unit == 'party1' end
local read = C_DamageMeter.GetCombatSessionFromID
function C_DamageMeter.GetCombatSessionFromID(id, kind)
    local session = read(id, kind)
    if session and (kind == 0 or lateHealing) then
        table.insert(session.combatSources, {sourceGUID='Player-1-party1',
            amountPerSecond=kind == 0 and observedDPS or 75})
        table.insert(session.combatSources, {sourceGUID='Player-1-party2', amountPerSecond=90000})
    end
    return session
end
emit('GROUP_ROSTER_UPDATE')
function witnessedRun(id, damage, swapped, partial)
    observedDPS = damage
    lateHealing = false
    function GetInstanceInfo() return 'World','none',0,"Normal", 0, 0, false,1 end
    emit('ZONE_CHANGED_NEW_AREA')
    function GetInstanceInfo() return 'Dungeon','party',1,"Normal", 5, 0, false,55 end
    emit('ZONE_CHANGED_NEW_AREA')
    emit('PLAYER_REGEN_DISABLED')
    meterSample(id, 10, 100, 50)
    clock = clock + 10
    if swapped then
        UnitInRange = function() return false end
        emit('GROUP_ROSTER_UPDATE')
    end
    emit('PLAYER_REGEN_ENABLED')
    if not partial then
        emit('LFG_COMPLETION_REWARD')
        emit('LFG_COMPLETION_REWARD')
    end
    tick(clock + .5)
    lateHealing = true
    emit('DAMAGE_METER_COMBAT_SESSION_UPDATED', 1, id)
    tick(clock + .5)
    function GetInstanceInfo() return 'World','none',0,"Normal", 0, 0, false,1 end
    emit('ZONE_CHANGED_NEW_AREA')
    UnitInRange = function(unit) return unit == 'party1' end
end
""")

first, second, viewer = observers
advance(observers, 7)
key = "silent-adventurer"
assert first.s.Eligible(key) and first.s.SaveReview(key, 4, "Good run")
first.g.witnessedRun(1, 200, False)
second.g.witnessedRun(1, 300, False)
first.g.clock = now + 100
first.g.witnessedRun(2, 400, False)
second.g.clock = now + 200
second.g.witnessedRun(2, 500, False)
second.g.clock = now + 300
second.g.witnessedRun(3, 9000, True)
assert first.s.ProfileStats(key).runs[5] == second.s.ProfileStats(key).runs[5] == 2
assert first.s.ProfileStats("remote-adventurer") is None
now += 320
advance(observers, 1)
for observer in observers:
    observer.g.tickers[60]()
advance(observers, 5)
assert viewer.s.LookupGroupProfile(key)
advance(observers, 12)
stats = viewer.s.ProfileStats(key)
assert viewer.s.Eligible(key) and stats.runs[5] == stats.groupRuns[5] == stats.dungeons == 3
assert stats.rates[5][2] == 30 and stats.rates[5][1] == 11000
assert stats.rates[5][4] == 2250 and stats.rates[5][5] == 30
assert stats.gear is None and stats.played is None and stats.battlegrounds is None
viewer.g.emit("PLAYER_LOGOUT")
viewer.g.SocialCreditDB.groupClears = viewer.lua.table()
viewer.s.me = None
viewer.g.emit("PLAYER_LOGIN")
assert viewer.s.ProfileStats(key).runs[5] == 3
viewer.lua.execute("""
local key = 'silent-adventurer'
local rows = state.db.groupClears[key]['second-scout']
local latest = 0
for _, row in pairs(rows) do latest = math.max(latest, row.stamp) end
state.db.stats[key] = {level60Since=latest, runs={[5]=1}, dungeons=1,
    rates={[5]={6000,10,1,0,0,0}}}
state.InvalidateScores()
local combined = state.ProfileStats(key)
assert(combined.runs[5] == 3 and combined.groupRuns[5] == 2)
assert(combined.rates[5][1] == 17000)
""")

first.lua.execute("""
local S = state
function GetInstanceInfo() return 'Raid','raid',1,"Normal", 20, 0, false,17 end
function GetNumSavedInstances() return 1 end
local kills = 2
function GetSavedInstanceInfo() return 'Raid',42,3600,1,true,false,0,true,20,'Normal',3,kills end
emit('ZONE_CHANGED_NEW_AREA')
emit('ENCOUNTER_END', 99, 'Final boss', 1, 20, 1)
UnitInRange = function(unit) return unit == 'party2' end
kills = 3
emit('UPDATE_INSTANCE_INFO')
emit('UPDATE_INSTANCE_INFO')
local key = 'silent-adventurer'
assert(S.ProfileStats(key).groupRuns[20] == 1)
assert(S.ProfileStats('remote-adventurer') == nil)
function GetInstanceInfo() return 'World','none',0,"Normal", 0, 0, false,1 end
emit('ZONE_CHANGED_NEW_AREA')
emit('PLAYER_REGEN_DISABLED')
meterSample(77, 10, 99999, 99999)
emit('PLAYER_REGEN_ENABLED')
assert(S.ProfileStats(key).groupRuns[20] == 1)
assert(S.ProfileStats(key).rates[20][2] == 0)
""")

# Matching partial runs survive logout, sync to a third client and never create a clear.
first.lua.execute("function UnitInRange(unit) return unit == 'party1' end")
first.g.clock = second.g.clock = now + 2
first.g.witnessedRun(81, 600, False, True)
second.g.witnessedRun(181, 700, False, True)
first.g.emit("PLAYER_LOGOUT")
first.g.SocialCreditDB.instanceFights = first.lua.table()
first.s.me = None
first.g.emit("PLAYER_LOGIN")
assert first.s.ProfileStats(key).rates[5][2] == 30
now += 195
advance(observers, 1)
for observer in observers:
    observer.g.tickers[60]()
advance(observers, 5)
assert viewer.s.LookupGroupProfile(key, True)
advance(observers, 15)
stats = viewer.s.ProfileStats(key)
assert stats.runs[5] == 3 and stats.rates[5][2] == 50 and stats.rates[5][1] == 23000

# Load a 2.9.0 owner snapshot and a delayed instance, then verify manual boss credit.
returning = Client("Returning Raider", saved="""
SocialCreditDB = {version=1, stats={["returning-raider"] = {
    level60Since=1770000001, ratesSince=1770000001, dungeons=2,
    runs={[5]=2}, rates={[5]={500, 10, 1, 0, 0, 0}}, raidRuns={}, completedLocks={},
}}}
""")
returning.lua.execute("""
local S, profile = state
local ready, inside = false, true
function IsInInstance() return inside, inside and "party" or "none" end
function GetInstanceInfo()
    if ready and inside then return "Test Depths", "party", 1, "Normal", 5, 0, false, 36, 5 end
    return "World", "none", 0, "", 0, 0, false, 1, 0
end
C_EncounterJournal = {GetInstanceForGameMap = function(map) assert(map == 36); return 63 end}
function EJ_GetEncounterInfoByIndex(index, journal)
    assert(journal == 63)
    if index <= 2 then return "Boss", "", 40 + index, 0, "", 63, 400 + index, 36 end
end
SlashCmdList.SOCIALCREDITSYSTEM("self")
profile = SocialCreditSystemProfile
emit("PLAYER_ENTERING_WORLD", false, true)
assert(not S.ActiveInstance())
ready = true
tick(clock + .3)
assert(S.ActiveInstance() == "Test Depths" and profile.activeInstance.text:find("Waiting for meter data"))
local run = S.db.stats[S.me.key].run
emit("ZONE_CHANGED_NEW_AREA")
assert(S.db.stats[S.me.key].run == run)
emit("PLAYER_REGEN_DISABLED")
clock = clock + 10
emit("PLAYER_REGEN_ENABLED")
-- The archive session appears only after leaving combat.
meterSample(31, 10, 100, nil)
tick(clock + .3)
assert(profile.activeInstance.text:find("100 DPS"))
assert(S.ProfileStats(S.me.key).rates[5][1] == 1500)
assert(S.ProfileStats(S.me.key).runs[5] == 2)
emit("PLAYER_LOGOUT")
emit("PLAYER_ENTERING_WORLD", false, true)
assert(S.db.stats[S.me.key].run == run and select(2, S.ActiveInstance())[1] == 1000)
emit("ENCOUNTER_END", 401, "First boss", 1, 5, 1)
assert(S.ProfileStats(S.me.key).runs[5] == 2)
emit("ENCOUNTER_END", 402, "Last boss", 1, 5, 1)
emit("LFG_COMPLETION_REWARD")
assert(S.ProfileStats(S.me.key).runs[5] == 3 and S.ProfileStats(S.me.key).rates[5][1] == 1500)
inside = false
emit("ZONE_CHANGED_NEW_AREA")
assert(not S.ActiveInstance() and profile.activeInstance.text == "")
inside = true
emit("PLAYER_ENTERING_WORLD", false, false)
assert(S.db.stats[S.me.key].run ~= run and not select(2, S.ActiveInstance()))
""")
print("PASS: Forever instance entry and manual clear, partial fights, witness deduplication and upgrade")

author, guildmate, outsider, target = (Client(name) for name in
    ("Zero Reviewer", "Guild Viewer", "Other Viewer", "Test Subject"))
author.lua.execute("""
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(index) return ({"Guild Viewer", "Test Subject"})[index] end
emit("GUILD_ROSTER_UPDATE")
""")
guildmate.lua.execute("""
function GetNumGuildMembers() return 1 end
function GetGuildRosterInfo() return "Zero Reviewer" end
emit("GUILD_ROSTER_UPDATE")
state.db.profiles["test-subject"] = nil
""")
author.g.SlashCmdList.SOCIALCREDITSYSTEM("")
author.lua.execute("""
local S, key = state, "test-subject"
local p = SocialCreditSystemProfile
p.edit.OnClick()
p.editor.stars = nil
p.editor.save.OnClick()
assert(not popup)
p.editor.zero.OnClick()
p.editor.body:SetText("Draft")
p.editor.save.OnClick()
assert(popup and popup.name == "Test Subject" and S.ReviewAverage(key) == 0)
StaticPopup_Hide(popup.which)
assert(p.editor.body:GetText() == "Draft" and p.editorShade:IsVisible())
p.editor.save.OnClick()
local stale = popup
SlashCmdList.SOCIALCREDITSYSTEM("")
assert(not popup)
StaticPopupDialogs[stale.which].OnAccept(nil, stale.data)
assert(S.ReviewAverage(key) == 0)
p.edit.OnClick()
p.editor.zero.OnClick()
p.editor.save.OnClick()
local confirmed = popup
StaticPopupDialogs[confirmed.which].OnAccept(nil, confirmed.data)
assert(S.ReviewAverage(key) == 1 and S.BlackMarkReviewers(key)[1] == "Your review")
assert(p.blackMark.shown and p.blackPortrait.shown and p.rows[1].zero.shown)
assert(S.Reviews(key, "Negative")[1].stars == 0)
assert(select(5, S.Composite(key, 0)) == 0)
""")
advance([author, guildmate, outsider, target], 14)
assert guildmate.s.BlackMarkReviewers(target.name)[1] == "Zero Reviewer"
assert guildmate.s.Eligible(target.name)
assert outsider.s.ReviewAverage(target.name)[0] == 1
assert outsider.s.BlackMarkReviewers(target.name) is None
assert target.s.BlackMarkReviewers(target.name) is None
guildmate.lua.execute("""
local S, key = state, "test-subject"
local name = "Test Subject"
local originalName = UnitName
function UnitName(unit)
    if unit == "target" then return "Other Target" end
    if unit == "focus" or unit == "party1" then return name end
    return originalName(unit)
end
FocusFrame = CreateFrame("Frame")
FocusFrame.Portrait = FocusFrame:CreateTexture()
PartyFrame = {GetPartyMemberFrame = function(_, index) if index == 1 then return PartyMemberFrame1 end end}
PartyMemberFrame1 = CreateFrame("Frame")
PartyMemberFrame1.Portrait = PartyMemberFrame1:CreateTexture()
XPerl_Focus = CreateFrame("Frame")
XPerl_Focus.portraitFrame = CreateFrame("Frame", nil, XPerl_Focus)
emit("PLAYER_FOCUS_CHANGED")
tick(clock + .2)
local shown = 0
for _, child in ipairs(UIParent.children) do
    if child.children[1] and (child.children[1].texture or ""):match("BlackMark") and child.shown then
        shown = shown + 1
    end
end
assert(shown == 3)
local link = "|Hplayer:Test-Subject|h[Test Subject]|h"
local function render(guid, event)
    return markSender(event or "CHAT_MSG_GUILD", link, "hello", name, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, guid)
end
assert(render("Player-1-1234"):find(link, 1, true))
assert(render(nil):find(link, 1, true))
local hiddenGUID = {}
issecretvalue = function(value) return value == hiddenGUID end
assert(render(hiddenGUID):find(link, 1, true))
issecretvalue = nil
function GetPlayerInfoByGUID() return nil, nil, nil, nil, nil, "Test Subject", "Layer" end
assert(markSender("CHAT_MSG_GUILD", "[Test]", "hello", "Test", nil, nil, nil, nil,
    nil, nil, nil, nil, nil, "Player-1-1234"):find("BlackMark", 1, true))
assert(not render("Player-1-1234", "CHAT_MSG_WHISPER_INFORM"))
assert(not render("Creature-1-1234"))
Prat = {
    RegisterMessageItem = function(section, anchor, direction)
        assert(section == "SCSBLACKMARK" and anchor == "pP" and direction == "before")
    end,
    RegisterChatEvent = function(_, hook, callback)
        assert(hook == "Prat_PreAddMessage")
        pratChat = callback
    end,
}
emit("ADDON_LOADED", "Prat-3.0")
for _, shownName in ipairs({"Test Subject", "|cffaabbccNick|r"}) do
    local message = {PLAYER = shownName, PLAYERLINK = "Test-Subject", ARGS = {[1] = "hi", [2] = name}}
    pratChat(nil, message, nil, "CHAT_MSG_GUILD")
    pratChat(nil, message, nil, "CHAT_MSG_GUILD")
    local result = message.SCSBLACKMARK .. "|Hplayer:" .. message.PLAYERLINK .. "|h[" .. message.PLAYER .. "]|h"
    local _, seals = result:gsub("BlackMark", "")
    assert(seals == 1 and result:find("|Hplayer:Test-Subject|h[" .. shownName .. "]|h", 1, true))
    message.ARGS[2] = "Different Subject"
    pratChat(nil, message, nil, "CHAT_MSG_GUILD")
    assert(not message.SCSBLACKMARK)
end
local predecorated = {PLAYER = render(nil), ARGS = {[2] = name}}
pratChat(nil, predecorated, nil, "CHAT_MSG_GUILD")
assert(not predecorated.SCSBLACKMARK and predecorated.PLAYER:find(link, 1, true))
local action
local menu = {CreateDivider = function() end, CreateButton = function(_, text, callback)
    assert(text == "Open SCS")
    action = callback
end}
menus.MENU_UNIT_FRIEND(nil, menu, {chatFrame = {}, name = name})
action()
assert(S.openSubject == key)
function GetNumGuildMembers() return 0 end
emit("GUILD_ROSTER_UPDATE")
tick(clock + .2)
assert(not SocialCreditSystemProfile.blackMark.shown and not render("Player-1-1234"))
function GetNumGuildMembers() return 1 end
emit("GUILD_ROSTER_UPDATE")
assert(S.BlackMarkReviewers(key))
staleZero = S.Copy(S.db.reviews[key]["zero-reviewer"])
assert(S.SaveReview(key, 0, "Second mark"))
assert(#S.BlackMarkReviewers(key) == 2)
assert(S.SaveReview(key, 1, "Raised"))
assert(#S.BlackMarkReviewers(key) == 1)
""")
assert author.s.SaveReview(target.name, .5, "Amended")
advance([author, outsider, target], 5)
# The guild viewer missed the amendment. Its guild greeting requests catch-up.
guildmate.g.emit("PLAYER_ENTERING_WORLD")
advance([author, guildmate, outsider, target], 24)
assert guildmate.s.BlackMarkReviewers(target.name) is None
assert guildmate.s.db.reviews[target.name][author.name].stars == .5
assert guildmate.s.Merge(guildmate.g.staleZero, True) is None
assert guildmate.s.BlackMarkReviewers(target.name) is None
talent_owner, talent_witness, old_reader, new_reader = (Client(name) for name in
    ("Talent Owner", "Talent Witness", "Legacy Reader", "Talent Reader"))
old_reader.legacy_combat = True
talent_mock = """
local S = state
talentConfig, staged = 1, false
local builds = {[1] = {31, 5, 0}, [2] = {0, 31, 5}, [3] = {20, 20, 0}, [99] = {0, 31, 0}}
C_SpecializationInfo = {
    GetActiveSpecGroup = function() return talentConfig end,
    GetCombatConfigIDForSpecGroup = function(group) return group end,
}
C_Traits = {
    ConfigHasStagedChanges = function() return staged end,
    GetConfigInfo = function() return {treeIDs = {800}} end,
    GetGroupDisplayInfoByTreeID = function()
        return {{groupID=101,displayName="Protection"}, {groupID=102,displayName="Fury"},
            {groupID=103,displayName="Arms"}}
    end,
    GetGroupCurrencyInfo = function(config)
        local out = {}
        for i, spent in ipairs(builds[config]) do
            out[i] = {traitNodeGroupID=100+i,currencyInfos={{spent=spent}}}
        end
        return out
    end,
}
Constants = {TraitConsts = {INSPECT_TRAIT_CONFIG_ID = 99}}
function GetInstanceInfo()
    if inside then return "Dungeon", "party", 1, "Normal", 5, 0, false, 50 end
    return "World", "none", 0, "Normal", 0, 0, false, 1
end
function enterDungeon(value)
    inside = value
    emit("ZONE_CHANGED_NEW_AREA")
end
function pull(id, dps, hps)
    emit("PLAYER_REGEN_DISABLED")
    meterSample(id, 10, dps, hps)
    clock = clock + 10
    emit("PLAYER_REGEN_ENABLED")
    tick(clock + .3)
end
"""
talent_owner.lua.execute(talent_mock)
talent_owner.lua.execute("""
local S = state
function IsInGroup() return true end
function UnitGroupRolesAssigned() return assigned end
function GetPartyAssignment(kind) return kind == "maintank" and mainTank end
assigned = "TANK"
emit("ACTIVE_TALENT_GROUP_CHANGED")
assert(S.CurrentBuild(S.me.key) == 101)
staged = true
emit("TRAIT_CONFIG_UPDATED")
assert(S.CurrentBuild(S.me.key) == 101)
staged = false
enterDungeon(true)
pull(50, 100, 2)
assigned = "DAMAGER"
pull(51, 300, 3)
assigned = "NONE"
pull(52, 9999, 2000)
emit("LFG_COMPLETION_REWARD")
local tank, nonTank = S.BuildStats(S.me.key, 101, "T"), S.BuildStats(S.me.key, 101, "N")
assert(tank[5].clears == 1 and tank[5].rate[1] == 1000)
assert(nonTank[5].clears == 1 and nonTank[5].rate[1] == 3000)
assert(S.db.stats[S.me.key].runs[5] == 1 and S.ProfileStats(S.me.key).rates[5][1] == 103990)
enterDungeon(false)
talentConfig = 3
emit("ACTIVE_TALENT_GROUP_CHANGED")
assert(not S.CurrentBuild(S.me.key))
talentConfig = 2
emit("ACTIVE_TALENT_GROUP_CHANGED")
assert(S.CurrentBuild(S.me.key) == 102)
""")
talent_witness.lua.execute(talent_mock)
talent_witness.lua.execute("""
local S = state
local originalName = UnitName
local rosterName = "Talent Owner"
function UnitName(unit) if unit == "party1" then return rosterName end return originalName(unit) end
UnitFullName = UnitName
function GetNumSubgroupMembers() return 1 end
function UnitGUID(unit) return unit == "party1" and ("Player-1-" .. rosterName) end
function UnitInRange(unit) return unit == "party1" end
function UnitGroupRolesAssigned(unit) return unit == "party1" and "DAMAGER" or "NONE" end
local guid
function CanInspect() return true end
function NotifyInspect(unit) guid = UnitGUID(unit) end
emit("GROUP_ROSTER_UPDATE")
tickers[3]()
assert(guid == "Player-1-Talent Owner")
emit("INSPECT_READY", "Player-1-Someone Else")
assert(not S.CurrentBuild("talent-owner"))
rosterName = "New Member"
emit("INSPECT_READY", guid)
assert(not S.CurrentBuild("talent-owner"))
rosterName = "Talent Owner"
clock = clock + 100
tickers[3]()
emit("INSPECT_READY", guid)
local tree, name, role = S.CurrentBuild("talent-owner")
assert(tree == 102 and name == "Fury" and role == "N")
local read = C_DamageMeter.GetCombatSessionFromID
function C_DamageMeter.GetCombatSessionFromID(id, kind)
    local session = read(id, kind)
    if session and (kind == 0 or lateRate) then
        table.insert(session.combatSources, {sourceGUID=guid, amountPerSecond=kind == 0 and 80 or 20})
    end
    return session
end
enterDungeon(true)
pull(80, 1, 1)
emit("LFG_COMPLETION_REWARD")
function UnitGroupRolesAssigned() return "TANK" end
emit("PLAYER_ROLES_ASSIGNED")
lateRate = true
emit("DAMAGE_METER_COMBAT_SESSION_UPDATED", 1, 80)
tick(clock + .3)
local build = S.BuildStats("talent-owner", 102, "N")
assert(build[5].rate[1] == 800 and build[5].rate[4] == 200)
assert(not S.BuildStats("talent-owner", 102, "T"))
enterDungeon(false)
""")
now += 110
mixed = [talent_owner, talent_witness, old_reader, new_reader]
advance(mixed, 17)
assert new_reader.s.CurrentBuild(talent_owner.name)[0] == 102
assert new_reader.s.BuildStats(talent_owner.name, 101, "T")[5].clears == 1
assert old_reader.s.ProfileStats(talent_owner.name).runs[5] == 1
assert old_reader.s.BuildStats(talent_owner.name, 101, "T") is None
assert new_reader.s.LookupGroupProfile(talent_owner.name, True)
advance(mixed, 8)
assert new_reader.s.BuildStats(talent_owner.name, 102, "N")[5].rate[4] == 200
new_reader.lua.execute("""
local S, key = state, "talent-owner"
local ownerReport = next(S.db.buildClears[key][key])
local row = S.Copy(S.db.buildClears[key][key][ownerReport])
row.cohorts["101:T"][1] = 999999
assert(S.ImportBuildClear(key, "duplicate-witness", S.ExportBuildClear(row)))
assert(S.BuildStats(key, 101, "T")[5].clears == 1)
assert(S.BuildStats(key, 101, "T")[5].rate[1] == 1000)
""")

cohorts = Client("Cohort Reader")
cohorts.lua.execute("""
local S = state
local stamp = S.Now()
local function add(key, class, tree, role, dps, hps)
    S.Remember({key=key,name=key,level=60,class=class,faction="Horde"})
    assert(S.ImportTalentContext(key, table.concat({1, tree, stamp*1000, "Tree", role, stamp*1000}, "~"), true))
    for i = 1, 3 do
        local when = stamp - i * 100
        local payload = table.concat({1, "12:1", when, 5, when, 1, tree .. ":" .. role, dps*10,
            10, 1, hps*10, 10, 1}, "~")
        assert(S.ImportBuildClear(key, key, payload))
    end
end
local function performance(key)
    return select(7, S.Composite(key, 3))
end
for i = 1, 5 do
    add("bear-" .. i, "DRUID", 201, "T", 60 + i * 10, 0)
    add("shield-" .. i, "WARRIOR", 101, "T", 70 + i * 10, 0)
    add("heal-" .. i, "PRIEST", 301, "N", 5 * (6-i), 100*i)
end
local bear, shield = performance("bear-4"), performance("shield-4")
assert(bear == 750 and shield == 750 and performance("heal-5") == 1000,
    table.concat({bear, shield, performance("heal-5")}, ", "))
for i = 1, 5 do
    add("cat-" .. i, "DRUID", 201, "N", 800 + i * 100, 0)
    add("fury-" .. i, "WARRIOR", 102, "T", 800 + i * 100, 0)
end
assert(performance("bear-4") == bear and performance("shield-4") == shield)
""")
deleter, disconnected, online = (Client(name) for name in ("Review Author", "Offline Reader", "Online Reader"))
review_clients = [deleter, disconnected, online]
advance(review_clients, 15)
key = "test-subject"
original = deleter.s.SaveReview(key, 0, "Withdraw this")
assert original
original_revision, original_time = original.revision, original.time
advance(review_clients, 8)
assert disconnected.s.db.reviews[key][deleter.name].revision == original_revision
assert online.s.DeleteReview(key, original_revision) is None
deleter.g.SlashCmdList.SOCIALCREDITSYSTEM("")
deleter.lua.execute("""
local S, key = state, "test-subject"
local p = SocialCreditSystemProfile
for _, suffix in ipairs({"One", "Two", "Three", "Four"}) do
    local name = "Other " .. suffix
    assert(S.Merge({author=S.Identity(name), name=name, subject=key, subjectName="Test Subject",
        revision=1, time=S.Now(), stars=4, text="", level60=true}, true))
end
assert(select(2, S.ReviewAverage(key)) == 3.2 and p.blackMark.shown)
p.edit.OnClick()
assert(p.editor.delete.shown)
p.editor.body:SetText("Unsaved draft")
p.editor.delete.OnClick()
assert(popup.which == "SOCIAL_CREDIT_CONFIRM_DELETE" and popup.name == "Test Subject")
StaticPopup_Hide(popup.which)
assert(p.editor.body:GetText() == "Unsaved draft" and S.ReviewAverage(key) == 5)
p.editor.delete.OnClick()
local oldDialog = popup
SlashCmdList.SOCIALCREDITSYSTEM("")
assert(not popup)
StaticPopupDialogs[oldDialog.which].OnAccept(nil, oldDialog.data)
assert(S.ReviewAverage(key) == 5)
p.edit.OnClick()
p.editor.delete.OnClick()
local accepted = popup
StaticPopupDialogs[accepted.which].OnAccept(nil, accepted.data)
assert(not p.editorShade:IsVisible() and p.edit.caption.text == "Write review")
assert(not p.blackMark.shown and p.score.text == "Social Credit Score —")
assert(S.ReviewAverage(key) == 4 and select(2, S.ReviewAverage(key)) == nil)
assert(#S.Reviews(key, "Newest") == 4 and #S.Reviews(key, "Positive") == 4)
assert(#S.Reviews(key, "Negative") == 0 and S.ExportReviewsGiven():match("~0$"))
p.edit.OnClick()
assert(not p.editor.delete.shown and p.editor.body:GetText() == "")
""")
advance([deleter, online], 18)
tombstone = online.s.db.reviews[key][deleter.name]
assert tombstone.deleted and tombstone.stars is None and tombstone.text is None
assert disconnected.s.ReviewAverage(key)[0] == 1
disconnected.g.emit("PLAYER_ENTERING_WORLD")
advance(review_clients, 14)
assert disconnected.s.ReviewAverage(key)[0] == 0
stale_review = disconnected.lua.eval(f'''{{author="review-author", name="Review Author",
        subject="test-subject", subjectName="Test Subject", revision={original_revision},
        time={original_time}, stars=0, text="Withdraw this", level60=true}}''')
assert disconnected.s.Merge(stale_review, True) is None

backup = f'''
clock = {now}
local base = {{subject="test-subject", subjectName="Test Subject", author="review-author",
    name="Review Author", time={original_time}, level60=true, direct=true}}
local stale, deleted = state.Copy(base), state.Copy(base)
stale.stars, stale.text, stale.revision = 0, "Withdraw this", {original_revision}
deleted.deleted, deleted.revision = true, {tombstone.revision}
SocialCreditDB = {{version=1, alts={{["review-author"]=true}},
    reviews={{["test-subject"]={{["review-author"]=stale}}}}}}
SocialCreditBackup = {{version=1, reviews={{["test-subject"]={{["review-author"]=deleted}}}}}}
'''
alt = Client("Reviewer Alt", saved=backup)
assert alt.s.ReviewAverage(key)[0] == 0 and alt.s.db.authored[key] == deleter.name
assert alt.s.SaveReview(key, 4, "Account slot is reserved") is None
assert alt.s.DeleteReview(key, tombstone.revision) is None
fresh = deleter.s.SaveReview(key, 4.5, "Fresh review")
assert fresh.revision > tombstone.revision
advance(review_clients, 10)
assert disconnected.s.db.reviews[key][deleter.name].stars == 4.5
assert deleter.s.ExportReviewsGiven().endswith("~1")
prat_formatter = ADDON.parent / "Prat-3.0" / "services" / "chatsections.lua"
if prat_formatter.is_file():
    guildmate.lua.execute("""
    Constants = {ChatFrameConstants = {MaxChatChannels = 20}}
    """)
    guildmate.lua.eval('function(source) assert(loadstring(source))("Prat-3.0", Prat) end')(
        prat_formatter.read_text(encoding="utf-8")
    )
    guildmate.lua.execute("""
    local S, key = state, "test-subject"
    assert(S.SaveReview(key, 0, "Formatter check"))
    Prat.RegisterMessageItem("SCSBLACKMARK", "pP", "before")
    local message = {pP="[", lL="|Hplayer:", PLAYERLINK="Test-Subject", LL="|h",
        PLAYER="|cff11aaaaNick|r", Ll="|h", Pp="]", TYPEPOSTFIX=": ", MESSAGE="Hi",
        ARGS={[2]="Test Subject"}}
    pratChat(nil, message, nil, "CHAT_MSG_GUILD")
    local line = Prat.BuildChatText(message)
    local _, seals = line:gsub("BlackMark", "")
    assert(seals == 1 and line:find("[|Hplayer:Test-Subject|h|cff11aaaaNick|r|h]: Hi", 1, true))
    """)
# Reviews from and about leveling players survive syncing and unlock at level 60.
leveling = Client("Leveling Player", 59)
viewer = Client("Promotion Viewer")
reviewers = [Client(f"Leveling {name}", 59 if name == "One" else 60)
             for name in ("One", "Two", "Three", "Four", "Five")]
clients = [leveling, viewer, *reviewers]
advance(clients, 12)
assert viewer.s.db.profiles[leveling.name].level == 59
assert leveling.s.SaveReview(viewer.name, 4.5, "Review from level 59")
for reviewer in reviewers:
    assert reviewer.s.SaveReview(leveling.name, 4, "Before level 60")
advance(clients, 12)
assert any(
    witness.s.db.reviews[viewer.name] and witness.s.db.reviews[viewer.name][leveling.name]
    and witness.s.db.reviews[viewer.name][leveling.name].stars == 4.5
    for witness in reviewers
)
viewer.g.SlashCmdList.SOCIALCREDITSYSTEM("Leveling Player")
advance(clients, 12)
assert viewer.s.ReviewAverage(leveling.name) == (5, 4)
assert viewer.s.RatingSummary(leveling.name) is None
p = viewer.g.SocialCreditSystemProfile
assert p.score.text == "SCS unlocks at level 60" and p.reviewMean.text == "5 reviews"

edited = reviewers[0].s.SaveReview(leveling.name, 5, "Amended before level 60")
assert edited
removed = reviewers[-1].s.db.reviews[leveling.name][reviewers[-1].name]
assert reviewers[-1].s.DeleteReview(leveling.name, removed.revision)
advance(clients, 30)
viewer.s.Query(leveling.name)
advance(clients, 12)
assert viewer.s.ReviewAverage(leveling.name) == (4, None)
# Older SavedVariables can contain reviews without the legacy level-60 flag.
viewer.s.db.reviews[leveling.name][reviewers[1].name].level60 = None
viewer.g.emit("PLAYER_LOGOUT")
viewer.s.me = None
viewer.g.emit("PLAYER_LOGIN")
assert viewer.s.ReviewAverage(leveling.name) == (4, None)

leveling.g.level = 60
leveling.g.emit("PLAYER_LEVEL_UP", 60)
assert leveling.s.db.stats[leveling.name].level60Since
advance(clients, 12)
assert viewer.s.Eligible(leveling.name)
assert viewer.s.RatingSummary(leveling.name) == (4, None)
assert reviewers[-1].s.SaveReview(leveling.name, 3, "Fresh review")
advance(clients, 30)
viewer.s.Query(leveling.name)
advance(clients, 12)
count, mean, score, *_ = viewer.s.RatingSummary(leveling.name)
assert count == 5 and mean == 4 and score is not None

viewer.lua.execute("""
local S, p = state, SocialCreditSystemProfile
function InCombatLockdown() return true end
p.close.OnClick()
assert(not p:IsVisible() and not S.openSubject)
SlashCmdList.SOCIALCREDITSYSTEM("Leveling Player")
p.edit.OnClick()
p.editor.zero.OnClick()
p.editor.save.OnClick()
assert(popup)
for _, child in ipairs(p.editorShade.children) do
    if child.kind == "Button" then child.OnClick() end
end
assert(not p:IsVisible() and not p.editorShade:IsVisible() and not popup and not S.openSubject)
SlashCmdList.SOCIALCREDITSYSTEM("Leveling Player")
p.edit.OnClick()
local function escape(frame)
    if frame.OnEscapePressed ~= nil and frame.kind == "EditBox" then
        frame:OnEscapePressed()
        return
    end
    for _, child in ipairs(frame.children) do escape(child) end
end
escape(p.editorShade)
assert(not p:IsVisible() and not S.openSubject)
function InCombatLockdown() return false end
emit("PLAYER_REGEN_ENABLED")
assert(not p:IsVisible())
""")
# Character-specific minimap history and navigation through the real window scripts.
history = Client("History Tester", 59)
history.lua.execute("""
local S = state
local unitName, unitLevel = UnitName, UnitLevel
local raid, grouped = false, true
function IsInRaid() return raid end
function GetNumGroupMembers() return grouped and 2 or 0 end
function GetNumSubgroupMembers() return grouped and 1 or 0 end
function UnitName(unit)
    if unit == "party1" or unit == "raid2" then return "Group Contact" end
    if unit == "raid1" then return character end
    return unitName(unit)
end
UnitFullName = UnitName
function UnitLevel(unit)
    if unit == "party1" or unit == "raid2" then return 48 end
    return unitLevel(unit)
end
emit("GROUP_ROSTER_UPDATE")
local recent = S.db.recentPlayers[S.me.key]
assert(#recent == 1 and recent[1].interaction == "Group")
local first = recent[1]
raid = true
emit("GROUP_ROSTER_UPDATE")
emit("GROUP_ROSTER_UPDATE")
assert(recent[1] == first and #recent == 1)
grouped = false
emit("GROUP_ROSTER_UPDATE")
grouped = true
emit("GROUP_ROSTER_UPDATE")
assert(recent[1] ~= first and #recent == 1)
emit("CHAT_MSG_WHISPER_INFORM", "private", "Group-Contact")
assert(#recent == 1 and recent[1].interaction == "Whisper" and recent[1].message == nil)
for i = 1, 101 do emit("CHAT_MSG_WHISPER", "private", "Whisper " .. string.char(64 + math.ceil(i / 26), 65 + i % 26)) end
assert(#recent == 100 and recent[100].key ~= "group-contact")
emit("CHAT_MSG_WHISPER", "private", "Group-Contact")
assert(#recent == 100 and recent[1].key == "group-contact")
assert(S.SaveReview("group-contact", 4, ""))
local icon = SocialCreditSystemMinimapButton
icon:OnMouseDown()
icon:OnDragStart()
icon.x, icon.y = 12, 30
icon:OnDragStop()
icon:OnClick()
assert(not SocialCreditSystemHistory and S.db.historyMinimap.x == 12)
icon:OnMouseDown()
icon:OnClick()
local list = SocialCreditSystemHistory
assert(list.rows[1].entry.key == "group-contact")
assert(list.rows[1].portrait.texture == "raid2" and list.rows[1].border.texture:match("Neutral$"))
assert(list.rows[1].metadata.text == "Level 48  " .. string.char(226,128,162) .. "  Warrior  "
    .. string.char(226,128,162) .. "  Example Guild")
assert(list.rows[1].score.text == "Unlocks at level 60")
emit("CHAT_MSG_WHISPER", "private", "Unknown Contact")
list.rows[1]:OnClick()
assert(list:IsShown() and not S.openSubject)
S.Remember({key = "unknown-contact", name = "Unknown Contact", level = 48, faction = S.faction})
S.OpenDiscoveredProfile("unknown-contact")
assert(not list:IsShown() and S.openSubject == "unknown-contact")
SocialCreditSystemProfile.back:OnClick()
assert(list:IsShown() and list.rows[1].entry.key == "unknown-contact")
list.Reviewed:OnClick()
assert(list.rows[1].entry.subject == "group-contact" and not list.rows[2].entry)
list.rows[1]:OnClick()
assert(not list:IsShown() and S.openSubject == "group-contact")
SocialCreditSystemProfile.back:OnClick()
assert(list:IsShown() and list.rows[1].entry.subject == "group-contact")
assert(S.SaveReview("group-contact", 2, "edited"))
assert(list.rows[1].entry.stars == 2)
assert(S.DeleteReview("group-contact", list.rows[1].entry.revision))
assert(not list.rows[1].entry)
for i = 1, 101 do
    local who = "Review " .. string.char(64 + math.ceil(i / 26), 65 + i % 26)
    local key = S.Identity(who)
    S.Remember({key = key, name = who, level = 50, faction = S.faction})
    assert(S.SaveReview(key, 3, ""))
end
list.scroll:SetVerticalScroll(94 * 60)
assert(list.rows[7].entry and not list.rows[8].entry)
local subject = list.rows[7].entry.subject
list.rows[7]:OnClick()
assert(S.openSubject == subject)
SocialCreditSystemProfile.back:OnClick()
assert(list.rows[7].entry.subject == subject)
function InCombatLockdown() return true end
icon:OnClick()
assert(not list:IsShown())
emit("PLAYER_LOGOUT")
S.me = nil
emit("PLAYER_LOGIN")
assert(#S.db.recentPlayers[S.me.key] == 100 and S.db.historyMinimap.y == 30)
local previousKey = S.me.key
character = "Other Character"
S.me = nil
emit("PLAYER_LOGIN")
assert(S.db.recentPlayers[S.me.key] == nil and #S.db.recentPlayers[previousKey] == 100)
""")
restored = Client("History Tester", 59, saved="""
SocialCreditDB = {version = 1, historyMinimap = {x = 12, y = 30}, recentPlayers = {
    ["history-tester"] = {{key = "group-contact", name = "Group Contact", interaction = "Group", time = GetServerTime()}}
}}
""")
restored.lua.execute("""
local icon = SocialCreditSystemMinimapButton
assert(icon.point[4] == 12 and icon.point[5] == 30)
icon:OnClick()
assert(SocialCreditSystemHistory.rows[1].entry.key == "group-contact")
""")
offline = Client("Offline Tester")
offline.lua.execute("""
local S = state
local name, key = "Departing Player", "departing-player"
local rosterOnline = false
local attempts, online = 0, false
Enum.SendAddonMessageResult.TargetOffline = 99
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
function GetNumGuildMembers() return rosterOnline ~= nil and 1 or 0 end
function GetGuildRosterInfo() return name, nil, nil, nil, nil, nil, nil, nil, rosterOnline end
C_ChatInfo.SendAddonMessage = function(_, _, route, address)
    if route == "WHISPER" and S.Identity(address) == key then
        attempts = attempts + 1
        return online and 0 or Enum.SendAddonMessageResult.TargetOffline
    end
    return 0
end
S.Remember({key = key, name = name, level = 60, class = "WARRIOR", faction = S.faction})
emit("CHAT_MSG_WHISPER", "", name)
SocialCreditSystemMinimapButton:OnClick()
local list = SocialCreditSystemHistory
list.scroll:SetVerticalScroll(0)
assert(attempts == 0)
list.rows[1]:OnClick()
assert(S.openSubject == key)
for i = 1, 40 do tick(clock + .2) end
tickers[60]()
for i = 1, 40 do tick(clock + .2) end
assert(attempts == 0)

-- A greeting can arrive immediately before logout. The first offline send drops the rest of the queue.
rosterOnline = nil
emit("GUILD_ROSTER_UPDATE")
emit("CHAT_MSG_ADDON", "SocialCredit2", "990:1:1:H~Horde~60~WARRIOR~", "GUILD", name)
for i = 1, 40 do tick(clock + .2) end
assert(attempts == 1)
tickers[60]()
for i = 1, 40 do tick(clock + .2) end
assert(attempts == 1)

-- A fresh greeting lifts the offline cooldown.
online = true
local before = attempts
tick(clock + 31)
emit("CHAT_MSG_ADDON", "SocialCredit2", "991:1:1:H~Horde~60~WARRIOR~", "GUILD", name)
for i = 1, 40 do tick(clock + .2) end
assert(attempts > before)

-- An explicit unknown profile sends just the greeting, even after repeated clicks.
name, key = "Unknown Player", "unknown-player"
online = false
attempts = 0
emit("CHAT_MSG_WHISPER", "", name)
SocialCreditSystemProfile.back:OnClick()
list.rows[1]:OnClick()
list.rows[1]:OnClick()
for i = 1, 40 do tick(clock + .2) end
assert(attempts == 1 and list.status.text:match("offline"))

-- Some clients surface offline delivery through the localized system event.
name, key = "System Player", "system-player"
attempts = 0
C_ChatInfo.SendAddonMessage = function(_, _, route, address)
    if route == "WHISPER" and S.Identity(address) == key then
        attempts = attempts + 1
        emit("CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format(name))
    end
    return 0
end
emit("CHAT_MSG_ADDON", "SocialCredit2", "992:1:1:H~Horde~60~WARRIOR~", "GUILD", name)
for i = 1, 40 do tick(clock + .2) end
assert(attempts == 1)
""")
# Combat and instances alone do not block score generation, sync, or local review actions.
fighter, witness = Client("Combat Reviewer"), Client("Combat Witness")
for client in (fighter, witness):
    client.lua.execute("""
    function InCombatLockdown() return true end
    function IsInInstance() return true end
    """)
advance([fighter, witness], 12)
key = "test-subject"
assert fighter.s.SaveReview(key, 4, "Saved in combat")
advance([fighter, witness], 8)
assert witness.s.db.reviews[key][fighter.name].stars == 4
fighter.lua.execute("""
local S, key = state, "test-subject"
for _, name in ipairs({"First", "Second", "Third", "Fourth"}) do
    assert(S.Merge({subject = key, subjectName = "Test Subject",
        author = name:lower() .. "-tester", name = name .. " Tester",
        stars = 4, time = S.Now(), revision = S.Now(), text = ""}, true))
end
S.InvalidateScores()
assert(select(3, S.RatingSummary(key)))
SlashCmdList.SOCIALCREDITSYSTEM("")
assert(SocialCreditSystemProfile.score.text:match("SCS"))
SocialCreditSystemProfile.close:OnClick()
assert(not SocialCreditSystemProfile:IsShown())
""")
fighter.lua.execute("""
local send = C_ChatInfo.SendAddonMessage
chatLocked, apiLocked, lockResults = true, true, 0
Enum.SendAddonMessageResult.AddOnMessageLockdown = 11
C_ChatInfo.InChatMessagingLockdown = function() return chatLocked end
C_ChatInfo.SendAddonMessage = function(...)
    if apiLocked then
        lockResults = lockResults + 1
        return Enum.SendAddonMessageResult.AddOnMessageLockdown
    end
    return send(...)
end
""")
assert fighter.s.SaveReview(key, 5, "Edited while chat is locked")
advance([fighter, witness], 4)
assert fighter.g.lockResults == 0 and witness.s.db.reviews[key][fighter.name].stars == 4
fighter.g.chatLocked = False
advance([fighter, witness], 4)
assert fighter.g.lockResults > 0 and witness.s.db.reviews[key][fighter.name].stars == 4
fighter.g.apiLocked = False
advance([fighter, witness], 8)
assert witness.s.db.reviews[key][fighter.name].stars == 5
# Right-click chat lookup opens immediately even when the client blocks addon messages.
chat_reader = Client("Chat Reader")
chat_reader.lua.execute("""
local S = state
function InCombatLockdown() return true end
C_ChatInfo.InChatMessagingLockdown = function() return true end
local function click(name, unit)
    local action
    local menu = {CreateDivider = function() end, CreateButton = function(_, _, fn) action = fn end}
    menus.MENU_UNIT_FRIEND(nil, menu, {chatFrame = {}, name = name, unit = unit})
    assert(action)
    action()
    return SocialCreditSystemProfile
end
local p = click("Young Adventurer")
assert(p:IsShown() and p.name.text == "Young Adventurer")
assert(p.score.text == "Same-faction profile unverified" and p.status.text:find("/who", 1, true))
assert(S.db.profiles["young-adventurer"] == nil and not S.SaveReview("young-adventurer", 5, ""))
emit("CHAT_MSG_ADDON", "SocialCredit2", "997:1:1:H~Horde~42~WARRIOR~", "GUILD", "Young Adventurer")
assert(p:IsShown() and not p.preview and p.score.text == "SCS unlocks at level 60")
assert(S.SaveReview("young-adventurer", 5, ""))

-- A live nameplate can verify faction before the level is readable.
local originalName, originalLevel = UnitName, UnitLevel
function UnitName(unit)
    if unit == "nameplate1" then return "Visible Adventurer" end
    return originalName(unit)
end
UnitFullName = UnitName
function UnitLevel(unit) if unit ~= "nameplate1" then return originalLevel(unit) end end
C_NamePlate = {GetNamePlates = function() return {{namePlateUnitToken = "nameplate1"}} end}
p = click("Visible Adventurer")
assert(p:IsShown() and not p.preview and p.score.text == "Level unknown")
assert(p.portrait.texture == "nameplate1" and S.Viewable("visible-adventurer"))
assert(not S.Eligible("visible-adventurer") and S.SaveReview("visible-adventurer", 4, ""))
p.close:OnClick()
assert(not p:IsShown())

-- The native Who list can verify a low-level player without a unit or an addon reply.
local rows, queries = {}, {}
C_FriendList = {
    GetNumWhoResults = function() return #rows, #rows end,
    GetWhoInfo = function(index) return rows[index] end,
    SendWho = function(filter) queries[#queries + 1] = filter end,
}
p = click("Distant Player")
assert(p.preview and queries[1] == 'n-"Distant Player"')
rows = {{fullName = "Distant Players", level = 55, filename = "MAGE"}}
emit("WHO_LIST_UPDATE")
assert(p.preview and not S.Viewable("distant-player"))
rows[2] = {fullName = "Distant-Player-Layer", level = 38, filename = "MAGE", fullGuildName = "Who Guild"}
emit("WHO_LIST_UPDATE")
assert(not p.preview and S.db.profiles["distant-player"].level == 38)
assert(S.db.profiles["distant-player"].class == "MAGE" and p.guild.text == "Who Guild")
assert(S.SaveReview("distant-player", 4, ""))

-- Short /who results may arrive as localized system chat while the Who panel is shut.
WHO_LIST_GUILD_FORMAT = "%2$d Level %1$s %3$s %4$s <%5$s> - %6$s"
WHO_LIST_FORMAT = "%s: Level %d %s %s - %s"
LOCALIZED_CLASS_NAMES_MALE = {MAGE = "Mage", DEATHKNIGHT = "Death Knight"}
rows = {}
p = click("Manual Player")
assert(p.preview and #queries == 1)
emit("CHAT_MSG_SYSTEM", "35 Level |Hplayer:Manual-Players:9|h[Manual Players]|h Blood Elf Mage <Guild> - City")
assert(p.preview)
emit("CHAT_MSG_SYSTEM", "36 Level |Hplayer:Manual-Player:9|h[Manual Player]|h Blood Elf Death Knight <Guild> - City")
assert(not p.preview and S.db.profiles["manual-player"].level == 36)
assert(S.db.profiles["manual-player"].class == "DEATHKNIGHT")
emit("CHAT_MSG_SYSTEM", "|Hplayer:Cached-Player:9|h[Cached Player]|h: Level 25 Blood Elf Mage - City")
assert(not click("Cached Player").preview and S.db.profiles["cached-player"].level == 25)
""")
chat_reader.lua.execute("""
local S = state
local rows = {
    {fullName = "First Result", level = 34, filename = "MAGE"},
    {fullName = "Second Result", level = 57, filename = "WARRIOR"},
}
C_FriendList.GetWhoInfo = function(index) return rows[index] end
C_FriendList.GetNumWhoResults = function() return #rows end
local row = CreateFrame("Button")
local data = rows[1]
row.GetElementData = function() return data end
local root = {
    CreateDivider = function() end,
    CreateButton = function(_, label, fn)
        assert(label == "Open SCS")
        whoAction = fn
    end,
}
local nativeClicks, fallbackMenus = 0, 0
row:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        nativeClicks = nativeClicks + 1
        if data == rows[1] then
            menus.MENU_UNIT_FRIEND(nil, root, {name = "First Result"})
        end
    end
end)
MenuUtil = {CreateContextMenu = function(owner, generator)
    assert(owner == row)
    fallbackMenus = fallbackMenus + 1
    generator(owner, root)
end}
local initialize
ScrollUtil = {AddInitializedFrameCallback = function(_, fn, owner)
    initialize = function(other) fn(owner, other) end
end}
LFGWhoListFrame = {ScrollBox = {ForEachFrame = function(_, fn) fn(row) end}}
emit("ADDON_LOADED", "Blizzard_GroupFinder_VanillaStyle")
initialize(row)
row:OnMouseDown("LeftButton")
row:OnMouseUp("LeftButton")
tick(clock + .1)
assert(not whoAction and fallbackMenus == 0)
row:OnMouseDown("RightButton")
row:OnMouseUp("RightButton")
tick(clock + .1)
assert(whoAction and nativeClicks == 1 and fallbackMenus == 0)
whoAction()
assert(S.openSubject == "first-result" and S.db.profiles["first-result"].level == 34)

-- Reused rows still open the character currently displayed, including index-only rows.
data = {index = 2}
row.Name = row:CreateFontString()
row.Name:SetText("Second Result")
initialize(row)
whoAction = nil
row:OnMouseDown("RightButton")
row:OnMouseUp("RightButton")
tick(clock + .1)
assert(whoAction and fallbackMenus == 1)
whoAction()
assert(S.openSubject == "second-result" and S.db.profiles["second-result"].level == 57)
""")
print("PASS: Who list right-click menu, load-on-demand hooks, and recycled rows")
print("PASS: chat profile previews, verified low-level players, and unreadable levels during combat")
print("PASS: combat and instance scores and sync, including client lockdown and retry")
print("PASS: offline whisper gating, queue cancellation, reconnect, and lookup status")
print("PASS: minimap history, navigation, whisper and roster deduplication, and active reviews")
print("PASS: level-60 promotion, pre-60 review sync, and combat close handlers")
print("PASS: review deletion, backup and reconnect sync, native and Prat chat, half-star layout, talent benchmarks, and existing regressions")

release_client = Client("Release Tester", saved="""
function JoinTemporaryChannel() error("Joined a custom channel") end
function GetChannelName() error("Looked up a custom channel") end
""")
release_client.lua.execute("""
local S = state
local channelCalls = 0
function JoinTemporaryChannel() channelCalls = channelCalls + 1 end
function GetChannelName() channelCalls = channelCalls + 1; return 1 end
tick(clock + 4)
tickers[60]()
tick(clock + 1)
assert(channelCalls == 0)
assert(outbox[1][3] == "GUILD")
for _, packet in ipairs(outbox) do assert(packet[3] ~= "CHANNEL") end
emit("CHAT_MSG_ADDON", "SocialCredit2", "990:1:1:H~Horde~60~WARRIOR~Old Guild", "CHANNEL", "Old Peer")
assert(S.db.profiles["old-peer"] == nil)

assert(S.SaveReview("test-subject", 4, "A visible review"))
SlashCmdList.SOCIALCREDITSYSTEM("")
local profile = SocialCreditSystemProfile
assert(profile.rows[1].fullText == "A visible review" and profile.reviewHeading:IsShown())
SlashCmdList.SOCIALCREDITSYSTEM("self")
assert(S.openSubject == S.me.key and profile.score.text == "Your character")
assert(not profile.reviewHeading:IsShown() and not profile.filters.Newest:IsShown())
assert(not profile.edit:IsShown() and not profile.page:IsShown())
assert(not profile.previous:IsShown() and not profile.next:IsShown())
assert(not profile.rows[1].card:IsShown() and not profile.rows[1].fullText and profile.rows[1].body.text == "")
SlashCmdList.SOCIALCREDITSYSTEM("")
assert(profile.reviewHeading:IsShown() and profile.filters.Newest:IsShown() and profile.page:IsShown())
assert(profile.rows[1].card:IsShown() and profile.rows[1].fullText == "A visible review")
profile:Hide()

local scoreByKey = {}
local ratingSummary = S.RatingSummary
S.RatingSummary = function(key)
    local score = S.Viewable(key) and scoreByKey[key]
    if score then return 5, 4, score, true end
    return ratingSummary(key)
end
local function member(wing, index, guild, score, realm)
    local name = wing .. " " .. string.char(64 + index)
    local key = S.Identity(name)
    scoreByKey[key] = score
    S.Remember({key = key, name = name, guild = guild, guildRealm = realm, faction = S.faction, level = 60})
end
local icon = SocialCreditSystemMinimapButton
icon:OnClick()
local list = SocialCreditSystemHistory
for i = 1, 5 do
    member("Bright", i, "Bright", 900, S.realm)
    member("Amber", i, "Amber", 700, S.realm)
    member("Cedar", i, "Cedar", 700, S.realm)
    member("Remote", i, "Remote", 1000, "Another Realm")
    member("Legacy", i, "Legacy", 1000, nil)
end
for i = 1, 4 do member("Dusk", i, "Dusk", 1000, S.realm) end
member("Dusk", 5, "Dusk", nil, S.realm)
list.Guilds:OnClick()
assert(list.rows[1].name.text == "Bright" and list.rows[1].rank.text == "1")
assert(list.rows[1].score.text == "900.00 SCS" and list.rows[1].metadata.text == "5 scored members")
assert(list.rows[2].entry.name == "Amber" and list.rows[3].entry.name == "Cedar")
assert(not list.rows[4].entry)
member("Dusk", 5, "Dusk", 500, S.realm)
S.InvalidateScores()
tick(clock + 1)
assert(list.rows[1].entry.name == "Bright" and list.rows[2].name.text == "Dusk")
member("Bright", 5, "", 900, S.realm)
tick(clock + 1)
assert(list.rows[1].entry.name == "Dusk" and not list.rows[4].entry)
list.rows[1]:OnClick()
assert(not S.openSubject)
list.Reviewed:OnClick()
assert(list.rows[1].entry.subject == "test-subject" and not list.rows[1].rank:IsShown())
list.rows[1]:OnClick()
assert(S.openSubject == "test-subject")
""")
print("PASS: channel-free sync, private self profile, and five-member guild rankings")

