-- Only test code contains example characters. Production code reads the client.
return function(Mock, config)
    config = config or {}
    Mock.clock, Mock.epoch, Mock.sent, Mock.scheduled = 0, 1794300000, {}, {}
    Mock.name, Mock.realm, Mock.guild = config.name or "Alice", "Forever", "TestGuild"
    Mock.gold, Mock.level, Mock.class, Mock.zone = config.gold or 1234567, 42, "WARRIOR", "Stranglethorn Vale"
    Mock.items = { [1] = "item:123:456:0:0:0:0:0:0:42", [16] = "item:789:0:0:0:0:0:0:0:42" }
    Mock.complete, Mock.quests = { [155] = true }, { [166] = { done = false, objectives = { { finished = false, numFulfilled = 0, numRequired = 1 } } } }
    Mock.roster = {
        { name = "Alice-Forever", level = 42, classID = 1, presence = 1, zone = "Stranglethorn Vale" },
        { name = "Bob-Forever", level = 40, classID = 8, presence = 1, zone = "Tanaris" },
        { name = "Clara-Forever", level = 39, classID = 5, presence = 3, zone = "Ironforge" },
    }
    Mock.party = { party1 = "Bob", party2 = "Outsider" }
    Mock.units = {}
    local function unit(u)
        if u == "player" then return { name = Mock.name, level = Mock.level, guid = "Player-1-" .. Mock.name } end
        if Mock.party[u] then return { name = Mock.party[u] } end
        return Mock.units[u]
    end
    debugprofilestop = function() return os.clock() * 1000 end
    GetTime = function() return Mock.clock end
    GetServerTime = function() return Mock.epoch + math.floor(Mock.clock) end
    GetNormalizedRealmName = function() return Mock.realm end
    GetGuildInfo = function() return Mock.guild end
    UnitFullName = function(u) local v = unit(u); if v then return v.name, Mock.realm end end
    UnitGUID = function(u) local v = unit(u); return v and v.guid end
    UnitLevel = function(u) local v = unit(u); return v and v.level end
    UnitClass = function() return "Warrior", Mock.class end
    UnitFactionGroup = function() return "Alliance" end
    GetClassInfo = function(id) local names = { [1] = { "Warrior", "WARRIOR" }, [8] = { "Mage", "MAGE" }, [5] = { "Priest", "PRIEST" } }; return unpack(names[id] or { "Unknown", "UNKNOWN" }) end
    C_Club = {
        GetGuildClubId = function() return Mock.guild and Mock.guild .. "-id" end,
        GetClubMembers = function() local ids = {}; for i = 1, #Mock.roster do ids[i] = i end; return ids end,
        GetMemberInfo = function(_, i) return Mock.roster[i] end,
    }
    C_GuildInfo = { GuildRoster = function() Mock.rosterRequests = (Mock.rosterRequests or 0) + 1 end }
    GetNumGroupMembers = function() return 3 end
    IsInRaid = function() return false end
    GetRealZoneText = function() return Mock.zone end
    GetMoney = function() return Mock.gold end
    GetInventoryItemLink = function(_, slot) return Mock.items[slot] end
    GetInventoryItemID = function(_, slot) local s = Mock.items[slot]; if type(s) == "table" then return s end; return s and tonumber(s:match("item:(%d+)")) end
    C_Item = { GetItemInfo = function(link) return "Verified item " .. link:match("item:(%d+)"), link, 3, 42, 40, "Armor", "Plate", 1, "", "Interface\\Icons\\INV_Helmet_03" end }
    C_QuestLog = {
        IsQuestFlaggedCompleted = function(id) return Mock.complete[id] or false end,
        GetLogIndexForQuestID = function(id) return Mock.quests[id] and 1 or nil end,
        IsComplete = function(id) return Mock.quests[id] and Mock.quests[id].done or false end,
        GetQuestObjectives = function(id) return Mock.quests[id] and Mock.quests[id].objectives end,
        GetTitleForQuestID = function(id) return "Quest " .. id end,
    }
    IsInInstance = function() return Mock.instance or false, Mock.instance and "pvp" or "none" end
    UnitIsPlayer = function(u) local v = unit(u); return v and v.guid and v.guid:find("Player-", 1, true) == 1 or false end
    UnitCanAttack = function(_, u) return u ~= "player" and Mock.units[u] ~= nil end
    QuestDifficultyColors = { trivial = { r = .5, g = .5, b = .5 } }
    GetCreatureDifficultyColor = function(level) if not level or type(level) ~= "number" then return nil end; return level <= Mock.level - 10 and QuestDifficultyColors.trivial or { r = 1, g = 1, b = 0 } end
    issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) Mock.prefix = prefix; return config.prefixResult or 0 end,
        AreOutgoingAddonChatMessagesRestricted = function() return Mock.restricted or false end,
        SendAddonMessage = function(prefix, message, channel)
            assert(channel == "GUILD", "Only hidden guild traffic is allowed")
            assert(#prefix + #message <= 254, "Chat payload exceeds limit")
            -- The advisory restriction flag and the actual API result are
            -- independent: Forever can report true while delivering messages.
            Mock.sendAttempts = (Mock.sendAttempts or 0) + 1
            if Mock.sendResult and Mock.sendResult ~= 0 then return Mock.sendResult end
            Mock.sent[#Mock.sent + 1] = { prefix, message, channel, Mock.name .. "-" .. Mock.realm, at = Mock.clock }
            return 0
        end,
    }
    C_Timer.After = function(delay, fn) Mock.scheduled[#Mock.scheduled + 1] = { at = Mock.clock + delay, fn = fn } end
    GameTooltip.SetHyperlink = function(_, link) Mock.tooltip = link end
    function Mock.Advance(seconds)
        local limit = Mock.clock + seconds
        while Mock.clock < limit - .000001 do
            local delta = math.min(.1, limit - Mock.clock); Mock.clock = Mock.clock + delta
            local due = {}
            for i = #Mock.scheduled, 1, -1 do
                if Mock.scheduled[i].at <= Mock.clock then table.insert(due, 1, table.remove(Mock.scheduled, i).fn) end
            end
            for _, fn in ipairs(due) do fn() end
            for _, frame in ipairs(Mock.objects) do if frame.scripts.OnUpdate and frame:IsVisible() then frame.scripts.OnUpdate(frame, delta) end end
        end
    end
    return Mock
end
