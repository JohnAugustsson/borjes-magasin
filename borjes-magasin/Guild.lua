local _, BM = ...
local host, tab
local nativeTabs = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }
local opening = false
local coveredScrollBar, originalScrollBarStrata

local function coverChatScrollBar()
    if coveredScrollBar then return end
    local bar = host.Chat and host.Chat.ScrollBar
    if not bar then return end
    -- The native chat scrollbar explicitly uses HIGH strata. Frame levels
    -- alone cannot cover it with our panel in the guild window's strata.
    coveredScrollBar, originalScrollBarStrata = bar, bar:GetFrameStrata()
    bar:SetFrameStrata(BM.Window:GetFrameStrata())
end

local function restoreChatScrollBar()
    if not coveredScrollBar then return end
    coveredScrollBar:SetFrameStrata(originalScrollBarStrata)
    coveredScrollBar, originalScrollBarStrata = nil, nil
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffe8ba6eborjes-magasin:|r " .. message)
end
local function updateTab()
    if not host then return end
    local last
    for _, key in ipairs(nativeTabs) do
        local native = host[key]
        if native and native:IsShown() then
            last = native
            if BM.GuildActive then native:SetChecked(false) end
        end
    end
    tab:ClearAllPoints()
    if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -20)
    else tab:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, -36) end
    tab:SetShown(host:GetWidth() >= 600)
    tab:SetChecked(BM.GuildActive or false)
    if BM.GuildActive then tab:SetBackdropBorderColor(.91, .73, .43, 1)
    else tab:SetBackdropBorderColor(.35, .38, .43, 1) end
end
local function deactivate()
    BM.GuildActive = false
    restoreChatScrollBar()
    if BM.Window then BM.Window:Hide() end
    if tab then tab:SetChecked(false); updateTab() end
end
function BM.AttachGuildUI()
    if host then return true end
    if not BM.DB or not CommunitiesFrame or InCombatLockdown() then return false end
    host = CommunitiesFrame
    BM.GuildHost = host
    BM.CreateGuildPanel(host)
    tab = CreateFrame("CheckButton", "BorjesMagasinGuildTab", host, "BackdropTemplate")
    BM.GuildTab = tab
    tab:SetSize(32, 36); tab:SetFrameLevel(host:GetFrameLevel() + 510)
    tab:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    tab:SetBackdropColor(.08, .09, .11, 1)
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28); icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\borjes-magasin\\Textures\\MinimapIcon")
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    tab:SetScript("OnClick", function() BM.Open() end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("borjes-magasin", .91, .73, .43)
        GameTooltip:AddLine("PvP, dungeon quests, gold and gear", .9, .9, .9)
        GameTooltip:AddLine("Hidden guild data sharing", .7, .7, .7)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Observe native navigation without replacing Blizzard methods or modes.
    hooksecurefunc(host, "SetDisplayMode", function()
        if BM.GuildActive and not opening then
            deactivate()
            host:UpdateCommunitiesTabs()
        end
    end)
    hooksecurefunc(host, "UpdateCommunitiesTabs", updateTab)
    host:HookScript("OnHide", deactivate)
    host:HookScript("OnSizeChanged", function()
        if host:GetWidth() < 600 then deactivate() end
        BM.ApplyScale(); updateTab()
    end)
    updateTab()
    return true
end
function BM.Open()
    if InCombatLockdown() then
        if not BM.PendingOpen then say("The guild ledger will open when combat ends.") end
        BM.PendingOpen = true
        return
    end
    BM.PendingOpen = nil
    if not CommunitiesFrame then
        local loaded, reason = C_AddOns.LoadAddOn("Blizzard_Communities")
        if not loaded then say("Could not load the guild window: " .. tostring(reason)); return end
    end
    if not BM.AttachGuildUI() then say("The guild window is not available yet."); return end
    opening = true
    if not host:IsShown() then ShowUIPanel(host) end
    if not host:IsShown() then opening = false; return end
    if host:GetWidth() < 600 and host.MaximizeMinimizeFrame then
        host.MaximizeMinimizeFrame.MaximizeButton:Click()
    end
    if host:GetWidth() < 600 then
        opening = false; say("Expand the guild window to open the ledger."); return
    end
    host:CloseActiveDialogs()
    if host.ChatEditBox then host.ChatEditBox:ClearFocus() end
    opening = false
    BM.GuildActive = true
    coverChatScrollBar()
    BM.MarkDirty()
    BM.ApplyScale(); BM.Window:Show(); BM.Refresh(); updateTab()
end
function BM.Close()
    BM.PendingOpen = nil
    deactivate()
    if host and host:IsShown() then
        if InCombatLockdown() then host:UpdateCommunitiesTabs()
        else HideUIPanel(host) end
    end
end
function BM.Toggle()
    if BM.PendingOpen then BM.PendingOpen = nil; return end
    if BM.GuildActive and host and host:IsShown() then BM.Close() else BM.Open() end
end
