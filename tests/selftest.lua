local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function client(config)
    config = config or {}
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.BorjesMagasinDB = config.db or { sharing = false, heartbeatMinutes = 15 }
    env.loadfile = function(path) return setfenv(assert(loadfile(path)), env) end
    env.dofile = function(path) return env.loadfile(path)() end
    local m = env.dofile("tests/mock_wow.lua")
    env.dofile("tests/live_mock.lua")(m, { name = "Suer Fisk" })
    m.clock, m.restricted, m.probes, m.registrations, m.messages = 1367913.313, true, {}, {}, {}
    m.realm = "CAMWOWEU4Realm2PvP"
    m.roster = { { name = "Suer Fisk", level = 42, classID = 1, presence = 1 } }
    m.party = {}
    env.RegionalUniqueNamesEnabled = function() return config.legacy ~= true end
    env.UnitFullName = function(unit)
        if unit == "player" then
            if config.legacy then return "Alice", "Forever" end
            return "Suer", "Fisk"
        end
    end
    env.GetBuildInfo = function() return "1.60.1", "12345", "date", 16001 end
    env.IsTrialAccount = function() return false end
    env.IsVeteranTrialAccount = function() return false end
    env.C_ChatInfo.InChatMessagingLockdown = function() return false end
    env.DEFAULT_CHAT_FRAME.AddMessage = function(_, message) m.message = message; m.messages[#m.messages + 1] = message end
    env.C_ChatInfo.RegisterAddonMessagePrefix = function(prefix)
        m.registrations[#m.registrations + 1] = prefix
        if prefix == "BorjesDebug1" and config.registerResult ~= nil then return config.registerResult end
        return 0
    end
    env.C_ChatInfo.SendAddonMessage = function(prefix, message, channel, target)
        assert(prefix == "BorjesDebug1", "Paused production sync must stay paused")
        assert(channel == "GUILD" or channel == "WHISPER", "Only normal hidden addon channels")
        assert(#prefix + #message < 254, "Bounded probe size")
        m.probes[#m.probes + 1] = { prefix, message, channel, target, at = m.clock }
        if config.throw then error("Simulated send API error") end
        if config.echo and (channel == "WHISPER" or config.echo == "all") then
            -- A synchronous echo also tests that the receiver is ready before
            -- SendAddonMessage returns; real delivery may be asynchronous.
            m.Fire("CHAT_MSG_ADDON", prefix, message, channel, config.sender or (target or "Suer Fisk"))
        end
        if config.returnNil then return nil end
        if config.result ~= nil then return config.result end
        return 0
    end
    local bm = env.dofile("tests/load.lua")
    m.Fire("ADDON_LOADED", "borjes-magasin"); m.Fire("PLAYER_LOGIN")
    return bm, m, env
end
local bm, m, env = client({ echo = "all" })
m.Advance(200)
check(#m.probes == 0 and #m.registrations == 1, "Login and idle time neither register nor send debug traffic")
local cache, memberCount = bm.GuildCache, #bm.Members
env.SlashCmdList.BORJESMAGASIN("selftest")
local report = bm.DB.lastSelfTest
check(report.state == "running" and report.flags.restricted == true, "Manual command records the actual restriction flag")
check(report.flags.trial == false and report.clientBuild == "12345" and report.interface == 16001, "Client and account observations are retained")
check(report.codec.passed and report.codec.bytes > 0, "Actual profile survives production encode/decode round trip")
check(not report.codec.wire and not report.codec.gold and not report.codec.items, "Report omits profile contents")
env.SlashCmdList.BORJESMAGASIN("selftest")
check(bm.DB.lastSelfTest == report, "Repeated command cannot restart an active test")
m.Advance(15.1)
check(#m.probes == 3 and report.state == "complete", "Exactly three direct probes run despite a true early restriction flag")
check(m.probes[1][3] == "GUILD" and m.probes[1][4] == nil, "Guild probe has no target")
check(m.probes[2][3] == "WHISPER" and m.probes[2][4] == "Suer Fisk", "First whisper uses the full spaced name")
check(m.probes[3][4] == "Suer-Fisk", "Second whisper tests the full hyphenated name")
check(m.probes[2].at - m.probes[1].at >= .89 and m.probes[3].at - m.probes[2].at >= .89, "Probes are spaced rather than burst or retried")
for _, p in ipairs(report.probes) do
    check(p.api.accepted and p.api.result == 0 and p.echoes == 1, "API acceptance and observed echo are separate facts")
    check(p.identityMatches and p.canonicalSender == "suer-fisk" and p.latencyMs >= 0, "Returned sender identity and latency are observed")
    check(p.message:match("^1|T|[%d%-]+|%d$") and #p.message < 120, "Network probes contain only protocol, nonce and index")
end
check(bm.GuildCache == cache and next(cache) == nil and #bm.Members == memberCount, "No synthetic guild members or cache writes")
check(bm.DB.sharing == false and bm.DB.heartbeatMinutes == 15, "Explicit probes preserve sharing and heartbeat preferences")
local diagnostic = bm.SaveSyncReport().diagnostic
check(diagnostic.sent == 0 and diagnostic.received == 0, "Diagnostic prefix does not affect production sync counters")
local savedEchoes = report.probes[1].echoes
m.Fire("CHAT_MSG_ADDON", unpack(m.probes[1], 1, 4))
check(report.probes[1].echoes == savedEchoes, "Completed reports ignore late events")
env.SlashCmdList.BORJESMAGASIN("selftest report")
check(m.message:find("/reload saves", 1, true), "Report command explains local persistence")
env.SlashCmdList.BORJESMAGASIN("selftest")
check(bm.DB.lastSelfTest == report, "Cooldown prevents repeated network tests")
m.Advance(300)
check(#m.probes == 3, "Finished test has no idle sends or polling")

local accepted, am, ae = client()
accepted.StartSelfTest(); am.Advance(15.1)
local ar = accepted.DB.lastSelfTest
check(ar.probes[1].api.accepted and ar.probes[1].echoes == 0, "API success without delivery is never called an echo")
check(table.concat(am.messages, "\n"):find("no echo observed", 1, true), "No-echo results are explicit")

local blocked, b, be = client({ result = 11 })
blocked.StartSelfTest(); b.Advance(80)
check(#b.probes == 3 and blocked.DB.lastSelfTest.probes[2].api.result == 11, "Real API refusal is retained with no retries")
check(not blocked.DB.lastSelfTest.probes[2].api.accepted, "Lockdown is not accepted")
check(table.concat(b.messages, "\n"):find("AddOnMessageLockdown (11)", 1, true), "Readable enum is printed")

local failed, f = client({ throw = true })
failed.StartSelfTest(); f.Advance(16)
check(failed.DB.lastSelfTest.state == "complete" and #f.probes == 3, "API exceptions do not abort report completion")
check(not failed.DB.lastSelfTest.probes[1].api.ok and failed.DB.lastSelfTest.probes[1].api.result:find("Simulated send API error", 1, true), "API error detail is retained")

local mismatch, mm = client({ echo = "all", sender = "Suer" })
mismatch.StartSelfTest(); mm.Advance(16)
check(mismatch.DB.lastSelfTest.probes[2].echoes == 1 and not mismatch.DB.lastSelfTest.probes[2].identityMatches,
    "An actual echo with an incomplete name diagnoses identity failure independently")

local noise, n = client()
noise.StartSelfTest(); n.Advance(.2)
local nr, np = noise.DB.lastSelfTest, n.probes[1]
n.Fire("CHAT_MSG_ADDON", np[1], np[2] .. "old", "GUILD", "Suer Fisk")
n.Fire("CHAT_MSG_ADDON", np[1], np[2], "WHISPER", "Suer Fisk")
n.Fire("CHAT_MSG_ADDON", np[1], { secret = true }, "GUILD", "Suer Fisk")
n.Fire("CHAT_MSG_ADDON", np[1], np[2], "GUILD", { secret = true })
n.Fire("CHAT_MSG_ADDON", np[1], string.rep("x", 500), "GUILD", "Suer Fisk")
check(nr.probes[1].echoes == 0, "Unrelated nonces, wrong channels, secret values and oversized data cannot count as an echo")
n.Fire("CHAT_MSG_ADDON", np[1], np[2], "GUILD", "Suer Fisk")
check(nr.probes[1].echoes == 1, "Matching asynchronous event counts")
for _ = 1, 110 do n.Fire("CHAT_MSG_ADDON", np[1], np[2], "GUILD", "Suer Fisk") end
check(nr.probes[1].echoes == 100 and nr.probes[1].sender == "Suer Fisk", "Duplicate echo accounting is bounded")
n.Advance(60); noise.StartSelfTest(); n.Advance(.2)
local fresh = noise.DB.lastSelfTest
n.Fire("CHAT_MSG_ADDON", np[1], np[2], "GUILD", "Suer Fisk")
check(fresh ~= nr and fresh.probes[1].echoes == 0, "New run cannot mistake an old nonce for its own response")

local leaving, lm = client()
leaving.StartSelfTest(); lm.Advance(.2); lm.Fire("PLAYER_LOGOUT"); lm.Advance(20)
check(#lm.probes == 1 and leaving.DB.lastSelfTest.state == "interrupted by logout/reload", "Logout cancels pending probes and preserves an honest partial report")

local unregistered, um = client({ registerResult = 2 })
unregistered.StartSelfTest(); um.Advance(16)
check(#um.probes == 0 and unregistered.DB.lastSelfTest.probes[1].skipped, "Failed prefix registration prevents sends")
local duplicate, dm = client({ registerResult = 1 })
duplicate.StartSelfTest(); dm.Advance(16)
check(#dm.probes == 3, "Already registered prefix remains usable")

local brokenCodec, cm = client()
brokenCodec.UnpackProfile = function() return nil end
brokenCodec.StartSelfTest(); cm.Advance(16)
check(not brokenCodec.DB.lastSelfTest.codec.passed and #cm.probes == 3, "Codec failure is distinct from and does not suppress transport tests")
local brokenCapture, fm = client()
fm.Advance(6)
brokenCapture.Capture = function() error("Simulated capture failure") end
brokenCapture.StartSelfTest(); fm.Advance(16)
check(brokenCapture.DB.lastSelfTest.codec.error:find("Simulated capture failure", 1, true) and #fm.probes == 3, "Capture exceptions are diagnosed independently")

local missing, xm, xe = client()
xe.C_ChatInfo.SendAddonMessage, xe.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = nil, nil
missing.StartSelfTest(); xm.Advance(16)
check(not missing.DB.lastSelfTest.probes[1].api.called and missing.DB.lastSelfTest.flags.restricted == "API unavailable", "Missing APIs are explicit rather than false success")
local secret, sm = client({ result = { secret = true } })
secret.StartSelfTest(); sm.Advance(16)
check(secret.DB.lastSelfTest.probes[1].api.result == "secret" and not secret.DB.lastSelfTest.probes[1].api.accepted, "Secret return values are not inspected")
local nilResult, nm = client({ returnNil = true })
nilResult.StartSelfTest(); nm.Advance(16)
check(not nilResult.DB.lastSelfTest.probes[1].api.accepted and nilResult.DB.lastSelfTest.probes[1].api.result == "nil", "Nil return is not silently accepted")

local solo, so = client()
so.guild = nil; solo.UpdateRoster(); solo.StartSelfTest(); so.Advance(16)
check(#so.probes == 2 and solo.DB.lastSelfTest.probes[1].skipped == "skipped: no guild", "Guildless test still tries both self-whisper forms")
local legacy, le = client({ legacy = true, echo = "whisper", sender = "Alice-Forever" })
legacy.StartSelfTest(); le.Advance(16)
check(#le.probes == 2 and le.probes[2][4] == "Alice" and legacy.DB.lastSelfTest.probes[2].identityMatches, "Conventional names use one self whisper and retain realm identity")

local persisted = bm.DB.lastSelfTest
m.Fire("PLAYER_LOGOUT")
local reloaded, rm, re = client({ db = bm.DB })
re.SlashCmdList.BORJESMAGASIN("selftest report")
check(reloaded.DB.lastSelfTest == persisted and table.concat(rm.messages, "\n"):find("identity match=true", 1, true), "A new addon instance can display the persisted completed report")
check(#rm.probes == 0, "Reading a persisted report never restarts the network test")

print(checks .. " solo diagnostic checks passed: API results, echoes, names, persistence, bounds and isolation.")
