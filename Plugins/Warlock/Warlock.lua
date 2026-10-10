-- Plugins/Warlock/Warlock.lua: soul shards, and whether a Healthstone and a
-- Soulstone are in the bags (#67). Warlocks only: any other class gets no
-- block (nil text takes no space).
--
-- Forever (70338 dump): C_Item.GetItemCount(item), C_Container.GetItemCooldown
-- (itemID) -> start, duration, enable, BAG_UPDATE_DELAYED, BAG_UPDATE_COOLDOWN.
-- Item ids: Soul Shard 6265; the stones from the consumables list (70009),
-- talented healthstones (19004-19013) included since the client has them.
-- Every number through API.Plain: unreadable is a grey "?", never a guess.
-- No click: using a stone is a secure action.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local SHARD = 6265
local LOW = 5   -- fewer shards than this: yellow; none: red

-- Best rank first, so the tooltip names the best one carried.
local HEALTHSTONES = {
    { 19013, "Major Healthstone" }, { 19012, "Major Healthstone" }, { 9421, "Major Healthstone" },
    { 19011, "Greater Healthstone" }, { 19010, "Greater Healthstone" }, { 5510, "Greater Healthstone" },
    { 19009, "Healthstone" }, { 19008, "Healthstone" }, { 5509, "Healthstone" },
    { 19007, "Lesser Healthstone" }, { 19006, "Lesser Healthstone" }, { 5511, "Lesser Healthstone" },
    { 19005, "Minor Healthstone" }, { 19004, "Minor Healthstone" }, { 5512, "Minor Healthstone" },
}
local SOULSTONES = {
    { 16896, "Major Soulstone" }, { 16895, "Greater Soulstone" }, { 16893, "Soulstone" },
    { 16892, "Lesser Soulstone" }, { 5232, "Minor Soulstone" },
}

local ICON_SHARD = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local ICON_HEALTHSTONE = "Interface\\Icons\\INV_Stone_04"
local ICON_SOULSTONE = "Interface\\Icons\\INV_Misc_Orb_04"

local UNKNOWN = "|cff888888?|r"

local function isWarlock()
    local _, class = UnitClass("player")
    return P(class) == "WARLOCK"
end

-- How many of an item are in the bags: a number, or nil (unreadable).
local function count(id)
    local ok, n = pcall(C_Item.GetItemCount, id)
    n = ok and P(n) or nil
    return type(n) == "number" and n or nil
end

-- The best stone carried from a list: { id, name }, false (none), or nil
-- (none readable as carried, and some count couldn't be read).
local function carried(list)
    local unknown = false
    for _, s in ipairs(list) do
        local n = count(s[1])
        if n == nil then unknown = true
        elseif n > 0 then return s end
    end
    if unknown then return nil end
    return false
end

-- Seconds left on an item's cooldown (0: ready), or nil (unreadable).
local function cooldown(id)
    local ok, start, duration, enable = pcall(C_Container.GetItemCooldown, id)
    if not ok then return nil end
    start, duration, enable = P(start), P(duration), P(enable)
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if enable == 0 or start <= 0 or duration <= 0 then return 0 end
    local now = P(GetTime())
    if type(now) ~= "number" then return nil end
    local left = start + duration - now
    return left > 0 and math.ceil(left) or 0
end

local function clock(s)
    if s >= 3600 then return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60) end
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function icon(path) return "|T" .. path .. ":14:14:0:0:64:64:5:59:5:59|t" end

local function shardText(n)
    if n == nil then return UNKNOWN end
    if n == 0 then return "|cffff4040" .. n .. "|r" end
    if n < LOW then return "|cffffd200" .. n .. "|r" end
    return tostring(n)
end

-- A stone's tooltip line: its name and whether it's ready.
local function stoneLine(tt, label, stone)
    if stone == nil then
        tt:AddDoubleLine(label, UNKNOWN, 1, 0.82, 0, 1, 1, 1)
    elseif stone == false then
        tt:AddDoubleLine(label, "none", 1, 0.82, 0, 1, 0.25, 0.25)
    else
        local left = cooldown(stone[1])
        local state = left == nil and UNKNOWN or left > 0 and ("|cffffd200" .. clock(left) .. "|r") or "|cff40ff40ready|r"
        tt:AddDoubleLine(label, stone[2] .. " (" .. state .. ")", 1, 0.82, 0, 1, 1, 1)
    end
end

local block = GlassPanel.RegisterBlock({
    id = "warlock",
    label = "Warlock",
    showLabel = false,   -- the shard icon says it
    icon = ICON_SHARD,
    side = "right",
    order = 140,
    events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN" },
    -- Every second while a carried stone's cooldown runs (the tooltip counts
    -- down), else rarely: bag events cover the rest.
    interval = function()
        if not isWarlock() then return 60 end
        for _, list in ipairs({ HEALTHSTONES, SOULSTONES }) do
            local s = carried(list)
            local left = s and cooldown(s[1])
            if left and left > 0 then return 1 end
        end
        return 30
    end,
    text = function()
        if not isWarlock() then return nil end
        local t = shardText(count(SHARD))
        if carried(HEALTHSTONES) then t = t .. " " .. icon(ICON_HEALTHSTONE) end
        if carried(SOULSTONES) then t = t .. " " .. icon(ICON_SOULSTONE) end
        return t
    end,
    tooltip = function(_, tt)
        tt:AddLine("Warlock")
        local n = count(SHARD)
        tt:AddDoubleLine("Soul Shards", shardText(n), 1, 0.82, 0, 1, 1, 1)
        stoneLine(tt, "Healthstone", carried(HEALTHSTONES))
        stoneLine(tt, "Soulstone", carried(SOULSTONES))
        if n == nil then tt:AddLine("Some counts can't be read right now.", 0.7, 0.7, 0.7, true) end
    end,
})

if block then
    block._test = { carried = carried, cooldown = cooldown, HEALTHSTONES = HEALTHSTONES, SOULSTONES = SOULSTONES }
end
