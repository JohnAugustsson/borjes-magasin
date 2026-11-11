-- Run each bootstrap case in a fresh Lua process.
local scenario = assert(arg[1])
local Mock = dofile("tests/mock_wow.lua")
dofile("tests/live_mock.lua")(Mock)
BorjesMagasinDB = { introduced = true, partyOnly = true }
if scenario == "preloaded" or scenario == "combat" then Mock.LoadGuildUI() end
if scenario == "combat" then Mock.combat = true end
local BM = dofile("tests/load.lua")
Mock.Fire("ADDON_LOADED", "borjes-magasin")
Mock.Fire("PLAYER_LOGIN")
assert(BM.State.partyOnly, "Saved party filter must survive reload")
if scenario == "preloaded" then
    assert(BM.GuildTab and not BM.Window:IsShown(), "Attach to an existing native frame without opening it")
elseif scenario == "late" then
    assert(not BM.GuildTab, "Guild UI is not loaded yet")
    Mock.LoadGuildUI()
    assert(BM.GuildTab and not BM.Window:IsShown(), "Attach when the native UI loads later")
elseif scenario == "failed" then
    Mock.loadFails = true; BM.Open()
    assert(not BM.Window and Mock.message:find("DISABLED"), "Explain load failure without creating a floating fallback")
    Mock.loadFails = false
elseif scenario == "combat" then
    assert(not BM.GuildTab, "Defer attachment during combat")
    BM.Open(); assert(BM.PendingOpen)
    Mock.combat = false; Mock.Fire("PLAYER_REGEN_ENABLED")
else error("Unknown scenario") end
BM.Open()
assert(BM.GuildActive and BM.Window:IsVisible(), "Opening must recover after the bootstrap condition")
assert(BM.Window:GetParent() == CommunitiesFrame, "No standalone window")
assert(#BM.FilterMembers("", "name", "week", true, BM.State.partyOnly) == 2)
print("Bootstrap passed: " .. scenario)
