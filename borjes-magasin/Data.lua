local _, BM = ...

BM.VERSION = "0.3.6"
BM.ClassColors = {
    WARRIOR = { .78, .61, .43 }, PALADIN = { .96, .55, .73 },
    HUNTER = { .67, .83, .45 }, ROGUE = { 1, .96, .41 },
    PRIEST = { .95, .95, .95 }, MAGE = { .25, .78, .92 },
    WARLOCK = { .62, .52, .90 }, DRUID = { 1, .49, .04 }, SHAMAN = { .1, .45, 1 }, UNKNOWN = { .6, .65, .7 },
}
BM.Statuses = {
    [0] = { label = "Unknown / no snapshot", short = "Unknown", color = { .55, .60, .67 } },
    { label = "Not in log", short = "Not in log", color = { .55, .60, .67 } },
    { label = "In progress", short = "In progress", color = { .42, .71, .94 } },
    { label = "Ready to turn in", short = "Ready", color = { .96, .77, .40 } },
    { label = "Completed", short = "Done", color = { .45, .80, .65 } },
    { label = "Prerequisite missing", short = "Blocked", color = { .91, .48, .43 } },
    { label = "Requirements not met", short = "Unavailable", color = { .55, .60, .67 } },
}
BM.Dungeons = {
    { id = "deadmines", name = "The Deadmines", range = "Level 18-26", quests = {
        { id = 166, minLevel = 14, faction = "Alliance", prereq = 155, name = "The Defias Brotherhood", short = "Defias", objective = "Defeat the Defias leader" },
        { id = 2040, minLevel = 15, faction = "Alliance", name = "Underground Assault", short = "Assault", objective = "Collect the Gnoam Sprecklesprocket" },
        { id = 168, minLevel = 14, faction = "Alliance", name = "Collecting Memories", short = "Memories", objective = "Collect the miners' union cards" },
        { id = 167, minLevel = 15, faction = "Alliance", name = "Oh Brother...", short = "Brother", objective = "Recover the missing badge" },
    } },
    { id = "wailing", name = "Wailing Caverns", range = "Level 17-27", quests = {
        { id = 1486, minLevel = 13, name = "Deviate Hides", short = "Hides", objective = "Collect 20 deviate hides" },
        { id = 1487, minLevel = 15, name = "Deviate Eradication", short = "Deviates", objective = "Defeat the deviate creatures" },
        { id = 959, minLevel = 14, name = "Trouble at the Docks", short = "Docks", objective = "Recover the shipment" },
        { id = 1491, minLevel = 13, prereq = 865, name = "Smart Drinks", short = "Drinks", objective = "Collect 6 portions of wailing essence" },
    } },
    { id = "stockades", name = "The Stockade", range = "Level 24-32", quests = {
        { id = 391, minLevel = 16, faction = "Alliance", prereq = 389, name = "The Stockade Riots", short = "Riots", objective = "Defeat the riot leader" },
        { id = 387, minLevel = 22, faction = "Alliance", name = "Quell the Uprising", short = "Uprising", objective = "Defeat the escaped prisoners" },
        { id = 388, minLevel = 22, faction = "Alliance", name = "The Color of Blood", short = "Bandanas", objective = "Collect 10 red wool bandanas" },
        { id = 377, minLevel = 22, faction = "Alliance", name = "Crime and Punishment", short = "Justice", objective = "Bring the criminal to justice" },
    } },
    { id = "scarlet", name = "Scarlet Monastery", range = "Level 30-45", quests = {
        { id = 1053, minLevel = 34, faction = "Alliance", prereq = 1052, name = "In the Name of the Light", short = "The Light", objective = "Defeat the four Scarlet leaders" },
        { id = 1050, minLevel = 28, faction = "Alliance", name = "Mythology of the Titans", short = "Titans", objective = "Recover the book from the library" },
        { id = 96800, minLevel = 30, faction = "Alliance", name = "Past Due", short = "Past Due", objective = "Recover the Runemasters book" },
        { id = 1113, minLevel = 30, faction = "Horde", prereq = 1109, name = "Hearts of Zeal", short = "Hearts", objective = "Collect 20 hearts of zeal" },
    } },
    { id = "razorfen", name = "Razorfen Downs", range = "Level 37-46", quests = {
        { id = 3636, minLevel = 39, faction = "Alliance", name = "Bring the Light", short = "The Light", objective = "Defeat the lich" },
        { id = 6626, minLevel = 28, name = "A Host of Evil", short = "Host", objective = "Clear the entrance of undead" },
        { id = 3523, minLevel = 32, name = "Scourge of the Downs", short = "Scourge", objective = "Speak with Belnistrasz inside the dungeon" },
        { id = 3525, minLevel = 32, prereq = 3523, name = "Extinguishing the Idol", short = "The Idol", objective = "Protect the ritual at the idol" },
    } },
    { id = "zulfarrak", name = "Zul'Farrak", range = "Level 44-54", quests = {
        { id = 2768, minLevel = 40, name = "Divino-matic Rod", short = "The Rod", objective = "Recover the divino-matic rod" },
        { id = 3042, minLevel = 40, name = "Troll Temper", short = "Temper", objective = "Collect 20 troll tempers" },
        { id = 2770, minLevel = 40, name = "Gahz'rilla", short = "Gahz'rilla", objective = "Recover the electrified scale" },
        { id = 3527, minLevel = 40, prereq = 3520, name = "The Prophecy of Mosh'aru", short = "Prophecy", objective = "Recover the two tablets" },
    } },
}

