-- Independent Lua globals simulate separate clients, connected only by the
-- same public CHAT_MSG_ADDON payloads used by WoW. No transport shortcuts.
local checks = 0
local function check(value, description) checks = checks + 1; assert(value, description) end
local function client(name, gold, db)
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.BorjesMagasinDB = db
    env.loadfile = function(path) return setfenv(assert(loadfile(path)), env) end
    env.dofile = function(path) return env.loadfile(path)() end
    local mock = env.dofile("tests/mock_wow.lua")
    env.dofile("tests/live_mock.lua")(mock, { name = name, gold = gold })
    local bm = env.dofile("tests/load.lua")
    mock.Fire("ADDON_LOADED", "borjes-magasin"); mock.Fire("PLAYER_LOGIN")
    return { env = env, m = mock, b = bm, cursor = 0 }
end
local function relay(from, to)
    for i = from.cursor + 1, #from.m.sent do
        local msg = from.m.sent[i]; to.m.Fire("CHAT_MSG_ADDON", unpack(msg, 1, 4))
    end
    from.cursor = #from.m.sent
end
local function advance(a, b, seconds)
    for _ = 1, seconds * 2 do a.m.Advance(.5); b.m.Advance(.5); relay(a, b); relay(b, a) end
end
local a, b = client("Alice", 1234567), client("Bob", 7654321)
check(a.b.GetMember("bob-forever").gold == nil, "No placeholder gold before discovery")
advance(a, b, 40)
check(a.b.GetMember("bob-forever").gold == 7654321, "Alice receives Bob's full snapshot")
check(b.b.GetMember("alice-forever").gold == 1234567, "Bob receives Alice's full snapshot")
check(a.b.GetMember("clara-forever").allKills == nil, "Non-addon / unobserved member remains unknown")
check(a.b.GetMember("bob-forever").gear[1].link == b.m.items[1], "Enchants and item string survive transport")
check(a.b.GetMember("bob-forever").quests.deadmines[1].status == 2, "Quest log status survives transport")
for _, c in ipairs({ a, b }) do
    for i, packet in ipairs(c.m.sent) do
        if i > 1 then check(packet.at - c.m.sent[i - 1].at >= .399, "Sending is throttled") end
        check(packet[3] == "GUILD" and packet[1] == "BorjesMagasin1", "Only registered hidden guild messages")
    end
end
local m, bm, env = a.m, a.b, a.env
check(bm.SelfProfile.quests[2][1] == 1, "Nil log index means not in log, not unavailable")
check(bm.SelfProfile.quests[8][1] == 5, "Unfinished prerequisite is reported")
check(bm.SelfProfile.quests[16][1] == 6, "Opposite faction quests are unavailable")
m.quests[166].done = true; m.Fire("QUEST_LOG_UPDATE"); m.Advance(2)
check(bm.SelfProfile.quests[1][1] == 3, "Ready-to-turn-in update")
m.complete[166] = true; m.quests[166] = nil; m.Fire("QUEST_TURNED_IN", 166); m.Advance(2)
check(bm.SelfProfile.quests[1][1] == 4, "Quest completion update")
m.gold = 543210; m.Fire("PLAYER_MONEY"); m.Advance(2)
check(bm.GetMember("alice-forever").gold == 543210, "Actual money event")
m.items[16] = "item:333:444:0:0:0:0:0:0:42"; m.Fire("PLAYER_EQUIPMENT_CHANGED", 16); m.Advance(2)
check(bm.SelfProfile.items[17] == m.items[16], "Main hand inventory mapping and event")
m.items[17] = "item:555"; m.Fire("UNIT_INVENTORY_CHANGED", "player"); m.Advance(2)
check(bm.SelfProfile.items[18] == "item:555", "Off hand capture")
env.CharacterFrame = env.CreateFrame("Frame", "CharacterFrame", env.UIParent); env.CharacterFrame:Hide()
m.Fire("ADDON_LOADED", "Blizzard_CharacterUI"); m.gold = 600000; env.CharacterFrame:Show(); m.Advance(2)
check(bm.SelfProfile.gold == 600000, "Opening character pane refreshes data")
m.items[1] = { secret = true }; bm.Capture()
check(bm.SelfProfile.items[1] == false, "Restricted item is unknown, never empty")
m.items[1] = "item:123"
local function kill(name, level, options)
    options = options or {}
    m.units.target = { name = name, guid = "Player-2-" .. name, level = level }
    m.Fire("PLAYER_TARGET_CHANGED")
    m.instance = options.instance
    m.Fire("PARTY_KILL", options.attacker or "Player-1-Alice", "Player-2-" .. name)
    m.instance = nil
