local Mock = dofile("tests/mock_wow.lua")
dofile("tests/live_mock.lua")(Mock)
local BM = dofile("tests/load.lua")
local checks = 0
local function check(value, description) checks = checks + 1; assert(value, description) end
Mock.Fire("ADDON_LOADED", "unrelated-addon")
check(BM.DB == nil, "Ignore other addon loading")
Mock.Fire("ADDON_LOADED", "borjes-magasin")
Mock.Fire("PLAYER_LOGIN")
Mock.Advance(2)
BM.Open()
check(BM.Window:IsVisible() and BM.Window:GetParent() == CommunitiesFrame, "Ledger opens inside the standard guild window")
check(#BM.Members == 3, "Real guild roster loaded from client API")
check(BM.GetMember("clara-forever").gold == nil, "No invented data for members without snapshots")
check(SLASH_BORJESMAGASIN1 == "/borjes" and SLASH_BORJESMAGASIN2 == "/bm", "Slash command aliases")
local initialGold = BM.GetMember("alice-forever").gold
local sourceOrder = BM.Members[1].id
check(BM.FilterMembers("", "kills", "week")[1].id == "alice-forever", "Known zero ranks above unknown")
check(BM.FilterMembers("", "gold")[1].id == "alice-forever", "Gold ranking")
check(BM.Members[1].id == sourceOrder, "Sorting does not mutate source order")
check(#BM.FilterMembers("priest", "name", "week", true) == 1, "Class search")
check(#BM.FilterMembers("[", "name") == 0, "Search treats patterns as literal text")
check(BM.Money(1234567) == "123g 45s 67c", "Money formatting")
local totals = BM.Totals("week"); check(totals.kills == 0 and totals.gold > 0, "Summary aggregates")

local pvp = BM.Window.pages.pvp
Mock.Click(pvp.headers.ganks)
check(BM.State.pvpSort == "ganks" and pvp.rows[1].member.id == "alice-forever", "Sort by ganks")
Mock.Click(pvp.headers.ganks)
check(BM.State.ascending and BM.Ganks(pvp.rows[1].member, "week") == 0, "Reverse sorting")
Mock.Click(pvp.all); check(BM.State.period == "all", "All-time view")
Mock.Click(pvp.week); check(BM.State.period == "week", "Weekly view")
Mock.Click(pvp.rows[1]); check(BM.State.member == pvp.rows[1].member.id, "Member selection")
Mock.Click(Mock.FindButton("View gear snapshot")); check(BM.State.tab == "gear", "Inspect navigation")
local gear = BM.Window.pages.gear
check(#gear.slots == 19, "All equipment slots present")
gear.slots[1].scripts.OnEnter(gear.slots[1]); check(Mock.tooltip == gear.slots[1].item.link, "Item tooltip")
gear.slots[6].scripts.OnEnter(gear.slots[6]); check(Mock.tooltip:find("Empty") ~= nil, "Empty-slot tooltip")

BM.Window.search:SetText("no such person")
check(gear.empty:IsShown() and not gear.rows[1]:IsShown(), "Empty search state")
BM.Window.search:SetText("alice-forever")
check(gear.rows[1].member.id == "alice-forever" and not gear.rows[2]:IsShown(), "Filtered roster")
Mock.Click(gear.rows[1])
BM.Window.search:SetText("")
BM.ShowTab("quests")
local quests = BM.Window.pages.quests
Mock.Click(quests.dungeonButtons.deadmines)
check(BM.State.dungeon == "deadmines", "Dungeon selection")
Mock.Click(quests.rows[2].cells[3])
check(BM.State.member == quests.rows[2].member.id and BM.State.quest == 3, "Quest-cell selection")
check(quests.detailTitle:GetText():find("Collecting Memories", 1, true) ~= nil, "Quest details follow selection")
quests.rows[2].cells[3].scripts.OnEnter(quests.rows[2].cells[3])
check(Mock.tooltip == "Collecting Memories", "Quest tooltip")
BM.State.member, BM.State.dungeon, BM.State.quest = "alice-forever", "scarlet", 1
BM.ShowTab("gold")
Mock.gold = initialGold + 12783
Mock.Fire("PLAYER_MONEY"); Mock.Advance(2)
check(BM.GetMember("alice-forever").gold == initialGold + 12783, "Money event captures actual balance")
check(BM.Window.pages.gold.balance:GetText() == BM.Money(initialGold + 12783), "Visible balance refreshes")
check(BM.GetMember("alice-forever").history[1] == nil, "No fabricated historical balances")

BM.State.member = "clara-forever" -- Guild member outside the actual party.
Mock.Click(BM.Window.partyFilter)
check(BM.State.partyOnly and BM.DB.partyOnly and BM.GetMember(BM.State.member).inParty, "Party filter saves its setting and replaces an excluded selection")
for _, tab in ipairs({ "pvp", "quests", "gold", "gear" }) do
    BM.ShowTab(tab)
    local count, onlyParty = 0, true
    for _, row in ipairs(BM.Window.pages[tab].rows) do
        if row:IsShown() then count = count + 1; onlyParty = onlyParty and row.member.inParty end
    end
    check(count == 2 and onlyParty, "Party filter applies to " .. tab)
    Mock.Snapshot(CommunitiesFrame, "tests/" .. tab .. "-party.json")
end
BM.Window.search:SetText("warrior")
check(gear.rows[1].member.id == "alice-forever" and not gear.rows[2]:IsShown(), "Class search intersects party membership")
BM.Window.search:SetText("clara-forever")
check(gear.empty:IsShown() and not gear.details:IsShown() , "Excluded members show no stale details or update action")
BM.Window.search:SetText("")
BM.ShowTab("gold")
local partyTotals = BM.Totals("week", BM.FilterMembers("", "name", "week", true, true))
check(BM.Window.pages.gold.total.value:GetText() == BM.Money(partyTotals.gold, true), "Gold totals follow the party scope")
BM.ShowTab("pvp")
check(pvp.total.value:GetText() == tostring(partyTotals.kills), "PvP totals follow the party scope")
Mock.Click(BM.Window.partyFilter)
local count = 0; for _, row in ipairs(pvp.rows) do if row:IsShown() then count = count + 1 end end
check(count == 3 and not BM.DB.partyOnly, "Turning party filter off restores the full roster")

-- A larger minimap must move the launcher outwards instead of keeping radius 82.
local function radius()
    local _, _, _, x, y = BM.Launcher:GetPoint()
    return math.sqrt(x * x + y * y), x, y
end
Minimap:SetSize(240, 240)
check(math.abs(radius() - 125) < .001, "Launcher follows the resized round minimap ring")
GetMinimapShape = function() return "SQUARE" end
BM.PositionLauncher()
local _, x, y = radius()
check(math.abs(math.max(math.abs(x), math.abs(y)) - 125) < .001, "Launcher follows a square minimap edge")
GetMinimapShape = nil
Minimap:SetSize(140, 140)
check(math.abs(radius() - 75) < .001, "Launcher follows the ring after shrinking the minimap")

for _, page in pairs(BM.Window.pages) do
    if page.rows then
    page.scroll.scripts.OnMouseWheel(page.scroll, -1000)
    check(page.scroll:GetVerticalScroll() <= page.scroll:GetVerticalScrollRange(), "Scroll clamps at bottom")
    page.scroll.scripts.OnMouseWheel(page.scroll, 1000)
    check(page.scroll:GetVerticalScroll() == 0, "Scroll clamps at top")
    end
end
BM.ShowTab("settings")
local settings = BM.Window.pages.settings
check(settings:IsVisible() and not BM.Window.partyFilter:IsVisible() and not BM.Window.searchBox:IsVisible(), "Settings has its own view without member filters")
check(BM.GetHeartbeatMinutes() == 15, "Heartbeat defaults to 15 minutes")
for _, minutes in ipairs({ 5, 10, 15, 30, 0 }) do
    Mock.Click(settings.heartbeatButtons[minutes])
    check(BM.GetHeartbeatMinutes() == minutes and BM.DB.heartbeatMinutes == minutes, "Heartbeat setting is applied and persisted")
end
Mock.Snapshot(CommunitiesFrame, "tests/settings.json")
BM.ShowTab("pvp")
check(BM.Window.partyFilter:IsVisible() and BM.Window.searchBox:IsVisible(), "Member filters return when leaving Settings")
for _, name in ipairs({ "pvp", "quests", "gold", "gear" }) do BM.ShowTab(name) end
local frames = #Mock.objects
for i = 1, 40 do
    BM.ShowTab(({ "pvp", "quests", "gold", "gear" })[i % 4 + 1])
    BM.Window.search:SetText(i % 2 == 0 and "warrior" or "")
end
check(#Mock.objects == frames, "Refresh reuses widgets without leaking frames")
BM.Window.search:SetText("")
CommunitiesFrame:SetSize(714, 400); BM.ApplyScale()
check(BM.Window:GetScale() * 800 <= 700, "Embedded panel fits a resized guild window")
CommunitiesFrame:SetSize(814, 426); BM.ResetPosition()
check(BM.Window:GetScale() == 1, "Default guild size uses full-sized text")
SlashCmdList.BORJESMAGASIN(""); check(not BM.Window:IsShown(), "Slash toggles closed")
SlashCmdList.BORJESMAGASIN(""); check(BM.Window:IsShown(), "Slash toggles open")
local host = CommunitiesFrame
check(BM.GuildTab:GetChecked() and not host.RosterTab:GetChecked(), "Bear tab replaces native checked state")
check(host.NativeContent:IsShown(), "Native content visibility is never overwritten")
Mock.Click(host.ChatTab)
check(not BM.GuildActive and not BM.Window:IsShown() and host.ChatTab:GetChecked(), "Native tab restores its content and checked state")
local chatBar = host.Chat.ScrollBar
check(host.Chat:IsVisible() and chatBar:GetFrameStrata() == "HIGH", "Native chat initially uses the HIGH scrollbar layer")
Mock.Click(BM.GuildTab)
check(Mock.IsAbove(BM.Window, chatBar), "Chat scrollbar must not draw or receive clicks above the ledger")
check(host.Chat:IsShown() and chatBar:IsShown() and chatBar.scrollPosition == 37, "Preserve native chat visibility and scroll position")
BM.Open()
check(Mock.IsAbove(BM.Window, chatBar), "Opening an already active ledger retains the scrollbar layer")
check(BM.Window:IsVisible() and BM.GuildActive, "Guild bear tab opens the embedded ledger")
Mock.Click(host.ChatTab) -- Same native mode, early-return path.
check(not BM.GuildActive and host.ChatTab:GetChecked(), "Clicking an already selected native mode still exits the ledger")
check(chatBar:GetFrameStrata() == "HIGH" and chatBar:IsVisible(), "Same-mode Chat navigation restores the original scrollbar layer")
Mock.Click(BM.GuildTab); Mock.Click(host.RosterTab)
check(chatBar:GetFrameStrata() == "HIGH" and not chatBar:IsVisible(), "Different native mode restores the layer without revealing hidden chat")
Mock.Click(host.ChatTab)
Mock.Click(BM.Launcher)
check(BM.GuildActive and host:IsShown(), "Minimap opens the bear tab directly")
host:UpdateCommunitiesTabs()
check(BM.GuildTab:GetChecked() and not host.ChatTab:GetChecked(), "Native roster updates keep the bear tab selected")
Mock.Click(host.CloseButton)
check(not BM.GuildActive and not BM.Window:IsVisible(), "Native close button closes the ledger too")
check(chatBar:GetFrameStrata() == "HIGH", "Closing the guild window restores the native scrollbar layer")
ShowUIPanel(host)
check(not BM.Window:IsShown() and host.ChatTab:GetChecked(), "Reopening the guild window shows the native page normally")
host:SetSize(322, 406)
check(not BM.GuildTab:IsShown(), "Bear tab hides in minimized chat view")
check(chatBar:GetFrameStrata() == "HIGH", "Minimized native chat keeps the scrollbar layer")
Mock.Click(BM.Launcher)
check(host:GetWidth() == 814 and BM.Window:IsVisible(), "Minimap expands minimized guild window")
check(Mock.IsAbove(BM.Window, chatBar), "Reopening from minimized chat covers the scrollbar again")
host:SetSize(322, 406)
check(not BM.GuildActive and chatBar:GetFrameStrata() == "HIGH", "Minimizing while the ledger is active restores the scrollbar")
BM.Open()
local frameCount = #Mock.objects
Mock.Fire("ADDON_LOADED", "Blizzard_Communities")
check(#Mock.objects == frameCount, "Attaching twice does not duplicate tabs or frames")
BM.Close()
check(chatBar:GetFrameStrata() == "HIGH", "Explicit ledger close restores the scrollbar")
Mock.combat = true
BM.Open()
check(BM.PendingOpen and not host:IsShown(), "Opening in combat is deferred without touching the native panel")
check(chatBar:GetFrameStrata() == "HIGH", "Deferred open leaves the native scrollbar unchanged")
Mock.combat = false; Mock.Fire("PLAYER_REGEN_ENABLED")
check(BM.GuildActive and not BM.PendingOpen, "Deferred opening resumes after combat")
BM.Close(); Mock.combat = true; BM.Open(); BM.Toggle()
Mock.combat = false; Mock.Fire("PLAYER_REGEN_ENABLED")
check(not host:IsShown(), "Toggling again cancels a deferred opening")
BM.Open()
Mock.benefits, Mock.preferred = true, true; host:UpdateCommunitiesTabs()
local _, relative = BM.GuildTab:GetPoint()
check(relative == host.GuildPreferredPlaySettingsTab, "Bear tab follows the last visible native tab")
Mock.benefits, Mock.preferred = false, false; host:UpdateCommunitiesTabs()
-- A completely empty roster must render all pages without stale details.
local realMembers = BM.Members
BM.Members = {}
for _, page in ipairs({ "pvp", "quests", "gold", "gear" }) do
    BM.ShowTab(page); check(BM.Window.pages[page].empty:IsShown(), "Empty roster: " .. page)
end
BM.Members = realMembers
for _, tab in ipairs({ "pvp", "quests", "gold", "gear" }) do
    BM.ShowTab(tab)
    Mock.Snapshot(CommunitiesFrame, "tests/" .. tab .. ".json")
end
print(checks .. " checks passed. UI snapshots generated with the mock runtime (not in-game captures).")
