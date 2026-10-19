---------------------------------------------------------------------
-- DecorSync 1.5 - the window, the minimap button
-- Skinned to match Regional Edge: flat dark navy panels, 1px borders,
-- stat cards, underlined tab, lime row bars, slim scrollbar.
---------------------------------------------------------------------
local ADDON_NAME, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT

-- Same palette as Regional Edge's "Midnight" theme
local K = {
    window   = { 0.047, 0.055, 0.075, 0.98 },
    card     = { 0.075, 0.087, 0.118, 1 },
    cardHi   = { 0.105, 0.120, 0.158, 1 },
    input    = { 0.035, 0.040, 0.055, 1 },
    border   = { 0.140, 0.160, 0.210, 1 },
    accent   = { 0.31, 0.64, 1.00, 1 },
    accentBg = { 0.16, 0.38, 0.72, 1 },
    accentHi = { 0.21, 0.47, 0.86, 1 },
    text     = { 0.92, 0.93, 0.95, 1 },
    dim      = { 0.52, 0.56, 0.63, 1 },
    faint    = { 0.36, 0.40, 0.47, 1 },
    lime     = { 0.67, 0.85, 0.32, 1 },
    amber    = { 1.00, 0.72, 0.26, 1 },
}

local WIDTH, HEIGHT = 620, 704
local ROWS, ROW_H = 10, 26
local f, statusFS, partnerBox, targetFS, onlyMeCB, autoCB, guildCB, stat1, stat2, listFrame, sb, emptyFS
local craftTab, stockTab, h2, h3, searchBox
local mode, needed, stock = "craft", {}, {}
local rows, list, listState = {}, {}, "nolist"
local offset, updating = 0, false

---------------------------------------------------------------------
-- Widget helpers (same shapes as Regional Edge's Box / Text / Button)
---------------------------------------------------------------------
local function SetFont(fs, size)
    if not fs:SetFont(FONT, size, "") then fs:SetFont(STANDARD_TEXT_FONT, size, "") end
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetFont(fs, size)
    fs:SetTextColor(unpack(color or K.text))
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Box(parent, bg, border, frameType, name)
    local b = CreateFrame(frameType or "Frame", name, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    b:SetBackdropColor(unpack(bg))
    b:SetBackdropBorderColor(unpack(border))
    return b
end

-- tooltip in the addon's own style
local Tip = {}
local tipFrame
local TIP_MAX_W = 280
function Tip.Show(owner, anchor, title, body)
    if not tipFrame then
        local t = Box(UIParent, K.window, K.border)
        t:SetFrameStrata("TOOLTIP")
        t:SetClampedToScreen(true)
        t:EnableMouse(false)
        t.title = Text(t, 13, K.accent)
        t.title:SetPoint("TOPLEFT", 11, -9)
        t.title:SetJustifyV("TOP")
        t.body = Text(t, 12, K.text)
        t.body:SetJustifyV("TOP")
        t:SetScript("OnUpdate", function(self)
            local o = self.owner
            if not (o and o:IsVisible() and o:IsMouseOver()) then self:Hide() end
        end)
        t:Hide()
        tipFrame = t
    end
    local t = tipFrame
    t.owner = owner
    t.title:SetTextColor(unpack(body and K.accent or K.text))
    t.title:SetWidth(TIP_MAX_W)
    t.title:SetText(title or "")
    t.body:SetWidth(TIP_MAX_W)
    t.body:SetText(body or "")
    local w = math.max(t.title:GetStringWidth(), body and math.min(TIP_MAX_W, t.body:GetStringWidth()) or 0)
    w = math.ceil(w) + 1
    t.title:SetWidth(w)
    t.body:SetWidth(w)
    t.body:ClearAllPoints()
    t.body:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -5)
    local h = t.title:GetStringHeight() + 18
    if body then h = h + 5 + t.body:GetStringHeight() end
    t:SetSize(w + 22, math.ceil(h))
    t:ClearAllPoints()
    if anchor == "ANCHOR_BOTTOM" then
        t:SetPoint("TOP", owner, "BOTTOM", 0, -6)
    elseif anchor == "ANCHOR_RIGHT" then
        t:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 4, 0)
    else
        t:SetPoint("BOTTOM", owner, "TOP", 0, 6)
    end
    t:Show()
