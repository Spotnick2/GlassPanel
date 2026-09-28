-- Plugins/Bags/Bags.lua: bag space (#13), like the TBC Titan bar's
-- "Bags: 45/74" (used / total). Click opens all bags.
--
-- Only normal bags count towards the number on the bar: special bags
-- (quivers, ammo pouches, soul bags, herb bags...) hold one kind of item, so
-- their free slots aren't space you can use. C_Container.GetContainerNumFreeSlots'
-- second return is the bag family, 0 for a normal bag. They're listed apart in
-- the tooltip. Bag 5 (Retail's reagent bag slot) counts as special when it
-- exists, as in TitanBag.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local FIRST, LAST = 0, 5   -- backpack .. the reagent slot, if any

-- The cache: bags = { { bag, name, slots, used, special } }, and the normal
-- bags' totals (nil used/total: nothing readable).
local state = { bags = {}, used = nil, total = nil }

local function scan()
    local bags, used, total = {}, 0, 0
    for bag = FIRST, LAST do
        local slots = P(C_Container.GetContainerNumSlots(bag))
        if slots and slots > 0 then
            local free, family = C_Container.GetContainerNumFreeSlots(bag)
            free, family = P(free), P(family)
            if free then
                local special = (family ~= nil and family ~= 0) or bag == 5
                local name = P(C_Container.GetBagName(bag))
                bags[#bags + 1] = { bag = bag, name = type(name) == "string" and name or ("Bag " .. bag),
                                    slots = slots, used = slots - free, special = special }
                if not special then
                    used, total = used + slots - free, total + slots
                end
            end
        end
    end
    state.bags = bags
    if total > 0 then state.used, state.total = used, total else state.used, state.total = nil, nil end
end

-- White while there's room, yellow from 75% full, red from 90%.
local function colour(used, total)
    local f = used / total
    if f >= 0.9 then return "ff4040" end
    if f >= 0.75 then return "ffd200" end
    return "ffffff"
end

GlassPanel.RegisterBlock({
    id = "bags",
    label = "Bags",
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    side = "right",
    order = 120,   -- right lane, left of durability
    events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
    onEvent = function() scan() end,
    onInit = function() scan() end,
    text = function()
        if not state.total then return nil end
        return "|cff" .. colour(state.used, state.total) .. state.used .. "/" .. state.total .. "|r"
    end,
    tooltip = function(_, tt)
        tt:AddLine("Bags")
        if not state.total then
            tt:AddLine("Bag contents aren't readable right now.", 0.7, 0.7, 0.7, true)
            return
        end
        local specials = 0
        for _, b in ipairs(state.bags) do
            if not b.special then
                tt:AddDoubleLine(b.name, b.used .. "/" .. b.slots, 1, 1, 1, 1, 1, 1)
            else
                specials = specials + 1
            end
        end
        tt:AddDoubleLine("Free", tostring(state.total - state.used), 1, 0.82, 0, 1, 1, 1)
        if specials > 0 then
            tt:AddLine(" ")
            tt:AddLine("Special bags (not counted)", 1, 0.82, 0)
            for _, b in ipairs(state.bags) do
                if b.special then tt:AddDoubleLine(b.name, b.used .. "/" .. b.slots, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Click: open all bags", 0.3, 1, 0.3)
    end,
    onClick = function() ToggleAllBags() end,
})
