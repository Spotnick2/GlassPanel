-- Plugins/Durability/Durability.lua: the lowest durability among equipped
-- items and what repairing them costs (#12), like the TBC Titan bar's
-- "Durability: 97% (70s 4c)".
--
-- Forever notes:
-- - GetInventoryItemDurability (global walk only, no documented signature):
--   current, maximum, or nil for an item without durability. Secrecy is
--   per-API and situational: every number goes through API.Plain first. A
--   client secret keeps its type ("number", "table"), so a type() check is no
--   secrecy check.
-- - Repair cost: C_TooltipInfo.GetInventoryItem("player", slot).repairCost,
--   TitanRepair's Retail path. The field isn't in the dump's structures, so
--   a missing or unreadable cost just isn't shown (to be confirmed in game).
-- - Honest over plausible: when an item's durability can't be read, the bar
--   marks its figure with a grey "?" (the real lowest may be lower) and the
--   repair total becomes unknown, never a partial sum shown as the total.
-- - Tooltip data is heavy, and one equipment-set swap fires a dozen events:
--   events only mark the cache stale, and it is rebuilt at most once per
--   repaint (from text/tooltip), asking tooltip data only for damaged items.
-- - The alert (#130, the plugin option, off by default): once when the lowest
--   item drops to 25% (yellow) and once when one breaks (red), after combat,
--   through API.LevelAlert; a repair arms it again. Only a sure reading counts:
--   with an item unreadable the lowest may be lower, so nothing is said.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

-- Equipped slots, in paper-doll order; the label is the client's localized
-- slot name when it has one.
local SLOTS = {
    { 1, "HEADSLOT", "Head" }, { 3, "SHOULDERSLOT", "Shoulder" }, { 15, "BACKSLOT", "Back" },
    { 5, "CHESTSLOT", "Chest" }, { 9, "WRISTSLOT", "Wrist" }, { 10, "HANDSSLOT", "Hands" },
    { 6, "WAISTSLOT", "Waist" }, { 7, "LEGSSLOT", "Legs" }, { 8, "FEETSLOT", "Feet" },
    { 16, "MAINHANDSLOT", "Main Hand" }, { 17, "SECONDARYHANDSLOT", "Off Hand" },
    { 18, "RANGEDSLOT", "Ranged" },
}

-- The cache: items = { { slot, label, cur, max, cost } } for readable items
-- with durability; lowest = their lowest fraction (nil: none readable);
-- unreadable = how many items with durability couldn't be read; cost =
-- total repair cost in copper, nil when any part of it is unknown.
local state = { items = {}, lowest = nil, unreadable = 0, cost = nil }
local stale = true

-- GlassPanelDurabilityDB.alert: true, or nothing (off).
local function alertOn()
    local d = rawget(_G, "GlassPanelDurabilityDB")
    return type(d) == "table" and d.alert == true
end
local function setAlert(on)
    if type(rawget(_G, "GlassPanelDurabilityDB")) ~= "table" then GlassPanelDurabilityDB = {} end
    GlassPanelDurabilityDB.alert = on and true or nil
end
local alert = API.LevelAlert("durability", alertOn)

local function slotLabel(s)
    local name = rawget(_G, s[2])
    return type(name) == "string" and name or s[3]
end

-- The tooltip data and its repairCost, both through API.Plain, all inside
-- the pcall: indexing a secret table throws.
local function readCost(slot)
    local data = P(C_TooltipInfo.GetInventoryItem("player", slot))
    if type(data) ~= "table" then return nil end
    local cost = P(data.repairCost)
    return type(cost) == "number" and cost or nil
end

local function repairCost(slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, cost = pcall(readCost, slot)
    return ok and cost or nil
end

local function scan()
    local items, lowest, unreadable, total, known = {}, nil, 0, 0, true
    for _, s in ipairs(SLOTS) do
        local rawCur, rawMax = GetInventoryItemDurability(s[1])
        local cur, max = P(rawCur), P(rawMax)
        if cur and max and max > 0 then
            local cost
            if cur < max then
                cost = repairCost(s[1])
                if cost then total = total + cost else known = false end
            end
            items[#items + 1] = { slot = s[1], label = slotLabel(s), cur = cur, max = max, cost = cost }
            local f = cur / max
            if not lowest or f < lowest then lowest = f end
        elseif API.Returned(rawCur) or API.Returned(rawMax) then
            -- It has durability, but we can't read it: its cost is unknown too.
            unreadable = unreadable + 1
            known = false
        end
    end
    state.items, state.lowest, state.unreadable = items, lowest, unreadable
    state.cost = known and total or nil
end

-- Fine (0), damaged (1: <= 25%, where Blizzard's armour figure turns yellow)
-- or broken (2): green, yellow, red.
local function level(f)
    if f <= 0 then return 2 end
    if f <= 0.25 then return 1 end
    return 0
end
local COLOUR = { [0] = "40ff40", [1] = "ffd200", [2] = "ff4040" }
local function colour(f) return COLOUR[level(f)] end

-- Rounded DOWN: 99.5% isn't "100%" while it costs to repair; and anything
-- above zero is "<1%", never the broken "0%".
local function pct(f)
    local p = math.floor(f * 100)
    if p == 0 and f > 0 then return "<1%" end
    return p .. "%"
end

-- After a fresh scan: the alert hears a sure reading only.
local function report()
    if not state.lowest or state.unreadable > 0 then return end
    local l = level(state.lowest)
    alert.Set(l, l == 2 and "Durability critical: an item is broken."
        or "Durability low: " .. pct(state.lowest) .. ".")
end

-- A scan that throws leaves the cache stale (tried again on the next
-- repaint) and is recorded, rather than leaving an old cache marked fresh.
local function ensure()
    if not stale then return end
    local ok, err = pcall(scan)
    if ok then
        stale = false
        report()
    else
        API.Fail("durability:scan", err)
    end
end

local UNSURE = "|cff888888?|r"

GlassPanel.RegisterBlock({
    id = "durability",
    label = "Durability",
    icon = "Interface\\Icons\\Trade_BlackSmithing",
    side = "right",
    order = 110,   -- right lane, left of the clock
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED",
               "MERCHANT_SHOW", "MERCHANT_CLOSED" },
    onEvent = function() stale = true end,
    text = function()
        ensure()
        if not state.lowest then
            if state.unreadable > 0 then return "|cff888888hidden|r" end
            return nil   -- nothing with durability equipped
        end
        local t = "|cff" .. colour(state.lowest) .. pct(state.lowest) .. "|r"
        if state.unreadable > 0 then t = t .. UNSURE end
        if state.cost and state.cost > 0 then t = t .. " (" .. API.CoinText(state.cost) .. ")" end
        return t
    end,
    tooltip = function(_, tt)
        ensure()
        tt:AddLine("Durability")
        if not state.lowest and state.unreadable == 0 then
            tt:AddLine("Nothing equipped has durability.", 0.7, 0.7, 0.7)
            return
        end
        local damaged = 0
        for _, it in ipairs(state.items) do
            if it.cur < it.max then
                damaged = damaged + 1
                local f = it.cur / it.max
                local right = "|cff" .. colour(f) .. it.cur .. "/" .. it.max .. " (" .. pct(f) .. ")|r"
                if it.cost and it.cost > 0 then right = right .. "  " .. API.CoinText(it.cost) end
                tt:AddDoubleLine(it.label, right, 1, 1, 1, 1, 1, 1)
            end
        end
        if state.unreadable > 0 then
            tt:AddLine(state.unreadable .. " item(s) can't be read right now; the lowest may be lower.",
                0.7, 0.7, 0.7, true)
        elseif damaged == 0 then
            tt:AddLine("Everything is fully repaired.", 0.3, 1, 0.3)
        end
        tt:AddLine(" ")
        if state.cost then
            tt:AddDoubleLine("Repair cost", state.cost > 0 and API.CoinText(state.cost) or "none", 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddLine("Repair cost unknown here.", 0.7, 0.7, 0.7)
        end
    end,
    options = {
        { label = "Alert when it runs low",
          note = "Once, with a sound, when an item drops to 25% and when one breaks; after combat.",
          get = alertOn, set = setAlert },
    },
})
