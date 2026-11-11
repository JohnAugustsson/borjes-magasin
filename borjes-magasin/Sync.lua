local _, BM = ...
BM.PREFIX = "BorjesMagasin1"
local CHUNK, MAX_CHUNKS = 180, 89
local assemblies, completed, helloSeen = {}, {}, {}
local pending, current, hello, due = false, nil, false, 0
local serial, lastStart, lastHello, lastPacket = 0, -60, -60, -60
local timerPending, generation, deadline, loggingOut, lastSharedSignature = false, 0, 0, false, nil
local heartbeatGeneration, pendingReason = 0, nil
local heartbeatOptions = { [0] = true, [5] = true, [10] = true, [15] = true, [30] = true }
local session = tostring(BM.Now()) .. tostring(math.random(1000, 9999))
local function enabled() return BM.DB and BM.DB.sharing ~= false and BM.GuildScope and BM.Registered end
local function notify() if BM.RefreshSyncStatus then BM.RefreshSyncStatus() end end
-- Bounded local diagnostics: no payloads, visible guild chat or idle polling.
local diagnostic = { sent = 0, received = 0, accepted = 0, ticks = 0, blocked = 0, rejected = {}, recent = {} }
local function record(kind, detail)
    local rows = diagnostic.recent
    rows[#rows + 1] = { at = GetTime(), kind = kind, detail = BM.Text(tostring(detail or ""), 240) }
    if #rows > 24 then table.remove(rows, 1) end
end
local function reject(reason)
    diagnostic.rejected[reason] = (diagnostic.rejected[reason] or 0) + 1
end
function BM.SaveSyncReport()
    if not BM.DB then return end
    local roster, party, units = {}, {}, {}
    for id, member in pairs(BM.Roster or {}) do
        if #roster < 100 then roster[#roster + 1] = { id = id, name = member.name } end
    end
    for id in pairs(BM.Party or {}) do party[#party + 1] = id end
    for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        local fullName, fullRealm = BM.Read(UnitFullName, unit)
        local name, realm = BM.Read(UnitName, unit)
        units[#units + 1] = { unit = unit, firstName = fullName or name,
            surname = BM.RegionalNames and (fullRealm or realm) or nil,
            realm = not BM.RegionalNames and (fullRealm or realm) or nil,
            displayName = BM.Read(GetUnitName, unit, true) }
    end
    BM.DB.lastSyncReport = { version = BM.VERSION, at = BM.Now(), clock = GetTime(),
        status = BM.SyncStatus(), registered = BM.Registered, sharing = BM.DB.sharing,
        selfID = BM.SelfID, realm = BM.Realm, identityRealm = BM.IdentityRealm,
        regionalNames = BM.RegionalNames,
        guildScope = BM.GuildScope, roster = roster, party = party, partyUnits = BM.PartyUnits,
        units = units, raid = BM.Read(IsInRaid), groupSize = BM.Read(GetNumGroupMembers),
        partyOnly = BM.State and BM.State.partyOnly, hasSnapshot = BM.SelfProfile ~= nil,
        pending = pending, hello = hello, timerPending = timerPending, due = due,
        deadline = deadline, lastStart = lastStart, lastHello = lastHello, lastPacket = lastPacket,
        currentPart = current and current.next, currentCount = current and current.count,
        diagnostic = diagnostic }
    return BM.DB.lastSyncReport
end
function BM.SyncReport()
    BM.UpdateParty()
    local report = BM.SaveSyncReport()
    local function say(message) DEFAULT_CHAT_FRAME:AddMessage("|cffe8ba6eborjes debug:|r " .. message) end
    say(BM.VERSION .. " / " .. report.status .. " / self " .. tostring(BM.SelfID))
    say("Sent " .. diagnostic.sent .. " / received " .. diagnostic.received .. " / accepted " .. diagnostic.accepted .. " snapshots / ticks " .. diagnostic.ticks)
    say("Last send result " .. tostring(diagnostic.lastSendResult) .. " / restriction flag " .. tostring(diagnostic.restrictionFlag)
        .. " / own echoes " .. (diagnostic.rejected["self echo"] or 0))
    say("Guild members " .. #report.roster .. " / party identities " .. #report.party .. " / filter " .. tostring(report.partyOnly))
    if diagnostic.error then say("Last error: " .. diagnostic.error) end
    for reason, count in pairs(diagnostic.rejected) do say("Ignored " .. reason .. ": " .. count) end
    say("Local report ready. /reload saves it to disk for inspection.")
end
function BM.GetHeartbeatMinutes()
    local value = BM.DB and BM.DB.heartbeatMinutes
    return heartbeatOptions[value] and value or 15
end
function BM.ScheduleHeartbeat()
    heartbeatGeneration = heartbeatGeneration + 1
    local minutes, token = BM.GetHeartbeatMinutes(), heartbeatGeneration
    if minutes == 0 or not enabled() or loggingOut then return end
    C_Timer.After(minutes * 60, function()
        if token ~= heartbeatGeneration then return end
        BM.QueueSnapshot(false, "heartbeat")
        BM.ScheduleHeartbeat()
    end)
end
function BM.SetHeartbeatMinutes(minutes)
    if not BM.DB or not heartbeatOptions[minutes] then return false end
    BM.DB.heartbeatMinutes = minutes
    if pendingReason == "heartbeat" then pending, pendingReason = false, nil end
    if current and current.reason == "heartbeat" then current = nil end
    BM.ScheduleHeartbeat()
    BM.RebuildMembers()
    return true
end
local function wake()
    if timerPending or not enabled() or not (pending or current or hello) then return end
    timerPending = true
    local token = generation
    C_Timer.After(.4, function()
        if token ~= generation then return end
        timerPending = false
        local ok, err = pcall(BM.SyncTick)
        if not ok then
            diagnostic.error = BM.Text(tostring(err), 240)
            record("tick error", diagnostic.error)
            pending, current, hello = false, nil, false
            BM.SyncError = "Sync stopped; /bm debug"
            BM.SaveSyncReport()
            notify()
            return
        end
        wake()
    end)
end
function BM.ResetSync()
    record("reset", BM.GuildScope)
    assemblies, completed, helloSeen = {}, {}, {}
    pending, current, hello, due, lastStart, lastHello = false, nil, false, 0, -60, -60
    generation, timerPending, loggingOut, lastSharedSignature = generation + 1, false, false, nil
    pendingReason = nil
    BM.SyncRequest = nil
    BM.SyncError = nil
    BM.ScheduleHeartbeat()
    notify()
end
function BM.InitializeSync()
    local result = BM.Read(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix, BM.PREFIX)
    BM.Registered = result == true or result == 0 or result == 1
    if not BM.Registered then BM.SyncError = "Addon channel unavailable" end
    record("register", result)
    BM.ResetSync()
    if not BM.Registered then BM.SyncError = "Addon channel unavailable" end
end
function BM.QueueSnapshot(immediate, reason)
    if not enabled() then return end
    if not pending then
        due = math.max(due, GetTime() + 2 + math.random() * 2)
        deadline = GetTime() + 120
    end
    if immediate then due, lastStart = GetTime(), -60 end
    if not pending or pendingReason == "heartbeat" then pendingReason = reason or "request" end
    pending = true
    wake()
    notify()
end
function BM.RequestSync(manual)
    BM.RequestRoster(); BM.UpdateRoster(); BM.UpdateParty(); BM.Capture()
    if not enabled() then notify(); return end
    record("request", manual == false and "login" or "manual")
    if manual ~= false then BM.SyncRequest = { started = GetTime(), received = {}, count = 0 } end
    hello = true
    BM.QueueSnapshot(); BM.RebuildMembers()
end
function BM.TryLoginSync(force)
    if not BM.LoginSyncPending then return end
    if not BM.RosterReady and not force then return end
    BM.LoginSyncPending = false
    BM.RequestSync(false)
end
function BM.ToggleSharing()
    BM.DB.sharing = BM.DB.sharing == false
    BM.LoginSyncPending = false
    BM.ResetSync()
    BM.RebuildMembers()
end
function BM.SyncStatus()
    if not BM.DB or BM.DB.sharing == false then return "Sharing paused" end
    if not BM.GuildScope then return "Local only / no guild" end
    if not BM.Registered then return "Addon channel unavailable" end
    if BM.SyncError then return BM.SyncError end
    if current then return "Sending snapshot " .. (current.next - 1) .. "/" .. current.count end
    if pending or hello then return "Sync queued" end
    local request = BM.SyncRequest
    if request and request.sent then
        if request.count > 0 then return "Received " .. request.count .. " guild snapshot" .. (request.count == 1 and "" or "s") end
        return request.finished and "No guild replies received" or "Waiting for guild replies"
    end
    local minutes = BM.GetHeartbeatMinutes()
    return minutes > 0 and ("Heartbeat: " .. minutes .. " min") or "Heartbeat off"
end
function BM.SyncButtonText()
    if not enabled() then return "Sync now" end
    if current then return "Sending..." end
    if pending or hello then return "Sync queued..." end
    return "Sync now"
end
local function requested()
    local request = BM.SyncRequest
    if not request or request.sent then return end
    request.sent = GetTime()
    C_Timer.After(90, function()
        if BM.SyncRequest ~= request then return end
        request.finished = true
        notify()
    end)
end
local function send(message)
    -- Forever 1.60.1 can report this flag as true while the ordinary API
    -- succeeds and GUILD messages echo back. Retain it as an observation;
    -- let SendAddonMessage enforce restrictions and use its actual result.
    diagnostic.restrictionFlag = BM.Read(C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
    local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage
    local ok, result
    if type(fn) == "function" then ok, result = pcall(fn, BM.PREFIX, message, "GUILD") end
    if not ok then diagnostic.error = BM.Text(tostring(result or "SendAddonMessage missing"), 240) end
    if BM.Secret(result) then result = nil end
    diagnostic.lastSendResult = ok and BM.Text(tostring(result), 80) or "API error"
    record("send", ok and tostring(result) or "API error")
    if ok and (result == true or result == 0) then
        diagnostic.sent = diagnostic.sent + 1
        BM.SyncError = nil; return true
    end
    if result == 3 or result == 8 then BM.SyncError = "Waiting for chat throttle"
    elseif result == 11 then
        diagnostic.blocked = diagnostic.blocked + 1
        record("client restriction", "SendAddonMessage: 11")
        BM.SyncError = "Client restricts addon messages"
    elseif result == 10 then BM.SyncError = "Client reports no guild"
    else BM.SyncError = "Addon send unavailable (" .. tostring(result) .. ")" end
    notify()
    return false
end
local function transfer(signature)
    local payload = BM.Character and BM.Character.wire
    if not payload then BM.SyncError = "Snapshot unavailable"; pending = false; return end
    serial = serial + 1
    return { payload = payload, id = session .. "-" .. serial, count = math.ceil(#payload / CHUNK), next = 1,
        started = GetTime(), reason = pendingReason, signature = signature or BM.PackProfile(BM.SelfProfile, true) }
end
local function sendNext()
    local c = current
    local message = "1|S|" .. c.id .. "|" .. c.next .. "|" .. c.count .. "|" .. c.payload:sub((c.next - 1) * CHUNK + 1, c.next * CHUNK)
    lastPacket = GetTime()
    if not send(message) then return false end
    c.next = c.next + 1
    if c.next > c.count then
        current = nil; lastSharedSignature = c.signature
        BM.LastSent = BM.Now(); BM.RebuildMembers()
    end
    notify()
    return true
end
function BM.SyncTick()
    diagnostic.ticks = diagnostic.ticks + 1
    local now = GetTime()
    if not enabled() or now - lastPacket < .4 then return end
    if not (pending or current or hello) then return end
    if now > deadline then
        pending, current, hello = false, nil, false
        record("timeout", BM.SyncError)
        BM.SyncError = BM.SyncError or "Sync timed out; use Sync now"
        notify()
        return
    end
    if now < due then return end
    if hello and now - lastHello >= 30 then
        lastPacket = now
        if send("1|H") then hello = false; lastHello = now; requested(); notify() else due = now + 10 end
        return
    end
    if not current and pending and now - lastStart >= 30 and BM.SelfProfile then
        BM.Capture()
        current = transfer()
        pending, lastStart = false, now
    end
    if not current then return end
    if now - current.started > 80 then current = nil; pending = true; due = now + 10; return end
    if not sendNext() then due = now + 10 end
end
function BM.PrepareLogout()
    -- The logout countdown leaves time for the normal paced transfer.
    if loggingOut or not enabled() then return end
    loggingOut = true
    BM.ScheduleHeartbeat()
    current, hello = nil, false
    BM.QueueSnapshot(true, "logout")
end
function BM.CancelLogout()
    if not loggingOut then return end
    loggingOut, pending, current, hello = false, false, nil, false
    generation, timerPending = generation + 1, false
    BM.ScheduleHeartbeat()
end
function BM.FlushLogout()
    BM.LoginSyncPending = false
    BM.Capture() -- Always persist the latest local data, even when sharing is paused.
    generation, timerPending, pending, hello = generation + 1, false, false, false
    heartbeatGeneration = heartbeatGeneration + 1
    if not enabled() or not BM.SelfProfile then current = nil; return end
    local signature = BM.PackProfile(BM.SelfProfile, true)
    if signature == lastSharedSignature then current = nil; return end
    if not current or current.signature ~= signature then current = transfer(signature) end
    -- No timers run after PLAYER_LOGOUT. Try the remaining bounded packets now;
    -- stop on the first client restriction/throttle. Delivery is best effort.
    while current do if not sendNext() then current = nil; break end end
end
function BM.Receive(prefix, message, channel, sender)
    if BM.Secret(prefix) or BM.Secret(message) or BM.Secret(channel) or BM.Secret(sender) then return end
    if prefix ~= BM.PREFIX then return end
    diagnostic.received = diagnostic.received + 1
    if channel ~= "GUILD" then reject("channel"); return end
    if not enabled() then reject("sharing unavailable"); return end
    if type(message) ~= "string" or #message > 240 then reject("message size"); return end
    local peer = BM.Canonical(sender)
    if peer == BM.SelfID then reject("self echo"); return end
    if not peer or not BM.Roster[peer] then reject("unknown guild sender"); record("unknown sender", peer); return end
    local now = GetTime()
    for id, a in pairs(assemblies) do if now - a.started > 90 then assemblies[id] = nil end end
    if message == "1|H" then
        if not helloSeen[peer] or now - helloSeen[peer] >= 30 then helloSeen[peer] = now; BM.QueueSnapshot() end
        return
    end
    local id, part, count, chunk = message:match("^1|S|([%d%-]+)|(%d+)|(%d+)|(.*)$")
    part, count = tonumber(part), tonumber(count)
    if not id or #id > 32 or not part or not count or part < 1 or count < 1 or count > MAX_CHUNKS or part > count or #chunk < 1 or #chunk > CHUNK then reject("packet format"); return end
    if completed[peer] == id then return end
    local a = assemblies[peer]
    if not a or a.id ~= id then
        -- One bounded assembly per known member; never allocate by attacker-controlled message IDs.
        local size = 0; for _ in pairs(assemblies) do size = size + 1 end
        if not a and size >= 64 then return end
        a = { id = id, total = count, pieces = {}, received = 0, bytes = 0, started = now }
        assemblies[peer] = a
    end
    if a.total ~= count then assemblies[peer] = nil; return end
    if a.pieces[part] then
        if a.pieces[part] ~= chunk then assemblies[peer] = nil end
        return
    end
    a.pieces[part], a.received, a.bytes = chunk, a.received + 1, a.bytes + #chunk
    if a.bytes > BM.MAX_WIRE_BYTES then assemblies[peer] = nil; return end
    if a.received ~= a.total then return end
    assemblies[peer] = nil
    local wire = table.concat(a.pieces)
    local p = BM.UnpackProfile(wire)
    if not p or not BM.GuildCache then reject("snapshot format"); return end
    local old = BM.GuildCache[peer]
    if old and old.profile and p.at < old.profile.at then return end
    completed[peer] = id
    BM.GuildCache[peer] = { wire = wire, profile = p, received = BM.Now() }
    diagnostic.accepted = diagnostic.accepted + 1
    record("snapshot", peer)
    BM.LastReceived = BM.Now()
    local request = BM.SyncRequest
    if request and request.sent and not request.finished and not request.received[peer] then
        request.received[peer] = true; request.count = request.count + 1
        notify()
    end
    BM.RebuildMembers()
end
