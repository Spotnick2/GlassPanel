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

-- The shared loader (API.ItemLoader, #74). `failed`: Reagents' own rule, the
-- ids whose load failed with still no icon.
local failed = {}
local knownIcon
local refreshWindowSoon
local loader = API.ItemLoader("Reagents", function(id, success)
    if success == false and not knownIcon(id) then failed[id] = true end
    GlassPanel.Refresh("reagents")
    refreshWindowSoon()
end)
local request = loader.Request

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
-- The chooser window (API.Picker, #74): the class's reagents, a checkbox to
-- show each, Up/Down to order the shown ones; the unpicked ones in the
-- class's order.
--------------------------------------------------------------------------------

local picker = API.Picker({
    name = "GlassPanelReagentsWindow",
    title = "Reagents on the bar",
    hint = "Tick to show, Up/Down to order. Counts are what your bags hold.",
    empty = "|cffaaaaaaNo class reagents for this character.|r",
    items = available,
    picks = function() return picks() end,
    resolve = function(id) return info(id, true) end,
    save = setPicks,
    label = function(c) return icon(c, 16) .. " " .. name(c) .. "  |cffaaaaaa" .. amount(c) .. "|r" end,
})
refreshWindowSoon = picker.RefreshSoon
local openWindow = picker.Open

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
    block._test = { CLASS = CLASS, available = available, picks = picks, rows = picker.rows,
                    window = picker.Window, pending = function() return loader.pending end,
                    answered = function() return loader.answered end, failed = function() return failed end }
end
