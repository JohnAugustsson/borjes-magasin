local _, BM = ...
local dirty, lastRosterRequest, enemies, dedup = false, -60, {}, {}
local function unitName(unit)
    local name, realm = BM.Read(UnitFullName or UnitName, unit)
    if not name then name, realm = BM.Read(UnitName, unit) end
    if BM.RegionalNames then
        return BM.FullCharacterName(name, realm) or BM.FullCharacterName(BM.Read(GetUnitName, unit, true))
    end
    if not name then return end
    return name, realm
end
local function identity(unit)
    local name, realm = unitName(unit)
    return BM.Canonical(name, realm ~= "" and realm or nil), name, realm
end
function BM.InitializeData()
    BM.DB.schema = 1
    BM.DB.characters = type(BM.DB.characters) == "table" and BM.DB.characters or {}
    BM.DB.guilds = type(BM.DB.guilds) == "table" and BM.DB.guilds or {}
    BM.Realm = BM.Read(GetNormalizedRealmName) or BM.Read(GetRealmName) or ""
    local regional = BM.Read(RegionalUniqueNamesEnabled)
    if regional == nil then
        local _, _, _, interface = BM.Read(GetBuildInfo)
        regional = type(interface) == "number" and interface >= 16000 and interface < 17000
    end
    BM.RegionalNames = regional == true
    if BM.RegionalNames then
        BM.IdentityRealm, BM.RealmAliases = nil, nil
    else
        local _, publicRealm = unitName("player")
        BM.SetIdentityRealm(publicRealm, BM.Read(GetRealmName))
    end
    BM.SelfID, BM.SelfName = identity("player")
    if not BM.SelfID then return false end
    local char = BM.DB.characters[BM.SelfID]
    if type(char) ~= "table" then
        local newest
        for id, previous in pairs(BM.DB.characters) do
            if BM.StoredMemberID(id) == BM.SelfID and type(previous) == "table" and type(previous.wire) == "string" then
                local p = BM.UnpackProfile(previous.wire)
                if p and (not newest or p.at > newest) then char, newest = previous, p.at end
            end
        end
        char = type(char) == "table" and char or {}
        BM.DB.characters[BM.SelfID] = char
    end
    BM.Character = char
    -- Saved snapshots have the same bounded schema as network snapshots.
    local previous = type(char.wire) == "string" and BM.UnpackProfile(char.wire)
    BM.SelfProfile = previous
    BM.PVP = previous and previous.pvp or { since = BM.Now(), allKills = 0, allGanks = 0, days = {}, recent = {} }
    BM.History = previous and previous.history or {}
    BM.UpdateRoster(); BM.UpdateParty(); BM.Capture()
    return true
end
function BM.RequestRoster()
    if GetTime() - lastRosterRequest < 15 then return end
    lastRosterRequest = GetTime()
    BM.Read(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster)
