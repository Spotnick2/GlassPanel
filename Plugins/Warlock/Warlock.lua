-- Plugins/Warlock/Warlock.lua: soul shards, and whether a Healthstone and a
-- Soulstone are in the bags (#67). Warlocks only: another class doesn't
-- register the block at all (no events), read once at load. A class that
-- can't be read then registers it, and its text stays nil until it can.
--
-- Forever (70338 dump): C_Item.GetItemCount(item), C_Container.GetItemCooldown
-- (itemID) -> start, duration, enable, BAG_UPDATE_DELAYED.
-- Item ids: Soul Shard 6265; the stones from the consumables list (70009),
-- talented healthstones (19004-19013) included since the client has them.
-- Every number through API.Plain: unreadable is a grey "?", never a guess.
-- Counts are a snapshot: bag events mark it stale and it's rebuilt at most
-- once per repaint (Durability's pattern). Cooldowns are read only by the
-- tooltip, fresh each time it's drawn, so BAG_UPDATE_COOLDOWN (it fires on
-- most casts, and the bar text can't change from it) isn't registered. The
-- countdown ticks (a 1 s C_Timer) only while the tooltip is open on the block
-- with a cooldown counting down ("waiting" doesn't count: nothing changes).
-- No click: using a stone is a secure action.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local SHARD = 6265
local LOW = 5   -- fewer shards than this: yellow; none: red

-- Best rank first, so the tooltip names the best one carried; within a rank,
-- most healing first (the talented 19004-19013 come in a weaker and a
-- stronger copy: forever-consumables 70009).
local HEALTHSTONES = {
    { 19013, "Major Healthstone" }, { 9421, "Major Healthstone" }, { 19012, "Major Healthstone" },
    { 19011, "Greater Healthstone" }, { 5510, "Greater Healthstone" }, { 19010, "Greater Healthstone" },
    { 19009, "Healthstone" }, { 5509, "Healthstone" }, { 19008, "Healthstone" },
    { 19007, "Lesser Healthstone" }, { 5511, "Lesser Healthstone" }, { 19006, "Lesser Healthstone" },
    { 19005, "Minor Healthstone" }, { 5512, "Minor Healthstone" }, { 19004, "Minor Healthstone" },
}
local SOULSTONES = {
    { 16896, "Major Soulstone" }, { 16895, "Greater Soulstone" }, { 16893, "Soulstone" },
    { 16892, "Lesser Soulstone" }, { 5232, "Minor Soulstone" },
}

local ICON_SHARD = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local ICON_HEALTHSTONE = "Interface\\Icons\\INV_Stone_04"
local ICON_SOULSTONE = "Interface\\Icons\\INV_Misc_Orb_04"

local UNKNOWN = "|cff888888?|r"

local function classFile()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and P(class) or nil
    return type(class) == "string" and class or nil
end

-- How many of an item are in the bags: a number, or nil (unreadable).
local function count(id)
    local ok, n = pcall(C_Item.GetItemCount, id)
    n = ok and P(n) or nil
    return type(n) == "number" and n or nil
end

-- The client's (localised) name for an item, else ours.
local function itemName(stone)
    local ok, name = pcall(C_Item.GetItemNameByID, stone[1])
    name = ok and P(name) or nil
    if type(name) == "string" and name ~= "" then return name end
    return stone[2]
end

-- The best stone carried from a list: { id, name }, false (none), or nil
-- (unknown: a count that could be the best one couldn't be read; a lower
-- rank carried under it isn't presented as the best).
local function carried(list)
    local unknown = false
    for _, s in ipairs(list) do
        local n = count(s[1])
        if n == nil then unknown = true
        elseif n > 0 then
            if unknown then return nil end
            return s
        end
    end
    if unknown then return nil end
    return false
end

-- The snapshot: shards (number|nil), healthstone and soulstone (see carried).
local state = {}
local stale = true
local function scan()
    state = { shards = count(SHARD), healthstone = carried(HEALTHSTONES), soulstone = carried(SOULSTONES) }
end
-- A scan that throws leaves it stale (tried again on the next repaint).
local function ensure()
    if not stale then return end
    local ok, err = pcall(scan)
    if ok then stale = false else API.Fail("warlock:scan", err) end
end

local GCD = 1.5   -- a cooldown this short is the global cooldown, not the stone's

-- An item's cooldown: 0 (ready), seconds left, "waiting" (held until
-- something ends, enable == 0: the bags grey it out), or nil (unreadable).
local function cooldown(id)
    local ok, start, duration, enable = pcall(C_Container.GetItemCooldown, id)
    if not ok then return nil end
    start, duration, enable = P(start), P(duration), P(enable)
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if duration > 0 and enable == 0 then return "waiting" end
    if start <= 0 or duration <= GCD then return 0 end
    local now = P(GetTime())
    if type(now) ~= "number" then return nil end
    local left = start + duration - now
    return left > 0 and math.ceil(left) or 0
end

-- Counting down (the tooltip's ticker runs for it); "waiting" doesn't change.
local function running(left) return type(left) == "number" and left > 0 end

-- The longest stone cooldown is 30 min: minutes and seconds.
local function clock(s)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function icon(path) return "|T" .. path .. ":14:14:0:0:64:64:5:59:5:59|t" end

local function shardText(n)
    if n == nil then return UNKNOWN end
    if n == 0 then return "|cffff4040" .. n .. "|r" end
    if n < LOW then return "|cffffd200" .. n .. "|r" end
    return tostring(n)
end

-- A stone's tooltip line: its name and whether it's ready. Returns whether
-- its cooldown counts down, and whether that cooldown couldn't be read.
local function stoneLine(tt, label, stone)
    if stone == nil then
        tt:AddDoubleLine(label, UNKNOWN, 1, 0.82, 0, 1, 1, 1)
    elseif stone == false then
        tt:AddDoubleLine(label, "none", 1, 0.82, 0, 1, 0.25, 0.25)
    else
        local left = cooldown(stone[1])
        local shown = left == nil and UNKNOWN
            or left == "waiting" and "|cffffd200waiting|r"
            or left > 0 and ("|cffffd200" .. clock(left) .. "|r")
            or "|cff40ff40ready|r"
        tt:AddDoubleLine(label, itemName(stone) .. " (" .. shown .. ")", 1, 0.82, 0, 1, 1, 1)
        return running(left), left == nil
    end
    return false, false
end

local class = classFile()   -- kept once it reads plainly
if class and class ~= "WARLOCK" then return end

local block
-- The tooltip's countdown: a 1 s ticker while it's open on the block and a
-- cooldown runs; it stops itself otherwise.
local ticker
local function tooltipOpen()
    local w = block and block.widget
    return w ~= nil and GameTooltip:GetOwner() == w and GameTooltip:IsShown() and true or false
end
local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end
local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        if tooltipOpen() then GlassPanel.Refresh("warlock") else stopTicker() end
    end)
end

block = GlassPanel.RegisterBlock({
    id = "warlock",
    label = "Warlock",
    showLabel = false,   -- the shard icon says it
    icon = ICON_SHARD,
    side = "right",
    order = 145,   -- right lane, between Role and Professions
    events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
    onEvent = function() stale = true end,
    text = function()
        if class == nil then class = classFile() end
        if class ~= "WARLOCK" then return nil end
        ensure()
        local t = shardText(state.shards)
        if state.healthstone then t = t .. " " .. icon(ICON_HEALTHSTONE) end
        if state.soulstone then t = t .. " " .. icon(ICON_SOULSTONE) end
        return t
    end,
    tooltip = function(_, tt)
        ensure()
        tt:AddLine("Warlock")
        tt:AddDoubleLine("Soul Shards", shardText(state.shards), 1, 0.82, 0, 1, 1, 1)
        local hs, hsUnread = stoneLine(tt, "Healthstone", state.healthstone)
        local ss, ssUnread = stoneLine(tt, "Soulstone", state.soulstone)
        if state.shards == nil or state.healthstone == nil or state.soulstone == nil
            or hsUnread or ssUnread then
            tt:AddLine("Some counts or cooldowns can't be read right now.", 0.7, 0.7, 0.7, true)
        end
        if hs or ss then startTicker() else stopTicker() end
    end,
})

if block then
    block._test = { carried = carried, cooldown = cooldown, HEALTHSTONES = HEALTHSTONES, SOULSTONES = SOULSTONES,
                    ticker = function() return ticker end }
end
