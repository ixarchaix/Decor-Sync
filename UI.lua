---------------------------------------------------------------------
-- DecorSync - the window, the minimap button
-- Skinned to match Regional Edge: flat dark navy panels, 1px borders,
-- stat cards, underlined tabs, lime row bars, slim scrollbar.
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

local WIDTH, HEIGHT = 620, 590
local ROWS, ROW_H = 11, 26
local f                          -- the main window
local W = {}                     -- every other widget, so nothing runs into Lua's upvalue limit
local mode, needed, stock, tracked = "craft", {}, {}, {}
local trackedChars, trackedTotal = 0, 0
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

local function StatCard(parent, label, h)
    local c = Box(parent, K.card, K.border)
    c:SetHeight(h or 64)
    c.label = Text(c, 10, K.dim)
    c.label:SetPoint("TOPLEFT", 12, -9)
    c.label:SetText(label)
    c.value = Text(c, 22, K.text)
    c.value:SetPoint("TOPLEFT", 12, -27)
    c.sub = Text(c, 11, K.dim)
    c.sub:SetPoint("BOTTOMLEFT", 12, 8)
    c.sub:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.sub:SetWordWrap(false)
    return c
end

-- one half of the Crafter | Seller switch
local function Segment(parent, label, w, onclick)
    local b = Box(parent, K.card, K.border, "Button")
    b:SetSize(w, 24)
    b.text = Text(b, 12, K.dim, "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    function b:SetActive(on)
        self.active = on and true or false
        self:SetBackdropColor(unpack(self.active and K.accentBg or K.card))
        self:SetBackdropBorderColor(unpack(self.active and K.accent or K.border))
        self.text:SetTextColor(unpack(self.active and K.text or K.dim))
    end
    b:SetScript("OnEnter", function(self) if not self.active then self:SetBackdropColor(unpack(K.cardHi)) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    b:SetScript("OnClick", onclick)
    return b
end

local function ShowAll(group, on)
    for _, w in ipairs(group) do w:SetShown(on) end
end

---------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------
-- lists arrive sorted by expansion; put a collapsible heading row above each group.
-- Collapsed groups are remembered. While searching, every group stays open so
-- matches are never hidden.
local NO_EXP = "Other (expansion not recorded)"
local function Grouped(items, which)
    local counts, lumNeed = {}, {}
    for _, e in ipairs(items) do
        local p = e.exp or NO_EXP
        counts[p] = (counts[p] or 0) + 1
        if which == "craft" and e.lumber then
            local g = lumNeed[p]
            if not g then g = {}; lumNeed[p] = g end
            for n, q in pairs(e.lumber) do g[n] = (g[n] or 0) + q end
        end
    end
    local _, _, owned = ns.GetLumber()
    local function LumberText(p)
        local g = lumNeed[p]
        if not g then return nil end
        local names = {}
        for n, q in pairs(g) do if q > 0 then names[#names + 1] = n end end
        table.sort(names)
        local parts = {}
        for _, n in ipairs(names) do
            local have, need = owned[n] or 0, g[n]
            parts[#parts + 1] = ("|cff%s%d/%d|r %s"):format(have < need and "ff5555" or "aad951", have, need, n)
        end
        return #parts > 0 and table.concat(parts, "   ") or nil
    end
    local DB = ns.DB
    local res, last, hidden = {}, nil, false
    for _, e in ipairs(items) do
        local p = e.exp or NO_EXP
        if p ~= last then
            local key = which .. ":" .. p
            local closed = DB.collapsed[key] and ns.search == ""
            res[#res + 1] = { header = p, count = counts[p], key = key, closed = closed, lumberText = LumberText(p) }
            last, hidden = p, closed
        end
        if not hidden then res[#res + 1] = e end
    end
    return res
end

-- Seller view: what "Send my decor" would send, per character, with the
-- warband bank and guild banks. Comes from Core, so TradeSkillMaster's counts
-- are included; the saved character list adds characters with nothing yet.
local SHOWN = { "bags", "bank", "mail", "auction house" }
local SHOWN_NAME = { ["auction house"] = "auctions" }
local srcLocs, srcAt = nil, 0

local function ShortOf(key)
    return key:match("^(.-) %- ") or key:match("^([^-]+)") or key
end

local function Tracked()
    local DB = ns.DB
    if not srcLocs or GetTime() - srcAt > 5 then      -- reading TSM isn't free
        local ok, res = pcall(ns.SourceLocs)
        srcLocs, srcAt = (ok and res) or {}, GetTime()
    end

    local groups, order, updated = {}, {}, {}
    local function G(who)
        local g = groups[who]
        if not g then g = { name = who, secs = {}, total = 0 }; groups[who] = g; order[#order + 1] = g end
        return g
    end
    for key, inv in pairs(DB.inv or {}) do
        local who = ShortOf(key)
        G(who)
        if inv.at and (not updated[who] or inv.at > updated[who]) then updated[who] = inv.at end
    end

    local warband, guilds = nil, {}
    for _, list in pairs(srcLocs) do
        for _, e in ipairs(list) do
            local label, c = e[1], e[2]
            if label == "warband bank" then
                warband = (warband or 0) + c
            elseif label:find("^guild bank %(") then
                guilds[label] = (guilds[label] or 0) + c
            else
                local who, sect = label:match("^(.*) %((.-)%)$")
                if who then
                    local g = G(who)
                    g.secs[sect] = (g.secs[sect] or 0) + c
                    g.total = g.total + c
                end
            end
        end
    end

    table.sort(order, function(a, b) return a.name < b.name end)
    local res, total = {}, 0
    for _, g in ipairs(order) do
        local parts, lines, shown = {}, {}, {}
        for _, sname in ipairs(SHOWN) do
            shown[sname] = true
            local line = ("%s %d"):format(SHOWN_NAME[sname] or sname, g.secs[sname] or 0)
            parts[#parts + 1] = line
            lines[#lines + 1] = line
        end
        local extra = {}
        for sname, c in pairs(g.secs) do
            if not shown[sname] and c > 0 then extra[#extra + 1] = ("%s %d"):format(sname, c) end
        end
        table.sort(extra)
        for _, line in ipairs(extra) do parts[#parts + 1] = line; lines[#lines + 1] = line end
        lines[#lines + 1] = updated[g.name] and ("Updated " .. ns.timeAgo(updated[g.name])) or "Known from TradeSkillMaster"
        res[#res + 1] = { name = g.name, total = g.total, text = table.concat(parts, ", "), tip = table.concat(lines, "\n") }
        total = total + g.total
    end

    local wb = DB.warband
    if warband or (wb and wb.items) then
        local c = warband or 0
        local when = wb and wb.at and ("updated " .. ns.timeAgo(wb.at)) or "from TradeSkillMaster"
        if ns.warbandBlocked then when = "|cffffb842NO ACCESS right now|r (last known, " .. when .. ")" end
        res[#res + 1] = { name = "Warband bank", total = c, text = when, tip = ("%d decor\n%s"):format(c, when) }
        total = total + c
    end

    local gseen = {}
    for g, data in pairs(DB.guild or {}) do
        local label = "guild bank (" .. g .. ")"
        gseen[label] = true
        local c = 0
        if DB.includeGuild then
            c = guilds[label] or 0
        else
            for _, items in pairs(data.tabs or {}) do
                for _, v in pairs(items) do c = c + v end
            end
        end
        res[#res + 1] = {
            name = "Guild bank: " .. g, total = c,
            text = DB.includeGuild and "counted" or "not counted (guild banks are off in Setup)",
            tip = ("%d decor\n%s"):format(c, DB.includeGuild and "Counted in your stock." or "Not counted: 'Include guild banks' is off."),
        }
        if DB.includeGuild then total = total + c end
    end
    for label, c in pairs(guilds) do                  -- guilds only TSM knows
        if not gseen[label] then
            res[#res + 1] = { name = "Guild bank: " .. (label:match("%((.*)%)$") or label), total = c,
                              text = "counted (TradeSkillMaster)", tip = ("%d decor\nFrom TradeSkillMaster."):format(c) }
            total = total + c
        end
    end
    return res, #order, total
end

local function DrawRows()
    for i = 1, ROWS do
        local r, e = rows[i], list[offset + i]
        r.n2:SetText(""); r.n3:SetText("")
        if e and e.header then
            r.entry = e
            r.name:SetTextColor(unpack(K.accent))
            r.name:SetText(("%s %s  (%d)"):format(e.closed and "[+]" or "[-]", e.header, e.count))
            r.need:SetText("")
            r.who:SetText(e.lumberText or "")
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
            elseif mode == "stock" then
                r.need:SetTextColor(unpack(e.have >= ns.DB.target and K.lime or K.amber))
                r.need:SetText(tostring(e.have))
                r.who:SetText(e.whereText ~= "" and e.whereText or "location unknown")
                r.bar:SetColorTexture(unpack(K.accent))
            elseif mode == "lumber" then
                r.need:SetTextColor(unpack(K.text))
                r.need:SetText(tostring(e.total))
                r.who:SetText(e.text)
                r.bar:SetColorTexture(unpack(K.accent))
                local function Cell(fs, n)
                    if n == nil or n <= 0 then
                        fs:SetTextColor(unpack(K.faint)); fs:SetText("-")
                    else
                        fs:SetTextColor(unpack(e.total >= n and K.lime or { 1, 0.33, 0.33, 1 }))
                        fs:SetText(tostring(n))
                    end
                end
                Cell(r.n2, e.needAll)
                Cell(r.n3, e.needProf)
            else
                r.need:SetTextColor(unpack(K.text))
                r.need:SetText(tostring(e.total))
                r.who:SetText(e.text)
                r.bar:SetColorTexture(unpack(K.accent))
            end
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
end

-- Lumber tab (Crafter view) has two extra columns, so the columns move over.
local layoutKind
local function ApplyLayout(kind)
    if layoutKind == kind then return end
    layoutKind = kind
    local lum = kind == "lumber"
    for _, r in ipairs(rows) do
        r.name:SetWidth(lum and 186 or 228)
        r.need:ClearAllPoints(); r.need:SetPoint("LEFT", r, "LEFT", lum and 200 or 238, 0)
        r.need:SetWidth(lum and 46 or 40)
        r.who:ClearAllPoints()
        r.who:SetPoint("LEFT", r, "LEFT", lum and 372 or 290, 0)
        r.who:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    end
    W.h2:ClearAllPoints(); W.h2:SetPoint("TOPLEFT", lum and 214 or 252, -232)
    W.h3:ClearAllPoints(); W.h3:SetPoint("TOPLEFT", lum and 386 or 304, -232)
end

local function RefreshStatus()
    if not f then return end
    local text = ns.msg or ""
    if ns.warbandBlocked then
        text = "|cffffb842Warband bank: no access (other account logged in first?)|r\n" .. text
    end
    local prog = ns.Progress()
    if prog then text = text .. "   |cffffb842" .. prog .. "|r" end
    W.statusFS:SetText(text)

    if ns.DB.role == "seller" then
        W.stat1.label:SetText("CHARACTERS TRACKED")
        W.stat1.value:SetText(tostring(trackedChars))
        W.stat2.label:SetText("DECOR TRACKED")
        W.stat2.value:SetText(tostring(trackedTotal))
    else
        W.stat1.label:SetText("DECOR TO CRAFT")
        W.stat1.value:SetText(tostring(#needed))
        W.stat2.label:SetText("DECOR IN STOCK")
        W.stat2.value:SetText(ns.DB.received and tostring(#stock) or "-")
    end
    W.stat1.sub:SetText("")
    W.stat2.sub:SetText("")
end

local function Refresh()
    if not f or not f:IsShown() then return end
    local DB = ns.DB
    local seller = DB.role == "seller"

    -- keep the current tab valid for the role
    if seller and (mode == "craft" or mode == "stock") then mode, offset = "tracked", 0 end
    if not seller and mode == "tracked" then mode, offset = "craft", 0 end
    local lumberTotal = 0
    local setup = mode == "setup"

    local state
    if seller then
        needed, stock, listState = {}, {}, "ok"
        tracked, trackedChars, trackedTotal = Tracked()
    else
        local l
        l, state = ns.GetNeeded()
        needed, listState = l or {}, state
        stock = ns.GetStock()
        tracked, trackedChars, trackedTotal = {}, 0, 0
    end
    if mode == "craft" then list = Grouped(needed, "craft")
    elseif mode == "stock" then list = Grouped(stock, "stock")
    elseif mode == "tracked" then list = tracked
    elseif mode == "lumber" then list, lumberTotal = ns.GetLumber()
    else list = {} end
    if mode ~= "lumber" then local _, t = ns.GetLumber(); lumberTotal = t end

    -- first run: ask which kind of account this is
    W.chooser:SetShown(DB.role == nil)
    ShowAll({ W.roleCrafter, W.roleSeller }, DB.role ~= nil)
    W.roleCrafter:SetActive(DB.role == "crafter")
    W.roleSeller:SetActive(DB.role == "seller")

    -- connection pill (top right, click it to open Setup)
    if DB.partner then
        W.pill.dot:SetColorTexture(unpack(K.lime))
        W.pill.text:SetTextColor(unpack(K.dim))
        W.pill.text:SetText("Linked: " .. DB.partner)
    else
        W.pill.dot:SetColorTexture(unpack(K.amber))
        W.pill.text:SetTextColor(unpack(K.amber))
        W.pill.text:SetText("Not linked")
    end

    -- the one action this role uses
    W.getBtn:SetShown(not seller)
    W.sendBtn:SetShown(seller)

    -- tabs
    W.craftTab:SetShown(not seller)
    W.stockTab:SetShown(not seller)
    W.trackTab:SetShown(seller)
    W.lumberTab:ClearAllPoints()
    W.lumberTab:SetPoint("TOPLEFT", seller and 164 or 294, -162)
    for _, t in ipairs({ { W.craftTab, "craft" }, { W.stockTab, "stock" }, { W.trackTab, "tracked" }, { W.lumberTab, "lumber" }, { W.setupTab, "setup" } }) do
        t[1].text:SetTextColor(unpack(mode == t[2] and K.text or K.dim))
        t[1].underline:SetShown(mode == t[2])
    end
    W.craftTab.text:SetText(("Decor to craft  %d"):format(#needed))
    W.stockTab.text:SetText(("In stock  %d"):format(#stock))
    W.trackTab.text:SetText(("Tracked stock  %d"):format(#tracked))
    W.lumberTab.text:SetText(("Lumber  %d"):format(lumberTotal))
    W.setupTab.text:SetText("Setup")

    -- which parts of the window show
    ShowAll(W.listGroup, not setup)
    ShowAll(W.toolbar, not setup and not seller and mode ~= "lumber")
    W.sellHelp:SetShown(not setup and seller and mode == "tracked")
    W.setupPanel:SetShown(setup)
    W.csBtn:SetShown(mode == "craft")
    ShowAll(W.guildGroup, seller)
    ShowAll(W.autoGroup, not seller)
    W.tools:SetShown(not seller)

    if mode == "craft" then
        W.h1:SetText("DECOR"); W.h2:SetText("NEED"); W.h3:SetText("WHO CAN CRAFT IT")
        W.footHint:SetText("Click an expansion to collapse it. Hover a row for owned / want / need.")
    elseif mode == "stock" then
        W.h1:SetText("DECOR"); W.h2:SetText("OWNED"); W.h3:SetText("WHERE IT IS")
        W.footHint:SetText("Click an expansion to collapse it. Hover a row to see where each piece is.")
    elseif mode == "lumber" then
        W.h1:SetText("LUMBER"); W.h2:SetText("OWNED"); W.h3:SetText("WHERE IT IS")
        if seller then
            W.footHint:SetText("Bags, bank and warband bank on this account. Hover a row for the breakdown.")
        else
            local _, _, pn = ns.LumberNeeds()
            W.footHint:SetText("Need = lumber for what is short of Want. NEED PROF: " ..
                (pn and ("the open " .. pn .. " window.") or "open a profession window."))
        end
    else
        W.h1:SetText("SOURCE"); W.h2:SetText("ITEMS"); W.h3:SetText("BREAKDOWN")
        W.footHint:SetText("Hover a row for details. 'Send my decor' sends this to your crafting account.")
    end

    local wide = mode == "lumber" and not seller
    ApplyLayout(wide and "lumber" or "default")
    W.h4:SetShown(wide and not setup); W.h5:SetShown(wide and not setup)

    local maxOff = math.max(0, #list - ROWS)
    if offset > maxOff then offset = maxOff end
    updating = true
    W.sb:SetMinMaxValues(0, maxOff)
    W.sb:SetValue(offset)
    updating = false
    W.sb:SetShown(maxOff > 0)

    DrawRows()

    W.emptyBtn:Hide()
    if #list > 0 then
        W.emptyFS:SetText("")
    elseif mode == "tracked" then
        W.emptyFS:SetText("Nothing recorded yet.\nLog into each character that holds decor, then open its bank, mailbox and the auction house's Auctions tab once (or use TradeSkillMaster).")
    elseif not DB.partner then
        W.emptyFS:SetText("Not linked to your other account yet.")
        W.emptyBtn:Show()
    elseif state == "nolist" then
        W.emptyFS:SetText("No decor list yet.\nPress 'Get decor list' above (the other account can also press 'Send my decor').")
    elseif ns.search ~= "" then
        W.emptyFS:SetText("Nothing matches that search.")
    elseif mode == "stock" then
        W.emptyFS:SetText("No sellable decor found yet.")
    elseif state == "norecipes" then
        W.emptyFS:SetText("No crafting recipes recorded yet.\nLog into each crafter and open each profession window once.")
    else
        W.emptyFS:SetText("Nothing needed. You're stocked!")
    end

    W.targetFS:SetText(tostring(DB.target))
    W.onlyMeCB:SetChecked(DB.onlyMe)
    W.autoCB:SetChecked(DB.autoRequest)
    W.guildCB:SetChecked(DB.includeGuild)
    if DB.partner then
        W.linkFS:SetTextColor(unpack(K.lime))
        W.linkFS:SetText("Linked to " .. DB.partner)
    else
        W.linkFS:SetTextColor(unpack(K.amber))
        W.linkFS:SetText("Not linked yet")
    end
    if not W.partnerBox:HasFocus() then W.partnerBox:SetText(DB.partner or "") end
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

    -- the first status line used to point at a box that now lives in Setup
    if ns.msg and ns.msg:find("^Ready%. Type your") then
        ns.msg = DB.partner and "Ready." or "Not linked yet. Open the Setup tab to link your other account."
    end

    -- opening tab: the role's own list, or Setup until the accounts are linked
    mode = (DB.role == "seller") and "tracked" or "craft"
    if DB.role and not DB.partner then mode = "setup" end

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

    local function GoTo(key)
        srcAt = 0
        mode, offset = key, 0
        Refresh()
    end

    -- Crafter or Seller. First choice (or switching later) lands on that role's list.
    local function SetRole(r)
        local first = DB.role == nil
        srcAt = 0
        DB.role = r
        offset = 0
        if first or mode ~= "setup" then mode = (r == "seller") and "tracked" or "craft" end
        if not DB.partner then mode = "setup" end
        Refresh()
    end

    -- a button that needs a linked account sends you to Setup instead of failing
    local function NeedsLink(fn)
        return function()
            if not DB.partner then
                ns.msg = "Link your other account first."
                GoTo("setup")
                return
            end
            fn()
        end
    end

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

    -- Crafter | Seller switch
    W.roleCrafter = Segment(f, "Crafter", 86, function() SetRole("crafter") end)
    W.roleCrafter:SetPoint("TOPLEFT", 142, -7)
    W.roleSeller = Segment(f, "Seller", 86, function() SetRole("seller") end)
    W.roleSeller:SetPoint("LEFT", W.roleCrafter, "RIGHT", -1, 0)
    Tooltip(W.roleCrafter, "Crafter view", "This account has your crafters: get the decor list and see what to craft.")
    Tooltip(W.roleSeller, "Seller view", "This account owns the decor: see what is recorded and send it to your crafting account.")

    -- connection pill: always shows whether you're linked, click for Setup
    W.pill = CreateFrame("Button", nil, f)
    W.pill:SetSize(200, 24)
    W.pill:SetPoint("TOPRIGHT", -40, -7)
    W.pill.text = Text(W.pill, 11, K.dim, "RIGHT")
    W.pill.text:SetPoint("RIGHT", W.pill, "RIGHT", 0, 0)
    W.pill.dot = W.pill:CreateTexture(nil, "OVERLAY")
    W.pill.dot:SetSize(7, 7)
    W.pill.dot:SetPoint("RIGHT", W.pill.text, "LEFT", -6, 0)
    W.pill:SetScript("OnClick", function() GoTo("setup") end)
    Tooltip(W.pill, "Connection", "Click to open Setup.")

    local tline = f:CreateTexture(nil, "ARTWORK")
    tline:SetColorTexture(unpack(K.border))
    tline:SetHeight(1)
    tline:SetPoint("TOPLEFT", 1, -37)
    tline:SetPoint("TOPRIGHT", -1, -37)

    -- the one action each role presses every time -------------------------
    W.getBtn = Button(f, "Get decor list", 150, 28, true, NeedsLink(function() ns.Request() end))
    W.getBtn:SetPoint("TOPLEFT", 14, -48)
    Tooltip(W.getBtn, "Get decor list", "Asks the other account to send what decor it owns.")
    W.sendBtn = Button(f, "Send my decor", 150, 28, true, NeedsLink(function() ns.Send() end))
    W.sendBtn:SetPoint("TOPLEFT", 14, -48)
    Tooltip(W.sendBtn, "Send my decor", "Sends your decor list to the other account.")

    W.statusFS = Text(f, 11, K.dim)
    W.statusFS:SetPoint("TOPLEFT", 178, -48)
    W.statusFS:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    W.statusFS:SetHeight(28)
    W.statusFS:SetJustifyV("MIDDLE")

    -- stat cards (their labels follow the role) ---------------------------
    W.stat1 = StatCard(f, "DECOR TO CRAFT")
    W.stat1:SetPoint("TOPLEFT", 14, -88)
    W.stat1:SetWidth((WIDTH - 28 - 8) / 2)
    W.stat2 = StatCard(f, "SELLABLE STOCK (OTHER ACCOUNT)")
    W.stat2:SetPoint("TOPRIGHT", -14, -88)
    W.stat2:SetWidth((WIDTH - 28 - 8) / 2)

    -- tabs ---------------------------------------------------------------
    local function MakeTab(point, x, w, key)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(w, 26)
        t:SetPoint(point, x, -162)
        t.text = Text(t, 12, K.dim, "CENTER")
        t.text:SetPoint("CENTER")
        t.underline = t:CreateTexture(nil, "OVERLAY")
        t.underline:SetColorTexture(unpack(K.accent))
        t.underline:SetHeight(2)
        t.underline:SetPoint("BOTTOMLEFT")
        t.underline:SetPoint("BOTTOMRIGHT")
        t:SetScript("OnClick", function() GoTo(key) end)
        t:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(K.text)) end)
        t:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(mode == key and K.text or K.dim)) end)
        return t
    end
    W.craftTab = MakeTab("TOPLEFT", 14, 150, "craft")
    W.stockTab = MakeTab("TOPLEFT", 164, 130, "stock")
    W.lumberTab = MakeTab("TOPLEFT", 294, 110, "lumber")
    W.trackTab = MakeTab("TOPLEFT", 14, 150, "tracked")
    W.setupTab = MakeTab("TOPRIGHT", -14, 80, "setup")
    local tabLine = f:CreateTexture(nil, "ARTWORK")
    tabLine:SetColorTexture(unpack(K.border))
    tabLine:SetHeight(1)
    tabLine:SetPoint("TOPLEFT", 14, -188)
    tabLine:SetPoint("TOPRIGHT", -14, -188)

    ---------------------------------------------------------------------
    -- Lists: filter row (Crafter), column headers, rows, footer
    ---------------------------------------------------------------------
    local sbox = Box(f, K.input, K.border)
    sbox:SetSize(190, 22)
    sbox:SetPoint("TOPLEFT", 14, -198)
    local searchBox = CreateFrame("EditBox", nil, sbox)
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

    W.onlyMeCB = CheckBox(f, "Only what this character can craft", function(v)
        DB.onlyMe = v
        Refresh()
    end)
    W.onlyMeCB:SetPoint("LEFT", sbox, "RIGHT", 14, 0)

    local plus = Button(f, "+", 24, 22, false, function()
        DB.target = math.min(99, DB.target + 1)
        Refresh()
    end)
    plus:SetPoint("TOPRIGHT", -14, -198)
    Tooltip(plus, "Want", "How many of each decor you want in stock to sell.")
    W.targetFS = Text(f, 13, K.text, "CENTER")
    W.targetFS:SetWidth(30)
    W.targetFS:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = Button(f, "-", 24, 22, false, function()
        DB.target = math.max(1, DB.target - 1)
        Refresh()
    end)
    minus:SetPoint("RIGHT", W.targetFS, "LEFT", -2, 0)
    local wl = Text(f, 10, K.dim, "RIGHT")
    wl:SetPoint("RIGHT", minus, "LEFT", -8, 0)
    wl:SetText("WANT")
    W.toolbar = { sbox, W.onlyMeCB, plus, W.targetFS, minus, wl }

    -- Seller: a line of guidance where the Crafter's filter row sits
    W.sellHelp = Text(f, 11, K.faint)
    W.sellHelp:SetPoint("TOPLEFT", 14, -197)
    W.sellHelp:SetWidth(WIDTH - 28)
    W.sellHelp:SetJustifyV("TOP")
    W.sellHelp:SetText("What 'Send my decor' will send: DecorSync's own records plus TradeSkillMaster's, if installed. Without TSM, log into each character and open its bank, mailbox and Auctions tab once.")

    -- column headers ------------------------------------------------------
    W.h1 = Text(f, 10, K.dim); W.h1:SetPoint("TOPLEFT", 26, -232)
    W.h2 = Text(f, 10, K.dim); W.h2:SetPoint("TOPLEFT", 252, -232)
    W.h3 = Text(f, 10, K.dim); W.h3:SetPoint("TOPLEFT", 304, -232)
    W.h4 = Text(f, 10, K.dim); W.h4:SetPoint("TOPLEFT", 264, -232); W.h4:SetText("NEED ALL")
    W.h5 = Text(f, 10, K.dim); W.h5:SetPoint("TOPLEFT", 324, -232); W.h5:SetText("NEED PROF")
    W.h4:Hide(); W.h5:Hide()

    -- list ----------------------------------------------------------------
    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetPoint("TOPLEFT", 14, -248)
    listFrame:SetPoint("TOPRIGHT", -14, -248)
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
        r.n2 = Text(r, 12, K.text); r.n2:SetPoint("LEFT", r, "LEFT", 250, 0); r.n2:SetWidth(56)
        r.n3 = Text(r, 12, K.text); r.n3:SetPoint("LEFT", r, "LEFT", 310, 0); r.n3:SetWidth(56)
        r:SetScript("OnEnter", function(self)
            self.hl:Show()
            local e = self.entry
            if e and e.header then
                if ns.search == "" then Tip.Show(self, "ANCHOR_RIGHT", e.header, e.closed and "Click to expand." or "Click to collapse.") end
                return
            end
            if not e then return end
            if mode == "craft" then
                Tip.Show(self, "ANCHOR_RIGHT", e.name,
                    ("Owned: %d   Want: %d   Need: %d more\n%s"):format(e.have or 0, DB.target, e.need, e.crafters))
            elseif mode == "stock" then
                local lines = { ("Owned: %d   Want: %d%s"):format(e.have, DB.target, e.have < DB.target and ("   (" .. (DB.target - e.have) .. " short)") or "") }
                if e.where and #e.where > 0 then
                    for _, l in ipairs(e.where) do lines[#lines + 1] = ("%s: %d"):format(l[1], l[2]) end
                else
                    lines[#lines + 1] = "Location unknown. Press 'Get decor list' again (the other account needs to send its list again)."
                end
                if e.crafters ~= "" then lines[#lines + 1] = "Can craft: " .. e.crafters end
                Tip.Show(self, "ANCHOR_RIGHT", e.name, table.concat(lines, "\n"))
            else
                Tip.Show(self, "ANCHOR_RIGHT", e.name, e.tip)
            end
        end)
        r:SetScript("OnLeave", function(self) self.hl:Hide(); Tip.Hide() end)
        r:SetScript("OnClick", function(self)
            local e = self.entry
            if e and e.header then
                DB.collapsed[e.key] = (not e.closed) or nil
                if ns.search ~= "" then ns.msg = "Groups stay open while you are searching." end
                Refresh()
            end
        end)
        rows[i] = r
    end

    W.emptyFS = Text(listFrame, 12, K.faint, "CENTER")
    W.emptyFS:SetPoint("CENTER", listFrame, "CENTER", -5, 10)
    W.emptyFS:SetWidth(460)
    W.emptyBtn = Button(listFrame, "Open Setup", 140, 26, true, function() GoTo("setup") end)
    W.emptyBtn:SetPoint("TOP", W.emptyFS, "BOTTOM", 0, -12)
    W.emptyBtn:Hide()

    -- slim scrollbar, same as Regional Edge
    local sb = CreateFrame("Slider", nil, listFrame)
    W.sb = sb
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

    -- footer: a hint on the left, the craft-queue action on the right ----------
    local fline = f:CreateTexture(nil, "ARTWORK")
    fline:SetColorTexture(unpack(K.border))
    fline:SetHeight(1)
    fline:SetPoint("BOTTOMLEFT", 14, 40)
    fline:SetPoint("BOTTOMRIGHT", -14, 40)

    W.footHint = Text(f, 11, K.faint)
    W.footHint:SetPoint("BOTTOMLEFT", 14, 14)

    W.csBtn = Button(f, "Import to CraftSim queue", 190, 24, false, NeedsLink(function() ns.ImportToCraftSim() end))
    W.csBtn:SetPoint("BOTTOMRIGHT", -14, 8)
    Tooltip(W.csBtn, "Import to CraftSim queue", "Adds every decor this character can craft and is short of (Want minus Owned) to CraftSim's Craft Queue. Needs CraftSim, and recipes recorded since this version (open each profession window once).")

    W.listGroup = { W.h1, W.h2, W.h3, listFrame, fline, W.footHint }

    ---------------------------------------------------------------------
    -- Setup tab: link (both roles), then the options for the current role
    ---------------------------------------------------------------------
    W.setupPanel = CreateFrame("Frame", nil, f)
    W.setupPanel:SetPoint("TOPLEFT", 14, -200)
    W.setupPanel:SetPoint("BOTTOMRIGHT", -14, 14)
    W.setupPanel:Hide()

    local function SectionLabel(parent, text)
        local t = Text(parent, 10, K.dim)
        t:SetPoint("TOPLEFT", 12, -10)
        t:SetText(text)
        return t
    end

    -- link ------------------------------------------------------------------
    local link = Box(W.setupPanel, K.card, K.border)
    link:SetPoint("TOPLEFT")
    link:SetPoint("TOPRIGHT")
    link:SetHeight(120)
    SectionLabel(link, "LINK YOUR OTHER ACCOUNT")
    W.linkFS = Text(link, 11, K.dim, "RIGHT")
    W.linkFS:SetPoint("TOPRIGHT", -12, -9)

    local help = Text(link, 11, K.faint)
    help:SetPoint("TOPLEFT", 12, -28)
    help:SetWidth(WIDTH - 28 - 24)
    help:SetJustifyV("TOP")
    help:SetText("Log into a character on each account at the same time, type a character from the OTHER account here (Name-Realm, e.g. Alice-Frostmourne) and press Connect. Press Yes on the pop-up that appears there.")

    local pbox = Box(link, K.input, K.border)
    pbox:SetSize(330, 26)
    pbox:SetPoint("BOTTOMLEFT", 12, 12)
    W.partnerBox = CreateFrame("EditBox", nil, pbox)
    SetFont(W.partnerBox, 13)
    W.partnerBox:SetPoint("TOPLEFT", 8, -1)
    W.partnerBox:SetPoint("BOTTOMRIGHT", -8, 1)
    W.partnerBox:SetAutoFocus(false)
    W.partnerBox:SetMaxLetters(64)
    W.partnerBox:SetTextColor(unpack(K.text))
    local function DoConnect()
        if ns.SetPartner(W.partnerBox:GetText()) then ns.Ping() end
        W.partnerBox:ClearFocus()
    end
    W.partnerBox:SetScript("OnEnterPressed", DoConnect)
    W.partnerBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    W.partnerBox:SetScript("OnEditFocusGained", function() pbox:SetBackdropBorderColor(unpack(K.accent)) end)
    W.partnerBox:SetScript("OnEditFocusLost", function() pbox:SetBackdropBorderColor(unpack(K.border)) end)

    local connect = Button(link, "Connect", 90, 26, true, DoConnect)
    connect:SetPoint("LEFT", pbox, "RIGHT", 8, 0)
    Tooltip(connect, "Connect", "Saves the name and sends a test message. The other account needs to be logged in with DecorSync installed. It will ask you to confirm the first time.")

    -- options: Seller gets the guild bank setting, Crafter gets the login request -
    local opts = Box(W.setupPanel, K.card, K.border)
    opts:SetPoint("TOPLEFT", link, "BOTTOMLEFT", 0, -10)
    opts:SetPoint("TOPRIGHT", link, "BOTTOMRIGHT", 0, -10)
    opts:SetHeight(86)
    SectionLabel(opts, "OPTIONS")

    W.guildCB = CheckBox(opts, "Include guild banks in my stock", function(v)
        ns.SetIncludeGuild(v)
    end)
    W.guildCB:SetPoint("TOPLEFT", 12, -32)
    local gd = Text(opts, 10, K.faint)
    gd:SetPoint("TOPLEFT", 36, -52)
    gd:SetWidth(WIDTH - 28 - 48)
    gd:SetJustifyV("TOP")
    gd:SetText("Counts decor in guild bank tabs you can view. Open each guild bank once. Press 'Send my decor' again after changing it.")
    W.guildGroup = { W.guildCB, gd }

    W.autoCB = CheckBox(opts, "Ask for a fresh list when I log in", function(v) DB.autoRequest = v end)
    W.autoCB:SetPoint("TOPLEFT", 12, -32)
    local ad = Text(opts, 10, K.faint)
    ad:SetPoint("TOPLEFT", 36, -52)
    ad:SetWidth(WIDTH - 28 - 48)
    ad:SetText("Requests the decor list from the other account shortly after you log in.")
    W.autoGroup = { W.autoCB, ad }

    -- tools (Crafter only) --------------------------------------------------
    W.tools = Box(W.setupPanel, K.card, K.border)
    W.tools:SetPoint("TOPLEFT", opts, "BOTTOMLEFT", 0, -10)
    W.tools:SetPoint("TOPRIGHT", opts, "BOTTOMRIGHT", 0, -10)
    W.tools:SetHeight(76)
    SectionLabel(W.tools, "TOOLS")
    local scan = Button(W.tools, "Scan profession window", 170, 26, false, function() ns.ScanRecipes(false) end)
    scan:SetPoint("TOPLEFT", 12, -32)
    local sd = Text(W.tools, 10, K.faint)
    sd:SetPoint("LEFT", scan, "RIGHT", 12, 0)
    sd:SetPoint("RIGHT", W.tools, "RIGHT", -12, 0)
    sd:SetJustifyV("MIDDLE")
    sd:SetText("Recipes are recorded automatically when you open a profession. Use this if one was missed.")

    ---------------------------------------------------------------------
    -- First run: which kind of account is this?  (covers everything below the title bar)
    ---------------------------------------------------------------------
    local ch = Box(f, K.window, K.window)
    W.chooser = ch
    ch:SetPoint("TOPLEFT", 1, -38)
    ch:SetPoint("BOTTOMRIGHT", -1, 1)
    ch:SetFrameLevel(f:GetFrameLevel() + 30)
    ch:EnableMouse(true)
    ch:Hide()

    local head = Text(ch, 18, K.text, "CENTER")
    head:SetPoint("TOP", 0, -34)
    head:SetText("What does this account do?")
    local sub = Text(ch, 12, K.dim, "CENTER")
    sub:SetPoint("TOP", head, "BOTTOM", 0, -10)
    sub:SetWidth(480)
    sub:SetText("DecorSync only shows what that role needs. You can switch any time with the Crafter and Seller buttons at the top.")

    local function RoleCard(x, titleText, body, btnText, role)
        local c = Box(ch, K.card, K.border)
        c:SetSize((WIDTH - 28 - 12) / 2, 190)
        c:SetPoint("TOPLEFT", x, -130)
        local t = Text(c, 15, K.accent)
        t:SetPoint("TOPLEFT", 16, -16)
        t:SetText(titleText)
        local b = Text(c, 12, K.dim)
        b:SetPoint("TOPLEFT", 16, -46)
        b:SetWidth((WIDTH - 28 - 12) / 2 - 32)
        b:SetJustifyV("TOP")
        b:SetText(body)
        local btn = Button(c, btnText, (WIDTH - 28 - 12) / 2 - 32, 28, true, function() SetRole(role) end)
        btn:SetPoint("BOTTOM", 0, 16)
    end
    RoleCard(14, "Seller account",
        "This account owns the decor and sells it.\n\nYou'll see what DecorSync has recorded on your characters, and a button to send it to your crafting account.",
        "This is my seller account", "seller")
    RoleCard(14 + (WIDTH - 28 - 12) / 2 + 12, "Crafter account",
        "This account has your crafters.\n\nYou'll see what to craft and what's in stock on the other account, and a button to get the decor list.",
        "This is my crafter account", "crafter")

    f:SetScript("OnShow", function() srcAt = 0; Refresh() end)
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
