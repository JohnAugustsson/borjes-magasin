local Mock = dofile("tests/mock_wow.lua")
dofile("tests/live_mock.lua")(Mock)
local BM = dofile("tests/load.lua")
local checks = 0
local function check(value, description) checks = checks + 1; assert(value, description) end
Mock.Fire("ADDON_LOADED", "borjes-magasin"); Mock.Fire("PLAYER_LOGIN"); Mock.Advance(40)
BM.Open(); BM.State.member = BM.SelfID; BM.ShowTab("gear"); Mock.Advance(2)
local gear = BM.Window.pages.gear
check(gear.xpFrame:IsVisible() and gear.xpBar.value == .42, "Selected member has a proportional XP bar")
check(gear.xpTitle:GetText() == "To level 43 / 42.0%" and gear.xpText:GetText() == "42000 / 100000 XP", "XP shows next level, percentage and actual values")
gear.xpFrame.scripts.OnEnter(gear.xpFrame)
check(Mock.tooltip == "Experience", "XP has a snapshot tooltip")
local reads, captures, xpCaptures, builds = 0, 0, 0, 0
local itemRead, questRead = GetInventoryItemLink, C_QuestLog.IsQuestFlaggedCompleted
GetInventoryItemLink = function(...) reads = reads + 1; return itemRead(...) end
C_QuestLog.IsQuestFlaggedCompleted = function(...) reads = reads + 1; return questRead(...) end
local full, xpOnly, build = BM.Capture, BM.CaptureXP, BM.BuildMembers
BM.Capture = function(...) captures = captures + 1; return full(...) end
BM.CaptureXP = function(...) xpCaptures = xpCaptures + 1; return xpOnly(...) end
BM.BuildMembers = function(...) builds = builds + 1; return build(...) end
local sent = #Mock.sent
Mock.xp = 50000
for i = 1, 100 do Mock.Fire("PLAYER_XP_UPDATE", "player") end
Mock.Advance(2)
check(xpCaptures == 1 and captures == 0 and reads == 0, "XP bursts coalesce without rescanning gear or quests")
check(gear.xpBar.value == .5 and #Mock.sent == sent, "Local XP redraw does not broadcast")
check(BM.UnpackProfile(BM.Character.wire).xp == 50000, "XP-only update persists the new value")
local previous = BM.Character.wire
Mock.Fire("PLAYER_XP_UPDATE", "party1"); Mock.Advance(2)
check(xpCaptures == 1 and BM.Character.wire == previous, "Ignore other units' XP events")
Mock.Fire("PLAYER_XP_UPDATE", "player"); Mock.Advance(2)
check(BM.Character.wire == previous, "Unchanged XP leaves the saved snapshot untouched")
Mock.xp, Mock.gold = 60000, 789000
Mock.Fire("PLAYER_XP_UPDATE", "player"); Mock.Fire("PLAYER_MONEY"); Mock.Advance(2)
check(captures == 1 and BM.SelfProfile.gold == 789000 and BM.SelfProfile.xp == 60000, "A full update takes priority over pending XP work")
Mock.xp = 65000; Mock.gold = 789001
Mock.Fire("PLAYER_MONEY"); Mock.Fire("PLAYER_XP_UPDATE", "player"); Mock.Advance(2)
check(captures == 2 and BM.SelfProfile.gold == 789001, "An XP event cannot downgrade a pending full update")
BM.Close(); local oldBuilds = builds
Mock.xp = 66000; Mock.Fire("PLAYER_XP_UPDATE", "player"); Mock.Advance(2)
check(builds == oldBuilds and BM.SelfProfile.xp == 66000, "Hidden XP updates do no UI roster rebuild")
BM.Open(); BM.ShowTab("gear")
Mock.level, Mock.xp, Mock.xpMax = 43, 0, 110000
Mock.Fire("PLAYER_LEVEL_UP", 43); Mock.Fire("PLAYER_XP_UPDATE", "player"); Mock.Advance(2)
check(gear.level:GetText() == "Level 43 Warrior" and gear.xpTitle:GetText() == "To level 44 / 0.0%", "Level-up refreshes level and resets progress before roster catches up")
check(gear.xpBar.value == 0 and gear.xpBar:IsVisible(), "Zero XP is known progress")
Mock.level, Mock.xp, Mock.xpMax = 60, 0, 0
Mock.Fire("PLAYER_LEVEL_UP", 60); Mock.Advance(2)
check(not gear.xpFrame:IsVisible() and BM.SelfProfile.xp == nil, "XP is hidden and omitted at level 60")
Mock.level, Mock.xp, Mock.xpMax = 42, 42000, 100000; BM.Capture(); BM.Refresh()
for _, values in ipairs({ { 1, 0 }, { 100001, 100000 }, { -1, 100000 }, { 1.5, 100000 }, { { secret = true }, 100000 }, { 2, { secret = true } } }) do
    Mock.xp, Mock.xpMax = values[1], values[2]; BM.CaptureXP(); BM.Refresh()
    check(BM.SelfProfile.xp == nil and not gear.xpBar:IsVisible() and gear.xpText:GetText() == "XP not shared yet", "Unavailable or invalid XP is unknown, never a fake zero")
end
Mock.xp, Mock.xpMax = 42000, 100000; BM.Capture()
local value = BM.Decode(BM.Character.wire)
for _, invalid in ipairs({ { 1, 0 }, { 11, 10 }, { false, 10 }, { 1, 1000000001 }, { 1 }, "bad" }) do
    value[11] = invalid
    check(BM.UnpackProfile(BM.Encode(value)) == nil, "Reject malformed received XP")
end
value[11], value[3] = { 1, 10 }, 60
check(BM.UnpackProfile(BM.Encode(value)) == nil, "Reject XP in a max-level snapshot")
value[1], value[3], value[11] = 1, 40, nil
local oldWire = BM.Encode(value)
local old = BM.UnpackProfile(oldWire)
check(old and old.xp == nil and old.gold == BM.SelfProfile.gold, "Legacy snapshots retain existing data without fabricated XP")
BM.GuildCache["bob-forever"] = { wire = oldWire, profile = old, received = BM.Now() }
BM.State.member = "bob-forever"; BM.RebuildMembers(); BM.Refresh()
check(gear.xpFrame:IsVisible() and not gear.xpBar:IsVisible() and gear.xpText:GetText() == "XP not shared yet", "Selecting an older client clears the previous member's XP")
old.xp, old.xpMax = 500, 1000; BM.RebuildMembers(); BM.Refresh()
check(gear.xpBar.value == .5, "Received XP matches the snapshot level")
Mock.roster[2].level = 41; BM.UpdateRoster(); BM.Refresh()
check(not gear.xpBar:IsVisible(), "A newer roster level suppresses stale previous-level XP")
Mock.roster[2].level = 60; BM.UpdateRoster(); BM.Refresh()
check(not gear.xpFrame:IsVisible(), "Roster level 60 hides XP even with an older snapshot")
BM.State.member = BM.SelfID; BM.Refresh()
check(gear.xpFrame:IsVisible() and gear.xpBar.value == .42, "Returning to a leveling member restores their own progress")
BM.Window.search:SetText("nobody matches")
check(not gear.xpFrame:IsVisible(), "Empty filters cannot expose stale XP")
print(checks .. " XP capture, schema, event and UI checks passed.")
