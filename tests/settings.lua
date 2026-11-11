-- Exercise scheduling and persisted settings through separate client globals.
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function client(db, delayedRoster)
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.BorjesMagasinDB = db
    env.loadfile = function(path) return setfenv(assert(loadfile(path)), env) end
    env.dofile = function(path) return env.loadfile(path)() end
    local m = env.dofile("tests/mock_wow.lua")
    env.dofile("tests/live_mock.lua")(m)
    if delayedRoster then m.roster = {} end
    local bm = env.dofile("tests/load.lua")
    m.Fire("ADDON_LOADED", "borjes-magasin"); m.Fire("PLAYER_LOGIN")
    bm.StopProfile()
    return bm, m, env
end
local bm, m, env = client()
m.Advance(40)
check(#m.sent > 0 and m.sent[1][2] == "1|H", "Login requests and sends guild snapshots")
check(bm.GetHeartbeatMinutes() == 0, "Existing installations default to heartbeat off")
local sent, captures, ticks = #m.sent, 0, 0
local capture, tick = bm.Capture, bm.SyncTick
bm.Capture = function(...) captures = captures + 1; return capture(...) end
bm.SyncTick = function(...) ticks = ticks + 1; return tick(...) end
m.Advance(31 * 60)
check(#m.sent == sent and captures == 0 and ticks == 0, "Heartbeat off has no idle captures, polling or messages")
for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED", "QUEST_LOG_UPDATE", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE" }) do
    m.Fire(event)
end
m.Advance(40)
check(#m.sent == sent, "Money, gear, quests, zoning and roster changes never trigger a broadcast")
for _, minutes in ipairs({ 5, 10, 15, 30 }) do
    check(bm.SetHeartbeatMinutes(minutes), "Allowed heartbeat interval accepted")
    local before = #m.sent
    m.gold = m.gold + 100
    m.Advance(minutes * 60 - 1)
    check(#m.sent == before, "Heartbeat does not fire early: " .. minutes)
    m.Advance(20)
    check(#m.sent > before and m.sent[before + 1][2]:sub(1, 4) == "1|S|", "Heartbeat sends own snapshot without requesting everyone: " .. minutes)
    check(bm.SelfProfile.gold == m.gold, "Heartbeat captures fresh data at send time")
    bm.SetHeartbeatMinutes(0)
end
check(not bm.SetHeartbeatMinutes(1) and not bm.SetHeartbeatMinutes("5") and bm.GetHeartbeatMinutes() == 0, "Unsupported intervals are rejected")
bm.SetHeartbeatMinutes(5); m.Advance(100); bm.SetHeartbeatMinutes(10)
sent = #m.sent; m.Advance(599)
check(#m.sent == sent, "Changing interval cancels the old schedule and restarts the clock")
m.Advance(20)
check(#m.sent > sent, "Replacement interval sends normally")
bm.SetHeartbeatMinutes(5); m.Advance(300); bm.SetHeartbeatMinutes(0)
sent = #m.sent; m.Advance(40)
check(#m.sent == sent, "Off cancels a queued heartbeat before the first chunk")
bm.SetHeartbeatMinutes(5); m.Advance(305); bm.SetHeartbeatMinutes(0)
sent = #m.sent; m.Advance(40)
check(#m.sent == sent, "Off cancels remaining chunks of an active heartbeat")
bm.SetHeartbeatMinutes(5); bm.ToggleSharing()
sent = #m.sent; m.Advance(320)
check(#m.sent == sent, "Pause sharing suppresses heartbeats")
bm.ToggleSharing(); m.Advance(299)
check(#m.sent == sent, "Resume schedules the next interval without an immediate broadcast")
m.Advance(20)
check(#m.sent > sent, "Heartbeat resumes after the chosen interval")
bm.SetHeartbeatMinutes(0); sent = #m.sent
bm.RequestSync(); m.Advance(40)
check(#m.sent > sent, "Sync now works with heartbeat off")
sent = #m.sent; m.gold = m.gold + 555
bm.Receive(bm.PREFIX, "1|H", "GUILD", "Bob-Forever"); m.Advance(40)
check(#m.sent > sent and bm.SelfProfile.gold == m.gold, "Peer login/manual request gets a fresh snapshot even with heartbeat off")
bm.SetHeartbeatMinutes(15)
local reloaded, rm = client(env.BorjesMagasinDB)
check(reloaded.GetHeartbeatMinutes() == 15, "Chosen interval survives reload")
rm.Advance(40); sent = #rm.sent; rm.Advance(859)
check(#rm.sent == sent, "Reload preserves interval scheduling without an extra early heartbeat")
rm.Advance(20)
check(#rm.sent > sent, "Persisted heartbeat runs after reload")
local invalid = client({ heartbeatMinutes = 7 })
check(invalid.GetHeartbeatMinutes() == 0 and invalid.DB.heartbeatMinutes == 0, "Invalid saved settings migrate safely to off")
bm.SetHeartbeatMinutes(0); sent = #m.sent
m.guild = "NewGuild"; m.Fire("PLAYER_GUILD_UPDATE"); m.Advance(40)
check(#m.sent == sent, "Changing guild after login does not trigger automatic sync")
local late, lm = client(nil, true)
lm.Advance(2); check(#lm.sent == 0, "Login waits briefly for the guild roster")
lm.roster = { { name = "Bob-Forever", level = 40, classID = 8, presence = 1 } }
lm.Fire("GUILD_ROSTER_UPDATE"); lm.Advance(40)
check(#lm.sent > 0, "Late login roster still enables one login sync")
local logout, om = client()
om.Advance(40); om.gold = 456789
sent = #om.sent; om.Fire("PLAYER_CAMPING"); om.Advance(20)
check(#om.sent > sent and logout.SelfProfile.gold == 456789, "Logout countdown sends a fresh paced snapshot")
sent = #om.sent; om.Fire("PLAYER_LOGOUT")
check(#om.sent == sent, "Final logout does not duplicate an unchanged completed countdown snapshot")
om.Fire("LOGOUT_CANCEL"); om.gold = 567890
om.Fire("PLAYER_LOGOUT")
check(#om.sent > sent and logout.SelfProfile.gold == 567890, "Immediate logout attempts the latest full snapshot without relying on future timers")
local paused, pm = client(); pm.Advance(40); paused.ToggleSharing()
sent = #pm.sent; pm.gold = 123; pm.Fire("PLAYER_LOGOUT")
check(#pm.sent == sent and paused.SelfProfile.gold == 123, "Paused logout saves locally without sending")
local cancel, cm = client(); cm.Advance(40)
cm.Fire("PLAYER_QUITING"); cm.Advance(.5); cm.Fire("LOGOUT_CANCEL")
sent = #cm.sent; cm.Advance(40)
check(#cm.sent == sent, "Cancelling logout stops its unfinished transfer")
local restricted, xm = client(); xm.Advance(40); xm.gold = 321
xm.restricted = true; sent = #xm.sent; xm.Fire("PLAYER_LOGOUT")
check(#xm.sent == sent and restricted.SyncStatus() == "Client restricts addon messages", "Logout respects client message restrictions")
local stalled, sm = client(); sm.restricted = true; sm.Advance(130)
check(stalled.SyncStatus() == "Client restricts addon messages", "A failed transfer keeps its specific restriction reason")
local calls = 0; local previousTick = stalled.SyncTick
stalled.SyncTick = function(...) calls = calls + 1; return previousTick(...) end
sm.Advance(60)
check(calls == 0, "An expired transfer stops polling")
print(checks .. " settings, heartbeat, idle and session sync checks passed.")