-- Inventory slot IDs are distinct from the display order used by the UI.
BM.GearSlots = {
    { "Head", 1 }, { "Neck", 2 }, { "Shoulders", 3 }, { "Back", 15 },
    { "Chest", 5 }, { "Shirt", 4 }, { "Tabard", 19 }, { "Wrists", 9 },
    { "Hands", 10 }, { "Waist", 6 }, { "Legs", 7 }, { "Feet", 8 },
    { "Ring 1", 11 }, { "Ring 2", 12 }, { "Trinket 1", 13 }, { "Trinket 2", 14 },
    { "Main hand", 16 }, { "Off hand", 17 }, { "Ranged", 18 },
}
BM.QuestList, BM.Members, BM.Roster = {}, {}, {}
for _, d in ipairs(BM.Dungeons) do
    for _, q in ipairs(d.quests) do BM.QuestList[#BM.QuestList + 1] = q end
end
function BM.Secret(v) return issecretvalue and issecretvalue(v) or false end
function BM.Probe(fn, ...)
    if type(fn) ~= "function" then return nil, false end
    local ok, v = pcall(fn, ...)
    if not ok or BM.Secret(v) then return nil, false end
    return v, true
end
function BM.Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if not ok then return nil end
    local values = { a, b, c, d, e, f, g, h, i, j, k }
    for n = 1, 11 do if BM.Secret(values[n]) then values[n] = nil end end
    return unpack(values, 1, 11)
end
function BM.Text(s, length)
    if BM.Secret(s) or type(s) ~= "string" then return "" end
    return s:gsub("[%z\1-\31\127|]", ""):sub(1, length or 96)
end
function BM.Integer(n, low, high)
    return not BM.Secret(n) and type(n) == "number" and n == math.floor(n) and n >= low and n <= high
end
function BM.Now() return BM.Read(GetServerTime) or time() end
function BM.Day() return math.floor(BM.Now() / 86400) end
local function realmKey(realm)
    if BM.Secret(realm) or type(realm) ~= "string" or realm == "" then return nil end
    return (realm:gsub("[%s%-]", "")):lower()
end
function BM.SetIdentityRealm(unitRealm, displayRealm)
    -- Compatibility for clients with conventional Name-Realm identities.
    -- Never use this for Forever: the second unit-name result is a surname.
    BM.IdentityRealm = realmKey(unitRealm) or realmKey(displayRealm) or realmKey(BM.Realm) or ""
    BM.RealmAliases = {}
    for _, realm in pairs({ BM.Realm, unitRealm, displayRealm }) do
        local key = realmKey(realm)
        if key then BM.RealmAliases[key] = BM.IdentityRealm end
    end
end
function BM.FullCharacterName(name, surname)
    if BM.Secret(name) or BM.Secret(surname) or type(name) ~= "string" or #name > 96
        or name:find("[%c|]") then return nil end
    name = name:match("^%s*(.-)%s*$"):gsub("%s+", " ")
    local first, last = name:match("^([^%s%-]+)[ %-]([^%s%-]+)$")
    if not first and not name:find("[%s%-]") and name ~= "" and type(surname) == "string"
        and #surname > 0 and #surname <= 48 and not surname:find("[%s%c|%-]") then
        first, last = name, surname
    end
    if first then return first .. " " .. last end
end
function BM.Canonical(name, realm)
    if BM.Secret(name) or type(name) ~= "string" or name == "" then return nil end
    if BM.RegionalNames then
        local full = BM.FullCharacterName(name, realm)
        return full and full:gsub(" ", "-"):lower() or nil
    end
    local n, r = name:match("^([^%-]+)%-(.+)$")
    n, r = n or name, realmKey(r) or realmKey(realm) or BM.IdentityRealm or realmKey(BM.Realm) or ""
    r = BM.RealmAliases and BM.RealmAliases[r] or r
    return (n .. "-" .. r):lower()
end
function BM.StoredMemberID(id)
    if BM.RegionalNames and type(id) == "string" then
        -- Versions through 0.3.5 appended an erroneous realm/surname suffix to
        -- the full guild-roster name. Only migrate a complete two-word prefix;
        -- never guess someone's surname from a first name alone.
        local full = id:match("^([^%-]+%s+[^%-]+)%-.+$")
        if full then return BM.Canonical(full) end
    end
    return BM.Canonical(id)
end
function BM.Age(at)
    if not at then return "No snapshot" end
    local age = math.max(0, BM.Now() - at)
    if age < 60 then return "just now" end
    if age < 3600 then return math.floor(age / 60) .. " min ago" end
    if age < 86400 then return math.floor(age / 3600) .. " hr ago" end
    return math.floor(age / 86400) .. " days ago"
end
function BM.GetMember(id)
    BM.EnsureMembers()
    for _, m in ipairs(BM.Members) do if m.id == id then return m end end
    return BM.Members[1]
end
function BM.GetDungeon(id)
    for _, d in ipairs(BM.Dungeons) do if d.id == id then return d end end
    return BM.Dungeons[4]
end
function BM.Kills(m, period) return period == "all" and m.allKills or m.weekKills end
function BM.Ganks(m, period) return period == "all" and m.allGanks or m.weekGanks end
function BM.FilterMembers(query, sort, period, ascending, partyOnly)
    BM.EnsureMembers()
    local list = {}; query = (query or ""):lower()
    for _, m in ipairs(BM.Members) do
        if (not partyOnly or m.inParty) and (query == "" or (m.name .. " " .. m.className):lower():find(query, 1, true)) then list[#list + 1] = m end
    end
    local function value(m)
        if sort == "gold" then return m.gold end
        if sort == "ganks" then return BM.Ganks(m, period) end
        if sort == "name" then return m.name end
        return BM.Kills(m, period)
    end
    table.sort(list, function(a, b)
        local x, y = value(a), value(b)
        if x == y then return a.id < b.id end
        if x == nil then return false end
        if y == nil then return true end
        if ascending then return x < y end
        return x > y
    end)
    return list
end
function BM.Totals(period, list)
    if not list then BM.EnsureMembers() end
    local t = { kills = 0, ganks = 0, gold = 0, online = 0, balances = 0, snapshots = 0 }
    for _, m in ipairs(list or BM.Members) do
        t.kills = t.kills + (BM.Kills(m, period) or 0); t.ganks = t.ganks + (BM.Ganks(m, period) or 0)
        t.gold = t.gold + (m.gold or 0); t.online = t.online + (m.online and 1 or 0)
        t.balances = t.balances + (m.gold and 1 or 0); t.snapshots = t.snapshots + (m.hasSnapshot and 1 or 0)
    end
    return t
end
function BM.Money(copper, compact)
    if copper == nil then return "Unknown" end
    local gold = math.floor(copper / 10000)
    if compact then return gold .. "g" end
    return string.format("%dg %02ds %02dc", gold, math.floor(copper / 100) % 100, copper % 100)
end
function BM.ItemString(link)
    if BM.Secret(link) or type(link) ~= "string" then return nil end
    local s = link:match("|H(item:[^|]+)|h") or link
    if #s <= 512 and s:match("^item:%d+[:%d%-]*$") then return s end
end
local itemCache, pendingItems, cacheSize = {}, {}, 0
local function itemInfo(link)
    local cached = itemCache[link]
    if cached and (cached.ready or GetTime() - cached.at < 5) then return cached end
    local name, _, q, _, _, _, _, _, _, texture = BM.Read(C_Item and C_Item.GetItemInfo or GetItemInfo, link)
    name = BM.Text(name)
    if cacheSize >= 1024 then itemCache, pendingItems, cacheSize = {}, {}, 0 end
    if not itemCache[link] then cacheSize = cacheSize + 1 end
    cached = { name = name ~= "" and name or "Loading item...", quality = q or 1,
        icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark", ready = name ~= "", at = GetTime() }
    itemCache[link] = cached
    if not cached.ready then pendingItems[tonumber(link:match("^item:(%d+)"))] = true end
    return cached
end
function BM.InvalidateItem(id, success)
    if BM.Secret(id) or BM.Secret(success) or not pendingItems[id] or success ~= true then return end
    pendingItems[id] = nil
    for link in pairs(itemCache) do
        if tonumber(link:match("^item:(%d+)")) == id then itemCache[link] = nil; cacheSize = cacheSize - 1 end
    end
    BM.RebuildMembers()
end
function BM.GearView(items)
    local result = {}
    for i, def in ipairs(BM.GearSlots) do
        local link = items and items[i]
        local item = { slot = def[1], name = "Unknown", quality = 1, icon = "Interface\\Icons\\INV_Misc_QuestionMark" }
        if link == "" then item.empty, item.name = true, "Empty slot"
        elseif link and BM.ItemString(link) then
            local data = itemInfo(link)
            item.link, item.name, item.quality, item.icon = link, data.name, data.quality, data.icon
        end
        result[i] = item
    end
    return result
end
-- Resolve item names/icons only when a member's equipment is actually viewed.
local memberMeta = { __index = function(m, key)
    if key == "gear" then local gear = BM.GearView(m.itemStrings); rawset(m, key, gear); return gear end
end }
local membersDirty, refreshQueued = true, false
function BM.EnsureMembers()
    if membersDirty then membersDirty = false; BM.BuildMembers() end
end
function BM.RebuildMembers()
    membersDirty = true
    if refreshQueued or not BM.Window or not BM.Window:IsVisible() then return end
    refreshQueued = true
    C_Timer.After(.1, function()
        refreshQueued = false
        if BM.Window and BM.Window:IsVisible() then BM.Refresh() end
    end)
end
function BM.BuildMembers()
    local list, day = {}, BM.Day()
    for id, r in pairs(BM.Roster) do
        local cached = BM.GuildCache and BM.GuildCache[id]
        local p = id == BM.SelfID and BM.SelfProfile or cached and cached.profile
        local m = setmetatable({ id = id, name = r.name, class = r.class or "UNKNOWN", className = r.className or "Unknown",
            level = r.level or "?", online = r.online, zone = r.zone or "", spec = "", inParty = BM.Party and BM.Party[id] or false,
            quests = {}, itemStrings = p and p.items, history = {}, kills = {}, age = "No snapshot" }, memberMeta)
        if p then
            m.hasSnapshot, m.gold, m.zone = true, p.gold, p.zone
            m.age = BM.Age(p.at); m.received = cached and cached.received
            m.allKills, m.allGanks, m.weekKills, m.weekGanks = p.pvp.allKills, p.pvp.allGanks, 0, 0
            for _, b in ipairs(p.pvp.days) do
                if b[1] >= day - 6 and b[1] <= day then m.weekKills = m.weekKills + b[2]; m.weekGanks = m.weekGanks + b[3] end
            end
            for _, k in ipairs(p.pvp.recent) do m.kills[#m.kills + 1] = { name = k[1], level = k[2] > 0 and k[2] or nil, zone = k[3], age = BM.Age(k[4]), kind = k[5] } end
            for _, b in ipairs(p.history) do if b[1] >= day - 6 and b[1] <= day then m.history[b[1] - day + 7] = b[2] end end
        end
        local n = 0
        for _, dungeon in ipairs(BM.Dungeons) do
            m.quests[dungeon.id] = {}
            for q = 1, #dungeon.quests do
                n = n + 1; local v = p and p.quests[n]
                m.quests[dungeon.id][q] = { status = v and v[1] or 0, progress = v and v[2] ~= "" and v[2] or nil }
            end
        end
        list[#list + 1] = m
    end
    BM.Members = list
end
