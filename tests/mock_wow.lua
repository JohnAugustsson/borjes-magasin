-- Strict, deliberately small WoW UI test double. This tests Lua interaction
-- paths; it does not emulate Blizzard templates or prove client compatibility.
local Mock = { objects = {}, timers = {} }
local methods = {}
local function object(kind, name, parent)
    local o = setmetatable({ kind = kind, name = name, parent = parent, children = {}, scripts = {}, events = {},
        shown = true, width = 0, height = 0, scale = 1, text = "", scroll = 0, alpha = 1 }, { __index = methods })
    if parent then table.insert(parent.children, o) end
    if name then _G[name] = o end
    Mock.objects[#Mock.objects + 1] = o
    return o
end
function methods:SetSize(w, h)
    assert(w >= 0 and h >= 0)
    self.width, self.height = w, h
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(point, a, b, c, d)
    if type(a) == "table" then self.anchor = { point, a, b or point, c or 0, d or 0 }
    elseif type(a) == "number" then self.anchor = { point, self.parent, point, a, b or 0 }
    else self.anchor = { point, self.parent, point, 0, 0 } end
end
function methods:GetPoint() return unpack(self.anchor) end
function methods:GetParent() return self.parent end
function methods:ClearAllPoints() self.anchor = nil end
function methods:SetAllPoints(relative) self.allPoints = relative or self.parent; self:SetSize(self.allPoints.width, self.allPoints.height) end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn)
    local old = self.scripts[event]
    self.scripts[event] = function(...) if old then old(...) end; fn(...) end
end
function methods:GetScript(event) return self.scripts[event] end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:Show() local changed = not self.shown; self.shown = true; if changed and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() local changed = self.shown; self.shown = false; if changed and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:CreateFontString(name, layer) local f = object("FontString", name, self); f.layer = layer; return f end
function methods:CreateTexture(name, layer) local t = object("Texture", name, self); t.layer = layer; return t end
function methods:SetFont(path, size) self.fontSize = size end
function methods:SetText(value) self.text = tostring(value or ""); if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
function methods:GetText() return self.text end
function methods:SetTextColor(...) self.color = { ... } end
function methods:SetBackdrop(backdrop) self.backdrop = backdrop end
function methods:SetBackdropColor(...) self.bg = { ... } end
function methods:SetBackdropBorderColor(...) self.border = { ... } end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetAlpha(alpha) self.alpha = alpha end
function methods:SetScale(scale) self.scale = scale end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.scale end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:GetFrameStrata() return rawget(self, "strata") or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM" end
function methods:GetFrameLevel() return rawget(self, "frameLevel") or 1 end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:ClearFocus() self.focused = false end
function methods:Click() if self.enabled ~= false and self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
function methods:SetFrameLevel(level) self.frameLevel = level end
function methods:SetScrollChild(child) self.scrollChild = child; child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0) end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll end
function methods:GetVerticalScrollRange() return math.max(0, self.scrollChild.height - self.height) end
function methods:SetStatusBarTexture(texture) self.texture = texture end
function methods:SetStatusBarColor(...) self.color = { ... } end
function methods:SetValue(value) assert(value >= 0 and value <= 1); self.value = value end
function methods:GetCenter() return 1800, 900 end
function methods:SetJustifyH(v) self.align = v end
function methods:SetJustifyV(v) self.alignV = v end
for _, name in ipairs({ "SetFontObject", "SetWordWrap", "SetMinMaxValues", "EnableMouse", "EnableMouseWheel",
    "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetHighlightTexture",
    "SetAutoFocus", "SetMaxLetters", "SetDesaturated" }) do methods[name] = function() end end

