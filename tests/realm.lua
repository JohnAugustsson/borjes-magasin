-- Compatibility tests for conventional Name-Realm clients. Actual Forever
-- first-name/surname behavior is covered in surnames.lua.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function client(name, gold, db)
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.BorjesMagasinDB = db
    env.loadfile = function(path) return setfenv(assert(loadfile(path)), env) end
    env.dofile = function(path) return env.loadfile(path)() end
    local m = env.dofile("tests/mock_wow.lua")
    env.dofile("tests/live_mock.lua")(m, { name = name, gold = gold })
    m.realm = "Fisk"
    env.GetNormalizedRealmName = function() return "CAMWOWEU4Realm2PvP" end
    env.GetRealmName = function() return "CAMWOWEU4Realm2PvP" end
    m.roster = {
        { name = "Alice", level = 42, classID = 1, presence = 1 },
        { name = "Bob-CAMWOWEU4Realm2PvP", level = 40, classID = 8, presence = 1 },
        { name = "Clara-Fisk", level = 39, classID = 5, presence = 1 },
        { name = "Bob-OtherRealm", level = 40, classID = 8, presence = 1 },
    }
    m.party = { party1 = "Bob" }
    local bm = env.dofile("tests/load.lua")
    m.Fire("ADDON_LOADED", "borjes-magasin"); m.Fire("PLAYER_LOGIN")
    return { b = bm, m = m, env = env, cursor = 0 }
end
local function relay(from, to)
    for i = from.cursor + 1, #from.m.sent do to.m.Fire("CHAT_MSG_ADDON", unpack(from.m.sent[i], 1, 4)) end
    from.cursor = #from.m.sent
end
local function advance(a, b, seconds)
    for i = 1, seconds * 2 do a.m.Advance(.5); b.m.Advance(.5); relay(a, b); relay(b, a) end