end
function Tip.Hide() if tipFrame then tipFrame:Hide() end end

local function Tooltip(widget, title, body)
    widget:HookScript("OnEnter", function(self) Tip.Show(self, "ANCHOR_TOP", title, body) end)
    widget:HookScript("OnLeave", Tip.Hide)
end

local function Button(parent, label, w, h, primary, onclick)
    local base = primary and K.accentBg or K.card
    local hi = primary and K.accentHi or K.cardHi
    local b = Box(parent, base, primary and K.accent or K.border, "Button")
    b:SetSize(w, h)
    b.text = Text(b, 12, K.text, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(hi)) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(base)) end)
    b:SetScript("OnClick", onclick)
    return b
end

local function CheckBox(parent, label, onclick)
    local b = Box(parent, K.input, K.border, "Button")
    b:SetSize(16, 16)
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetColorTexture(unpack(K.accent))
    b.mark:SetPoint("TOPLEFT", 3, -3)
    b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    b.mark:Hide()
    b.label = Text(b, 11, K.dim)
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label:SetText(label)
    function b:SetChecked(on) self.checked = on and true or false; self.mark:SetShown(self.checked) end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        onclick(self.checked)
    end)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(K.text)) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(K.dim)) end)
    return b
end

local function StatCard(parent, label)
    local c = Box(parent, K.card, K.border)
    c:SetHeight(64)
    c.label = Text(c, 10, K.dim)
    c.label:SetPoint("TOPLEFT", 12, -9)
    c.label:SetText(label)
    c.value = Text(c, 22, K.text)
    c.value:SetPoint("TOPLEFT", 12, -21)
    c.sub = Text(c, 11, K.dim)
    c.sub:SetPoint("BOTTOMLEFT", 12, 8)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.sub:SetWordWrap(false)
    return c
end

