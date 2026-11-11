local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local m = dofile("tests/mock_wow.lua")
dofile("tests/live_mock.lua")(m)
-- The real client GetTime is system uptime, not zero at login.
m.clock = 1367913.313
local bm = dofile("tests/load.lua")
m.Fire("ADDON_LOADED", "borjes-magasin"); m.Fire("PLAYER_LOGIN")
bm.Open()
m.Advance(40)
bm.RequestSync(true)
local capture = bm.Capture
bm.Capture = function() error("Simulated capture failure") end
m.Advance(10)
check(bm.SyncStatus() == "Sync stopped; /bm debug", "A timer error cannot leave an apparently queued transfer")
local report = bm.SaveSyncReport()
check(report.diagnostic.error:find("Simulated capture failure", 1, true), "The actual timer error is preserved locally")
local ticks = report.diagnostic.ticks
m.Advance(140)
check(bm.SaveSyncReport().diagnostic.ticks == ticks, "An error stops retries without idle polling")
bm.Capture = capture; bm.RequestSync(true); m.Advance(40)
check(bm.LastSent and bm.SyncStatus() == "Waiting for guild replies", "A manual retry can recover and send after an error")
bm.Receive(bm.PREFIX, "1|H", "GUILD", "Unknown-OtherRealm")
report = bm.SaveSyncReport()
check(report.diagnostic.rejected["unknown guild sender"] == 1, "Unmatched guild identities are diagnosed without accepting them")
check(#report.partyUnits == 2 and report.partyUnits[1].matched and not report.partyUnits[2].matched, "Report distinguishes matched and unmatched party identities")
check(report.selfID == "alice-forever" and #report.roster == 3, "Report preserves actual roster keys and self identity")
check(not report.wire and not report.gold and not report.items, "Report does not duplicate private snapshot contents")
SlashCmdList.BORJESMAGASIN("debug")
check(m.message:find("Local report ready", 1, true), "Debug command prints a locally saved report")
C_ChatInfo.SendAddonMessage = function() error("Simulated API failure") end
bm.RequestSync(true); m.Advance(50)
report = bm.SaveSyncReport()
check(report.diagnostic.error:find("Simulated API failure", 1, true), "Send API exceptions are preserved rather than swallowed")
check(#report.diagnostic.recent <= 24, "Diagnostic history stays bounded")
m.Fire("PLAYER_LOGOUT")
check(bm.DB.lastSyncReport.version == bm.VERSION and bm.DB.lastSyncReport.pending, "Logout saves the failing queue state before trying to flush it")
print(checks .. " sync diagnostics and timer recovery checks passed.")
