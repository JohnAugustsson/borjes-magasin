local _, BM = ...
local C = {
    bg = { .055, .065, .08, 1 }, panel = { .085, .10, .125, 1 },
    row = { .105, .12, .145, 1 }, selected = { .20, .18, .13, 1 },
    border = { .23, .27, .32, 1 }, gold = { .91, .73, .43 },
    text = { .91, .92, .94 }, muted = { .58, .64, .71 },
    green = { .45, .80, .65 }, red = { .91, .48, .43 },
}
local W, H = 800, 363
local window
local quality = { [1] = C.text, [2] = { .40, .82, .39 }, [3] = { .36, .65, 1 }, [4] = { .74, .48, .95 } }
local classCoords = {
    WARRIOR = { 0, .25, 0, .25 }, MAGE = { .25, .5, 0, .25 }, ROGUE = { .5, .75, 0, .25 },
    DRUID = { .75, 1, 0, .25 }, HUNTER = { 0, .25, .25, .5 }, PRIEST = { .5, .75, .25, .5 },
    WARLOCK = { .75, 1, .25, .5 }, PALADIN = { 0, .25, .5, .75 }, SHAMAN = { .25, .5, .25, .5 },
}
local function label(parent, x, y, w, h, value, size, color, align)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    f:SetPoint("TOPLEFT", x, -y); f:SetSize(w, h)
    f:SetJustifyH(align or "LEFT"); f:SetJustifyV("MIDDLE")
    f:SetWordWrap(false); f:SetText(value or ""); f:SetTextColor(unpack(color or C.text))
    return f
end
local function surface(parent, x, y, w, h, color, kind)
    local f = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    f:SetPoint("TOPLEFT", x, -y); f:SetSize(w, h)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(unpack(color or C.panel)); f:SetBackdropBorderColor(unpack(C.border))
    return f
end
local function tooltip(owner, title, lines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:SetText(title, unpack(C.gold))
    for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, .8, .84, .9, true) end
    GameTooltip:Show()
end
local function button(parent, x, y, w, h, title, click)
    local b = surface(parent, x, y, w, h, C.row, "Button")
    b.label = label(b, 5, 0, w - 10, h, title, 11, C.text, "CENTER")
    b:SetScript("OnClick", click)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.gold)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)); GameTooltip:Hide() end)
    return b
end
local function active(b, yes)
    b:SetBackdropColor(unpack(yes and C.selected or C.row))
    b.label:SetTextColor(unpack(yes and C.gold or C.muted))
end
local function icon(parent, x, y, size, texture)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", x, -y); t:SetSize(size, size)
    t:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    return t
end
local function setClass(texture, class)
    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    texture:SetTexCoord(unpack(classCoords[class] or classCoords.WARRIOR))
end
local function scroll(parent, x, y, w, h)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", x, -y); sf:SetSize(w - 24, h)
    local child = CreateFrame("Frame", nil, sf); child:SetSize(w - 26, h)
    sf:SetScrollChild(child); sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * 36, self:GetVerticalScrollRange())))
    end)
    sf.content, sf.contentWidth, sf.viewportHeight = child, w - 26, h
    return sf
end
local function stat(parent, x, w, title, accent)
    local f = surface(parent, x, 0, w, 42)
    f.title = label(f, 10, 3, w - 20, 13, title, 9, C.muted)
    f.value = label(f, 10, 17, w - 20, 22, "", 18, accent or C.gold)
    return f
end
local function members(query, sort, period, ascending)
    return BM.FilterMembers(query, sort, period, ascending, BM.State.partyOnly)
end
local function selectMember(id) BM.State.member = id; BM.Refresh() end
local function fillMember(row, m)
    row.member = m
    row.name:SetText(m.name); row.name:SetTextColor(unpack(BM.ClassColors[m.class] or C.muted))
    active(row, BM.State.member == m.id)
end
local function memberRow(parent, y, w, height)
    local row = button(parent, 0, y, w, height, "", function(r) selectMember(r.member.id) end)
    row.name = label(row, 8, 2, w - 16, 16, "", 11)
    row.sub = label(row, 8, 18, w - 16, 13, "", 9, C.muted)
    return row
