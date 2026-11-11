local Mock = dofile("tests/mock_wow.lua")
dofile("tests/live_mock.lua")(Mock)
local BM = dofile("tests/load.lua")
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
Mock.Fire("ADDON_LOADED", "borjes-magasin"); Mock.Fire("PLAYER_LOGIN"); Mock.Advance(2)
BM.DB.sharing = false
check(BM.Profile ~= nil, "First upgrade starts a bounded local profile")
for i = 1, 200 do
    local name = "Member" .. i .. "-Forever"
    Mock.roster[#Mock.roster + 1] = { name = name, level = 42, classID = 1, presence = 1 }
    local p = BM.UnpackProfile(BM.PackProfile(BM.SelfProfile))
    for slot = 1, 19 do p.items[slot] = "item:" .. (10000 + slot) end
    BM.GuildCache[BM.Canonical(name)] = { profile = p, wire = BM.PackProfile(p), received = BM.Now() }
end
BM.UpdateRoster()
local lookups, missing = 0, false
local original = C_Item.GetItemInfo
C_Item.GetItemInfo = function(link)
    lookups = lookups + 1
    if missing and link == "item:777777" then return nil end
    return original(link)
end
local function builds() local s = BM.Profile.functions.BuildMembers; return s and s.calls or 0 end
local before = builds()
for i = 1, 100 do BM.RebuildMembers(); Mock.Fire("GET_ITEM_INFO_RECEIVED", 10000 + i, true) end
Mock.Advance(.2)
check(builds() == before and lookups == 0, "Hidden update storms do no roster rendering or item queries")
BM.Open()
check(#BM.Members == 203 and builds() == before + 1, "Opening displays the latest roster with one build")
check(lookups == 0, "PvP list does not fetch any member's equipment")
before = builds()
for i = 1, 100 do BM.RebuildMembers(); Mock.Fire("GET_ITEM_INFO_RECEIVED", 90000 + i, true) end
Mock.Advance(.2)
check(builds() == before + 1 and lookups == 0, "Visible update bursts coalesce to a single roster build")
BM.State.member = "member1-forever"; BM.ShowTab("gear")
check(lookups == 19, "Viewing gear loads only the selected member's 19 items")
BM.State.member = "member2-forever"; BM.Refresh()
check(lookups == 19, "Identical item strings reuse cached metadata")
missing = true
BM.GuildCache["member2-forever"].profile.items[1] = "item:777777"
BM.RebuildMembers(); BM.Refresh()
check(BM.Window.pages.gear.slots[1].item.name == "Loading item...", "Uncached item displays a loading state")
local requests = lookups
for i = 1, 10 do BM.RebuildMembers(); BM.Refresh() end
check(lookups == requests, "Pending item reads are throttled")
missing = false; before = builds()
for i = 1, 100 do Mock.Fire("GET_ITEM_INFO_RECEIVED", 777777, true) end
Mock.Advance(.2)
check(builds() == before + 1 and lookups == requests + 1, "Loaded item events invalidate once and refresh once")
check(BM.Window.pages.gear.slots[1].item.name == "Verified item 777777", "Loaded metadata replaces the loading state")
before, requests = builds(), lookups
for i = 1, 100 do Mock.Fire("GET_ITEM_INFO_RECEIVED", 888888, true) end
Mock.Advance(.2)
check(builds() == before and lookups == requests, "Unrelated item-cache traffic causes no refresh")
BM.Close(); before, requests = builds(), lookups
for i = 1, 100 do BM.RebuildMembers() end
Mock.Advance(.2)
check(builds() == before and lookups == requests, "Closing the ledger stops view work again")
BM.ProfileFrame(.2)
check(BM.Profile.slowFrames >= 1 and BM.Profile.worstFrame >= 200, "Profiler records whole-client frame delays")
local p = BM.Profile
check(p.functions.GearView.calls > 0 and p.functions.BuildMembers.calls > 0 and p.functions.Events.calls > 0, "Profiler attributes calls to the correct functions")
Mock.Advance(120)
check(BM.Profile == nil and BM.DB.lastProfile == p and p.duration >= 120 and p.duration < 121, "Automatic capture stops and saves after two minutes")
local savedCalls = p.functions.Capture.calls
BM.Capture()
check(p.functions.Capture.calls == savedCalls, "Disabled profiling does not continue recording")
local messages = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, message) messages[#messages + 1] = message end
SlashCmdList.BORJESMAGASIN("profile report")
check(#messages > 3 and messages[1]:find("Saved capture", 1, true), "Report is available through the local slash command")
SlashCmdList.BORJESMAGASIN("profile start"); Mock.Advance(1)
check(BM.Profile ~= nil, "A manual capture can be restarted")
Mock.Fire("PLAYER_LOGOUT")
check(BM.Profile == nil and BM.DB.lastProfile.duration >= .99 and BM.DB.lastProfile.duration < 1.1, "Logout saves a partial capture")
check(#Mock.sent == 0, "Profiling never sends guild messages")
print(checks .. " performance and profiler checks passed with a 203-member simulated guild.")
