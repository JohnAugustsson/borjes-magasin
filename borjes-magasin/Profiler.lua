local _, BM = ...
-- Bounded local diagnostics. No global scriptProfile CVar and no guild traffic.
local clock = debugprofilestop or function() return (GetTimePreciseSec and GetTimePreciseSec() or GetTime()) * 1000 end
local frame = CreateFrame("Frame")
local function say(message) DEFAULT_CHAT_FRAME:AddMessage("|cffe8ba6eborjes profile:|r " .. message) end
function BM.ProfileCall(name, fn, ...)
    local profile = BM.Profile
    if not profile then return fn(...) end
    local start = clock()
    local result = fn(...)
    local elapsed = math.max(0, clock() - start)
    local stat = profile.functions[name]
    if not stat then stat = { calls = 0, total = 0, maximum = 0 }; profile.functions[name] = stat end
    stat.calls, stat.total, stat.maximum = stat.calls + 1, stat.total + elapsed, math.max(stat.maximum, elapsed)
    return result
end
function BM.ProfileEvent(event)
    local p = BM.Profile
    if p then p.events[event] = (p.events[event] or 0) + 1 end
end
function BM.ProfileFrame(delta)
    local p = BM.Profile
    if not p then return end
    p.frames = p.frames + 1
    p.slowFrames = p.slowFrames + (delta > .05 and 1 or 0)
    p.worstFrame = math.max(p.worstFrame, delta * 1000)
end
function BM.StartProfile()
    local p = { version = BM.VERSION, at = BM.Now(), started = GetTime(), functions = {}, events = {}, frames = 0, slowFrames = 0, worstFrame = 0 }
    BM.Profile = p
    frame:SetScript("OnUpdate", function(_, delta) BM.ProfileFrame(delta) end)
    C_Timer.After(120, function()
        if BM.Profile == p then BM.StopProfile(); say("120-second capture saved. /bm profile report shows the results.") end
    end)
end
function BM.StopProfile()
    if not BM.Profile then return end
    BM.Profile.duration = math.max(0, GetTime() - BM.Profile.started)
    BM.DB.lastProfile, BM.Profile = BM.Profile, nil
    frame:SetScript("OnUpdate", nil)
end
function BM.ProfileReport()
    local p = BM.Profile or BM.DB.lastProfile
    if not p then say("No capture yet. Use /bm profile start, reproduce the lag, then /bm profile report."); return end
    local duration = BM.Profile and GetTime() - p.started or p.duration
    say(string.format("%s / %.1fs / %d frames over 50ms / worst frame %.1fms", BM.Profile and "Recording" or "Saved capture", duration or 0, p.slowFrames, p.worstFrame))
    local rows = {}
    for name, stat in pairs(p.functions) do rows[#rows + 1] = { name = name, stat = stat } end
    table.sort(rows, function(a, b) return a.stat.total > b.stat.total end)
    for i = 1, math.min(8, #rows) do
        local r = rows[i]
        say(string.format("%s: %d calls / %.2fms total / %.3fms avg / %.2fms worst call", r.name, r.stat.calls, r.stat.total, r.stat.total / math.max(1, r.stat.calls), r.stat.maximum))
    end
    local events = {}
    for name, count in pairs(p.events) do events[#events + 1] = { name, count } end
    table.sort(events, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(3, #events) do say(events[i][1] .. ": " .. events[i][2] .. " events") end
    say("Total = all calls over the capture, not per frame. Worst call = one call. Times include nested calls; do not add them together. Frame delays cover the whole game.")
end
function BM.ProfileCommand(cmd)
    if cmd == "start" then BM.StartProfile(); say("Recording for 120 seconds. Reproduce the lag, then /bm profile report.")
    elseif cmd == "stop" then BM.StopProfile(); BM.ProfileReport()
    else BM.ProfileReport() end
end
function BM.InstallProfiler()
    if BM.ProfilerInstalled then return end
    BM.ProfilerInstalled = true
    -- These functions each return zero or one result. Preserve errors normally.
    for _, name in ipairs({ "Capture", "UpdateRoster", "UpdateParty", "BuildMembers", "RebuildMembers", "Refresh", "GearView", "SyncTick", "Receive" }) do
        local original = BM[name]
        BM[name] = function(...) return BM.ProfileCall(name, original, ...) end
    end
end