function CreateFrame(kind, name, parent) return object(kind, name, parent) end
UIParent = CreateFrame("Frame", "UIParent"); UIParent:SetSize(1920, 1080)
Minimap = CreateFrame("Frame", "Minimap", UIParent); Minimap:SetSize(140, 140); Minimap:SetPoint("TOPRIGHT", -30, -30)
UISpecialFrames, SlashCmdList = {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) Mock.message = message end }
C_Timer = { After = function(_, fn) Mock.timers[#Mock.timers + 1] = fn end }
GameTooltip = { SetOwner = function() end, SetText = function(_, text) Mock.tooltip = text end,
    AddLine = function() end, Show = function() end, Hide = function() end }
GetCursorPosition = function() return 1700, 900 end
InCombatLockdown = function() return Mock.combat or false end
function hooksecurefunc(target, key, hook)
    local original = assert(target[key], "Missing native method: " .. key)
    target[key] = function(...) local result = { original(...) }; hook(...); return unpack(result) end
end
function ShowUIPanel(frame) assert(not InCombatLockdown(), "Cannot open native panel in combat"); frame:Show() end
function HideUIPanel(frame) assert(not InCombatLockdown(), "Cannot close native panel in combat"); frame:Hide() end
function Mock.LoadGuildUI()
    if CommunitiesFrame then return CommunitiesFrame end
    local f = CreateFrame("Frame", "CommunitiesFrame", UIParent)
    f:Hide(); f:SetPoint("CENTER"); f:SetSize(814, 426)
    f:SetBackdrop({}); f:SetBackdropColor(.13, .12, .10, 1)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOPLEFT", 70, 0); title:SetSize(674, 23); title:SetFont("", 12)
    title:SetText("Guild & Communities"); title:SetTextColor(.9, .75, .45)
    f.NativeContent = CreateFrame("Frame", nil, f); f.NativeContent:SetAllPoints()
    f.Chat = CreateFrame("Frame", nil, f)
    f.Chat.ScrollBar = CreateFrame("Frame", nil, f.Chat)
    -- Forever's CommunitiesChatTemplate explicitly gives this HIGH strata.
    f.Chat.ScrollBar:SetFrameStrata("HIGH")
    f.Chat.ScrollBar.scrollPosition = 37
    f.ChatEditBox = CreateFrame("EditBox", nil, f)
    f.ChatEditBox:SetPoint("BOTTOMLEFT", 190, 4); f.ChatEditBox:SetSize(400, 30)
    f.CloseButton = CreateFrame("Button", nil, f)
    f.CloseButton:SetPoint("TOPRIGHT"); f.CloseButton:SetSize(24, 24)
    f.CloseButton:SetScript("OnClick", function() HideUIPanel(f) end)
    local names = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }
    for i, key in ipairs(names) do
        local mode = key
        local t = CreateFrame("CheckButton", nil, f); f[key] = t
        t:SetSize(32, 36); t:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -36 - (i - 1) * 56)
        t:SetBackdrop({}); t:SetBackdropColor(.2, .18, .13, 1)
        t:SetScript("OnClick", function() f:SetDisplayMode(mode) end)
    end
    f.mode = "RosterTab"; f.Chat:Hide()
    function f:UpdateCommunitiesTabs()
        for _, key in ipairs(names) do
            self[key]:SetShown(self:GetWidth() >= 600 and (key ~= "GuildBenefitsTab" or Mock.benefits) and (key ~= "GuildPreferredPlaySettingsTab" or Mock.preferred))
            self[key]:SetChecked(self.mode == key)
        end
    end
    function f:SetDisplayMode(mode)
        if self.mode == mode then return end -- Blizzard also returns early here.
        self.mode = mode; self.Chat:SetShown(mode == "ChatTab"); self:UpdateCommunitiesTabs()
    end
    function f:CloseActiveDialogs() self.dialogClosed = true end
    f:SetScript("OnShow", function(self) self:UpdateCommunitiesTabs() end)
    f.MaximizeMinimizeFrame = CreateFrame("Frame", nil, f)
    f.MaximizeMinimizeFrame.MaximizeButton = CreateFrame("Button", nil, f.MaximizeMinimizeFrame)
    f.MaximizeMinimizeFrame.MaximizeButton:SetScript("OnClick", function() f:SetSize(814, 426); f:UpdateCommunitiesTabs() end)
    f:UpdateCommunitiesTabs()
    Mock.Fire("ADDON_LOADED", "Blizzard_Communities")
    return f
