local _, BM = ...
-- Manual, bounded transport probes. This separate prefix carries only a nonce,
-- never a profile, and never feeds the normal guild snapshot receiver.
local PREFIX, DURATION, COOLDOWN = "BorjesDebug1", 15, 60
local active, lastStarted, serial = nil, -math.huge, 0
local results = { [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage",
    [3] = "AddonMessageThrottle", [4] = "InvalidChatType", [5] = "NotInGroup",
    [6] = "TargetRequired", [7] = "InvalidChannel", [8] = "ChannelThrottle",
    [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown", [12] = "TargetOffline" }
local function say(message) DEFAULT_CHAT_FRAME:AddMessage("|cffe8ba6eborjes self-test:|r " .. message) end
local function scalar(value)
    if BM.Secret(value) then return "secret" end
    local kind = type(value)
    if kind == "boolean" or kind == "number" then return value end
    if kind == "string" then return BM.Text(value, 200) end
    return kind == "nil" and "nil" or "unsupported value"
end
local function observe(fn, ...)
    if type(fn) ~= "function" then return "API unavailable" end
    local ok, value = pcall(fn, ...)
    if not ok then return "API error: " .. tostring(scalar(value)) end
    return scalar(value)
end
local function call(fn, ...)
    if type(fn) ~= "function" then return { called = false, result = "API unavailable", accepted = false } end
    local ok, value = pcall(fn, ...)
    value = scalar(value)
    return { called = true, ok = ok, result = value, accepted = ok and (value == 0 or value == true) }
end
local function resultText(result)
    if not result then return "not attempted" end
    if not result.ok then return "unavailable/error: " .. tostring(result.result) end
    if result.result == true then return "accepted (true)" end
    return (results[result.result] or "Result") .. " (" .. tostring(result.result) .. ")"
end
local function codecTest()
    BM.Capture()
    local wire = BM.Character and BM.Character.wire
    if type(wire) ~= "string" then return { passed = false, error = "No local snapshot" } end
    -- Exercise the production codec on the actual snapshot, without installing
    -- a synthetic peer or changing the guild cache. No contents enter the report.
    local decoded = BM.UnpackProfile(wire)
    return { passed = decoded ~= nil and BM.PackProfile(decoded) == wire, bytes = #wire }
end
function BM.SelfTestReport()
    local report = BM.DB and BM.DB.lastSelfTest
    if not report then say("No test yet. Run /bm selftest."); return end
    say(report.version .. " / " .. report.state .. " / " .. tostring(report.selfName))
    local codec = report.codec
    say("Local profile codec: " .. (codec.passed and "PASS" or "FAIL") .. " / " .. tostring(codec.bytes or 0) .. " bytes"
        .. (codec.error and (" / " .. codec.error) or ""))
    say("Restriction=" .. tostring(report.flags.restricted) .. "; chat lockdown=" .. tostring(report.flags.chatLockdown)
        .. "; combat=" .. tostring(report.flags.combat))
    say("Trial=" .. tostring(report.flags.trial) .. "; veteran trial=" .. tostring(report.flags.veteranTrial)
        .. "; debug prefix=" .. tostring(report.registration.result))
    for _, probe in ipairs(report.probes) do
        local delivery = probe.echoes > 0 and ("returned in " .. probe.latencyMs .. " ms; sender=" .. probe.sender
            .. "; identity match=" .. tostring(probe.identityMatches)) or (report.state == "running" and "waiting for echo" or "no echo observed")
        say(probe.channel .. (probe.target and (" [" .. probe.target .. "]") or "") .. ": "
            .. (probe.skipped or ("API " .. resultText(probe.api) .. "; " .. delivery)))
    end
    say("API acceptance is not delivery. A missing guild echo alone is inconclusive; self echoes do not prove delivery to another account.")
    say("/bm selftest report repeats this. /reload saves the local report to disk.")
end
function BM.StartSelfTest()
    if not BM.DB or not BM.Character or not BM.SelfID then say("Wait until your character has loaded."); return end
    if active then say("Test already running; results appear after 15 seconds."); return end
    local now = GetTime()
    if now - lastStarted < COOLDOWN then
        say("Wait " .. math.ceil(COOLDOWN - (now - lastStarted)) .. " seconds before another test, or use /bm selftest report."); return
    end
    lastStarted, serial = now, serial + 1
    local chat = C_ChatInfo or {}
    local version, build, _, interface = BM.Read(GetBuildInfo)
    local report = { version = BM.VERSION, at = BM.Now(), started = now, state = "running",
        selfID = BM.SelfID, selfName = BM.SelfName, realm = BM.Realm, regionalNames = BM.RegionalNames,
        sharing = BM.DB.sharing, guildScope = BM.GuildScope, syncStatus = BM.SyncStatus(),
        clientVersion = scalar(version), clientBuild = scalar(build), interface = scalar(interface),
        flags = { restricted = observe(chat.AreOutgoingAddonChatMessagesRestricted),
            chatLockdown = observe(chat.InChatMessagingLockdown), combat = observe(InCombatLockdown),
            trial = observe(IsTrialAccount), veteranTrial = observe(IsVeteranTrialAccount) }, probes = {} }
    local ok, codec = pcall(codecTest)
    report.codec = ok and codec or { passed = false, error = tostring(scalar(codec)) }
    report.registration = call(chat.RegisterAddonMessagePrefix, PREFIX)
    -- Registration enums include DuplicatePrefix (1), which is already usable.
    report.registration.accepted = report.registration.ok and
        (report.registration.result == 0 or report.registration.result == 1 or report.registration.result == true) or false
    local nonce = tostring(report.at) .. "-" .. math.floor(now * 1000) .. "-" .. serial
    local function add(channel, target, skipped)
        local index = #report.probes + 1
        report.probes[index] = { channel = channel, target = target, skipped = skipped,
            message = "1|T|" .. nonce .. "|" .. index, echoes = 0 }
    end
    add("GUILD", nil, not BM.GuildScope and "skipped: no guild" or nil)
    if BM.RegionalNames then
        local name = BM.FullCharacterName(BM.SelfName)
        if name then add("WHISPER", name); add("WHISPER", (name:gsub(" ", "-")))
        else add("WHISPER", nil, "skipped: full character name unavailable") end
    else
        local name = BM.SelfName
        add("WHISPER", name, not name and "skipped: character name unavailable" or nil)
    end
    active, BM.DB.lastSelfTest = report, report
    say("Started. Testing your local profile and up to three tiny hidden messages; results in 15 seconds.")
    for index, probe in ipairs(report.probes) do
        local p = probe
        C_Timer.After(index - 1, function()
            if active ~= report or p.skipped then return end
            if not report.registration.accepted then p.skipped = "skipped: debug prefix registration failed"; return end
            p.sentAt = GetTime()
            p.restrictedAtSend = observe(C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
            -- Observe the flag but deliberately call the ordinary API once. The
            -- API/server still enforces restrictions; no retries or fallback API.
            p.api = call(C_ChatInfo and C_ChatInfo.SendAddonMessage, PREFIX, p.message, p.channel, p.target)
        end)
    end
    C_Timer.After(DURATION, function()
        if active ~= report then return end
        active, report.state, report.finished = nil, "complete", GetTime()
        BM.SelfTestReport()
    end)
end
function BM.ReceiveSelfTest(prefix, message, channel, sender)
    if BM.Secret(prefix) or prefix ~= PREFIX then return false end
    -- Consume only this dedicated prefix, even outside an active test.
    if not active or BM.Secret(message) or BM.Secret(channel) or BM.Secret(sender) then return true end
    if type(message) ~= "string" or #message > 120 or type(sender) ~= "string" or #sender > 96 then return true end
    for _, probe in ipairs(active.probes) do
        if probe.sentAt and probe.channel == channel and probe.message == message then
            probe.echoes = math.min(probe.echoes + 1, 100)
            if probe.echoes == 1 then
                probe.latencyMs = math.floor(math.max(0, GetTime() - probe.sentAt) * 1000 + .5)
                probe.sender = BM.Text(sender, 96)
                probe.canonicalSender = BM.Canonical(sender)
                probe.identityMatches = probe.canonicalSender == active.selfID
            end
            return true
        end
    end
    return true
end
function BM.EndSelfTest()
    if not active then return end
    active.state, active.finished = "interrupted by logout/reload", GetTime()
    active = nil
end
