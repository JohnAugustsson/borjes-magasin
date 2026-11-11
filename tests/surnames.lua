-- Real Forever semantics: UnitFullName returns first name, surname; the guild
-- roster uses a space and addon senders may use a space or a hyphen.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function client(name, gold, db, hyphenSender)
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.BorjesMagasinDB = db
    env.loadfile = function(path) return setfenv(assert(loadfile(path)), env) end
    env.dofile = function(path) return env.loadfile(path)() end
    local m = env.dofile("tests/mock_wow.lua")
    env.dofile("tests/live_mock.lua")(m, { name = name, gold = gold })
    m.realm = "CAMWOWEU4Realm2PvP"
    env.GetRealmName = function() return m.realm end
    env.RegionalUniqueNamesEnabled = function() return true end
    m.roster = {
        { name = "Suer Fisk", level = 39, classID = 1, presence = 1 },
        { name = "Suer Stone", level = 40, classID = 8, presence = 1 },
        { name = "Bogge Tjogge", level = 40, classID = 8, presence = 1 },
        { name = "Bogge Fisk", level = 39, classID = 5, presence = 1 },
        { name = "Mormis Sidlöv", level = 42, classID = 1, presence = 1 },
    }
    m.party = { party1 = "Bogge Tjogge" }
    local function fullName(unit)
        if unit == "player" then return m.name end
        return m.party[unit] or m.units[unit] and m.units[unit].name
    end
    env.GetUnitName = fullName
    env.UnitFullName = function(unit)
        local n = fullName(unit)
        if n then return n:match("^(%S+) (%S+)$") end
    end
    env.UnitName, env.UnitNameUnmodified = env.UnitFullName, env.UnitFullName
    local send = env.C_ChatInfo.SendAddonMessage
    env.C_ChatInfo.SendAddonMessage = function(...)
        local result = send(...)
        if result == 0 then m.sent[#m.sent][4] = hyphenSender and name:gsub(" ", "-") or name end
        return result
    end
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
local a, b = client("Suer Fisk", 123456), client("Bogge Tjogge", 654321, nil, true)
check(a.b.SelfName == "Suer Fisk", "The player's full name includes the surname, not just Suer")
check(a.b.SelfID == "suer-fisk" and b.b.SelfID == "bogge-tjogge", "Canonical identity contains both name words and no local player's surname suffix")
local all = a.b.FilterMembers("", "name")
check(#all == 5, "Guild roster and self produce exactly one row per full character name")
check(a.b.GetMember("suer-fisk").gold == 123456 and a.b.GetMember("suer-fisk").name == "Suer Fisk", "Own gold and full name share one row")
check(a.b.Canonical("Bogge Tjogge") == a.b.Canonical("Bogge-Tjogge") and a.b.Canonical("Bogge", "Tjogge") == "bogge-tjogge", "Spaced names, transport names and separate API results agree")
check(a.b.Canonical("Suer Fisk") ~= a.b.Canonical("Suer Stone") and a.b.Canonical("Suer Fisk") ~= a.b.Canonical("Bogge Fisk"), "Neither first names nor surnames alone merge different people")
check(a.b.Canonical("Suer") == nil and a.b.Canonical("Bogge", "") == nil, "Incomplete names never inherit the current player's surname")
local party = a.b.FilterMembers("", "name", "week", true, true)
check(#party == 2 and a.b.Party["suer-fisk"] and a.b.Party["bogge-tjogge"] and not a.b.Party["bogge-fisk"], "Party filter matches full identities and excludes same-first-name members")
a.b.Open(); a.m.Click(a.b.Window.partyFilter)
local shown = 0
for _, row in ipairs(a.b.Window.pages.pvp.rows) do if row:IsShown() then shown = shown + 1 end end
check(a.b.State.partyOnly and shown == 2, "Actual Party only button renders the two party members")
advance(a, b, 40)
check(a.b.GuildCache["bogge-tjogge"] and a.b.GetMember("bogge-tjogge").gold == 654321, "Hyphenated sender matches the spaced guild roster")
check(b.b.GuildCache["suer-fisk"] and b.b.GetMember("suer-fisk").gold == 123456, "Spaced sender matches the other client's different surname")
check(a.b.GetMember("bogge-fisk").gold == nil, "A received snapshot cannot be attached to a different surname")
a.b.Receive(a.b.PREFIX, "1|H", "GUILD", "Bogge")
a.b.Receive(a.b.PREFIX, "1|H", "GUILD", "Bogge Stranger")
check(a.b.SaveSyncReport().diagnostic.rejected["unknown guild sender"] == 2, "First-name-only and non-guild senders remain rejected")
a.m.party = { party1 = "Mormis Sidlöv" }; a.m.Fire("GROUP_ROSTER_UPDATE")
check(a.b.Party["mormis-sidlöv"] and not a.b.Party["bogge-tjogge"], "Group updates preserve accented surnames")
a.env.UnitFullName = function() return nil end; a.b.UpdateParty()
check(a.b.Party["mormis-sidlöv"], "UnitName fallback preserves both words")
a.env.UnitName = function(unit) return (a.env.GetUnitName(unit) or ""):match("^(%S+)") end
a.b.UpdateParty()
check(a.b.Party["mormis-sidlöv"], "Complete GetUnitName can fill an unavailable surname")
a.env.GetUnitName = function(unit) if unit == "party1" then return "Mormis" end end
a.b.UpdateParty()
check(not a.b.Party["mormis-sidlöv"], "Missing surname does not guess at a guild member")
a.env.IsInRaid = function() return true end; a.env.GetNumGroupMembers = function() return 4 end
a.env.UnitIsUnit = function(unit) return unit == "raid1" end
a.env.GetRaidRosterInfo = function(i) return "Unused", nil, i <= 2 and 1 or 2 end
a.env.UnitFullName = function(unit)
    local names = { raid1 = { "Suer", "Fisk" }, raid2 = { "Suer", "Stone" }, raid3 = { "Bogge", "Tjogge" }, raid4 = { "Bogge", "Fisk" } }
    if names[unit] then return unpack(names[unit]) end
end
a.b.UpdateParty()
check(a.b.Party["suer-fisk"] and a.b.Party["suer-stone"] and not a.b.Party["bogge-tjogge"], "Raid subgroup filter uses both words")
local p = a.b.UnpackProfile(a.b.Character.wire)
p.pvp.allKills = 7; local ownWire = a.b.PackProfile(p)
p.gold = 888; local older = a.b.PackProfile(p)
p.at = p.at + 1; p.gold = 999; local newer = a.b.PackProfile(p)
local scope = a.b.GuildScope
local migrated = client("Suer Fisk", 100, {
    characters = { ["suer-fisk"] = { wire = ownWire }, ["suer-stone"] = { wire = older } },
    guilds = { [scope] = {
        ["bogge tjogge-fisk"] = { wire = older, received = a.m.epoch },
        ["bogge tjogge-camwoweu4realm2pvp"] = { wire = newer, received = a.m.epoch + 1 },
        ["bogge fisk-fisk"] = { wire = older, received = a.m.epoch },
    } },
})
check(migrated.b.PVP.allKills == 7 and migrated.b.DB.characters["suer-stone"].wire == older, "Existing local history is preserved without taking another character's history")
check(migrated.b.GuildCache["bogge-tjogge"].profile.gold == 999 and migrated.b.GuildCache["bogge-fisk"].profile.gold == 888, "Old erroneous realm suffixes migrate by full name and keep the newest snapshot")
check(not migrated.b.GuildCache["bogge tjogge-fisk"], "Old duplicate cache keys no longer appear")
local solo = client("Suer Fisk", 100)
solo.m.restricted = true; solo.m.Advance(130)
local report = solo.b.SaveSyncReport()
check(report.status == "Client restricts addon messages" and report.diagnostic.blocked > 0 and report.diagnostic.sent == 0, "Timeout preserves and records the actual client restriction")
check(report.regionalNames == true and report.units[1].surname == "Fisk", "Diagnostics label surnames correctly")
print(checks .. " Forever surname, migration and communication checks passed.")