end
C_AddOns = { LoadAddOn = function(name)
    assert(name == "Blizzard_Communities")
    if Mock.loadFails then return nil, "DISABLED" end
    Mock.LoadGuildUI(); return true
end }
-- Any accidental live data collection or communication is a hard test failure.
local function forbidden() error("UI prototype attempted live data or communication") end
C_ChatInfo = { SendAddonMessage = forbidden, RegisterAddonMessagePrefix = forbidden }
SendChatMessage, SendAddonMessage, GetMoney, GetInventoryItemLink, UnitGUID = forbidden, forbidden, forbidden, forbidden, forbidden
function Mock.Fire(event, ...)
    for _, o in ipairs(Mock.objects) do if o.events[event] then o.scripts.OnEvent(o, event, ...) end end
end
function Mock.IsAbove(a, b)
    local strata = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local x, y = strata[a:GetFrameStrata()], strata[b:GetFrameStrata()]
    return x > y or (x == y and a:GetFrameLevel() > b:GetFrameLevel())
end
function Mock.Click(o)
    assert(o and o.scripts.OnClick, "Missing click handler")
    if o.enabled ~= false then o.scripts.OnClick(o, "LeftButton") end
end
function Mock.FindButton(text)
    for _, o in ipairs(Mock.objects) do
        local l = rawget(o, "label")
        if o.kind == "Button" and l and l.text == text and o:IsVisible() then return o end
    end
    error("Button not found: " .. text)
end
local function encode(v)
    if type(v) == "nil" then return "null" end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    if type(v) == "string" then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"' end
    local t = {}
    if #v > 0 then for _, x in ipairs(v) do t[#t + 1] = encode(x) end; return '[' .. table.concat(t, ',') .. ']' end
    for key, x in pairs(v) do t[#t + 1] = encode(key) .. ':' .. encode(x) end
    return '{' .. table.concat(t, ',') .. '}'
end
local factors = { TOPLEFT = { 0, 0 }, TOP = { .5, 0 }, TOPRIGHT = { 1, 0 }, LEFT = { 0, .5 }, CENTER = { .5, .5 }, RIGHT = { 1, .5 }, BOTTOMLEFT = { 0, 1 }, BOTTOM = { .5, 1 }, BOTTOMRIGHT = { 1, 1 } }
local function rect(o)
    if not o then return 0, 0, 0, 0 end
    local all = rawget(o, "allPoints"); if all then return rect(all) end
    local anchor = rawget(o, "anchor")
    if not anchor then return 0, 0, o.width, o.height end
    local x, y, w, h = rect(anchor[2]); local a, b = factors[anchor[1]], factors[anchor[3]]
    local top = y + h * b[2] - o.height * a[2] - anchor[5]
    if o.parent and o.parent.kind == "ScrollFrame" then top = top - o.parent.scroll end
    return x + w * b[1] - o.width * a[1] + anchor[4], top, o.width, o.height
end
function Mock.Snapshot(root, path)
    local output = {}; local rx, ry = rect(root)
    local function walk(o, clip)
        if not o:IsVisible() then return end
        local x, y, w, h = rect(o)
        if o.kind == "ScrollFrame" then clip = { x - rx, y - ry, w, h } end
        output[#output + 1] = { kind = o.kind, x = x - rx, y = y - ry, w = w, h = h,
            text = o.text, bg = rawget(o, "bg"), border = rawget(o, "border"), font = rawget(o, "fontSize"),
            align = rawget(o, "align"), color = rawget(o, "color"), texture = rawget(o, "texture"),
            alpha = o.alpha, value = o.kind == "StatusBar" and rawget(o, "value") or nil, clip = clip }
        for _, child in ipairs(o.children) do walk(child, clip) end
    end
    walk(root)
    local f = assert(io.open(path, "w")); f:write(encode(output)); f:close()
end
return Mock