end
function BM.UpdateRoster()
    if not BM.SelfID then return end
    local guildName = BM.Read(GetGuildInfo, "player")
    local club = guildName and BM.Read(C_Club and C_Club.GetGuildClubId)
    if club and club ~= BM.FocusedClub then
        BM.Read(C_Club and C_Club.FocusMembers, club)
        BM.FocusedClub = club
    elseif not guildName then BM.FocusedClub = nil end
    local scope = guildName and ((club and tostring(club) or BM.Text(guildName)) .. ":" .. BM.Realm)
    if scope ~= BM.GuildScope then
        BM.GuildScope = scope
        BM.GuildCache = nil
        if scope then
            BM.DB.guilds[scope] = type(BM.DB.guilds[scope]) == "table" and BM.DB.guilds[scope] or {}
            BM.GuildCache = {}
            for id, cached in pairs(BM.DB.guilds[scope]) do
                local p = type(cached) == "table" and type(cached.wire) == "string" and BM.UnpackProfile(cached.wire)
                local key = BM.StoredMemberID(id)
                local old = key and BM.GuildCache[key]
                if p and key and (not old or p.at > old.profile.at) then
                    BM.GuildCache[key] = { wire = cached.wire, profile = p, received = cached.received }
                end
            end
            BM.DB.guilds[scope] = BM.GuildCache
        end
        if BM.ResetSync then BM.ResetSync() end
    end
    BM.GuildName = guildName
    local roster, count = {}, 0
    local function add(name, level, class, className, zone, online)
        local id = BM.Canonical(name)
        if not id then return end
        class = BM.ClassColors[class] and class or "UNKNOWN"
        if not roster[id] then count = count + 1 end
        roster[id] = { name = BM.RegionalNames and BM.FullCharacterName(name) or BM.Text(name), level = BM.Integer(level, 1, 100) and level or nil, class = class,
            className = BM.Text(className) ~= "" and BM.Text(className) or (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or "Unknown",
            zone = BM.Text(zone), online = online == true }
    end
    local memberIDs = club and BM.Read(C_Club and C_Club.GetClubMembers, club)
    if type(memberIDs) == "table" then
        for _, memberID in ipairs(memberIDs) do
            local info = BM.Read(C_Club.GetMemberInfo, club, memberID)
            if type(info) == "table" and not BM.Secret(info.name) and not BM.Secret(info.classID) and not BM.Secret(info.presence) then
                local className, class = BM.Read(GetClassInfo, info.classID)
                local presence = info.presence
                add(info.name, info.level, class, className, info.zone, presence == 1 or presence == 4 or presence == 5)
            end
        end
    end
    if count == 0 and guildName then
        local n = BM.Read(GetNumGuildMembers) or 0
        for i = 1, math.min(n, 2000) do
            local name, _, _, level, className, zone, _, _, online, _, class = BM.Read(GetGuildRosterInfo, i)
            add(name, level, class, className, zone, online)
        end
    end
    -- An unavailable roster is not evidence that everyone left. Keep the last
    -- roster within this session, but never carry it across a guild change.
    if count == 0 and BM.RosterScope == scope and scope then roster = BM.Roster end
    BM.RosterScope = scope
    local className, class = BM.Read(UnitClass, "player")
    add(BM.SelfName, BM.Read(UnitLevel, "player"), class, className, BM.Read(GetRealZoneText), true)
    BM.Roster = roster
    BM.RosterReady = scope ~= nil and count > 1
    BM.RebuildMembers()
end
function BM.UpdateParty()
    local party = {}; if BM.SelfID then party[BM.SelfID] = true end
    local units = {}
    local function addUnit(unit)
        local id, name, realm = identity(unit)
        if id then
            party[id] = true
            units[#units + 1] = { unit = unit, name = name, realm = realm, id = id, matched = BM.Roster[id] ~= nil }
        end
    end
    if BM.Read(IsInRaid) then
        local ownGroup
        local n = BM.Read(GetNumGroupMembers) or 0
        for i = 1, n do
            if BM.Read(UnitIsUnit, "raid" .. i, "player") then local _, _, group = BM.Read(GetRaidRosterInfo, i); ownGroup = group; break end
        end
        if ownGroup then
            for i = 1, n do
                local _, _, group = BM.Read(GetRaidRosterInfo, i)
                if group == ownGroup then addUnit("raid" .. i) end
            end
        end
    else
        for i = 1, 4 do addUnit("party" .. i) end
    end
    BM.PartyUnits = units
    BM.Party = party; BM.RebuildMembers()
end
local function questState(q, level, faction)
    local api = C_QuestLog or {}
    local complete = BM.Read(api.IsQuestFlaggedCompleted, q.id)
    if complete == true then return { 4, "" } end
    local index = BM.Read(api.GetLogIndexForQuestID, q.id)
    if index and index > 0 then
        local objectives = BM.Read(api.GetQuestObjectives, q.id)
        local done, count, progressParts = 0, 0, {}
        if type(objectives) == "table" then
            for _, objective in ipairs(objectives) do
                if not BM.Secret(objective.finished) then
                    count = count + 1; done = done + (objective.finished and 1 or 0)
                    if #progressParts < 6 and BM.Integer(objective.numFulfilled, 0, 1000000) and BM.Integer(objective.numRequired, 1, 1000000) then
                        progressParts[#progressParts + 1] = objective.numFulfilled .. "/" .. objective.numRequired
                    end
                end
            end
        end
        local progress = count > 0 and (done .. "/" .. count .. " objectives") or "In quest log"
        if #progressParts > 0 then progress = progress .. " (" .. table.concat(progressParts, ", ") .. ")" end
        local ready = BM.Read(api.IsComplete, q.id)
        return { ready == true and 3 or 2, progress }
    end
    if q.faction and faction and q.faction ~= faction then return { 6, q.faction .. " quest" } end
    if level < q.minLevel then return { 6, "Requires level " .. q.minLevel } end
    if complete == nil then return { 0, "Quest information unavailable" } end
    if q.prereq then
        local pre = BM.Read(api.IsQuestFlaggedCompleted, q.prereq)
        if pre == nil then return { 0, "Prerequisite status unavailable" } end
        if not pre then
            local title = BM.Text(BM.Read(api.GetTitleForQuestID, q.prereq), 110)
            return { 5, "Requires " .. (title ~= "" and title or "quest #" .. q.prereq) }
        end
    end
    return { 1, "Not in quest log; availability not confirmed" }
end
local function readXP(level)
    if level >= BM.MAX_LEVEL then return end
    local xp, maximum = BM.Read(UnitXP, "player"), BM.Read(UnitXPMax, "player")
    if BM.Integer(maximum, 1, 1000000000) and BM.Integer(xp, 0, maximum) then return xp, maximum end
end
function BM.Capture()
    dirty = false
    if not BM.Character then return end
    local level = BM.Read(UnitLevel, "player")
    local _, class = BM.Read(UnitClass, "player")
    if not BM.Integer(level, 1, 100) or not BM.ClassColors[class] then return end
    local now, day = BM.Now(), BM.Day()
    local p = { at = now, level = level, class = class, zone = BM.Text(BM.Read(GetRealZoneText)), items = {}, quests = {}, pvp = BM.PVP, history = BM.History }
    p.xp, p.xpMax = readXP(level)
    local gold = BM.Read(GetMoney)
    if BM.Integer(gold, 0, 100000000000) then p.gold = gold end
    local found
    for _, b in ipairs(BM.History) do if b[1] == day then b[2] = p.gold or b[2]; found = true end end
    if p.gold and not found then BM.History[#BM.History + 1] = { day, p.gold } end
    for i = #BM.History, 1, -1 do if BM.History[i][1] < day - 6 then table.remove(BM.History, i) end end
    for i = #BM.PVP.days, 1, -1 do if BM.PVP.days[i][1] < day - 6 then table.remove(BM.PVP.days, i) end end
    for i, slot in ipairs(BM.GearSlots) do
        local link = BM.Read(GetInventoryItemLink, "player", slot[2])
        local id, readable = BM.Probe(GetInventoryItemID, "player", slot[2])
        if BM.ItemString(link) then p.items[i] = BM.ItemString(link)
        elseif BM.Integer(id, 1, 10000000) then p.items[i] = "item:" .. id
        elseif readable then p.items[i] = ""
        else p.items[i] = false end
    end
    local faction = BM.Read(UnitFactionGroup, "player")
    for i, q in ipairs(BM.QuestList) do p.quests[i] = questState(q, level, faction) end
    local wire = BM.PackProfile(p)
    if not wire then return end
    BM.SelfProfile, BM.Character.wire = p, wire
    -- Local tracking does not schedule a guild broadcast.
    BM.RebuildMembers()
end
function BM.CaptureXP()
    dirty = false
    local p = BM.SelfProfile
    if not p then return end
    local level = BM.Read(UnitLevel, "player")
    if not BM.Integer(level, 1, 100) then return end
    if level ~= p.level then BM.Capture(); return end
    local xp, maximum = readXP(level)
    if xp == p.xp and maximum == p.xpMax then return end
    p.xp, p.xpMax, p.at = xp, maximum, BM.Now()
    BM.Character.wire = BM.PackProfile(p)
    BM.RebuildMembers()
end
function BM.MarkDirty(xpOnly)
    if not BM.Character then return end
    local pending = dirty
    dirty = (dirty == true or xpOnly ~= true) and true or "xp"
    if pending then return end
    C_Timer.After(1, function()
        if dirty == "xp" then BM.CaptureXP() elseif dirty then BM.Capture() end
    end)
end
function BM.ObserveEnemy(unit)
    if BM.Read(UnitIsPlayer, unit) ~= true or BM.Read(UnitCanAttack, "player", unit) ~= true then return end
    local guid, level = BM.Read(UnitGUID, unit), BM.Read(UnitLevel, unit)
    if type(guid) ~= "string" or not guid:match("^Player%-") then return end
    local color = BM.Read(GetCreatureDifficultyColor or GetQuestDifficultyColor, level)
    local gray
    if type(color) == "table" and not BM.Secret(color.r) and not BM.Secret(color.g) and not BM.Secret(color.b) then
        local trivial = QuestDifficultyColors and QuestDifficultyColors.trivial
        if trivial then gray = color.r == trivial.r and color.g == trivial.g and color.b == trivial.b end
        if not BM.Secret(color.font) and color.font == "GameFontDisable" then gray = true end
    end
    enemies[guid] = { name = BM.Text((unitName(unit))), level = BM.Integer(level, 1, 100) and level or nil, gray = gray, at = GetTime() }
    local count = 0
    for id, e in pairs(enemies) do count = count + 1; if GetTime() - e.at > 30 or count > 256 then enemies[id] = nil end end
end
function BM.RecordKill(attacker, victim)
    if BM.Secret(attacker) or BM.Secret(victim) or not BM.PVP or type(victim) ~= "string" or not victim:match("^Player%-") then return end
    local player, pet = BM.Read(UnitGUID, "player"), BM.Read(UnitGUID, "pet")
    if not attacker or (attacker ~= player and attacker ~= pet) or BM.Read(IsInInstance) ~= false then return end
    local now = GetTime()
    if dedup[victim] and now - dedup[victim] < 5 then return end
    dedup[victim] = now
    for id, at in pairs(dedup) do if now - at > 30 then dedup[id] = nil end end
    BM.ObserveEnemy("target"); BM.ObserveEnemy("mouseover")
    local e, kind = enemies[victim], "Unclassified"
    if e and now - e.at > 30 then e = nil end
    local level = BM.Read(UnitLevel, "player")
    if e and e.level and BM.Integer(level, 1, 100) then
        if e.gray == true then kind = "Gank"
        elseif e.gray == false and e.level >= level - 5 then kind = "Qualifying"
        elseif e.gray == false then kind = "Out of range" end
    end
    local pvp, day = BM.PVP, BM.Day()
    if kind == "Gank" or kind == "Qualifying" then
        local bucket
        for _, b in ipairs(pvp.days) do if b[1] == day then bucket = b end end
        if not bucket then bucket = { day, 0, 0 }; pvp.days[#pvp.days + 1] = bucket end
        if kind == "Gank" then pvp.allGanks = pvp.allGanks + 1; bucket[3] = bucket[3] + 1
        else pvp.allKills = pvp.allKills + 1; bucket[2] = bucket[2] + 1 end
    end
    table.insert(pvp.recent, 1, { e and e.name ~= "" and e.name or "Unknown opponent", e and e.level or 0, BM.Text(BM.Read(GetRealZoneText)), BM.Now(), kind })
    while #pvp.recent > 8 do table.remove(pvp.recent) end
    BM.Capture()
end
function BM.HookCharacterPane()
    if CharacterFrame and not BM.CharacterHooked then
        BM.CharacterHooked = true
        CharacterFrame:HookScript("OnShow", BM.MarkDirty)
    end
end