end
kill("Enemy", 40)
check(bm.PVP.allKills == 1 and bm.PVP.allGanks == 0, "Qualifying personal world killing blow")
kill("Enemy", 40)
check(bm.PVP.allKills == 1, "Repeated death event is deduplicated")
kill("Gray", 25)
check(bm.PVP.allGanks == 1, "Gray victim uses client difficulty color")
kill("Orange", 48)
check(bm.PVP.allKills == 2, "Higher-level opponents qualify")
kill("Low", 35)
check(bm.PVP.recent[1][5] == "Out of range" and bm.PVP.allGanks == 1, "Low non-gray opponent is neither ranked nor a gank")
kill("Hidden", -1)
check(bm.PVP.recent[1][5] == "Unclassified" and bm.PVP.allKills == 2, "Unreadable level stays unclassified")
kill("BG", 40, { instance = true }); kill("PartyKill", 40, { attacker = "Player-1-Bob" })
check(bm.PVP.allKills == 2, "Instanced kills and someone else's blow do not count")
m.units.pet = { name = "Pet", guid = "Pet-1-1" }
kill("PetVictim", 40, { attacker = "Pet-1-1" })
check(bm.PVP.allKills == 3, "Own pet killing blow counts")
m.Fire("PARTY_KILL", { secret = true }, "Player-2-Secret")
check(bm.PVP.allKills == 3, "Restricted event is ignored without inference")
m.units.target = nil; m.Fire("PARTY_KILL", "Player-1-Alice", "Player-2-Unseen")
check(bm.PVP.recent[1][5] == "Unclassified", "Unseen GUID never inherits another target's level")
advance(a, b, 50)
check(b.b.GetMember("alice-forever").gold == 1234567, "Local changes do not broadcast with heartbeat off")
bm.RequestSync(); advance(a, b, 50)
check(b.b.GetMember("alice-forever").allKills == 3, "Real captured counters arrive on the peer")
check(b.b.GetMember("alice-forever").gold == 600000, "Manual sync shares the latest money")
-- Serialize/reload with the same saved variables, using no shared runtime globals.
local saved = a.env.BorjesMagasinDB
local reloaded = client("Alice", 600000, saved)
check(reloaded.b.PVP.allKills == 3 and reloaded.b.PVP.allGanks == 1, "Own counters survive reload")
check(reloaded.b.GetMember("bob-forever").gold == 7654321, "Offline cache survives reload")
reloaded.m.party = {}; reloaded.m.Fire("GROUP_ROSTER_UPDATE")
check(#reloaded.b.FilterMembers("", "name", "week", true, true) == 1, "Party filter follows live group changes")
local old = b.b.GuildCache["alice-forever"].wire
local function inject(wire, sender, id, order, drop)
    local n = math.ceil(#wire / 180)
    for j = 1, n do
        local i = order == "reverse" and n - j + 1 or j
        if i ~= drop then
            b.b.Receive(b.b.PREFIX, "1|S|" .. id .. "|" .. i .. "|" .. n .. "|" .. wire:sub((i - 1) * 180 + 1, i * 180), "GUILD", sender)
        end
    end
end
local valid = bm.Decode(bm.PackProfile(bm.SelfProfile)); valid[6] = 777777
local wire = bm.Encode(valid)
inject(wire, "Stranger-Forever", "123-1")
check(b.b.GuildCache["stranger-forever"] == nil, "Non-guild sender cannot create a member")
inject(wire, "Alice-Forever", "123-2", nil, 2)
check(b.b.GuildCache["alice-forever"].wire == old, "Incomplete snapshot never replaces good data")
b.m.Advance(91)
inject(wire, "Alice-Forever", "123-3", "reverse")
check(b.b.GetMember("alice-forever").gold == 777777, "Out-of-order complete snapshot assembles")
inject(wire, "Alice-Forever", "123-3")
check(b.b.GetMember("alice-forever").gold == 777777, "Duplicate completed message is harmless")
valid[7][1] = "|Hspell:1|hSpoof|h"; local malformed = bm.Encode(valid)
inject(malformed, "Alice-Forever", "123-4")
check(b.b.GetMember("alice-forever").gold == 777777, "Reject arbitrary links in equipment")
for _, garbage in ipairs({ "a999:", "s999999999999:", "n1:e", "a1:a1:a1:a1:a1:a1:a1:a1:a0:", "return os.execute('oops')", "s1:\0" }) do
    check(bm.Decode(garbage) == nil, "Reject malformed codec input")
end
valid[7][1], valid[6], valid[2] = "item:123", 888888, valid[2] - 100
inject(bm.Encode(valid), "Alice-Forever", "123-5")
check(b.b.GetMember("alice-forever").gold == 777777, "Old snapshots cannot overwrite newer ones")
b.b.Receive(b.b.PREFIX, "1|S|777|1|999999|x", "GUILD", "Alice-Forever")
b.b.Receive(b.b.PREFIX, "2|H", "GUILD", "Alice-Forever")
check(b.b.GetMember("alice-forever").gold == 777777, "Reject over-limit chunks and protocol mismatch")
local before = #m.sent
bm.ToggleSharing(); m.gold = 999999; m.Fire("PLAYER_MONEY"); m.Advance(40)
check(#m.sent == before and bm.SelfProfile.gold == 999999, "Paused sharing sends nothing, but keeps collecting locally")
bm.ToggleSharing(); m.Advance(5)
check(#m.sent == before, "Resuming sharing with heartbeat off does not broadcast")
m.restricted = true; m.sendResult = 11; bm.RequestSync(); m.Advance(40)
check(#m.sent == before and bm.SyncStatus() == "Client restricts addon messages", "Client restriction is visible and sends no chat fallback")
m.restricted = false; m.sendResult = 0; advance(a, b, 50)
check(b.b.GetMember("alice-forever").gold == 999999, "Sync resumes after restriction clears")
local localKills = bm.PVP.allKills
m.guild = nil; m.Fire("PLAYER_GUILD_UPDATE"); m.Advance(2)
check(#bm.FilterMembers("", "name") == 1 and bm.GuildCache == nil, "Leaving guild removes foreign cached profiles from the view")
before = #m.sent; m.Advance(40)
check(#m.sent == before, "No guild means no outgoing messages")
m.guild = "OtherGuild"; m.roster = { { name = "Alice-Forever", level = 42, classID = 1, presence = 1 } }
m.Fire("PLAYER_GUILD_UPDATE"); m.Advance(2)
check(bm.GetMember("alice-forever").allKills == localKills and #bm.FilterMembers("", "name") == 1, "New guild retains only own character data")
-- Day rollover changes the rolling window without erasing lifetime history.
m.epoch = m.epoch + 8 * 86400; bm.Capture()
check(bm.GetMember("alice-forever").weekKills == 0 and bm.PVP.allKills == localKills, "Seven-day rollover retains lifetime totals")
check(#bm.History == 1, "History only contains actual observed days")
local leaving, receiver = client("Alice", 100), client("Bob", 200)
advance(leaving, receiver, 40)
leaving.m.gold = 123456
leaving.m.Fire("PLAYER_LOGOUT"); relay(leaving, receiver)
check(receiver.b.GetMember("alice-forever").gold == 123456, "Immediate logout packets assemble into the latest snapshot on another client")
print(checks .. " checks passed across separate client environments, capture, persistence and protocol edge cases.")