---------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------
-- stock list is sorted by profession already; put a heading row above each group
local function Grouped(items)
    local counts = {}
    for _, e in ipairs(items) do
        local p = e.prof or "Other (no recorded crafter)"
        counts[p] = (counts[p] or 0) + 1
    end
    local res, last = {}, nil
    for _, e in ipairs(items) do
        local p = e.prof or "Other (no recorded crafter)"
        if p ~= last then res[#res + 1] = { header = p, count = counts[p] }; last = p end
        res[#res + 1] = e
    end
    return res
end

local function DrawRows()
    for i = 1, ROWS do
        local r, e = rows[i], list[offset + i]
        if e and e.header then
            r.entry = e
            r.name:SetTextColor(unpack(K.accent))
            r.name:SetText(("%s  (%d)"):format(e.header, e.count))
            r.need:SetText("")
            r.who:SetText("")
            r.bar:SetColorTexture(unpack(K.accent))
            r:Show()
        elseif e then
            r.entry = e
            r.name:SetTextColor(unpack(K.text))
            r.name:SetText(e.name)
            if mode == "craft" then
                r.need:SetTextColor(unpack(K.amber))
                r.need:SetText("x" .. e.need)
                r.who:SetText(e.crafters)
                r.bar:SetColorTexture(unpack(K.lime))
            else
                r.need:SetTextColor(unpack(e.have >= ns.DB.target and K.lime or K.amber))
                r.need:SetText(tostring(e.have))
                r.who:SetText(e.whereText ~= "" and e.whereText or "location unknown")
                r.bar:SetColorTexture(unpack(K.accent))
            end
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
end

local function RefreshStatus()
    if not f then return end
    local text = ns.msg or ""
    local prog = ns.Progress()
    if prog then text = text .. "   |cffffb842" .. prog .. "|r" end
    statusFS:SetText(text)

    local nrec, rec = ns.Info()
    stat1.value:SetText(tostring(#needed))
    if listState == "ok" then
        stat1.sub:SetText(("%d craftable decor recorded"):format(nrec))
    elseif listState == "norecipes" then
        stat1.sub:SetText("Open each profession window on each crafter")
    else
        stat1.sub:SetText(("%d craftable decor recorded"):format(nrec))
    end
    if rec then
        stat2.value:SetText(tostring(rec.count or 0))
        stat2.sub:SetText(("from %s, %s"):format(tostring(rec.from), ns.timeAgo(rec.at)))
    else
        stat2.value:SetText("-")
        stat2.sub:SetText("No decor list received yet")
    end
end

local function Refresh()
    if not f or not f:IsShown() then return end
    local DB = ns.DB
    local l, state = ns.GetNeeded()
    needed, listState = l or {}, state
    stock = ns.GetStock()
    list = (mode == "craft") and needed or Grouped(stock)

    craftTab.text:SetTextColor(unpack(mode == "craft" and K.text or K.dim))
    craftTab.underline:SetShown(mode == "craft")
    stockTab.text:SetTextColor(unpack(mode == "stock" and K.text or K.dim))
    stockTab.underline:SetShown(mode == "stock")
    craftTab.text:SetText(("Decor to craft  %d"):format(#needed))
    stockTab.text:SetText(("In stock  %d"):format(#stock))
    h2:SetText(mode == "craft" and "NEED" or "OWNED")
    h3:SetText(mode == "craft" and "WHO CAN CRAFT IT" or "WHERE IT IS")

    local maxOff = math.max(0, #list - ROWS)
    if offset > maxOff then offset = maxOff end
    updating = true
    sb:SetMinMaxValues(0, maxOff)
    sb:SetValue(offset)
    updating = false
    sb:SetShown(maxOff > 0)

    DrawRows()

    if state == "nolist" then
        emptyFS:SetText("No decor list yet.\nPress 'Get decor list' (or 'Send my decor' from the account that owns it).")
    elseif #list > 0 then
        emptyFS:SetText("")
    elseif ns.search ~= "" then
        emptyFS:SetText("Nothing matches that search.")
    elseif mode == "stock" then
        emptyFS:SetText("No sellable decor found yet.")
    elseif state == "norecipes" then
        emptyFS:SetText("No crafting recipes recorded yet.\nLog into each crafter and open each profession window once.")
    else
        emptyFS:SetText("Nothing needed. You're stocked!")
    end

    targetFS:SetText(tostring(DB.target))
    onlyMeCB:SetChecked(DB.onlyMe)
    autoCB:SetChecked(DB.autoRequest)
    guildCB:SetChecked(DB.includeGuild)
    if not partnerBox:HasFocus() then partnerBox:SetText(DB.partner or "") end
    RefreshStatus()
end

---------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------
local mb

function ns.UpdateMinimap()
    if not mb then return end
    local m = ns.DB.minimap
    if m.hide then mb:Hide() return end
    local rad = math.rad(m.angle or 215)
    mb:ClearAllPoints()
    mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * 80, math.sin(rad) * 80)
    mb:Show()
end

local function BuildMinimapButton()
    mb = CreateFrame("Button", "DecorSyncMinimapButton", Minimap)
    mb:SetSize(31, 31)
    mb:SetFrameStrata("MEDIUM")
    mb:SetFrameLevel(8)
    mb:RegisterForClicks("LeftButtonUp")
    mb:RegisterForDrag("LeftButton")
    mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = mb:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)

    local border = mb:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    mb:SetScript("OnClick", function() ns.Toggle() end)
    mb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            ns.DB.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            ns.UpdateMinimap()
        end)
    end)
    mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Tooltip(mb, "DecorSync", "Click to open. Drag to move.")
    ns.UpdateMinimap()
end

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function ns.Toggle()
    if not f then return end
    if f:IsShown() then f:Hide() else f:Show() end
end

function ns.InitUI()
    local DB = ns.DB

    f = Box(UIParent, K.window, K.border, "Frame", "DecorSyncFrame")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "DecorSyncFrame")

    -- title bar -------------------------------------------------------
    local title = Text(f, 20, K.text)
    title:SetPoint("TOPLEFT", 14, -8)
    title:SetText("DecorSync")

    local close = CreateFrame("Button", nil, f)
    close:SetSize(34, 34)
    close:SetPoint("TOPRIGHT", -2, -1)
    close.text = Text(close, 20, K.dim, "CENTER")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("×")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(K.text)) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(K.dim)) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local tline = f:CreateTexture(nil, "ARTWORK")
    tline:SetColorTexture(unpack(K.border))
    tline:SetHeight(1)
    tline:SetPoint("TOPLEFT", 1, -37)
    tline:SetPoint("TOPRIGHT", -1, -37)

    -- connection card ---------------------------------------------------
    local card = Box(f, K.card, K.border)
    card:SetPoint("TOPLEFT", 14, -50)
    card:SetPoint("TOPRIGHT", -14, -50)
    card:SetHeight(122)

    local cl = Text(card, 10, K.dim)
    cl:SetPoint("TOPLEFT", 12, -10)
    cl:SetText("YOUR OTHER ACCOUNT'S CHARACTER  (NAME-REALM, E.G. ALICE-FROSTMOURNE)")

    local pbox = Box(card, K.input, K.border)
    pbox:SetSize(330, 26)
    pbox:SetPoint("TOPLEFT", 12, -26)
    partnerBox = CreateFrame("EditBox", nil, pbox)
    SetFont(partnerBox, 13)
    partnerBox:SetPoint("TOPLEFT", 8, -1)
    partnerBox:SetPoint("BOTTOMRIGHT", -8, 1)
    partnerBox:SetAutoFocus(false)
    partnerBox:SetMaxLetters(64)
    partnerBox:SetTextColor(unpack(K.text))
    local function DoConnect()
        if ns.SetPartner(partnerBox:GetText()) then ns.Ping() end
        partnerBox:ClearFocus()
    end
    partnerBox:SetScript("OnEnterPressed", DoConnect)
    partnerBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    partnerBox:SetScript("OnEditFocusGained", function() pbox:SetBackdropBorderColor(unpack(K.accent)) end)
    partnerBox:SetScript("OnEditFocusLost", function() pbox:SetBackdropBorderColor(unpack(K.border)) end)

    local connect = Button(card, "Connect", 90, 26, true, DoConnect)
    connect:SetPoint("LEFT", pbox, "RIGHT", 8, 0)
    Tooltip(connect, "Connect", "Saves the name and sends a test message. The other account needs to be logged in with DecorSync installed. It will ask you to confirm the first time.")

    local get = Button(card, "Get decor list", 150, 26, false, function() ns.Request() end)
    get:SetPoint("TOPLEFT", 12, -62)
    Tooltip(get, "Get decor list", "Use this on the account with your CRAFTERS. Asks the other account to send what decor it owns.")
    local send = Button(card, "Send my decor", 150, 26, false, function() ns.Send() end)
    send:SetPoint("LEFT", get, "RIGHT", 8, 0)
    Tooltip(send, "Send my decor", "Use this on the account that OWNS the decor. Sends your decor list to the other account.")

    statusFS = Text(card, 11, K.dim)
    statusFS:SetPoint("TOPLEFT", 12, -96)
    statusFS:SetSize(WIDTH - 28 - 24, 20)
    statusFS:SetJustifyV("TOP")

    -- stat cards ---------------------------------------------------------
    stat1 = StatCard(f, "DECOR TO CRAFT")
    stat1:SetPoint("TOPLEFT", 14, -182)
    stat1:SetWidth((WIDTH - 28 - 8) / 2)
    stat2 = StatCard(f, "SELLABLE STOCK (OTHER ACCOUNT)")
    stat2:SetPoint("TOPRIGHT", -14, -182)
    stat2:SetWidth((WIDTH - 28 - 8) / 2)

    -- tabs + controls ----------------------------------------------------
    local function MakeTab(x, w, key)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(w, 26)
        t:SetPoint("TOPLEFT", x, -258)
        t.text = Text(t, 12, K.dim, "CENTER")
        t.text:SetPoint("CENTER")
        t.underline = t:CreateTexture(nil, "OVERLAY")
        t.underline:SetColorTexture(unpack(K.accent))
        t.underline:SetHeight(2)
        t.underline:SetPoint("BOTTOMLEFT")
        t.underline:SetPoint("BOTTOMRIGHT")
        t:SetScript("OnClick", function()
            mode, offset = key, 0
            Refresh()
        end)
        return t
    end
    craftTab = MakeTab(14, 150, "craft")
    stockTab = MakeTab(164, 130, "stock")
    local tabLine = f:CreateTexture(nil, "ARTWORK")
    tabLine:SetColorTexture(unpack(K.border))
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", 14, -284)
    tabLine:SetPoint("TOPRIGHT", -14, -284)

    -- filter row: only-me checkbox on the left, search on the right
    onlyMeCB = CheckBox(f, "Only what this character can craft", function(v)
        DB.onlyMe = v
        Refresh()
    end)
    onlyMeCB:SetPoint("TOPLEFT", 14, -296)

    local sbox = Box(f, K.input, K.border)
    sbox:SetSize(190, 22)
    sbox:SetPoint("TOPRIGHT", -14, -293)
    searchBox = CreateFrame("EditBox", nil, sbox)
    SetFont(searchBox, 12)
    searchBox:SetPoint("TOPLEFT", 8, -1)
    searchBox:SetPoint("BOTTOMRIGHT", -8, 1)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    searchBox:SetTextColor(unpack(K.text))
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); ns.search = ""; self:ClearFocus(); Refresh() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEditFocusGained", function() sbox:SetBackdropBorderColor(unpack(K.accent)) end)
    searchBox:SetScript("OnEditFocusLost", function() sbox:SetBackdropBorderColor(unpack(K.border)) end)
    searchBox:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        ns.search = (self:GetText() or ""):lower()
        offset = 0
        Refresh()
    end)
    local sl = Text(sbox, 11, K.faint)
    sl:SetPoint("LEFT", 8, 0)
    sl:SetText("Search...")
    searchBox:HookScript("OnTextChanged", function(self) sl:SetShown(self:GetText() == "") end)

    local plus = Button(f, "+", 24, 22, false, function()
        DB.target = math.min(99, DB.target + 1)
        Refresh()
    end)
    plus:SetPoint("TOPRIGHT", -14, -260)
    Tooltip(plus, "Want", "How many of each decor you want in stock to sell.")
    targetFS = Text(f, 13, K.text, "CENTER")
    targetFS:SetWidth(30)
    targetFS:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = Button(f, "-", 24, 22, false, function()
        DB.target = math.max(1, DB.target - 1)
        Refresh()
    end)
    minus:SetPoint("RIGHT", targetFS, "LEFT", -2, 0)
    local wl = Text(f, 10, K.dim, "RIGHT")
    wl:SetPoint("RIGHT", minus, "LEFT", -8, 0)
    wl:SetText("WANT")

    -- column headers ------------------------------------------------------
    local h1 = Text(f, 10, K.dim); h1:SetPoint("TOPLEFT", 26, -324); h1:SetText("DECOR")
    h2 = Text(f, 10, K.dim); h2:SetPoint("TOPLEFT", 252, -324); h2:SetText("NEED")
    h3 = Text(f, 10, K.dim); h3:SetPoint("TOPLEFT", 304, -324); h3:SetText("WHO CAN CRAFT IT")

    -- list ----------------------------------------------------------------
    listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT", 14, -340)
    listFrame:SetPoint("TOPRIGHT", -14, -340)
    listFrame:SetHeight(ROWS * ROW_H)
    listFrame:EnableMouseWheel(true)

    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, listFrame)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -10, -(i - 1) * ROW_H)
        r.stripe = r:CreateTexture(nil, "BACKGROUND")
        r.stripe:SetAllPoints()
        r.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.035 or 0)
        r.hl = r:CreateTexture(nil, "BORDER")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(K.accent[1], K.accent[2], K.accent[3], 0.13)
        r.hl:Hide()
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetWidth(2)
        r.bar:SetPoint("TOPLEFT")
        r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetColorTexture(unpack(K.lime))
        r.name = Text(r, 12, K.text)
        r.name:SetPoint("LEFT", r, "LEFT", 12, 0)
        r.name:SetWidth(228)
        r.name:SetWordWrap(false)
        r.need = Text(r, 12, K.amber)
        r.need:SetPoint("LEFT", r, "LEFT", 238, 0)
        r.need:SetWidth(40)
        r.who = Text(r, 11, K.dim)
        r.who:SetPoint("LEFT", r, "LEFT", 290, 0)
        r.who:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.who:SetWordWrap(false)
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            local e = self.entry
            if not e or e.header then return end
            if mode == "craft" then
                Tip.Show(self, "ANCHOR_RIGHT", e.name,
                    ("Owned: %d   Want: %d   Need: %d more\n%s"):format(e.have or 0, DB.target, e.need, e.crafters))
            else
                local lines = { ("Owned: %d   Want: %d%s"):format(e.have, DB.target, e.have < DB.target and ("   (" .. (DB.target - e.have) .. " short)") or "") }
                if e.where and #e.where > 0 then
                    for _, l in ipairs(e.where) do lines[#lines + 1] = ("%s: %d"):format(l[1], l[2]) end
                else
                    lines[#lines + 1] = "Location unknown. Press 'Get decor list' again with both accounts on DecorSync 1.4."
                end
                if e.crafters ~= "" then lines[#lines + 1] = "Can craft: " .. e.crafters end
                Tip.Show(self, "ANCHOR_RIGHT", e.name, table.concat(lines, "\n"))
            end
        end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); Tip.Hide() end)
        rows[i] = r
    end

    emptyFS = Text(listFrame, 12, K.faint, "CENTER")
    emptyFS:SetPoint("CENTER", listFrame, "CENTER", -5, 0)
    emptyFS:SetWidth(460)

    -- slim scrollbar, same as Regional Edge
    sb = CreateFrame("Slider", nil, listFrame)
    sb:SetPoint("TOPRIGHT")
    sb:SetPoint("BOTTOMRIGHT")
    sb:SetWidth(6)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(1)
    sb:SetObeyStepOnDrag(true)
    local sbBg = sb:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(1, 1, 1, 0.04)
    sb:SetThumbTexture(FLAT)
    local th = sb:GetThumbTexture()
    th:SetSize(6, 30)
    th:SetVertexColor(0.40, 0.45, 0.54, 1)
    sb:SetScript("OnValueChanged", function(self, v)
        if updating then return end
        offset = math.floor(v + 0.5)
        DrawRows()
    end)
    listFrame:SetScript("OnMouseWheel", function(_, delta) sb:SetValue(sb:GetValue() - delta * 3) end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) sb:SetValue(sb:GetValue() - delta * 3) end)

    -- footer ----------------------------------------------------------------
    local fline = f:CreateTexture(nil, "ARTWORK")
    fline:SetColorTexture(unpack(K.border))
    fline:SetHeight(1)
    fline:SetPoint("BOTTOMLEFT", 14, 94)
    fline:SetPoint("BOTTOMRIGHT", -14, 94)

    -- settings section ------------------------------------------------------
    local setHead = Text(f, 10, K.dim)
    setHead:SetPoint("BOTTOMLEFT", 14, 76)
    setHead:SetText("SETTINGS")

    guildCB = CheckBox(f, "Include guild banks in my stock", function(v)
        ns.SetIncludeGuild(v)
    end)
    guildCB:SetPoint("BOTTOMLEFT", 14, 50)
    Tooltip(guildCB, "Include guild banks",
        "Counts decor held in guild bank tabs you can view. Off by default.\nOpen each guild bank once so it is remembered (or use TradeSkillMaster). Applies on the account that sends the list - press 'Send my decor' again after changing it.")

    autoCB = CheckBox(f, "Ask for a fresh list when I log in", function(v) DB.autoRequest = v end)
    autoCB:SetPoint("BOTTOMLEFT", 14, 24)
    local scan = Button(f, "Scan profession window", 170, 24, false, function() ns.ScanRecipes(false) end)
    scan:SetPoint("BOTTOMRIGHT", -14, 20)
    local csBtn = Button(f, "Import to CraftSim queue", 170, 24, false, function() ns.ImportToCraftSim() end)
    csBtn:SetPoint("BOTTOMRIGHT", -14, 52)
    Tooltip(csBtn, "Import to CraftSim queue", "Adds every decor this character can craft and is short of (Want minus Owned) to CraftSim's Craft Queue. Needs CraftSim, and recipes recorded since this version (open each profession window once).")
    Tooltip(scan, "Scan profession window", "Recipes are recorded automatically when you open a profession. Use this if one was missed.")

    f:SetScript("OnShow", Refresh)
    local acc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc > 0.4 then
            acc = 0
            RefreshStatus()
        end
    end)

    ns.OnChange = function()
        if f:IsShown() then Refresh() end
    end

    BuildMinimapButton()
end

---------------------------------------------------------------------
-- Addon compartment (the little menu next to the minimap)
---------------------------------------------------------------------
function DecorSync_OnAddonCompartmentClick()
    ns.Toggle()
end
function DecorSync_OnAddonCompartmentEnter(addonName, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("DecorSync")
    GameTooltip:AddLine("Click to open", 1, 1, 1)
    GameTooltip:Show()
end
function DecorSync_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