end
local function rowsFor(page, list, factory, fill, rowHeight)
    local sf = page.scroll
    for _, r in ipairs(page.rows) do r:Hide() end
    for i, m in ipairs(list) do
        if not page.rows[i] then page.rows[i] = factory(sf.content, (i - 1) * rowHeight, sf.contentWidth) end
        local r = page.rows[i]; fill(r, m, i); r:Show()
    end
    sf.content:SetHeight(math.max(sf.viewportHeight, #list * rowHeight))
    sf:SetVerticalScroll(math.min(sf:GetVerticalScroll(), math.max(0, #list * rowHeight - sf.viewportHeight)))
    page.empty:SetShown(#list == 0)
    page.details:SetShown(#list > 0)
end
local function createPVP(parent)
    local p = CreateFrame("Frame", nil, parent); p:SetAllPoints(); p.rows = {}
    p.total = stat(p, 0, 194, "QUALIFYING KILLS")
    p.ganks = stat(p, 202, 194, "GRAY-PLAYER GANKS", C.red)
    for _, card in ipairs({ p.total, p.ganks }) do
        card:EnableMouse(true)
        card:SetScript("OnEnter", function(self)
            tooltip(self, "World PvP killing blows", { "Tracked since installing the live addon, including your pet.", "Qualifying: non-gray enemies at your level minus 5 or higher.", "Gray enemies count as ganks; unknown levels stay unclassified.", "Battlegrounds, arenas and other instances are excluded.", "Last 7 days uses UTC days. Counters are reported by members." })
        end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    p.leader = stat(p, 404, 188, "TOP OF THE BOARD", C.green)
    p.week = button(p, 600, 0, 88, 42, "Last 7 days", function() BM.State.period = "week"; BM.Refresh() end)
    p.all = button(p, 696, 0, 88, 42, "All time", function() BM.State.period = "all"; BM.Refresh() end)
    local panel = surface(p, 0, 50, 502, 228)
    label(panel, 4, 0, 24, 26, "#", 10, C.muted, "CENTER")
    local function sort(key)
        if BM.State.pvpSort == key then BM.State.ascending = not BM.State.ascending
        else BM.State.pvpSort, BM.State.ascending = key, key == "name" end
        BM.Refresh()
    end
    p.headers = {
        name = button(panel, 32, 3, 244, 22, "Member", function() sort("name") end),
        kills = button(panel, 282, 3, 92, 22, "Qualifying", function() sort("kills") end),
        ganks = button(panel, 380, 3, 92, 22, "Ganks", function() sort("ganks") end),
    }
    p.scroll = scroll(panel, 4, 30, 494, 192)
    p.empty = label(panel, 8, 95, 486, 30, "No members match these filters.", 12, C.muted, "CENTER")
    local d = surface(p, 510, 50, 274, 228); p.details = d
    p.detailName = label(d, 10, 5, 254, 20, "", 15)
    p.detailSub = label(d, 10, 26, 254, 14, "", 10, C.muted)
    p.encounters = {}
    for i = 1, 4 do
        local y = 48 + (i - 1) * 36
        p.encounters[i] = { name = label(d, 10, y, 254, 16, "", 11),
            sub = label(d, 10, y + 16, 180, 13, "", 9, C.muted),
            kind = label(d, 190, y + 16, 74, 13, "", 9, C.green, "RIGHT") }
    end
    button(d, 10, 197, 254, 24, "View gear snapshot", function() BM.ShowTab("gear") end)
    function p:Refresh()
        local ranking = members("", "kills", BM.State.period)
        local total = BM.Totals(BM.State.period, ranking)
        self.total.value:SetText(total.snapshots > 0 and total.kills or "--"); self.ganks.value:SetText(total.snapshots > 0 and total.ganks or "--")
        self.leader.title:SetText(BM.State.partyOnly and "TOP OF YOUR PARTY" or "TOP OF THE BOARD")
        self.leader.value:SetText(ranking[1] and BM.Kills(ranking[1], BM.State.period) and (ranking[1].name:match("^([^%-]+)") .. " / " .. BM.Kills(ranking[1], BM.State.period)) or "No snapshots")
        active(self.week, BM.State.period == "week"); active(self.all, BM.State.period == "all")
        for key, b in pairs(self.headers) do active(b, key == BM.State.pvpSort) end
        local ranks = {}; for i, m in ipairs(ranking) do ranks[m.id] = i end
        rowsFor(self, members(BM.State.query, BM.State.pvpSort, BM.State.period, BM.State.ascending), function(par, y, width)
            local row = button(par, 0, y, width, 36, "", function(r) selectMember(r.member.id) end)
            row.rank = label(row, 0, 0, 24, 36, "", 12, C.gold, "CENTER")
            row.name = label(row, 32, 2, 238, 17, "", 12)
            row.sub = label(row, 32, 20, 238, 13, "", 9, C.muted)
            row.kills = label(row, 278, 0, 92, 36, "", 15, C.text, "CENTER")
            row.ganks = label(row, 376, 0, 92, 36, "", 15, C.red, "CENTER")
            return row
        end, function(row, m)
            fillMember(row, m); row.rank:SetText(m.hasSnapshot and ranks[m.id] or "--")
            row.sub:SetText("Lv " .. m.level .. " " .. m.className .. " / " .. m.age)
            row.kills:SetText(BM.Kills(m, BM.State.period) or "--"); row.ganks:SetText(BM.Ganks(m, BM.State.period) or "--")
        end, 38)
        local m = BM.GetMember(BM.State.member)
        if not m then return end
        self.detailName:SetText(m.name); self.detailName:SetTextColor(unpack(BM.ClassColors[m.class] or C.muted))
        self.detailSub:SetText(m.hasSnapshot and ("Recent killing blows / " .. m.age) or "Waiting for this member to share")
        for i, row in ipairs(self.encounters) do
            local k = m.kills[i]
            row.name:SetText(k and (k.name .. (k.level and " (" .. k.level .. ")" or "")) or (i == 1 and "No recorded encounters" or ""))
            row.sub:SetText(k and (k.zone .. " / " .. k.age) or "")
            row.kind:SetText(k and k.kind or ""); row.kind:SetTextColor(unpack(k and k.kind == "Gank" and C.red or k and k.kind == "Qualifying" and C.green or C.muted))
        end
    end
    return p
end
local function createQuests(parent)
    local p = CreateFrame("Frame", nil, parent); p:SetAllPoints(); p.rows = {}; p.dungeonButtons = {}
    local side = surface(p, 0, 0, 160, 278)
    label(side, 8, 5, 144, 18, "DUNGEON QUESTS", 10, C.gold)
    for i, d in ipairs(BM.Dungeons) do
        local id = d.id
        local b = button(side, 6, 30 + (i - 1) * 39, 148, 35, "", function() BM.State.dungeon = id; BM.State.quest = 1; BM.Refresh() end)
        label(b, 6, 2, 136, 18, d.name, 11)
        label(b, 6, 20, 136, 12, d.range, 9, C.muted)
        p.dungeonButtons[id] = b
    end
    local panel = surface(p, 168, 0, 616, 278)
    p.title = label(panel, 10, 3, 596, 22, "", 14)
    label(panel, 8, 28, 174, 20, "MEMBER", 9, C.muted)
    p.questHeaders = {}
    for i = 1, 4 do p.questHeaders[i] = label(panel, 196 + (i - 1) * 94, 28, 90, 20, "", 10, C.gold, "CENTER") end
    p.scroll = scroll(panel, 8, 50, 600, 132)
    p.empty = label(panel, 10, 87, 596, 30, "No members match these filters.", 12, C.muted, "CENTER")
    local d = surface(panel, 6, 190, 604, 82, C.bg); p.details = d
    p.detailTitle = label(d, 8, 3, 588, 20, "", 12, C.gold)
    p.detailStatus = label(d, 8, 23, 588, 16, "", 11)
    p.detailObjective = label(d, 8, 42, 588, 16, "", 10, C.muted)
    p.detailPrerequisite = label(d, 8, 61, 588, 16, "", 10, C.muted)
    function p:Refresh()
        local dungeon = BM.GetDungeon(BM.State.dungeon)
        self.title:SetText(dungeon.name .. " / " .. dungeon.range)
        for id, b in pairs(self.dungeonButtons) do active(b, id == dungeon.id) end
        for i, header in ipairs(self.questHeaders) do header:SetText(dungeon.quests[i].short) end
        rowsFor(self, members(BM.State.query, "name", "week", true), function(par, y, width)
            local row = button(par, 0, y, width, 24, "", function(r) selectMember(r.member.id) end)
            row.name = label(row, 5, 0, 177, 24, "", 10)
            row.cells = {}
            for q = 1, 4 do
                local index = q
                local cell = button(row, 188 + (q - 1) * 94, 1, 90, 22, "", function()
                    BM.State.member, BM.State.quest = row.member.id, index; BM.Refresh()
                end)
                cell:SetScript("OnEnter", function(self)
                    local d = BM.GetDungeon(BM.State.dungeon)
                    tooltip(self, d.quests[index].name, { row.member.name, BM.Statuses[row.member.quests[d.id][index].status].label, "Click for details" })
                end)
                row.cells[q] = cell
            end
            return row
        end, function(row, m)
            fillMember(row, m); row.name:SetText(m.name .. " / " .. m.level)
            for q, cell in ipairs(row.cells) do
                local s = BM.Statuses[m.quests[dungeon.id][q].status]
                cell.label:SetText(s.short); cell.label:SetTextColor(unpack(s.color))
                cell:SetBackdropColor(unpack(m.id == BM.State.member and q == BM.State.quest and C.selected or C.row))
            end
        end, 26)
        local m, q = BM.GetMember(BM.State.member), BM.State.quest or 1
        if not m then return end
        local quest, state = dungeon.quests[q], m.quests[dungeon.id][q]
        self.detailTitle:SetText(m.name .. " / " .. quest.name)
        self.detailStatus:SetText(BM.Statuses[state.status].label .. (state.progress and " - " .. state.progress or ""))
        self.detailStatus:SetTextColor(unpack(BM.Statuses[state.status].color))
        self.detailObjective:SetText("Objective: " .. quest.objective)
        self.detailPrerequisite:SetText("Snapshot: " .. m.age .. (quest.prereq and (" / prerequisite quest #" .. quest.prereq) or " / no prerequisite recorded"))
    end
    return p
end
local function createGold(parent)
    local p = CreateFrame("Frame", nil, parent); p:SetAllPoints(); p.rows = {}
    p.total = stat(p, 0, 256, "KNOWN GUILD BALANCES")
    p.average = stat(p, 264, 256, "AVERAGE KNOWN BALANCE", C.text)
    p.richest = stat(p, 528, 256, "LARGEST BALANCE", C.green)
    local panel = surface(p, 0, 50, 502, 228)
    label(panel, 12, 3, 228, 22, "MEMBER", 10, C.muted)
    label(panel, 246, 3, 116, 22, "BALANCE", 10, C.gold, "RIGHT")
    label(panel, 370, 3, 100, 22, "UPDATED", 10, C.muted, "RIGHT")
    p.scroll = scroll(panel, 4, 30, 494, 192)
    p.empty = label(panel, 8, 95, 486, 30, "No members match these filters.", 12, C.muted, "CENTER")
    local d = surface(p, 510, 50, 274, 228); p.details = d
    p.name = label(d, 10, 4, 254, 22, "", 15)
    p.balance = label(d, 10, 28, 254, 24, "", 20, C.gold)
    p.updated = label(d, 10, 54, 254, 16, "", 10, C.muted)
    label(d, 10, 75, 254, 15, "DAILY BALANCE OBSERVATIONS (UTC)", 9, C.muted)
    p.bars = {}
    for i = 1, 7 do
        local y = 96 + (i - 1) * 18
        local bar = CreateFrame("StatusBar", nil, d)
        bar:SetPoint("TOPLEFT", 50, -y); bar:SetSize(153, 10)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(unpack(C.gold)); bar:SetMinMaxValues(0, 1)
        label(d, 10, y - 3, 36, 16, i == 7 and "Today" or (7 - i) .. "d ago", 9, C.muted)
        p.bars[i] = { bar = bar, value = label(d, 207, y - 3, 57, 16, "", 9, C.text, "RIGHT") }
    end
    function p:Refresh()
        local roster = members("", "gold")
        local total, richest = BM.Totals("week", roster), roster[1]
        self.total.title:SetText(BM.State.partyOnly and "KNOWN PARTY BALANCES" or "KNOWN GUILD BALANCES")
        self.total.value:SetText(total.balances > 0 and BM.Money(total.gold, true) or "Unknown")
        self.average.value:SetText(total.balances > 0 and BM.Money(math.floor(total.gold / total.balances), true) or "Unknown")
        self.richest.value:SetText(richest and richest.gold and (richest.name:match("^([^%-]+)") .. " / " .. BM.Money(richest.gold, true)) or "No snapshots")
        rowsFor(self, members(BM.State.query, "gold"), function(par, y, width)
            local row = memberRow(par, y, width, 36)
            row.name:SetWidth(228); row.sub:SetWidth(228)
            row.money = label(row, 242, 0, 116, 36, "", 12, C.gold, "RIGHT")
            row.age = label(row, 366, 0, 100, 36, "", 10, C.muted, "RIGHT")
            return row
        end, function(row, m)
            fillMember(row, m); row.sub:SetText("Lv " .. m.level .. " " .. m.className)
            row.money:SetText(BM.Money(m.gold)); row.age:SetText(m.age)
        end, 38)
        local m = BM.GetMember(BM.State.member)
        if not m then return end
        self.name:SetText(m.name); self.name:SetTextColor(unpack(BM.ClassColors[m.class] or C.muted))
        self.balance:SetText(BM.Money(m.gold)); self.updated:SetText("Last snapshot: " .. m.age)
        local maximum = 1; for _, value in pairs(m.history) do maximum = math.max(maximum, value) end
        for i, b in ipairs(self.bars) do b.bar:SetValue((m.history[i] or 0) / maximum); b.value:SetText(BM.Money(m.history[i], true)) end
    end
    return p
end
local function gearSlot(parent, x, y, w, h)
    local b = button(parent, x, y, w, h, "", function() end)
    b.icon = icon(b, 3, (h - 20) / 2, 20)
    b.slot = label(b, 28, 0, w - 32, 10, "", 8, C.muted)
    b.name = label(b, 28, 10, w - 32, h - 10, "", 10)
    b:SetScript("OnEnter", function(self)
        local item = self.item; if not item then return end
        self:SetBackdropBorderColor(unpack(C.gold))
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if item.link then
            GameTooltip:SetHyperlink(item.link)
        else
            GameTooltip:SetText(item.empty and "Empty " .. item.slot:lower() .. " slot" or "No equipment snapshot", unpack(C.muted))
        end
        GameTooltip:Show()
    end)
    return b
end
local function createGear(parent)
    local p = CreateFrame("Frame", nil, parent); p:SetAllPoints(); p.rows = {}; p.slots = {}
    local side = surface(p, 0, 0, 174, 278)
    p.scroll = scroll(side, 4, 4, 166, 270)
    p.empty = label(side, 5, 98, 164, 40, "No matching members.", 11, C.muted, "CENTER")
    local panel = surface(p, 182, 0, 602, 278); p.details = panel
    p.name = label(panel, 8, 2, 340, 25, "", 16)
    p.age = label(panel, 356, 2, 238, 25, "", 10, C.muted, "RIGHT")
    for i = 1, 16 do
        p.slots[i] = gearSlot(panel, i <= 8 and 5 or 391, 31 + ((i - 1) % 8) * 26, 206, 24)
    end
    for i = 17, 19 do p.slots[i] = gearSlot(panel, 5 + (i - 17) * 199, 244, 194, 29) end
    p.portrait = icon(panel, 277, 57, 48)
    p.level = label(panel, 215, 122, 172, 22, "", 13, C.text, "CENTER")
    p.spec = label(panel, 215, 147, 172, 18, "", 11, C.muted, "CENTER")
    p.zone = label(panel, 215, 172, 172, 18, "", 10, C.muted, "CENTER")
    p.xpFrame = CreateFrame("Frame", nil, panel)
    p.xpFrame:SetPoint("TOPLEFT", 215, -194); p.xpFrame:SetSize(172, 44)
    p.xpTitle = label(p.xpFrame, 0, 0, 172, 13, "", 10, C.gold, "CENTER")
    p.xpBar = surface(p.xpFrame, 0, 16, 172, 9, C.row, "StatusBar")
    p.xpBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    p.xpBar:SetStatusBarColor(.48, .38, .78); p.xpBar:SetMinMaxValues(0, 1)
    p.xpText = label(p.xpFrame, 0, 28, 172, 13, "", 10, C.text, "CENTER")
    p.xpFrame:EnableMouse(true)
    p.xpFrame:SetScript("OnEnter", function(self)
        local m = self.member; if not m then return end
        local lines = { "Last snapshot: " .. m.age }
        if m.xp ~= nil then
            lines[#lines + 1] = string.format("%d XP remaining to level %d.", m.xpMax - m.xp, m.level + 1)
        else lines[#lines + 1] = "No XP for this level yet. The member needs the updated addon and a fresh sync." end
        tooltip(self, "Experience", lines)
    end)
    p.xpFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function p:Refresh()
        rowsFor(self, members(BM.State.query, "name", "week", true), function(par, y, width)
            return memberRow(par, y, width, 34)
        end, function(row, m)
            fillMember(row, m); row.sub:SetText("Lv " .. m.level .. " " .. m.className)
        end, 36)
        local m = BM.GetMember(BM.State.member)
        if not m then return end
        self.name:SetText(m.name); self.name:SetTextColor(unpack(BM.ClassColors[m.class] or C.muted))
        self.age:SetText((m.online and "Online" or "Offline") .. " / " .. m.age)
        setClass(self.portrait, m.class)
        self.level:SetText("Level " .. m.level .. " " .. m.className)
        self.spec:SetText(m.hasSnapshot and "Shared by member" or "Waiting for snapshot"); self.zone:SetText(m.zone)
        self.xpFrame.member = m
        self.xpFrame:SetShown(type(m.level) == "number" and m.level < BM.MAX_LEVEL)
        self.xpTitle:SetText("XP PROGRESS")
        self.xpBar:SetShown(m.xp ~= nil)
        self.xpBar:SetValue(m.xp ~= nil and m.xp / m.xpMax or 0)
        if m.xp ~= nil then
            self.xpTitle:SetText(string.format("To level %d / %.1f%%", m.level + 1, m.xp / m.xpMax * 100))
            self.xpText:SetText(string.format("%d / %d XP", m.xp, m.xpMax))
        else self.xpText:SetText("XP not shared yet") end
        for i, slot in ipairs(self.slots) do
            local item = m.gear[i]; slot.item = item
            slot.slot:SetText(item.slot); slot.icon:SetTexture(item.icon)
            slot.icon:SetDesaturated(item.empty == true); slot.icon:SetAlpha(item.empty and .25 or 1)
            slot.name:SetText(item.empty and "Empty slot" or item.name)
            slot.name:SetTextColor(unpack(item.empty and C.muted or quality[item.quality] or C.text))
        end
    end
    return p
end
local function createSettings(parent)
    local p = surface(parent, 0, 0, 784, 278)
    label(p, 16, 14, 740, 26, "Guild sync", 18, C.gold)
    label(p, 16, 48, 740, 20, "Heartbeat: how often to share an updated snapshot while you play.", 12)
    p.heartbeatButtons = {}
    for i, minutes in ipairs({ 0, 5, 10, 15, 30 }) do
        p.heartbeatButtons[minutes] = button(p, 16 + (i - 1) * 150, 82, 134, 32,
            minutes == 0 and "Off" or (minutes .. " minutes"), function()
                BM.SetHeartbeatMinutes(minutes); BM.Refresh()
            end)
    end
    p.summary = label(p, 16, 128, 740, 22, "", 12, C.green)
    label(p, 16, 164, 740, 20, "Login, logout and Sync now still share your latest data when the heartbeat is off.", 11)
    label(p, 16, 188, 740, 20, "Guildmates' login or manual sync requests can also receive your latest snapshot.", 11, C.muted)
    label(p, 16, 212, 740, 20, "Pause sharing stops all sending and receiving. Your own tracking continues.", 11, C.muted)
    label(p, 16, 244, 740, 18, "Logout delivery is best effort; a fast exit or disconnect can interrupt it.", 10, C.muted)
    function p:Refresh()
        local minutes = BM.GetHeartbeatMinutes()
        for value, b in pairs(self.heartbeatButtons) do active(b, minutes == value) end
        self.summary:SetText(minutes == 0 and "Heartbeat off. No periodic broadcasts." or
            ("Heartbeat every " .. minutes .. " minutes. Changing this restarts the interval."))
    end
    return p
end
function BM.ApplyScale()
    if not window then return end
    -- Normal guild-frame size renders at 100%; honor another addon's resizing.
    local host = window:GetParent()
    local fit = math.min(1, (host:GetWidth() - 14) / W, (host:GetHeight() - 63) / H)
    window:SetScale(math.max(.1, fit))
end
function BM.RefreshSyncStatus()
    if not window or not window.status or not window.sync or not window.sharing then return end
    window.status:SetText(BM.SyncStatus())
    window.sync.label:SetText(BM.SyncButtonText())
    window.sharing.label:SetText(BM.DB.sharing == false and "Resume sharing" or "Pause sharing")
end
function BM.Refresh()
    if not window or not window:IsVisible() then return end
    local settings = BM.State.tab == "settings"
    window.partyFilter:SetShown(not settings); window.searchBox:SetShown(not settings)
    for id, page in pairs(window.pages) do page:SetShown(id == BM.State.tab); active(window.tabs[id], id == BM.State.tab) end
    BM.RefreshSyncStatus()
    if settings then
        window.pages.settings:Refresh()
        window.footer:SetText("Settings saved for this account")
        return
    end
    local visible = members(BM.State.query, "name", "week", true)
    local selected = false
    for _, m in ipairs(visible) do if m.id == BM.State.member then selected = true; break end end
    if not selected and visible[1] then BM.State.member = visible[1].id end
    active(window.partyFilter, BM.State.partyOnly)
    window.partyFilter.label:SetText(BM.State.partyOnly and "Party only: On" or "Party only: Off")
    window.pages[BM.State.tab]:Refresh()
    local m = BM.GetMember(BM.State.member)
    local total = BM.Totals("week", visible)
    window.footer:SetText((#visible > 0 and m.name or "No matches") .. " / " .. total.snapshots .. "/" .. #visible .. " snapshots")
end
function BM.ShowTab(tab) BM.State.tab = tab; BM.Refresh() end
function BM.CreateGuildPanel(host)
    if window then return window end
    window = CreateFrame("Frame", "BorjesMagasinPanel", host, "BackdropTemplate")
    BM.Window = window
    window:Hide(); window:SetSize(W, H); window:SetPoint("TOPLEFT", host, "TOPLEFT", 7, -60)
    -- Above native content (including the chat edit box), below separate dialogs.
    window:SetFrameLevel(host:GetFrameLevel() + 1500); window:EnableMouse(true)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    window:SetBackdropColor(unpack(C.bg))
    local heading = surface(window, 64, -36, 736, 36, C.bg)
    heading:EnableMouse(true)
    label(heading, 10, 3, 440, 30, "borjes-magasin", 18, C.gold)
    window.status = label(heading, 440, 3, 284, 30, "", 10, C.gold, "RIGHT")
    window.tabs, window.pages = {}, {}
    local tabX = 8
    for _, tab in ipairs({ { "pvp", "World PvP", 92 }, { "quests", "Dungeon Quests", 112 }, { "gold", "Gold", 58 }, { "gear", "Gear", 58 }, { "settings", "Settings", 76 } }) do
        local id = tab[1]
        window.tabs[id] = button(window, tabX, 7, tab[3], 28, tab[2], function() BM.ShowTab(id) end)
        tabX = tabX + tab[3] + 6
    end
    window.partyFilter = button(window, 438, 7, 120, 28, "Party only: Off", function()
        BM.State.partyOnly = not BM.State.partyOnly; BM.DB.partyOnly = BM.State.partyOnly
        BM.UpdateParty()
        for _, page in pairs(window.pages) do if page.rows then page.scroll:SetVerticalScroll(0) end end
        BM.Refresh()
    end)
    window.partyFilter:SetScript("OnEnter", function(self)
        tooltip(self, "Party only", { "Filter all four views to your party.", "Shows guild members in your current party (or raid subgroup).", "You are included. Members outside the guild are not listed." })
    end)
    local searchBox = surface(window, 566, 7, 226, 28)
    window.searchBox = searchBox
    local search = CreateFrame("EditBox", nil, searchBox)
    search:SetPoint("LEFT", 8, 0); search:SetSize(184, 26); search:SetFontObject("GameFontHighlight")
    search:SetAutoFocus(false); search:SetMaxLetters(60)
    local placeholder = label(searchBox, 8, 0, 184, 28, "Search members or classes", 11, C.muted)
    search:SetScript("OnTextChanged", function(self)
        BM.State.query = self:GetText(); placeholder:SetShown(BM.State.query == "")
        if window.pages.pvp then
            for _, page in pairs(window.pages) do if page.rows then page.scroll:SetVerticalScroll(0) end end
            BM.Refresh()
        end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); BM.Close() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    button(searchBox, 198, 3, 24, 22, "x", function() search:SetText(""); search:ClearFocus() end)
    window.search = search
    local content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", 8, -43); content:SetSize(784, 278)
    window.pages.pvp = createPVP(content); window.pages.quests = createQuests(content)
    window.pages.gold = createGold(content); window.pages.gear = createGear(content)
    window.pages.settings = createSettings(content)
    window.footer = label(window, 8, 331, 430, 24, "", 10, C.muted)
    window.sync = button(window, 446, 331, 198, 24, "Sync now", function() BM.RequestSync(true); BM.Refresh() end)
    window.sync:SetScript("OnEnter", function(self)
        tooltip(self, "Request guild snapshots", { "Uses hidden addon messages; other members need this addon.", "Only each character can publish their own snapshot.", "Offline members keep their last received snapshot.", "Requests may wait up to 30 seconds for the send cooldown.", "The header shows sending progress and received snapshots.", "No replies can mean no online guildmates are using this addon." })
    end)
    window.sharing = button(window, 652, 331, 140, 24, "Pause sharing", function() BM.ToggleSharing(); BM.Refresh() end)
    window.sharing:SetScript("OnEnter", function(self)
        tooltip(self, "Guild data sharing", { "Shares gold, equipped items, tracked dungeon quests and PvP counters.", "Pausing stops sending and receiving; local tracking continues.", "Previously received copies remain on other guild members' clients." })
    end)
    window:SetScript("OnHide", function() search:ClearFocus(); GameTooltip:Hide() end)
    BM.ApplyScale(); BM.Refresh()
    return window
end
function BM.ResetPosition()
    BM.DB.position, BM.DB.scale = nil, nil
    BM.State.query, BM.State.partyOnly, BM.DB.partyOnly = "", false, false
    if window then window.search:SetText(""); BM.ApplyScale() end
end
function BM.CreateLauncher()
    local b = CreateFrame("Button", "BorjesMagasinMinimapButton", Minimap)
    b:SetSize(32, 32); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local texture = icon(b, 6, 6, 20, "Interface\\AddOns\\borjes-magasin\\Textures\\MinimapIcon")
    texture:SetTexCoord(0, 1, 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    local function position()
        local a = math.rad(BM.DB.minimapAngle or 220)
        local x, y = math.cos(a), math.sin(a)
        -- Follow the actual minimap edge, like the other addon launchers.
        local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
        if GetMinimapShape and GetMinimapShape() == "SQUARE" then
            local edge = math.max(math.abs(x), math.abs(y))
            x, y = x / edge, y / edge
        end
        b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
    end
    BM.PositionLauncher = position
    Minimap:HookScript("OnSizeChanged", position)
    b:SetScript("OnShow", position)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition(); local mx, my = Minimap:GetCenter(); local scale = Minimap:GetEffectiveScale()
            BM.DB.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx)); position()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function() BM.Toggle() end)
    b:SetScript("OnEnter", function(self) tooltip(self, "borjes-magasin", { "Click to open the guild ledger", "Drag to move this button", "Guild snapshots / " .. BM.SyncStatus() }) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    position(); BM.Launcher = b
    C_Timer.After(0, position)
end
