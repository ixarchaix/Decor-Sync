---------------------------------------------------------------------
-- DecorSync - core: talking between accounts, storing data
---------------------------------------------------------------------
local ADDON_NAME, ns = ...
local PREFIX = "DECORSYNC"
local PROTO = 2
local CHUNK_LIMIT = 190      -- bytes of decor data per message (hard cap is 255)

local DB

ns.msg = "Ready. Type your other account's character name above, then press Connect."
ns.sendTotal, ns.sendDone = 0, 0

local function Changed()
    if ns.OnChange then ns.OnChange() end
end

local function out(text)
    print("|cff33ccffDecorSync:|r " .. text)
    ns.msg = text
    Changed()
end

local function dbg(msg)
    -- "|" starts formatting codes in WoW chat, so double it to show it literally
    if DB and DB.debug then
        print("|cffff9900DecorSync debug:|r", (tostring(msg):gsub("|", "||")))
    end
end

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------
local function norm(name)
    if not name or name == "" then return "" end
    return (Ambiguate(name, "none")):lower()
end

local function esc(s)
    return (s:gsub("[%%;=|]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function unesc(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function ns.timeAgo(t)
    local s = time() - (t or 0)
    if s < 90 then return "just now" end
    if s < 5400 then return math.floor(s / 60) .. " minutes ago" end
    if s < 172800 then return math.floor(s / 3600) .. " hours ago" end
    return math.floor(s / 86400) .. " days ago"
end

local function MyKey()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    local name = UnitName("player")
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

---------------------------------------------------------------------
-- Sending: a slow, polite queue (WoW limits how fast addons can talk)
---------------------------------------------------------------------
local sendQueue, sendTicker = {}, nil
local throttleCodes = {}
do
    local e = Enum and Enum.SendAddonMessageResult
    if e then
        for _, k in ipairs({ "AddonMessageThrottle", "ChannelThrottle", "ChatThrottle" }) do
            if e[k] then throttleCodes[e[k]] = true end
        end
    end
end

local function Enqueue(target, text, counted)
    sendQueue[#sendQueue + 1] = { target = target, text = text, counted = counted }
    if counted then ns.sendTotal = ns.sendTotal + 1 end
    if sendTicker then return end
    sendTicker = C_Timer.NewTicker(0.15, function()
        local item = sendQueue[1]
        if not item then
            sendTicker:Cancel()
            sendTicker = nil
            return
        end
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.text, "WHISPER", item.target)
        dbg(("sent '%s' to %s -> result %s"):format(item.text:sub(1, 12), item.target, tostring(result)))
        if not throttleCodes[result] then      -- if throttled, just try again next tick
            table.remove(sendQueue, 1)
            if item.counted then
                ns.sendDone = ns.sendDone + 1
                if ns.sendDone >= ns.sendTotal then ns.sendTotal, ns.sendDone = 0, 0 end
            end
        end
    end)
end

---------------------------------------------------------------------
-- Scanning owned decor
---------------------------------------------------------------------
local searcher, scanBusy

-- locs[name] = { {label, count}, ... }  says where the copies of a decor are
local function AddLoc(locs, name, label, count)
    if not locs or not count or count <= 0 then return end
    local l = locs[name]
    if not l then l = {}; locs[name] = l end
    for _, e in ipairs(l) do
        if e[1] == label then e[2] = e[2] + count; return end
    end
    l[#l + 1] = { label, count }
end

local function ReadResults()
    local owned, n, locs = {}, 0, {}
    local results = searcher:GetCatalogSearchResults() or {}
    for _, entryID in ipairs(results) do
        local info = C_HousingCatalog.GetCatalogEntryInfo(entryID)
        if info and info.name then
            local stored, placed = info.quantity or 0, info.numPlaced or 0
            local total = stored + placed
            if total > 0 then
                owned[info.name] = (owned[info.name] or 0) + total
                AddLoc(locs, info.name, "housing storage", stored)
                AddLoc(locs, info.name, "placed in house", placed)
                n = n + 1
            end
        end
    end
    return owned, n, locs
end

local function ScanOwned(callback)
    if not (C_HousingCatalog and C_HousingCatalog.CreateCatalogSearcher) then
        return out("This game version has no housing catalog. Try /decorsync dump and tell me what happens.")
    end
    if scanBusy then return out("A scan is already running, give it a few seconds.") end
    scanBusy = true
    searcher = searcher or C_HousingCatalog.CreateCatalogSearcher()

    local finished, debounce = false, nil
    local function finish()
        if finished then return end
        finished, scanBusy = true, false
        if debounce then debounce:Cancel() end
        local ok, owned, n, locs = pcall(ReadResults)
        if not ok then return out("Scan failed: " .. tostring(owned)) end
        callback(owned, n, locs)
    end
    local function onUpdate()
        if finished then return end
        if debounce then debounce:Cancel() end
        debounce = C_Timer.NewTimer(0.75, finish)
    end

    if searcher.SetOwnedOnly then searcher:SetOwnedOnly(true) end
    if searcher.SetResultsUpdatedCallback then searcher:SetResultsUpdatedCallback(onUpdate) end
    if searcher.RunSearch then searcher:RunSearch() end
    C_Timer.After(4, finish)
end

---------------------------------------------------------------------
-- Decor sitting in bags, bank, mail and auctions.
-- The housing catalog only knows about decor in housing storage or placed in
-- a house. Decor you are holding to sell is an ordinary item, so it is
-- invisible to the catalog. The game can only show the character you are
-- logged in on, so each character's holdings are remembered in the saved
-- data and added up whenever the list is sent.
---------------------------------------------------------------------
local SECTIONS = { "bags", "bank", "mail", "ah" }
local SECTION_LABEL = { bags = "bags", bank = "bank", mail = "mail", ah = "auction house" }
local bankOpen = false
local timers = {}

local function Later(key, delay, fn)
    if timers[key] then timers[key]:Cancel() end
    timers[key] = C_Timer.NewTimer(delay, function()
        timers[key] = nil
        local ok, err = pcall(fn)
        if not ok then dbg(key .. " scan failed: " .. tostring(err)) end
    end)
end

local function MyInv()
    local key = MyKey()
    local inv = DB.inv[key]
    if not inv then inv = {}; DB.inv[key] = inv end
    inv.at = time()
    return inv
end

-- Looks an item up in the housing catalog. The "owned" form of the lookup may
-- only answer for decor you have already learned, so the plain form is tried
-- too, then an item link. As a last resort an item of the Housing class is
-- accepted under its item name.
local function CatalogInfo(ref)
    local fn = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
    if not fn or ref == nil then return nil end
    local id = type(ref) == "number" and ref or tonumber(tostring(ref):match("item:(%d+)"))
    local tries = { { ref, true }, { ref, false } }
    if id and type(ref) == "number" then tries[#tries + 1] = { "item:" .. id, false } end
    for _, t in ipairs(tries) do
        local ok, info = pcall(fn, t[1], t[2])
        if ok and type(info) == "table" and info.name then return info end
    end
    if id and C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemNameByID
        and Enum and Enum.ItemClass and Enum.ItemClass.Housing then
        local classID = select(6, C_Item.GetItemInfoInstant(id))
        if classID == Enum.ItemClass.Housing then
            local name = C_Item.GetItemNameByID(id)
            if name then return { name = name, fromItemName = true } end
        end
    end
    return nil
end

-- decor name for an item, or nil if the item is not decor.
-- Only positive answers are kept between scans; items that were not loaded
-- yet are asked about again next time.
local decorNameCache = {}
local function DecorNameForItem(itemID, miss)
    local hit = decorNameCache[itemID]
    if hit then return hit end
    if miss[itemID] then return nil end
    local info = CatalogInfo(itemID)
    -- only decor in the ID or name database counts
    if info and (ns.IsDecorItem(itemID) or ns.IsDecorName(info.name)) then
        decorNameCache[itemID] = info.name
        return info.name
    end
    miss[itemID] = true
    return nil
end

-- Lumber (housing crafting material, one kind per expansion) --------------
-- Matched by item NAME so no item IDs are needed. Anything else called "... Lumber"
-- is picked up too and listed under its own name.
ns.LUMBER = {
    { "Ironwood Lumber",     "Classic" },
    { "Olemba Lumber",       "Burning Crusade" },
    { "Coldwind Lumber",     "Wrath of the Lich King" },
    { "Ashwood Lumber",      "Cataclysm" },
    { "Bamboo Lumber",       "Mists of Pandaria" },
    { "Shadowmoon Lumber",   "Warlords of Draenor" },
    { "Fel-Touched Lumber",  "Legion" },
    { "Darkpine Lumber",     "Battle for Azeroth" },
    { "Arden Lumber",        "Shadowlands" },
    { "Dragonpine Lumber",   "Dragonflight" },
    { "Dornic Fir Lumber",   "The War Within" },
    { "Thalassian Lumber",   "Midnight" },
}
local function LKey(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end
local LUMBER_BY_KEY = {}
for _, l in ipairs(ns.LUMBER) do LUMBER_BY_KEY[LKey(l[1])] = l end

local lumberCache = {}       -- itemID -> canonical lumber name, or false for "not lumber"
local pendingItems = {}      -- item IDs whose names were requested; the window redraws when they arrive
local function LumberNameForItem(itemID)
    local hit = lumberCache[itemID]
    if hit ~= nil then return hit or nil end
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not n then                                      -- not loaded yet; ask for it and try again later
        if C_Item and C_Item.RequestLoadItemDataByID then
            pendingItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    local known = LUMBER_BY_KEY[LKey(n)]
    local res = known and known[1] or (n:find(" Lumber$") and n) or false
    lumberCache[itemID] = res
    return res or nil
end

local function ScanBagRange(bagIDs, into, miss, lum)
    for _, bag in ipairs(bagIDs) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = DecorNameForItem(info.itemID, miss)
                if name then into[name] = (into[name] or 0) + (info.stackCount or 1) end
                if lum then
                    local ln = LumberNameForItem(info.itemID)
                    if ln then lum[ln] = (lum[ln] or 0) + (info.stackCount or 1) end
                end
            end
        end
    end
end

local function EnumBags(prefix, count)
    local ids, E = {}, Enum and Enum.BagIndex
    if E then
        for i = 1, count do
            local v = E[prefix .. i]
            if v then ids[#ids + 1] = v end
        end
    end
    return ids
end

local function CarriedBagIDs()
    local E = Enum and Enum.BagIndex
    local last = (E and E.ReagentBag) or 5
    local ids = {}
    for b = 0, last do ids[#ids + 1] = b end
    return ids
end

local function ScanBags()
    if not C_Container then return end
    local into, lum = {}, {}
    ScanBagRange(CarriedBagIDs(), into, {}, lum)
    local inv = MyInv()
    if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then inv.bags = into end
    inv.lumber = inv.lumber or {}
    inv.lumber.bags = lum
end

-- Warband bank access. The warband bank can't be opened by a second game account
-- at the same time, so when the other account logged in first this one can't see it.
-- ns.warbandBlocked is true after a bank visit where that happened.
local function WarbandAccess()
    local B = Enum and Enum.BankType
    if C_Bank and C_Bank.CanViewBank and B and B.Account then
        local ok, can = pcall(C_Bank.CanViewBank, B.Account)
        if ok then return can and true or false end
    end
    local slots = 0
    for _, id in ipairs(EnumBags("AccountBankTab_", 8)) do
        slots = slots + (C_Container.GetContainerNumSlots(id) or 0)
    end
    return slots > 0
end
local warbandWarned = false

local function ScanBank()
    if not bankOpen then return end
    if not C_Container then return end
    local haveCat = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
    local miss = {}
    local mine, mineL = {}, {}
    ScanBagRange(EnumBags("CharacterBankTab_", 8), mine, miss, mineL)
    local legacy = EnumBags("BankBag_", 7)
    if Enum and Enum.BagIndex and Enum.BagIndex.Bank then table.insert(legacy, 1, Enum.BagIndex.Bank) end
    ScanBagRange(legacy, mine, miss, mineL)
    local inv = MyInv()
    if haveCat then inv.bank = mine end
    inv.lumber = inv.lumber or {}
    inv.lumber.bank = mineL

    if WarbandAccess() then
        ns.warbandBlocked = false
        local shared, sharedL = {}, {}
        ScanBagRange(EnumBags("AccountBankTab_", 8), shared, miss, sharedL)
        DB.warband = { items = haveCat and shared or (DB.warband and DB.warband.items) or {},
                       lumber = sharedL, at = time(), by = MyKey() }
        warbandWarned = false
    else
        -- keep the last known warband numbers rather than overwriting them with nothing
        ns.warbandBlocked = true
        if not warbandWarned then
            warbandWarned = true
            out("WARNING: no access to your Warband Bank on this account right now. This usually happens when your other " ..
                "account logged in first. Warband bank decor and lumber were NOT updated (last known numbers are kept). " ..
                "Log out of both, log into this account first, then open the bank again.")
        end
    end
end

local function ScanMail()
    if not (GetInboxNumItems and GetInboxItem) then return end
    if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return end
    local into, miss = {}, {}
    for i = 1, (GetInboxNumItems()) do
        for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local _, itemID, _, count = GetInboxItem(i, a)
            if itemID then
                local name = DecorNameForItem(itemID, miss)
                if name then into[name] = (into[name] or 0) + (count or 1) end
            end
        end
    end
    MyInv().mail = into
end

local function ScanAuctions()
    if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions) then return end
    if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return end
    local into, miss = {}, {}
    local soldStatus = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold
    for _, a in ipairs(C_AuctionHouse.GetOwnedAuctions() or {}) do
        local itemID = a.itemKey and a.itemKey.itemID
        if itemID and not (soldStatus and a.status == soldStatus) then
            local name = DecorNameForItem(itemID, miss)
            if name then into[name] = (into[name] or 0) + (a.quantity or 1) end
        end
    end
    MyInv().ah = into
end

-- Optional: TradeSkillMaster already tracks bags / bank / mail / auctions for
-- every character on this account. Its saved data is a plain global table once
-- loaded, so it can be read in-game (an addon can never open files itself).
-- Layout assumed (TSM 4): TradeSkillMasterDB["s@Name - Realm@internalData@bagQuantity"]
-- = { ["i:12345"] = count, ... }  (also bankQuantity, mailQuantity, auctionQuantity ...)
-- Run /decorsync tsm to see what was actually found.
local tsmMiss = {}
local function NormChar(key)
    return ((key or ""):lower():gsub("[%s%-']", ""))
end

local function ReadTSM()
    local db = _G.TradeSkillMasterDB
    if type(db) ~= "table" then return nil end
    if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return nil end
    local chars, any = {}, false
    for key, tbl in pairs(db) do
        if type(key) == "string" and type(tbl) == "table" then
            local who, section = key:match("^s@(.-)@internalData@(%w+Quantity)$")
            if who then
                local ch = chars[NormChar(who)]
                if not ch then
                    ch = { label = who, items = {}, sections = {}, detail = {} }
                    chars[NormChar(who)] = ch
                end
                for itemRef, count in pairs(tbl) do
                    local itemID
                    if type(itemRef) == "number" then
                        itemID = itemRef
                    elseif type(itemRef) == "string" then
                        itemID = tonumber(itemRef:match("^i:(%d+)"))
                    end
                    if itemID and type(count) == "number" and count > 0 and not tsmMiss[itemID] then
                        local name = decorNameCache[itemID]
                        if not name then
                            local info = CatalogInfo(itemID)
                            if info and (ns.IsDecorItem(itemID) or ns.IsDecorName(info.name)) then
                                name = info.name
                                decorNameCache[itemID] = name
                            else
                                tsmMiss[itemID] = true
                            end
                        end
                        if name then
                            ch.items[name] = (ch.items[name] or 0) + count
                            ch.sections[section] = (ch.sections[section] or 0) + count
                            local d = ch.detail[name]
                            if not d then d = {}; ch.detail[name] = d end
                            d[section] = (d[section] or 0) + count
                            any = true
                        end
                    end
                end
            end
        end
    end
    if not any and not next(chars) then return nil end
    return chars
end

-- Guild bank. Only the tabs you can view are readable, one tab at a time, so
-- each viewable tab is queried in turn and remembered per guild. It is only
-- added to the list when the "Include guild banks" setting is on.
local guildOpen, guildBusy = false, false

local function ReadGuildTab(tab, miss)
    local into = {}
    local slots = MAX_GUILDBANK_SLOTS_PER_TAB or 98
    for slot = 1, slots do
        local link = GetGuildBankItemLink(tab, slot)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID then
            local name = DecorNameForItem(itemID, miss)
            if name then
                local _, count = GetGuildBankItemInfo(tab, slot)
                into[name] = (into[name] or 0) + (count or 1)
            end
        end
    end
    return into
end

local function ScanGuildBank()
    if not guildOpen or guildBusy then return end
    if not (GetNumGuildBankTabs and QueryGuildBankTab and GetGuildBankItemLink and GetGuildBankItemInfo) then return end
    if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return end
    local gname = GetGuildInfo("player")
    if not gname then return end
    DB.guild = DB.guild or {}
    local g = DB.guild[gname]
    if not g then g = { tabs = {} }; DB.guild[gname] = g end
    local numTabs = GetNumGuildBankTabs() or 0
    local tab, miss = 0, {}
    guildBusy = true
    local function nextTab()
        tab = tab + 1
        if tab > numTabs or not guildOpen then
            guildBusy = false
            g.at = time()
            dbg("guild bank scan finished for " .. gname)
            return Changed()
        end
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if not viewable then
            g.tabs[tab] = nil
            return nextTab()
        end
        QueryGuildBankTab(tab)
        C_Timer.After(1.0, function()
            if guildOpen then
                local ok, items = pcall(ReadGuildTab, tab, miss)
                if ok then g.tabs[tab] = items end
            end
            nextTab()
        end)
    end
    nextTab()
end

-- keeps the tab you are looking at up to date after deposits / withdrawals
local function RescanCurrentGuildTab()
    if not guildOpen or guildBusy or not GetCurrentGuildBankTab then return end
    local gname = GetGuildInfo("player")
    local g = gname and DB.guild and DB.guild[gname]
    local tab = GetCurrentGuildBankTab()
    if not (g and tab) then return end
    local _, _, viewable = GetGuildBankTabInfo(tab)
    if viewable then g.tabs[tab] = ReadGuildTab(tab, {}) end
end

-- TSM keeps guild bank counts as "g@Guild Name@internalData@guildQuantity" (layout assumed).
local function ReadTSMGuilds()
    local db = _G.TradeSkillMasterDB
    if type(db) ~= "table" then return nil end
    if not (C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then return nil end
    local guilds, any = {}, false
    for key, tbl in pairs(db) do
        if type(key) == "string" and type(tbl) == "table" then
            local who = key:match("^g@(.-)@internalData@guildQuantity$")
            if who then
                local gd = guilds[NormChar(who)]
                if not gd then gd = { label = who, items = {} }; guilds[NormChar(who)] = gd end
                for itemRef, count in pairs(tbl) do
                    local itemID
                    if type(itemRef) == "number" then itemID = itemRef
                    elseif type(itemRef) == "string" then itemID = tonumber(itemRef:match("^i:(%d+)")) end
                    if itemID and type(count) == "number" and count > 0 and not tsmMiss[itemID] then
                        local name = decorNameCache[itemID]
                        if not name then
                            local info = CatalogInfo(itemID)
                            if info and (ns.IsDecorItem(itemID) or ns.IsDecorName(info.name)) then
                                name = info.name
                                decorNameCache[itemID] = name
                            else
                                tsmMiss[itemID] = true
                            end
                        end
                        if name then
                            gd.items[name] = (gd.items[name] or 0) + count
                            any = true
                        end
                    end
                end
            end
        end
    end
    if not any then return nil end
    return guilds
end

function ns.SetIncludeGuild(on)
    DB.includeGuild = on and true or false
    out(DB.includeGuild
        and "Guild banks will be INCLUDED the next time the list is sent (open each guild bank once so it is remembered)."
        or "Guild banks will be left out the next time the list is sent.")
end

local TSM_LABEL = { bagQuantity = "bags", bankQuantity = "bank", reagentBankQuantity = "reagent bank",
                      mailQuantity = "mail", auctionQuantity = "auction house" }

local function ShortName(key)
    return (key or "?"):match("^(.-) %- ") or (key or "?"):match("^([^-]+)") or key or "?"
end

local OWN_TO_TSM = { bags = "bagQuantity", bank = "bankQuantity", mail = "mailQuantity", ah = "auctionQuantity" }
local TSM_MAPPED = { bagQuantity = true, bankQuantity = true, mailQuantity = true, auctionQuantity = true }

-- Adds everything held outside the catalog into owned / locs.
-- For each character and place (bags, bank, mail, auctions) the addon's own
-- scan and TSM's numbers are both looked at and the HIGHER one is used, so a
-- gap in either source (TSM missing your auctions, or a place this addon has
-- not seen yet) can't hide decor. Places only TSM tracks (reagent bank) are added as is.
-- Returns the number of decor items added and how many names were new.
local function AddInventory(owned, locs)
    local added, newNames = 0, 0
    local function add(name, label, c)
        if not c or c <= 0 then return end
        if not owned[name] then newNames = newNames + 1 end
        owned[name] = (owned[name] or 0) + c
        AddLoc(locs, name, label, c)
        added = added + c
    end
    local tsm = ReadTSM() or {}
    local seen = {}
    for key, inv in pairs(DB.inv) do
        local nk = NormChar(key)
        seen[nk] = true
        local ch = tsm[nk]
        local who = ShortName(key)
        for _, sect in ipairs(SECTIONS) do
            local merged = {}
            for name, c in pairs(inv[sect] or {}) do merged[name] = c end
            if ch then
                local tsec = OWN_TO_TSM[sect]
                for name, byServ in pairs(ch.detail) do
                    local c = byServ[tsec]
                    if c and c > (merged[name] or 0) then merged[name] = c end
                end
            end
            for name, c in pairs(merged) do add(name, ("%s (%s)"):format(who, SECTION_LABEL[sect]), c) end
        end
        if ch then
            for name, byServ in pairs(ch.detail) do
                for section, c in pairs(byServ) do
                    if not TSM_MAPPED[section] then
                        add(name, ("%s (%s)"):format(who, TSM_LABEL[section] or (section:gsub("Quantity$", ""))), c)
                    end
                end
            end
        end
    end
    for nk, ch in pairs(tsm) do                       -- characters only TSM knows
        if not seen[nk] then
            local who = ShortName(ch.label)
            for name, byServ in pairs(ch.detail) do
                for section, c in pairs(byServ) do
                    add(name, ("%s (%s)"):format(who, TSM_LABEL[section] or (section:gsub("Quantity$", ""))), c)
                end
            end
        end
    end
    for name, c in pairs((DB.warband and DB.warband.items) or {}) do add(name, "warband bank", c) end
    if DB.includeGuild then
        local tsmG = ReadTSMGuilds() or {}
        local seenG = {}
        for gname, g in pairs(DB.guild or {}) do
            local nk = NormChar(gname)
            seenG[nk] = true
            local merged = {}
            for _, items in pairs(g.tabs or {}) do
                for name, c in pairs(items) do merged[name] = (merged[name] or 0) + c end
            end
            local tg = tsmG[nk]
            if tg then
                for name, c in pairs(tg.items) do
                    if c > (merged[name] or 0) then merged[name] = c end
                end
            end
            for name, c in pairs(merged) do add(name, ("guild bank (%s)"):format(gname), c) end
        end
        for nk, tg in pairs(tsmG) do                  -- guilds only TSM knows
            if not seenG[nk] then
                for name, c in pairs(tg.items) do add(name, ("guild bank (%s)"):format(tg.label), c) end
            end
        end
    end
    return added, newNames
end

-- For the window: everything "Send my decor" would send, with where each piece is
-- (own scans and TradeSkillMaster merged). Reads only; nothing is scanned or sent.
function ns.SourceLocs()
    local owned, locs = {}, {}
    AddInventory(owned, locs)
    return locs
end

---------------------------------------------------------------------
-- Sending the list
---------------------------------------------------------------------
local pendingAck

local MAX_LOCS = 8
local function escL(t)
    return (t:gsub("[%%;=|,~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function LocString(list, room)
    if not list then return "" end
    table.sort(list, function(x, y) if x[2] ~= y[2] then return x[2] > y[2] end return x[1] < y[1] end)
    local parts, extra = {}, 0
    for i, l in ipairs(list) do
        if i <= MAX_LOCS then parts[#parts + 1] = escL(l[1]) .. "~" .. l[2] else extra = extra + l[2] end
    end
    if extra > 0 then parts[#parts + 1] = "more~" .. extra end
    local str = table.concat(parts, ",")
    while #str > room and #parts > 1 do        -- an entry must fit in one message
        table.remove(parts)
        str = table.concat(parts, ",")
    end
    return str
end

local function BuildChunks(owned, locs)
    local names = {}
    for name in pairs(owned) do names[#names + 1] = name end
    table.sort(names)
    local chunks, cur = {}, ""
    for _, name in ipairs(names) do
        local head = esc(name) .. "=" .. owned[name] .. "="
        local entry = head .. LocString(locs and locs[name], CHUNK_LIMIT - #head - 1) .. ";"
        if #cur > 0 and #cur + #entry > CHUNK_LIMIT then
            chunks[#chunks + 1] = cur
            cur = ""
        end
        cur = cur .. entry
    end
    if #cur > 0 then chunks[#chunks + 1] = cur end
    return chunks
end

local function SendList(target)
    if ns.sendTotal > 0 then return out("Already sending, please wait for it to finish.") end
    -- Sellable stock only: bags, bank, mail, auction listings, warband bank.
    -- Decor you have learned or placed in a house is deliberately NOT counted.
    out("Collecting your sellable decor...")
    pcall(ScanBags)                                   -- freshen the character you're on
    do
        local owned, locs = {}, {}
        local heldCount, n = AddInventory(owned, locs)
        if n == 0 then
            return out("No sellable decor found in bags, bank, mail, auctions or the warband bank, so nothing was sent. " ..
                       "Log into each seller and open its bank, mailbox and the auction house once (or use TradeSkillMaster).")
        end
        dbg(("sending %d sellable decor items"):format(heldCount))
        local chunks = BuildChunks(owned, locs)
        local session = tostring(math.random(10000, 99999))
        Enqueue(target, ("H|%d|%s|%d|%d"):format(PROTO, session, #chunks, time()), true)
        for i, c in ipairs(chunks) do
            Enqueue(target, ("D|%s|%d|%s"):format(session, i, c), true)
        end
        pendingAck = session
        out(("Sending %d decor entries to %s..."):format(n, target))
        C_Timer.After(30 + #chunks * 0.4, function()
            if pendingAck == session then
                pendingAck = nil
                out(("No confirmation from %s. Is that character online, and is DecorSync installed there?"):format(target))
            end
        end)
    end
end

---------------------------------------------------------------------
-- Receiving, and pairing with the other account
---------------------------------------------------------------------
local incoming = {}      -- partial transfers, keyed by sender
local asked = {}         -- strangers we've already asked about this session
local pending = {}       -- first message from a stranger, replayed once accepted
local requestedAt, pingToken

local function ApplyTransfer(sender, inc)
    local owned, where, n = {}, {}, 0
    for i = 1, inc.total do
        for entry in (inc.chunks[i] or ""):gmatch("([^;]+);") do
            local name, count, locstr = entry:match("^([^=]+)=(%d+)=?(.*)$")
            if name then
                name = unesc(name)
                owned[name] = tonumber(count)
                n = n + 1
                if locstr and locstr ~= "" then
                    local list = {}
                    for tok in locstr:gmatch("[^,]+") do
                        local lab, c = tok:match("^(.-)~(%d+)$")
                        if lab then list[#list + 1] = { unesc(lab), tonumber(c) } end
                    end
                    where[name] = list
                end
            end
        end
    end
    DB.received = { from = sender, at = time(), sentAt = inc.stamp, owned = owned, where = where, count = n }
    requestedAt = nil
    out(("Received %d owned decor entries from %s."):format(n, sender))
    Enqueue(sender, "A|" .. inc.session)
end

local function HandleText(sender, text)
    local kind = text:sub(1, 1)
    if kind == "Q" then                                   -- partner asks for our list
        DB.partner = sender
        SendList(sender)
    elseif kind == "H" then                               -- start of a transfer
        local proto, session, total, stamp = text:match("^H|(%d+)|([^|]+)|(%d+)|(%d+)$")
        if tonumber(proto) ~= PROTO then
            return out("The other account runs a different DecorSync version. Update both.")
        end
        DB.partner = sender
        incoming[norm(sender)] = { session = session, total = tonumber(total), stamp = tonumber(stamp),
                                   chunks = {}, got = 0, t = GetTime() }
    elseif kind == "D" then                               -- one piece of data
        local session, idx, payload = text:match("^D|([^|]+)|(%d+)|(.*)$")
        local inc = incoming[norm(sender)]
        idx = tonumber(idx)
        if inc and inc.session == session and idx and not inc.chunks[idx] then
            inc.chunks[idx] = payload
            inc.got = inc.got + 1
            inc.t = GetTime()
            if inc.got == inc.total then
                incoming[norm(sender)] = nil
                ApplyTransfer(sender, inc)
            else
                Changed()
            end
        end
    elseif kind == "T" then                               -- connection test
        DB.partner = sender
        out(sender .. " connected to you.")
        Enqueue(sender, "P|1")
    elseif kind == "P" then
        pingToken = nil
        out("Connected! " .. sender .. " answered.")
    elseif kind == "A" then                               -- confirmation from receiver
        if text:sub(3) == pendingAck then
            pendingAck = nil
            out(sender .. " confirmed: your decor list was delivered.")
        end
    end
end

function ns.Trust(name)
    DB.trusted[norm(name)] = true
    DB.partner = name
end

StaticPopupDialogs["DECORSYNC_PAIR"] = {
    text = "DecorSync: |cffffff00%s|r is trying to connect.\n\nIs that a character on your other account?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, sender)
        ns.Trust(sender)
        local t = pending[norm(sender)]
        pending[norm(sender)] = nil
        if t then HandleText(sender, t) end
        Changed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OnMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or not DB then return end
    dbg(("heard '%s' from %s"):format(text:sub(1, 12), tostring(sender)))
    if norm(sender) == norm(UnitName("player")) then return end

    if not DB.trusted[norm(sender)] then
        local kind = text:sub(1, 1)
        if (kind == "T" or kind == "Q" or kind == "H") and not asked[norm(sender)] then
            asked[norm(sender)] = true
            pending[norm(sender)] = text
            StaticPopup_Show("DECORSYNC_PAIR", Ambiguate(sender, "none"), nil, sender)
        end
        return
    end
    HandleText(sender, text)
end

function ns.Progress()
    local parts = {}
    if ns.sendTotal > 0 then
        parts[#parts + 1] = ("Sending %d/%d"):format(ns.sendDone, ns.sendTotal)
    end
    for key, inc in pairs(incoming) do
        if GetTime() - inc.t > 60 then
            incoming[key] = nil
        else
            parts[#parts + 1] = ("Receiving %d/%d"):format(inc.got, inc.total)
        end
    end
    if #parts > 0 then return table.concat(parts, "   ") end
end

---------------------------------------------------------------------
-- Crafter side: record which decor your characters can make
---------------------------------------------------------------------
function ns.ScanRecipes(silent)
    if not (C_TradeSkillUI and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem) then
        if not silent then out("Recipe or housing support is missing in this game version.") end
        return 0
    end
    local ids = C_TradeSkillUI.GetAllRecipeIDs()
    if not ids or #ids == 0 then
        if not silent then out("Open a profession window first, then press this again.") end
        return 0
    end
    local prof = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    local profName = (prof and prof.professionName) or "?"
    local who = MyKey()
    local added = 0

    for _, rid in ipairs(ids) do
        local ri = C_TradeSkillUI.GetRecipeInfo(rid)
        if ri and ri.learned then
            local ok, od = pcall(C_TradeSkillUI.GetRecipeOutputItemData, rid)
            local ref = ok and type(od) == "table" and (od.itemID or od.hyperlink) or nil
            local outID = ok and type(od) == "table" and od.itemID or nil
            if not ref then
                local ok3, link = pcall(C_TradeSkillUI.GetRecipeItemLink, rid)
                if ok3 then ref = link end
            end
            if ref then
                local decor = CatalogInfo(ref)
                if decor then
                    local rec = DB.recipes[decor.name]
                    if not rec then rec = {}; DB.recipes[decor.name] = rec end
                    if not rec[who] then added = added + 1 end
                    rec[who] = profName
                    DB.recipeIDs[decor.name] = rid          -- needed to queue it in CraftSim
                    local exp = RecipeExpansion(rid, outID)
                    if exp then DB.expansions[decor.name] = exp end
                    -- remember what the recipe uses so lumber needs can be worked out
                    if C_TradeSkillUI.GetRecipeSchematic then
                        local ok2, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, rid, false)
                        if ok2 and type(sch) == "table" and sch.reagentSlotSchematics then
                            local rg = {}
                            for _, slot in ipairs(sch.reagentSlotSchematics) do
                                local r1 = slot.reagents and slot.reagents[1]
                                if r1 and r1.itemID then rg[r1.itemID] = (rg[r1.itemID] or 0) + (slot.quantityRequired or 0) end
                            end
                            DB.reagents[decor.name] = rg
                        end
                    end
                end
            end
        end
    end
    if not silent then out(("%s (%s): %d new decor recipes recorded."):format(who, profName, added)) end
    return added
end

---------------------------------------------------------------------
-- The "what to craft" list
---------------------------------------------------------------------
ns.search = ""

-- Expansions, oldest first. A recipe's profession info names its expansion
-- (e.g. "Khaz Algar Tailoring"), so the text is matched against these keywords.
ns.EXPANSIONS = {
    { "Classic",             { "classic" } },
    { "Burning Crusade",     { "outland", "burning crusade" } },
    { "Wrath of the Lich King", { "northrend", "wrath" } },
    { "Cataclysm",           { "cataclysm" } },
    { "Mists of Pandaria",   { "pandaria", "mists" } },
    { "Warlords of Draenor", { "draenor", "warlords" } },
    { "Legion",              { "legion" } },
    { "Battle for Azeroth",  { "kul tiran", "zandalari", "battle for azeroth" } },
    { "Shadowlands",         { "shadowlands" } },
    { "Dragonflight",        { "dragon isles", "dragonflight" } },
    { "The War Within",      { "khaz algar", "war within" } },
    { "Midnight",            { "midnight" } },
}
local EXP_BY_ID = {}      -- item expansionID (0 = Classic ...) -> label
for i, e in ipairs(ns.EXPANSIONS) do EXP_BY_ID[i - 1] = e[1] end
local EXP_ORDER = {}
for i, e in ipairs(ns.EXPANSIONS) do EXP_ORDER[e[1]] = i end

local function ExpFromText(text)
    text = (text or ""):lower()
    if text == "" then return nil end
    for i = #ns.EXPANSIONS, 1, -1 do                -- newest first so "Midnight" beats stray matches
        for _, kw in ipairs(ns.EXPANSIONS[i][2]) do
            if text:find(kw, 1, true) then return ns.EXPANSIONS[i][1] end
        end
    end
end

-- sort position of an expansion label (unknown ones go last)
function ns.ExpOrder(label) return EXP_ORDER[label or ""] or 99 end

-- which expansion a recipe belongs to: profession info first, item's own expansion as backup
local function RecipeExpansion(rid, itemID)
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID then
        local ok, pi = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, rid)
        if ok and type(pi) == "table" then
            local lab = ExpFromText((pi.expansionName or "") .. " " .. (pi.professionName or ""))
            if lab then return lab end
        end
    end
    if itemID and C_Item and C_Item.GetItemInfo then
        local ok, id = pcall(function() return select(15, C_Item.GetItemInfo(itemID)) end)
        if ok and id and EXP_BY_ID[id] then return EXP_BY_ID[id] end
    end
end

-- Expansion for a decor name, best source first:
--   1. DecorExpansions.lua (fixed list)   2. the recipe's profession (recorded when a
--   profession window is opened)   3. the item's own expansion as the game reports it
-- Source 3 is read for every item in DecorIDs.lua, so nobody has to log into crafters.
local function NameKey(name) return (tostring(name or ""):lower():gsub("[^%w]", "")) end

function ns.ExpansionOf(name)
    local k = NameKey(name)
    return (ns.StaticExpansion and ns.StaticExpansion[k])
        or (ns.DB.expansions and ns.DB.expansions[name])
        or (ns.DB.itemExp and ns.DB.itemExp[k])
end

local function NoteItemExpansion(id)
    if not (C_Item and C_Item.GetItemInfo) then return false end
    local ok, name, expID = pcall(function()
        local info = { C_Item.GetItemInfo(id) }
        return info[1], info[15]
    end)
    if not (ok and name) then return false end
    local label = expID and EXP_BY_ID[expID]
    if label then ns.DB.itemExp[NameKey(name)] = label end
    return true
end

-- asks the game about every decor item ID; answers arrive through GET_ITEM_INFO_RECEIVED
function ns.LoadItemExpansions()
    for _, id in ipairs(ns.DecorIDList or {}) do
        if not NoteItemExpansion(id) and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(id)
        end
    end
end

local function ByExpThenName(a, b)
    local oa, ob = ns.ExpOrder(a.exp), ns.ExpOrder(b.exp)
    if oa ~= ob then return oa < ob end
    return a.name < b.name
end

local function CraftersText(crafters)
    local who = {}
    for char, prof in pairs(crafters or {}) do who[#who + 1] = ("%s (%s)"):format(char, prof) end
    table.sort(who)
    return table.concat(who, ", ")
end

function ns.GetNeeded()
    local r = DB.received
    if not r then return {}, "nolist" end
    if not next(DB.recipes) then return {}, "norecipes" end
    local me = MyKey()
    local list = {}
    for name, crafters in pairs(DB.recipes) do
        local have = r.owned[name] or 0
        if have < DB.target and (not DB.onlyMe or crafters[me]) and (ns.search == "" or name:lower():find(ns.search, 1, true)) then
            local lum, rg = nil, DB.reagents and DB.reagents[name]
            if rg then
                lum = {}
                for id, q in pairs(rg) do
                    local ln = LumberNameForItem(id)
                    if ln then lum[ln] = (lum[ln] or 0) + q * (DB.target - have) end
                end
            end
            list[#list + 1] = { name = name, have = have, need = DB.target - have, crafters = CraftersText(crafters),
                                exp = ns.ExpansionOf(name), lumber = lum }
        end
    end
    table.sort(list, ByExpThenName)
    return list, "ok"
end

-- every decor you hold to sell (any amount above 0), and where it is
function ns.GetStock()
    local r = DB.received
    if not r then return {} end
    local me = MyKey()
    local list = {}
    for name, have in pairs(r.owned) do
        local crafters = DB.recipes[name]
        if have > 0
            and (not DB.onlyMe or (crafters and crafters[me]))
            and (ns.search == "" or name:lower():find(ns.search, 1, true)) then
            local wh = r.where and r.where[name]
            local parts = {}
            for _, l in ipairs(wh or {}) do parts[#parts + 1] = ("%s %d"):format(l[1], l[2]) end
            list[#list + 1] = { name = name, have = have, where = wh, whereText = table.concat(parts, ", "),
                                crafters = CraftersText(crafters), exp = ns.ExpansionOf(name) }
        end
    end
    table.sort(list, ByExpThenName)
    return list
end

-- CraftSim hand-off ---------------------------------------------------
-- Adds everything this character can craft and is short of (Want minus Owned)
-- to CraftSim's Craft Queue. Uses CraftSim's own classes (there is no
-- documented public API for this), so every call is guarded with pcall.
local function GetCraftSim()
    local api = _G.CraftSimAPI
    if type(api) == "table" and type(api.GetCraftSim) == "function" then
        local ok, cs = pcall(api.GetCraftSim)
        if ok and type(cs) == "table" then return cs end
    end
    if type(_G.CraftSim) == "table" then return _G.CraftSim end
end

local importing = false
function ns.ImportToCraftSim()
    if importing then return out("Import already running, give it a moment.") end
    local CS = GetCraftSim()
    local queue = CS and CS.CRAFTQ and CS.CRAFTQ.craftQueue
    if not (CS and CS.RecipeData and queue and queue.AddRecipe) then
        return out("CraftSim's craft queue isn't available. Is CraftSim installed and enabled on this account? " ..
                   "(If it is, its internals may have changed - /decorsync debug on and try again.)")
    end
    local r = DB.received
    if not r then return out("No decor list yet. Press 'Get decor list' first.") end
    if not next(DB.recipes) then return out("No decor recipes recorded yet. Open each profession window on each crafter.") end

    local me = MyKey()
    local todo, noID = {}, 0
    for name, crafters in pairs(DB.recipes) do
        local have = r.owned[name] or 0
        if have < DB.target and crafters[me] then
            local rid = DB.recipeIDs and DB.recipeIDs[name]
            if rid then
                todo[#todo + 1] = { name = name, rid = rid, need = DB.target - have }
            else
                noID = noID + 1
            end
        end
    end
    if #todo == 0 then
        if noID > 0 then
            return out(("%d needed recipes have no recipe ID saved yet. Open each profession window on this character once, then try again."):format(noID))
        end
        return out(me .. " has nothing to craft for the list (nothing short, or no matching recipes).")
    end
    table.sort(todo, function(a, b) return a.name < b.name end)

    importing = true
    out(("Importing %d recipes into the CraftSim queue..."):format(#todo))
    local i, added, updated, failed = 0, 0, 0, {}
    local function finish()
        importing = false
        pcall(function() queue:CacheQueueItems() end)
        pcall(function() CS.CRAFTQ.UI:UpdateDisplay() end)
        local msg = ("CraftSim queue: %d added, %d updated"):format(added, updated)
        if noID > 0 then msg = msg .. (", %d skipped (no recipe ID saved yet)"):format(noID) end
        if #failed > 0 then msg = msg .. (", %d failed"):format(#failed) end
        out(msg .. ".")
        for k = 1, math.min(3, #failed) do print("  " .. failed[k]) end
        if #failed > 0 then print("  Failed ones usually need the profession window open on this character.") end
    end
    local function step()
        local n = 0
        while i < #todo and n < 3 do               -- a few per tick so the game doesn't freeze
            i, n = i + 1, n + 1
            local t = todo[i]
            local ok, err = pcall(function()
                local rd = CS.RecipeData({ recipeID = t.rid })
                if not rd or not rd.recipeName or not rd.reagentData then
                    error("recipe data not available", 0)
                end
                local existing = queue.FindRecipe and queue:FindRecipe(rd)
                if existing then
                    queue:SetAmount(rd, t.need, false)      -- set, not add, so importing twice doesn't double it
                    updated = updated + 1
                else
                    queue:AddRecipe({ recipeData = rd, amount = t.need })
                    added = added + 1
                end
            end)
            if not ok then failed[#failed + 1] = t.name .. ": " .. tostring(err):sub(1, 120) end
        end
        if i < #todo then C_Timer.After(0.05, step) else finish() end
    end
    step()
end

local EXP_SHORT = {
    ["Classic"] = "Classic", ["Burning Crusade"] = "TBC", ["Wrath of the Lich King"] = "WotLK",
    ["Cataclysm"] = "Cata", ["Mists of Pandaria"] = "MoP", ["Warlords of Draenor"] = "WoD",
    ["Legion"] = "Legion", ["Battle for Azeroth"] = "BfA", ["Shadowlands"] = "SL",
    ["Dragonflight"] = "DF", ["The War Within"] = "TWW", ["Midnight"] = "Midnight",
}

local function CurrentProfName()
    if not ns.profOpen then return nil end
    local p = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    return p and p.professionName or nil
end

-- Lumber needed to cover the Want shortfall of recorded decor:
--   all  = every decor recipe recorded (any crafter)
--   prof = only decor of the profession window that is open on this character (nil if none open)
-- Returns nil until a decor list has been received and recipes have been scanned.
function ns.LumberNeeds()
    local r = DB.received
    if not r or not next(DB.reagents) then return nil end
    local me, pname = MyKey(), CurrentProfName()
    local all, prof = {}, pname and {} or nil
    for name, crafters in pairs(DB.recipes) do
        local have = r.owned[name] or 0
        local rg = DB.reagents[name]
        if rg and have < DB.target then
            local need = DB.target - have
            for id, q in pairs(rg) do
                local ln = LumberNameForItem(id)
                if ln then
                    all[ln] = (all[ln] or 0) + q * need
                    if prof and crafters[me] == pname then prof[ln] = (prof[ln] or 0) + q * need end
                end
            end
        end
    end
    return all, prof, pname
end

-- Lumber across this account: every character's bags and bank, plus the warband bank.
function ns.GetLumber()
    local per = {}                        -- lumber name -> { total, parts = {...} }
    local function add(name, label, c)
        if not c or c <= 0 then return end
        local e = per[name]
        if not e then e = { total = 0, parts = {} }; per[name] = e end
        e.total = e.total + c
        e.parts[#e.parts + 1] = { label, c }
    end
    local chars = {}
    for key in pairs(DB.inv) do chars[#chars + 1] = key end
    table.sort(chars)
    for _, key in ipairs(chars) do
        local lb = DB.inv[key].lumber
        if lb then
            local who = ShortName(key)
            for name, c in pairs(lb.bags or {}) do add(name, who .. " (bags)", c) end
            for name, c in pairs(lb.bank or {}) do add(name, who .. " (bank)", c) end
        end
    end
    for name, c in pairs((DB.warband and DB.warband.lumber) or {}) do add(name, "warband bank", c) end

    local names, seen = {}, {}
    for _, l in ipairs(ns.LUMBER) do names[#names + 1] = l[1]; seen[l[1]] = true end
    local extra = {}
    for name in pairs(per) do if not seen[name] then extra[#extra + 1] = name end end
    table.sort(extra)
    for _, n in ipairs(extra) do names[#names + 1] = n end

    local list, total, owned = {}, 0, {}
    local needAll, needProf = ns.LumberNeeds()
    for _, name in ipairs(names) do
        local e = per[name]
        local known = LUMBER_BY_KEY[LKey(name)]
        local exp = known and known[2]
        local parts, lines = {}, {}
        for _, p in ipairs(e and e.parts or {}) do
            parts[#parts + 1] = ("%s %d"):format(p[1], p[2])
            lines[#lines + 1] = ("%s: %d"):format(p[1], p[2])
        end
        local t = e and e.total or 0
        if ns.warbandBlocked then lines[#lines + 1] = "Warband bank: no access right now (last known numbers shown)" end
        list[#list + 1] = {
            name = exp and (name .. "  |cff7a8394" .. (EXP_SHORT[exp] or exp) .. "|r") or name,
            total = t,
            needAll = needAll and (needAll[name] or 0) or nil,
            needProf = needProf and (needProf[name] or 0) or nil,
            text = #parts > 0 and table.concat(parts, ", ") or "none recorded",
            tip = #lines > 0 and table.concat(lines, "\n") or "None recorded on any character yet.",
        }
        total = total + t
        owned[name] = t
    end
    return list, total, owned
end

function ns.Info()
    local n = 0
    for _ in pairs(DB.recipes) do n = n + 1 end
    return n, DB.received
end

---------------------------------------------------------------------
-- Actions used by the UI
---------------------------------------------------------------------
function ns.SetPartner(name)
    name = ((name or ""):gsub("%s", ""))
    if name == "" then
        out("Type the name of a character on your other account first (Name-Realm).")
        return false
    end
    ns.Trust(name)
    out("Other account's character set to " .. name .. ".")
    return true
end

local function needPartner()
    if DB.partner then return DB.partner end
    out("Type your other account's character name first, then press Connect.")
end

function ns.Send()
    local p = needPartner()
    if p then SendList(p) end
end

function ns.Request()
    local p = needPartner()
    if not p then return end
    Enqueue(p, "Q|1")
    requestedAt = time()
    out("Asked " .. p .. " to send their decor list...")
    C_Timer.After(30, function()
        if requestedAt and time() - requestedAt >= 29 then
            requestedAt = nil
            out(p .. " didn't answer. Is that character online with DecorSync installed?")
        end
    end)
end

function ns.Ping()
    local p = needPartner()
    if not p then return end
    local token = {}
    pingToken = token
    Enqueue(p, "T|1")
    out("Trying to reach " .. p .. "...")
    C_Timer.After(15, function()
        if pingToken == token then
            pingToken = nil
            out("No reply from " .. p .. ". Check the spelling (Name-Realm), that they're online, and that DecorSync is installed there.")
        end
    end)
end

local function Dump()
    out("Running a scan, then printing the raw fields of the first entry...")
    ScanOwned(function(owned, n)
        out(("Scan found %d owned entries."):format(n))
        local res = searcher and searcher:GetCatalogSearchResults() or {}
        local info = res[1] and C_HousingCatalog.GetCatalogEntryInfo(res[1])
        if not info then return out("No entries came back at all.") end
        for k, v in pairs(info) do print("  ", k, tostring(v)) end
    end)
end

local function Matches(name, text)
    return name:lower():find(text, 1, true) ~= nil
end

-- /decorsync find <text>: shows every number this addon has for a decor name
local function Find(text)
    text = (text or ""):lower()
    if text == "" then return out("Type part of a decor name, e.g. /decorsync find narache") end
    local any = false
    print("|cff33ccffDecorSync find:|r \"" .. text .. "\"")
    do
        local hits = {}
        for _, n in ipairs(ns.DecorNameList or {}) do
            if n:lower():find(text, 1, true) then hits[#hits + 1] = n end
        end
        print("  name database: " .. (#hits > 0 and table.concat(hits, ", ") or "NOT in the decor name database"))
    end

    for key, inv in pairs(DB.inv) do
        for _, sect in ipairs(SECTIONS) do
            for name, c in pairs(inv[sect] or {}) do
                if Matches(name, text) then
                    any = true
                    print(("  %s: %d in %s of %s"):format(name, c, SECTION_LABEL[sect], key))
                end
            end
        end
    end
    for name, c in pairs((DB.warband and DB.warband.items) or {}) do
        if Matches(name, text) then
            any = true
            print(("  %s: %d in the warband bank"):format(name, c))
        end
    end
    for gname, g in pairs(DB.guild or {}) do
        for _, items in pairs(g.tabs or {}) do
            for name, c in pairs(items) do
                if Matches(name, text) then
                    any = true
                    print(("  %s: %d in guild bank <%s> %s"):format(name, c, gname, DB.includeGuild and "" or "(NOT counted: setting is off)"))
                end
            end
        end
    end
    for _, ch in pairs(ReadTSM() or {}) do
        for name, c in pairs(ch.items) do
            if Matches(name, text) then
                any = true
                print(("  %s: %d on %s according to TSM"):format(name, c, ch.label))
            end
        end
    end
    if DB.received then
        for name, c in pairs(DB.received.owned) do
            if Matches(name, text) then
                any = true
                print(("  %s: list received from %s says %d owned"):format(name, tostring(DB.received.from), c))
            end
        end
    end
    for name, crafters in pairs(DB.recipes) do
        if Matches(name, text) then
            any = true
            local who = {}
            for char in pairs(crafters) do who[#who + 1] = char end
            table.sort(who)
            print(("  %s: craftable by %s"):format(name, table.concat(who, ", ")))
        end
    end

    ScanOwned(function()
        local res = searcher and searcher:GetCatalogSearchResults() or {}
        local seen = false
        for _, entryID in ipairs(res) do
            local info = C_HousingCatalog.GetCatalogEntryInfo(entryID)
            if info and info.name and Matches(info.name, text) then
                seen, any = true, true
                local bits = {}
                for k, v in pairs(info) do
                    if type(v) == "number" then bits[#bits + 1] = k .. "=" .. v end
                end
                table.sort(bits)
                print(("  housing catalog (learned/placed, NOT counted): %s  %s"):format(info.name, table.concat(bits, " ")))
            end
        end
        if not seen then print("  housing catalog: no owned entry matches on this account") end
        if not any then print("  (nothing known about that name)") end
    end)
end

local function ItemProbe(arg)
    local id = tonumber(arg)
    if not id then return out("Type an item ID, e.g. /decorsync item 245535") end
    print("|cff33ccffDecorSync item:|r " .. id)
    local fn = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem
    if not fn then return print("  no housing catalog in this game version") end
    for _, ref in ipairs({ id, "item:" .. id }) do
        for _, owned in ipairs({ true, false }) do
            local ok, info = pcall(fn, ref, owned)
            local what = (not ok) and ("error: " .. tostring(info))
                or (type(info) == "table" and (info.name or "table without a name") or tostring(info))
            print(("  lookup(%s, %s) -> %s"):format(tostring(ref), tostring(owned), what))
        end
    end
    local final = CatalogInfo(id)
    print("  in decor database: ID " .. (ns.IsDecorItem(id) and "YES" or "no") .. ", name " ..
        ((final and ns.IsDecorName(final.name)) and "YES" or "no") .. "  (needs one YES to be counted)")
    print("  addon resolves it as: " .. (final and (final.name .. (final.fromItemName and " (from item name)" or "")) or "NOTHING"))
    if C_Item then
        local cls = C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id))
        print(("  item name: %s   item class: %s"):format(tostring(C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)), tostring(cls)))
        if C_Item.GetItemCount then
            print("  carried by this character (bags + bank + warband): " .. tostring(C_Item.GetItemCount(id, true, false, true, true)))
        end
    end
    local db = _G.TradeSkillMasterDB
    if type(db) == "table" then
        local found = false
        for key, tbl in pairs(db) do
            if type(key) == "string" and type(tbl) == "table" and key:find("^s@") then
                local c = tbl["i:" .. id] or tbl[id]
                if type(c) == "number" and c > 0 then
                    found = true
                    print(("  TSM: %d in %s"):format(c, key:gsub("@internalData", "")))
                end
            end
        end
        if not found then print("  TSM: no character has it") end
    end
end

local function PrintTSM()
    wipe(tsmMiss)
    local db = _G.TradeSkillMasterDB
    if type(db) ~= "table" then
        return out("TradeSkillMasterDB isn't loaded. Is TradeSkillMaster installed and enabled on this account?")
    end
    local keys, inv = 0, 0
    for key in pairs(db) do
        keys = keys + 1
        if type(key) == "string" and key:find("internalData@%w+Quantity$") then inv = inv + 1 end
    end
    print(("  TradeSkillMasterDB found: %d keys, %d look like per-character inventory"):format(keys, inv))
    local chars = ReadTSM()
    if not chars then
        print("  No decor found in TSM's data. First few keys, to see the layout:")
        local shown = 0
        for key in pairs(db) do
            print("    " .. tostring(key):sub(1, 90))
            shown = shown + 1
            if shown >= 8 then break end
        end
        return
    end
    for _, ch in pairs(chars) do
        local parts = {}
        for sect, n in pairs(ch.sections) do parts[#parts + 1] = sect .. " " .. n end
        table.sort(parts)
        print(("  %s: %s"):format(ch.label, #parts > 0 and table.concat(parts, ", ") or "no decor"))
    end
end

local function PrintInventory(arg)
    if arg == "clear" then
        DB.inv, DB.warband, DB.guild = {}, {}, {}
        ScanBags()
        return out("Remembered bag/bank/mail/auction contents cleared (this character's bags re-read).")
    end
    local rows = 0
    for key, inv in pairs(DB.inv) do
        local parts = {}
        for _, sect in ipairs(SECTIONS) do
            local n = 0
            for _, c in pairs(inv[sect] or {}) do n = n + c end
            parts[#parts + 1] = ("%s %d"):format(SECTION_LABEL[sect], n)
        end
        print(("  %s: %s  (updated %s)"):format(key, table.concat(parts, ", "), ns.timeAgo(inv.at)))
        rows = rows + 1
    end
    if DB.warband and DB.warband.items then
        local n = 0
        for _, c in pairs(DB.warband.items) do n = n + c end
        print(("  warband bank: %d  (updated %s)"):format(n, ns.timeAgo(DB.warband.at)))
        rows = rows + 1
    end
    for gname, g in pairs(DB.guild or {}) do
        local n = 0
        for _, items in pairs(g.tabs or {}) do
            for _, c in pairs(items) do n = n + c end
        end
        print(("  guild bank <%s>: %d  (updated %s)  %s"):format(gname, n, ns.timeAgo(g.at),
            DB.includeGuild and "[included]" or "[not included - setting is off]"))
        rows = rows + 1
    end
    if rows == 0 then out("No bag/bank/mail/auction contents remembered yet.") end
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")

local recipePending, recipeScheduled = false, false

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        DecorSyncDB = DecorSyncDB or {}
        DB = DecorSyncDB
        ns.DB = DB
        DB.target = DB.target or 1
        DB.recipes = DB.recipes or {}
        DB.recipeIDs = DB.recipeIDs or {}
        DB.expansions = DB.expansions or {}
        DB.itemExp = DB.itemExp or {}
        DB.reagents = DB.reagents or {}
        DB.collapsed = DB.collapsed or {}
        DB.trusted = DB.trusted or {}
        DB.inv = DB.inv or {}
        DB.warband = DB.warband or {}
        DB.guild = DB.guild or {}
        DB.minimap = DB.minimap or { angle = 215 }
        DB.club = nil                                    -- community mode was dropped
        if (DB.recipesVersion or 0) < 2 then             -- recipes now store the realm too
            DB.recipes = {}
            DB.recipesVersion = 2
        end
        if DB.partner then DB.trusted[norm(DB.partner)] = true end
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:RegisterEvent("TRADE_SKILL_SHOW")
        self:RegisterEvent("TRADE_SKILL_CLOSE")
        self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- inventory tracking; pcall so one unknown event name can't break loading
        for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE",
                              "OWNED_AUCTIONS_UPDATED",
                              "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
                              "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
                              "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
                              "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
                              "GUILDBANKBAGSLOTS_CHANGED",
                              "GET_ITEM_INFO_RECEIVED" }) do
            pcall(self.RegisterEvent, self, ev)
        end
        if ns.InitUI then ns.InitUI() end
    elseif event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif event == "TRADE_SKILL_SHOW" then
        recipePending = true
        ns.profOpen = true
        Later("profchg", 2, Changed)
    elseif event == "TRADE_SKILL_CLOSE" then
        ns.profOpen = false
        Changed()
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        if recipePending and not recipeScheduled then
            recipeScheduled = true
            C_Timer.After(1.5, function()
                recipePending, recipeScheduled = false, false
                local ok, added = pcall(ns.ScanRecipes, true)
                if ok and added and added > 0 then
                    out(("Recorded %d new decor recipes for %s."):format(added, MyKey()))
                end
            end)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        Later("bags", 1, ScanBags)
        if bankOpen then Later("bank", 1, ScanBank) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local id = ...
        if ns.DecorIDs and ns.DecorIDs[id] and NoteItemExpansion(id) then Later("expchg", 2, Changed) end
        if pendingItems[id] then pendingItems[id] = nil; Later("lumchg", 1, Changed) end
    elseif event == "MAIL_INBOX_UPDATE" then
        Later("mail", 0.5, ScanMail)
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        -- passive: only reads what the game / TSM already fetched. DecorSync never sends
        -- its own auction queries, so it can't throttle TSM's posting.
        Later("ah", 3, ScanAuctions)
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        Later("bank", 1, ScanBank)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "GUILDBANKFRAME_OPENED" then
        guildOpen = true
        Later("guild", 1, ScanGuildBank)
    elseif event == "GUILDBANKFRAME_CLOSED" then
        guildOpen = false
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if guildOpen and not guildBusy then Later("guildtab", 1, RescanCurrentGuildTab) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local t = ...
        local P = Enum and Enum.PlayerInteractionType
        if P and P.GuildBanker and t == P.GuildBanker then
            guildOpen = (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
            if guildOpen then Later("guild", 1, ScanGuildBank) end
        end
        if P and (t == P.Banker or t == P.AccountBanker) then
            bankOpen = (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
            if bankOpen then Later("bank", 1, ScanBank) end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Later("bags", 3, ScanBags)
        Later("itemexp", 5, ns.LoadItemExpansions)
        local isLogin = ...
        if isLogin and DB.autoRequest and DB.partner and DB.role ~= "seller" then
            C_Timer.After(15, function() Enqueue(DB.partner, "Q|1") end)
        end
    end
end)

---------------------------------------------------------------------
-- Slash commands (everything is also in the window)
---------------------------------------------------------------------
local function PrintNeeded()
    local list, state = ns.GetNeeded()
    if state == "nolist" then return out("No decor list yet. Open the window (/decorsync) and press 'Get decor list'.") end
    if state == "norecipes" then return out("No decor recipes recorded yet. Open each profession window on each crafter.") end
    if #list == 0 then return out("Nothing needed. You're stocked!") end
    for _, e in ipairs(list) do print(("  %s x%d  -  %s"):format(e.name, e.need, e.crafters)) end
end

SLASH_DECORSYNC1 = "/decorsync"
SlashCmdList.DECORSYNC = function(msg)
    if not DB then return end
    local cmd, arg = msg:match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        if ns.Toggle then ns.Toggle() end
    elseif cmd == "needed" then PrintNeeded()
    elseif cmd == "debug" then
        DB.debug = (arg:lower() ~= "off")
        out("Debug " .. (DB.debug and "ON" or "OFF"))
    elseif cmd == "minimap" then
        DB.minimap.hide = not DB.minimap.hide
        if ns.UpdateMinimap then ns.UpdateMinimap() end
        out("Minimap button " .. (DB.minimap.hide and "hidden" or "shown"))
    elseif cmd == "reset" then
        DB.recipes, DB.recipeIDs, DB.expansions, DB.reagents = {}, {}, {}, {}
        out("Recipe list cleared.")
    elseif cmd == "dump" then Dump()
    elseif cmd == "find" then Find(arg)
    elseif cmd == "inv" then PrintInventory(arg:lower())
    elseif cmd == "guild" then
        local a = arg:lower()
        if a == "on" or a == "off" then
            ns.SetIncludeGuild(a == "on")
        else
            out("Guild banks are " .. (DB.includeGuild and "INCLUDED" or "left out") .. ". Use /decorsync guild on|off")
        end
    elseif cmd == "craftsim" then ns.ImportToCraftSim()
    elseif cmd == "expansions" then
        local counts, total = {}, 0
        for _, lab in pairs(DB.itemExp) do counts[lab] = (counts[lab] or 0) + 1; total = total + 1 end
        print(("  %d decor have an expansion from the game's item data:"):format(total))
        for _, e in ipairs(ns.EXPANSIONS) do
            if counts[e[1]] then print(("    %s: %d"):format(e[1], counts[e[1]])) end
        end
        if arg:lower() == "list" then
            local lines = {}
            for k, lab in pairs(DB.itemExp) do lines[#lines + 1] = ("%s = %s"):format(k, lab) end
            table.sort(lines)
            for _, l in ipairs(lines) do print("  " .. l) end
        else
            print("  /decorsync expansions list  prints every one (check them; fix wrong ones in DecorExpansions.lua)")
        end
    elseif cmd == "lumber" then
        local list = ns.GetLumber()
        for _, e in ipairs(list) do
            if e.total > 0 then print(("  %s x%d  -  %s"):format((e.name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), e.total, e.text)) end
        end
        if ns.warbandBlocked then print("  (warband bank: no access, last known numbers)") end
    elseif cmd == "tsm" then PrintTSM()
    elseif cmd == "item" then ItemProbe(arg)
    else
        out("Type /decorsync to open the window. Extras: needed, find <name>, item <id>, inv [clear], tsm, expansions [list], lumber, craftsim, guild on|off, debug on|off, minimap, reset, dump")
    end
end
