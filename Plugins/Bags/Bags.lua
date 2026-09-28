-- Plugins/Bags/Bags.lua: bag space (#13), like the TBC Titan bar's
-- "Bags: 45/74" (used / total). Left-click toggles all bags.
--
-- Only normal bags count towards the number on the bar: special bags
-- (quivers, ammo pouches, soul bags, herb bags...) hold one kind of item, so
-- their free slots aren't space you can use. C_Container.GetContainerNumFreeSlots'
-- second return is the bag family, 0 for a normal bag. They're listed apart in
-- the tooltip. The reagent bag slot counts as special when it exists, as in
-- TitanBag. Bag ids come from Enum.BagIndex: they already moved once on
-- Forever (porting guide, "Bag IDs all moved").
--
-- Honest over plausible: a bag whose free count or family can't be read is
-- left out AND flagged, so the figure shows a grey "?" (the real count
-- differs) instead of a smaller total passed off as the whole.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local BI = Enum and Enum.BagIndex or {}
local FIRST = BI.Backpack or 0
local LAST_NORMAL = BI.Bag_4 or 4
local REAGENT = BI.ReagentBag   -- nil when the client has no reagent slot

-- The cache: bags = { { bag, name, slots, used, special } }; used/total over
-- readable normal bags (nil: none readable); unreadable = bags left out.
local state = { bags = {}, used = nil, total = nil, unreadable = 0 }

local function scanBag(bag, out)
    local slots = P(C_Container.GetContainerNumSlots(bag))
    if not (slots and slots > 0) then return end
    local rawFree, rawFamily = C_Container.GetContainerNumFreeSlots(bag)
    local free, family = P(rawFree), P(rawFamily)
    -- A family that came back but can't be read: normal or special is
    -- unknown, so the bag can't be counted either way.
    if free == nil or (family == nil and rawFamily ~= nil) then
        out.unreadable = out.unreadable + 1
        return
    end
    local special = (family ~= nil and family ~= 0) or bag == REAGENT
    local name = P(C_Container.GetBagName(bag))
    out.bags[#out.bags + 1] = { bag = bag, name = type(name) == "string" and name or ("Bag " .. bag),
                                slots = slots, used = slots - free, special = special }
    if not special then
        out.used, out.total = out.used + slots - free, out.total + slots
    end
end

local function scan()
    local out = { bags = {}, used = 0, total = 0, unreadable = 0 }
    for bag = FIRST, LAST_NORMAL do scanBag(bag, out) end
    if REAGENT then scanBag(REAGENT, out) end
    state.bags, state.unreadable = out.bags, out.unreadable
    if out.total > 0 then state.used, state.total = out.used, out.total else state.used, state.total = nil, nil end
end

-- White while there's room, yellow from 75% full, red from 90%.
local function colour(used, total)
    local f = used / total
    if f >= 0.9 then return "ff4040" end
    if f >= 0.75 then return "ffd200" end
    return "ffffff"
end

local UNSURE = "|cff888888?|r"

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
        if not state.total then
            if state.unreadable > 0 then return "|cff888888hidden|r" end
            return nil
        end
        local t = "|cff" .. colour(state.used, state.total) .. state.used .. "/" .. state.total .. "|r"
        if state.unreadable > 0 then t = t .. UNSURE end
        return t
    end,
    tooltip = function(_, tt)
        tt:AddLine("Bags")
        local specials = 0
        for _, b in ipairs(state.bags) do
            if not b.special then
                tt:AddDoubleLine(b.name, b.used .. "/" .. b.slots, 1, 1, 1, 1, 1, 1)
            else
                specials = specials + 1
            end
        end
        if state.total then
            tt:AddDoubleLine("Free", tostring(state.total - state.used), 1, 0.82, 0, 1, 1, 1)
        end
        if state.unreadable > 0 then
            tt:AddLine(state.unreadable .. " bag(s) can't be read right now and aren't counted.", 0.7, 0.7, 0.7, true)
        end
        if specials > 0 then
            tt:AddLine(" ")
            tt:AddLine("Special bags (not counted)", 1, 0.82, 0)
            for _, b in ipairs(state.bags) do
                if b.special then tt:AddDoubleLine(b.name, b.used .. "/" .. b.slots, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: open or close your bags", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button == "LeftButton" then ToggleAllBags() end
    end,
})
