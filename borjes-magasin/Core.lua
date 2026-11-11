local addonName, BM = ...
local events = CreateFrame("Frame")
local function say(message) DEFAULT_CHAT_FRAME:AddMessage("|cffe8ba6eborjes-magasin:|r " .. message) end
local function initialize()
    if BM.DB then return end
    if type(BorjesMagasinDB) ~= "table" then BorjesMagasinDB = {} end
    BM.DB = BorjesMagasinDB
    BM.DB.heartbeatMinutes = BM.GetHeartbeatMinutes()
    if type(BM.DB.minimapAngle) ~= "number" then BM.DB.minimapAngle = 220 end
    BM.State = { tab = "pvp", query = "", period = "week", pvpSort = "kills", ascending = false, dungeon = "scarlet", quest = 1, partyOnly = BM.DB.partyOnly == true }
    BM.InstallProfiler()
    BM.CreateLauncher()
    SLASH_BORJESMAGASIN1, SLASH_BORJESMAGASIN2, SLASH_BORJESMAGASIN3 = "/borjes", "/bm", "/borjes-magasin"
    SlashCmdList.BORJESMAGASIN = function(message)
        local cmd = (message or ""):lower():match("^%s*(.-)%s*$")
        if cmd == "debug" then BM.SyncReport()
        elseif cmd:match("^profile") then BM.ProfileCommand(cmd:match("^profile%s+(%S+)$"))
        elseif cmd == "reset" then BM.ResetPosition(); BM.Open()
        elseif cmd == "sync" then BM.RequestSync(); say(BM.SyncStatus())
        elseif cmd == "share" then BM.ToggleSharing(); say(BM.SyncStatus())
        elseif cmd == "help" then say("/borjes opens the guild ledger. /borjes sync requests snapshots. /borjes share pauses/resumes sharing. /borjes reset resets filters; it keeps your history. /bm profile start records performance; /bm profile report shows it.")
        else BM.Toggle() end
    end
    BM.AttachGuildUI()
end
local function login()
    initialize()
    if BM.DB.profiledVersion ~= BM.VERSION then
        BM.DB.profiledVersion = BM.VERSION; BM.StartProfile()
    end
    if not BM.Character and BM.InitializeData() then
        BM.InitializeSync(); BM.RequestRoster(); BM.HookCharacterPane()
        BM.LoginSyncPending = true
        BM.TryLoginSync()
        C_Timer.After(5, function() BM.TryLoginSync(true) end)
        if BM.DB.introducedVersion ~= BM.VERSION then
            BM.DB.introducedVersion = BM.VERSION
            say("Guild sharing ready. /borjes opens the ledger; Settings controls the optional heartbeat. Login/logout and manual sync remain available. Pause with /borjes share.")
        end
    end
end
local eventNames = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_CAMPING", "PLAYER_QUITING", "LOGOUT_CANCEL", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "PLAYER_REGEN_ENABLED",
    "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "CLUB_ADDED", "CLUB_REMOVED", "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED", "CLUB_MEMBER_UPDATED", "CLUB_MEMBER_PRESENCE_UPDATED",
    "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
    "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "GET_ITEM_INFO_RECEIVED", "QUEST_DATA_LOAD_RESULT", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "PARTY_KILL" }
for _, event in ipairs(eventNames) do events:RegisterEvent(event) end
local rosterQueued = false
local function rosterChanged()
    if rosterQueued then return end
    rosterQueued = true
    C_Timer.After(1, function()
        rosterQueued = false
        BM.UpdateRoster(); BM.UpdateParty()
        BM.TryLoginSync()
    end)
end
local function onEvent(_, event, ...)
    BM.ProfileEvent(event)
    local a, b = ...
    if event == "ADDON_LOADED" then
        if a == addonName then initialize() end
        if BM.DB then BM.AttachGuildUI(); BM.HookCharacterPane() end
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then login(); BM.MarkDirty(); rosterChanged()
    elseif not BM.DB then return
    elseif event == "CHAT_MSG_ADDON" then BM.Receive(...)
    elseif event == "PARTY_KILL" then BM.RecordKill(a, b)
    elseif event == "PLAYER_TARGET_CHANGED" then BM.ObserveEnemy("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then BM.ObserveEnemy("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then BM.ObserveEnemy(a)
    elseif event == "GROUP_ROSTER_UPDATE" then BM.UpdateParty()
    elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event:match("^CLUB_") then rosterChanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        BM.AttachGuildUI(); BM.MarkDirty()
        if BM.PendingOpen then BM.Open() end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then BM.ApplyScale(); BM.PositionLauncher()
    elseif event == "UNIT_INVENTORY_CHANGED" then if a == "player" then BM.MarkDirty() end
    elseif event == "GET_ITEM_INFO_RECEIVED" then BM.InvalidateItem(a, b)
    elseif event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then BM.PrepareLogout()
    elseif event == "LOGOUT_CANCEL" then BM.CancelLogout()
    elseif event == "PLAYER_LOGOUT" then BM.SaveSyncReport(); BM.FlushLogout(); BM.StopProfile()
    else BM.MarkDirty() end
end
events:SetScript("OnEvent", function(...) return BM.ProfileCall("Events", onEvent, ...) end)
