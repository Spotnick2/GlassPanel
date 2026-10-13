-- Plugins/Reagents/Reagents.lua: your class reagents, the ones you pick, in
-- your order (#68). The chooser is Currencies' (#47); the list is a table
-- per class, since nothing in the client says which items a class uses.
--
-- Forever (70338 dump): C_Item.GetItemCount(id) for the count (bags only),
-- C_Item.GetItemInfoInstant(id)'s icon (no item data needed), else
-- C_Item.GetItemIconByID(id), for the icon, C_Item.GetItemNameByID(id) for
-- the name (nil until the item's data is loaded: requested once, on our own
-- frame, as GearScore does; an answered id is never requested again). The
-- global GetItemInfo is absent. Only the tooltip and the chooser ask for
-- names: the bar shows icons and counts.
--
-- UNMEASURED: what the client answers for an id it doesn't serve. A class id
-- with no icon (or the question-mark icon, 134400) is pending, not unknown:
-- its data is requested and it's kept, drawn with the question mark; only a
-- failed load (ITEM_DATA_LOAD_RESULT false) with still no icon leaves it out.
-- A failed load of an id with an icon only costs the name.
--
-- Ammo (#66) and the warlock's shards and stones (#67) have their own
-- plugins and aren't listed here. Picks are per character
-- (## SavedVariablesPerCharacter). Never chosen: up to 3 of the class's
-- reagents the character carries, saved the first time they're found once
-- bags have settled, so the bar doesn't change by itself. Every number
-- through API.Plain: a secret count is a grey "?", never a guess.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

-- Item ids by class file name, in the chooser's order. Poisons are in the
-- client's own consumables list (70009); the rest are Vanilla's reagents
-- (Informant's item data says class Reagent), not yet seen on this client:
-- an id it doesn't know is left out at runtime.
local CLASS = {
    ROGUE = {
        5140,                                       -- Flash Powder
        5530,                                       -- Blinding Powder (unverified)
        6947, 6949, 6950, 8926, 8927, 8928,         -- Instant Poison I-VI
        2892, 2893, 8984, 8985, 20844,              -- Deadly Poison I-V
        3775, 3776,                                 -- Crippling Poison I-II
        5237, 6951, 9186,                           -- Mind-numbing Poison I-III
        10918, 10920, 10921, 10922,                 -- Wound Poison I-IV
    },
    MAGE    = { 17020, 17031, 17032, 17056 },       -- Arcane Powder, Runes of Teleportation and Portals, Light Feather
    PRIEST  = { 17028, 17029, 17056 },              -- Holy Candle, Sacred Candle, Light Feather
    SHAMAN  = { 17030, 17058, 17057 },              -- Ankh, Fish Oil, Shiny Fish Scales
    PALADIN = { 17033, 21177 },                     -- Symbol of Divinity, Symbol of Kings
    DRUID   = { 17021, 17026,                       -- Wild Berries, Wild Thornroot
                17034, 17035, 17036, 17037, 17038 }, -- Maple, Stranglethorn, Ashwood, Hornbeam, Ironwood Seed
    WARLOCK = { 5565, 16583 },                      -- Infernal Stone, Demonic Figurine
}
-- A class with no list (hunter, warrior) gets no block. A class that can't be
-- read now gets the block, which stays empty while it can't.
local _, classFile = UnitClass("player")
classFile = P(classFile)
if type(classFile) == "string" and not CLASS[classFile] then return end

local DEFAULT_MAX = 3   -- first-run picks: up to this many carried
local QUESTION_MARK = 134400   -- the icon of an item with no data

local function db()
    local d = rawget(_G, "GlassPanelReagentsDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelReagentsDB = d
    end
    if d.order ~= nil and type(d.order) ~= "table" then d.order = nil end
    return d
end

local function classList()
    local _, file = UnitClass("player")
    file = P(file)
    return type(file) == "string" and CLASS[file] or {}
end

--------------------------------------------------------------------------------
-- Names load late: requested only while the client says the item isn't
-- cached (GearScore's guard), once, answered on our own frame, which listens
-- only while one of ours is pending (the load events fire for every item).
-- An answered id (loaded or failed) is never requested again this session:
-- one that loads but stays nameless would otherwise loop (request, load,
-- repaint, tooltip, request). It keeps its icon and count, named "item <id>".
-- Icons go through the same loader: a class id with no icon is requested
-- too, and `failed` holds the ids whose load failed with still no icon.
--------------------------------------------------------------------------------

local pending, answered, failed = {}, {}, {}
local knownIcon
local LOAD_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
local loader = CreateFrame("Frame")
local listening = false
local refreshWindowSoon
local function listen(on)
    if on == listening then return end
    listening = on
    for _, e in ipairs(LOAD_EVENTS) do
        if on then API.RegisterEvent(loader, e, "Reagents") else loader:UnregisterEvent(e) end
    end
end
loader:SetScript("OnEvent", function(_, _, rawId, success)
    local id = P(rawId)
    if id and pending[id] then
        pending[id] = nil
        answered[id] = true
        if P(success) == false and not knownIcon(id) then failed[id] = true end
        GlassPanel.Refresh("reagents")
        refreshWindowSoon()
    end
    if next(pending) == nil then listen(false) end
end)

local function request(id)
    if pending[id] or answered[id] then return end
    local ok, cached = pcall(C_Item.IsItemDataCachedByID, id)
    if ok and P(cached) == true then return end   -- loaded: a missing name won't come
    pending[id] = true
    C_Item.RequestLoadItemDataByID(id)
    listen(true)
end

-- The id's icon, or nil while the client has none for it: GetItemInfoInstant
-- needs no item data, GetItemIconByID may.
local function usable(icon)
    icon = P(icon)
    if icon == QUESTION_MARK or (type(icon) ~= "number" and type(icon) ~= "string") then return nil end
    return icon
end
knownIcon = function(id)
    local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, id)
    icon = ok and usable(icon) or nil
    if icon then return icon end
    local okI, byId = pcall(C_Item.GetItemIconByID, id)
    return okI and usable(byId) or nil
end

local function isClassId(id)
    for _, v in ipairs(classList()) do
        if v == id then return true end
    end
    return false
end

local function count(id)
    local ok, n = pcall(C_Item.GetItemCount, id)
    n = ok and P(n) or nil
    return type(n) == "number" and n or nil
end

-- One item by id: { id, name (nil while loading, or when not asked for),
-- count (nil = unreadable), icon (nil while loading) }, or nil when the
-- client doesn't know the id (a class id: only once its load failed).
-- withName: read the name, and request it while it's missing.
local function info(id, withName)
    local icon = knownIcon(id)
    if not icon then
        if failed[id] or not isClassId(id) then return nil end
        request(id)
    end
    local name
    if withName then
        local okN, n = pcall(C_Item.GetItemNameByID, id)
        name = okN and P(n) or nil
        if type(name) ~= "string" or name == "" then
            name = nil
            request(id)
        end
    end
    return { id = id, name = name, count = count(id), icon = icon }
end

-- The class's reagents, in the table's order, named (the chooser's list),
-- but for those whose load failed.
local function available()
    local list = {}
    for _, id in ipairs(classList()) do list[#list + 1] = info(id, true) end
    return list
end

-- Bags fill after PLAYER_ENTERING_WORLD: the first BAG_UPDATE_DELAYED of the
-- session says the counts are settled.
local bagsSettled = false

-- The picked ids, in order (each once). Never chosen: the carried ones,
-- saved once bags are settled so they stay put (until then, worked out
-- again each time). The search reads counts first, so an id that isn't
-- carried costs one call.
local function picks()
    local d = db()
    if not d.order then
        local out = {}
        for _, id in ipairs(classList()) do
            if #out >= DEFAULT_MAX then break end
            local n = count(id)
            if n and n > 0 and not failed[id] then out[#out + 1] = id end
        end
        -- Nothing carried yet, or a partial read: decide later.
        if #out == 0 or not bagsSettled then return out end
        d.order = out
    end
    local seen, out = {}, {}
    for _, id in ipairs(d.order) do
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local function setPicks(order)
    db().order = order
    GlassPanel.Refresh("reagents")
end

-- An icon still loading is drawn as the question mark.
local function icon(c, size)
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(c.icon or QUESTION_MARK), size, size)
end

-- None left is red: the spell won't cast.
local function amount(c)
    if c.count == nil then return "|cff888888?|r" end
    if c.count == 0 then return "|cffff40400|r" end
    return BreakUpLargeNumbers(c.count)
end

local function name(c)
    return c.name or ("|cff888888item " .. c.id .. "|r")
end

--------------------------------------------------------------------------------
-- The chooser window: the class's reagents, a checkbox to show each, Up/Down
-- to order the shown ones. (A copy of Currencies' chooser; sharing it, and
-- the name loader with GearScore, is #74.)
--------------------------------------------------------------------------------

local win, rows = nil, {}
local ROW_W, ROW_H = 340, 26

-- The rows: the shown ones first, in order (only those the client resolves),
-- then the rest in the class's order. `shown` is that first part, as ids;
-- `unresolved` the saved ids the client doesn't resolve right now.
local function entries()
    local avail = available()
    local byId = {}
    for _, c in ipairs(avail) do byId[c.id] = c end
    local list, shown, used, unresolved = {}, {}, {}, {}
    for _, id in ipairs(picks()) do
        local c = byId[id] or info(id, true)
        if c then
            list[#list + 1] = c
            shown[#shown + 1] = id
            used[id] = true
        else
            unresolved[#unresolved + 1] = id
        end
    end
    for _, c in ipairs(avail) do
        if not used[c.id] then list[#list + 1] = c end
    end
    return list, shown, used, unresolved
end

local refreshWindow

-- Write `shown` (the visible order) back, keeping the unresolved saved ids
-- at the end, untouched.
local function saveShown(shown, unresolved)
    local keep = {}
    for _, id in ipairs(shown) do keep[#keep + 1] = id end
    for _, id in ipairs(unresolved) do keep[#keep + 1] = id end
    setPicks(keep)
    refreshWindow()
end

local function move(id, step)
    local _, shown, _, unresolved = entries()
    for i, v in ipairs(shown) do
        if v == id then
            local j = i + step
            if j >= 1 and j <= #shown then shown[i], shown[j] = shown[j], shown[i] end
            break
        end
    end
    saveShown(shown, unresolved)
end

local function toggle(id, on)
    local _, shown, _, unresolved = entries()
    local out = {}
    for _, v in ipairs(shown) do
        if v ~= id then out[#out + 1] = v end
    end
    if on then out[#out + 1] = id end
    saveShown(out, unresolved)
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win.content)
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self) toggle(r.id, self:GetChecked() and true or false) end)
    r.text = Glass.Font(r, 12, "LEFT")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.up = API.Button(r, "Up", 44, function() move(r.id, -1) end)
    r.up:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.down = API.Button(r, "Down", 48, function() move(r.id, 1) end)
    r.down:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    rows[i] = r
    return r
end

refreshWindow = function()
    if not win then return end
    local list, shown, used = entries()
    local pos = {}
    for i, id in ipairs(shown) do pos[id] = i end
    for i, c in ipairs(list) do
        local r = row(i)
        r.id = c.id
        r.check:SetChecked(used[c.id] == true)
        r.text:SetText(icon(c, 16) .. " " .. name(c) .. "  |cffaaaaaa" .. amount(c) .. "|r")
        r.up:SetShown(used[c.id] == true)
        r.down:SetShown(used[c.id] == true)
        r.up:SetEnabled(pos[c.id] ~= nil and pos[c.id] > 1)
        r.down:SetEnabled(pos[c.id] ~= nil and pos[c.id] < #shown)
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    win.content:SetHeight(math.max(#list, 1) * ROW_H)
    win.empty:SetShown(#list == 0)
end

-- Bag and item-load events come in bursts: one refresh per frame.
local refreshQueued = false
refreshWindowSoon = function()
    if refreshQueued or not (win and win:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if win and win:IsShown() then refreshWindow() end
    end)
end

local function openWindow()
    if not win then
        win = API.Window("GlassPanelReagentsWindow", 400, 320)
        win.title:SetText("Reagents on the bar")
        win.hint:SetText("Tick to show, Up/Down to order. Counts are what your bags hold.")
        local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, -8)
        scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 42)
        win.content = CreateFrame("Frame", nil, scroll)
        win.content:SetSize(ROW_W, ROW_H)
        scroll:SetScrollChild(win.content)
        API.AutoHideScrollBar(scroll)
        win.empty = Glass.Font(win.content, 12, "LEFT")
        win.empty:SetPoint("TOPLEFT", win.content, "TOPLEFT", 4, -4)
        win.empty:SetText("|cffaaaaaaNo class reagents for this character.|r")
        local close = API.Button(win, "Close", 90, function() win:Hide() end)
        close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    end
    refreshWindow()
    win:Show()
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = "reagents",
    label = "Reagents",
    icon = "Interface\\Icons\\INV_Misc_Dust_02",   -- "Reagents: " like Bags' caption; each reagent has its own
    side = "right",
    order = 125,
    events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
    onEvent = function(_, event)
        if event == "BAG_UPDATE_DELAYED" then bagsSettled = true end
        refreshWindowSoon()
    end,
    -- nil hides the block: nothing picked.
    text = function()
        local parts = {}
        for _, id in ipairs(picks()) do
            local c = info(id)
            if c then parts[#parts + 1] = icon(c, 14) .. " " .. amount(c) end
        end
        if #parts == 0 then return nil end
        return table.concat(parts, "  ")
    end,
    tooltip = function(_, tt)
        tt:AddLine("Reagents")
        for _, id in ipairs(picks()) do
            local c = info(id, true)
            if c then tt:AddDoubleLine(icon(c, 14) .. " " .. name(c), amount(c), 1, 0.82, 0, 1, 1, 1) end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: choose reagents", 0.3, 1, 0.3)
    end,
    onClick = function(_, button) if button == "LeftButton" then openWindow() end end,
    options = {
        { label = "Choose reagents...", run = openWindow,
          note = "Which of your class's reagents the bar shows, and in what order (this character)." },
    },
})

if block then
    block._test = { CLASS = CLASS, available = available, picks = picks, rows = rows,
                    window = function() return win end, pending = function() return pending end,
                    answered = function() return answered end, failed = function() return failed end }
end
