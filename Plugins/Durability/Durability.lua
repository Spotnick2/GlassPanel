-- Plugins/Durability/Durability.lua: the lowest durability among equipped
-- items and what repairing them costs (#12), like the TBC Titan bar's
-- "Durability: 97% (70s 4c)".
--
-- Forever notes:
-- - GetInventoryItemDurability (global walk only, no documented signature):
--   current, maximum, or nil for an item without durability. Read through
--   API.Plain: secrecy is per-API and situational.
-- - Repair cost: C_TooltipInfo.GetInventoryItem("player", slot).repairCost,
--   TitanRepair's Retail path. The field isn't in the dump's structures, so
--   a missing or unreadable cost just isn't shown (to be confirmed in game).
-- - Tooltip data is heavier than a durability read: everything is measured
--   once per event into a cache, and text/tooltip only read the cache.

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

-- The cache: items = { { slot, label, cur, max, cost } } for items with
-- durability; lowest = the lowest fraction (nil: nothing has durability);
-- cost = total repair cost in copper (nil: unknown).
local state = { items = {}, lowest = nil, cost = nil }

local function slotLabel(s)
    local name = rawget(_G, s[2])
    return type(name) == "string" and name or s[3]
end

local function repairCost(slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    if not ok or type(data) ~= "table" then return nil end
    local cost = P(data.repairCost)
    if type(cost) ~= "number" then return nil end
    return cost
end

local function scan()
    local items, lowest, total, known = {}, nil, 0, true
    for _, s in ipairs(SLOTS) do
        local cur, max = GetInventoryItemDurability(s[1])
        cur, max = P(cur), P(max)
        if cur and max and max > 0 then
            local cost = repairCost(s[1])
            if cost then total = total + cost elseif cur < max then known = false end
            items[#items + 1] = { slot = s[1], label = slotLabel(s), cur = cur, max = max, cost = cost }
            local f = cur / max
            if not lowest or f < lowest then lowest = f end
        end
    end
    state.items, state.lowest = items, lowest
    state.cost = known and total or nil
end

-- Green while fine, yellow when an item is damaged (<= 25%, where Blizzard's
-- armour figure turns yellow), red when one is broken.
local function colour(f)
    if f <= 0 then return "ff4040" end
    if f <= 0.25 then return "ffd200" end
    return "40ff40"
end

local function pct(f) return string.format("%d%%", math.floor(f * 100 + 0.5)) end

GlassPanel.RegisterBlock({
    id = "durability",
    label = "Durability",
    icon = "Interface\\Icons\\Trade_BlackSmithing",
    side = "right",
    order = 110,   -- right lane, left of the clock
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED",
               "MERCHANT_SHOW", "MERCHANT_CLOSED" },
    onEvent = function() scan() end,
    onInit = function() scan() end,
    text = function()
        if not state.lowest then return nil end   -- nothing with durability equipped
        local t = "|cff" .. colour(state.lowest) .. pct(state.lowest) .. "|r"
        if state.cost and state.cost > 0 then t = t .. " (" .. API.CoinText(state.cost) .. ")" end
        return t
    end,
    tooltip = function(_, tt)
        tt:AddLine("Durability")
        if not state.lowest then
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
        if damaged == 0 then tt:AddLine("Everything is fully repaired.", 0.3, 1, 0.3) end
        tt:AddLine(" ")
        if state.cost then
            tt:AddDoubleLine("Repair cost", state.cost > 0 and API.CoinText(state.cost) or "none", 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddLine("Repair cost unknown here.", 0.7, 0.7, 0.7)
        end
    end,
})