end
local a, b = client("Alice", 123456), client("Bob", 654321)
check(a.b.Roster[a.b.SelfID] ~= nil, "Public self identity must match the unqualified guild roster entry")
check(a.b.GetMember(a.b.SelfID).gold == 123456, "Own snapshot is displayed under the correct guild member")
check(a.b.Canonical("Bob") == "bob-fisk" and a.b.Canonical("Bob-CAMWOWEU4Realm2PvP") == "bob-fisk", "Bare, public and internal local-realm names normalize together")
check(a.b.Canonical("Bob-OtherRealm") == "bob-otherrealm", "Other realms remain distinct")
local party = a.b.FilterMembers("", "name", "week", true, true)
check(#party == 2 and party[1].id == "alice-fisk" and party[2].id == "bob-fisk", "Party filter matches public unit names to mixed guild-roster names")
advance(a, b, 40)
check(a.b.GuildCache["bob-fisk"] and a.b.GetMember("bob-fisk").gold == 654321, "Public-realm chat sender is accepted against the internal-realm roster")
check(b.b.GuildCache["alice-fisk"] and b.b.GetMember("alice-fisk").gold == 123456, "Unqualified roster receives the other client's snapshot")
a.b.Open(); a.m.Click(a.b.Window.partyFilter)
check(a.b.State.partyOnly and #a.b.FilterMembers("", "name", "week", true, true) == 2, "Party button works against actual mixed realm naming")
a.m.party = { party1 = "Clara" }
a.m.Click(a.b.Window.partyFilter); a.m.Click(a.b.Window.partyFilter)
local changed = a.b.FilterMembers("", "name", "week", true, true)
check(#changed == 2 and changed[2].id == "clara-fisk", "Clicking refreshes party membership even before a group event arrives")
local fullName = a.env.UnitFullName
a.env.UnitFullName = function(unit) if unit == "party1" then return nil end; return fullName(unit) end
a.env.UnitName = function(unit) if unit == "party1" then return "Clara", "" end end
a.b.UpdateParty()
check(a.b.Party["clara-fisk"], "UnitName fallback and an empty local realm still match")
a.env.IsInRaid = function() return true end
a.env.GetNumGroupMembers = function() return 4 end
a.env.UnitIsUnit = function(unit) return unit == "raid1" end
a.env.GetRaidRosterInfo = function(i) return "Unused", nil, i <= 2 and 1 or 2 end
a.m.units.raid1 = { name = "Alice" }; a.m.units.raid2 = { name = "Clara" }
a.m.units.raid3 = { name = "Bob" }; a.m.units.raid4 = { name = "Bob-OtherRealm" }
a.b.UpdateParty()
local raid = a.b.FilterMembers("", "name", "week", true, true)
check(#raid == 2 and raid[2].id == "clara-fisk", "Raid party filter includes only the player's subgroup")
a.b.RequestSync(true)
check(a.b.Window.status:GetText() == "Sync queued" and a.b.Window.sync.label:GetText() == "Sync queued...", "Manual sync gives immediate visible queue feedback")
local sawProgress = false
for i = 1, 80 do
    advance(a, b, .5)
    sawProgress = sawProgress or a.b.Window.status:GetText():find("Sending snapshot", 1, true)
end
check(sawProgress, "Packet progress appears after the existing send cooldown")
advance(a, b, 40)
check(a.b.SyncRequest.count == 1 and a.b.Window.status:GetText() == "Received 1 guild snapshot", "Peer response produces a visible received count")
local sent = #a.m.sent
a.b.RequestSync(true); advance(a, b, 45)
check(#a.m.sent > sent and a.b.SyncRequest.count == 1, "A later manual request still works")
local solo = client("Alice", 100)
solo.m.Advance(40); solo.b.Open(); solo.b.RequestSync(true); solo.m.Advance(40)
check(solo.b.SyncStatus() == "Waiting for guild replies", "A successful local send is not falsely reported as peer delivery")
solo.m.Advance(60)
check(solo.b.Window.status:GetText() == "No guild replies received", "No responders is reported explicitly after the response window")
solo.b.ToggleSharing(); solo.b.RequestSync(true)
check(solo.b.Window.status:GetText() == "Sharing paused", "Clicking while paused explains why nothing is sent")
solo.b.ToggleSharing(); solo.m.restricted = true; solo.m.sendResult = 11; solo.b.RequestSync(true); solo.m.Advance(5)
check(solo.b.Window.status:GetText() == "Client restricts addon messages", "Client send failures appear without waiting for another UI refresh")
local invalidSender = "Unlisted-Fisk"
b.b.Receive(b.b.PREFIX, "1|H", "GUILD", invalidSender)
check(b.b.GuildCache[invalidSender:lower()] == nil, "Realm normalization does not admit non-guild senders")
local source = b.b.UnpackProfile(b.b.Character.wire)
source.at = b.m.epoch; source.pvp.allKills = 7
local characterWire = b.b.PackProfile(source)
source.gold = 888; local cachedWire = b.b.PackProfile(source)
source.at = source.at + 1; source.gold = 999; local newerWire = b.b.PackProfile(source)
local cacheScope = b.b.GuildScope
local migrated = client("Bob", 123, {
    characters = { ["bob-camwoweu4realm2pvp"] = { wire = characterWire } },
    guilds = { [cacheScope] = {
        ["alice-camwoweu4realm2pvp"] = { wire = cachedWire, received = b.m.epoch },
        ["alice-fisk"] = { wire = newerWire, received = b.m.epoch + 1 },
        ["alice-otherrealm"] = { wire = cachedWire, received = b.m.epoch },
    } },
})
check(migrated.b.PVP.allKills == 7 and migrated.b.DB.characters["bob-fisk"], "Character history migrates from the old internal-realm key")
check(migrated.b.GuildScope == cacheScope, "Existing guild storage namespace is retained")
check(migrated.b.GuildCache["alice-fisk"].profile.gold == 999 and not migrated.b.GuildCache["alice-camwoweu4realm2pvp"], "Cached aliases merge using the newest valid snapshot")
check(migrated.b.GuildCache["alice-otherrealm"].profile.gold == 888, "Migration preserves a different realm's identity")
print(checks .. " realm identity and communication regression checks passed.")
