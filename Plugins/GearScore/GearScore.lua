-- Plugins/GearScore/GearScore.lua: your GearScore and Blizzard's average
-- item level (#16), "GearScore: 1060 iLvl: 76", a port of the owner's
-- TitanGearScore (formula from GearScoreLite by Mirrikat45 and TacoTip by
-- kebabstorm: the tables, slot weights and quality scaling are kept as is).
--
-- Forever notes:
-- - The global GetItemInfo is absent on 70009: C_Item.GetItemInfo (quality,
--   level) and C_Item.GetItemInfoInstant (equip slot, no cache needed).
--   GetInventoryItemID / GetInventoryItemLink / GetAverageItemLevel are in
--   the global walk only (no documented signature).
-- - An item not in the client's cache yet has no level or quality: it's
--   requested once (C_Item.RequestLoadItemDataByID), left out of the score
--   and flagged with a grey "?". ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED
--   (itemID, success) fire for EVERY item the client loads (auction house,
--   loot, links), so they're listened to on a frame of our own, only while
--   one of ours is loading: they never repaint the bar otherwise. A load
--   that fails (success false) makes that item unreadable, not re-requested;
--   an equipment change asks again.
-- - Honest over plausible: a secret id, level or quality makes that item
--   unreadable (left out and flagged the same way), never a guess.
-- - The bar's colour is TitanGearScore's smooth item-quality ramp; the
--   bracket name (tooltip) goes by the 200 scale, as TitanGearScore did.
-- - Brackets: the Classic scale (200 per bracket), fixed. TitanGearScore
--   picked it from GetBuildInfo's interface number, which on a Retail-codebase
--   client could read >= 30000 (the Wrath scale) and call everyone "Trash".
-- - Events only mark the cache stale; it's rebuilt at most once per repaint.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain
local floor = math.floor

local BRACKET_SIZE = 200
local MAX_SCORE = BRACKET_SIZE * 6 - 1

local SLOT_MOD = {
    INVTYPE_RELIC = 0.3164, INVTYPE_TRINKET = 0.5625, INVTYPE_2HWEAPON = 2.0000,
    INVTYPE_WEAPONMAINHAND = 1.0000, INVTYPE_WEAPONOFFHAND = 1.0000, INVTYPE_RANGED = 0.3164,
    INVTYPE_THROWN = 0.3164, INVTYPE_RANGEDRIGHT = 0.3164, INVTYPE_SHIELD = 1.0000,
    INVTYPE_WEAPON = 1.0000, INVTYPE_HOLDABLE = 1.0000, INVTYPE_HEAD = 1.0000,
    INVTYPE_NECK = 0.5625, INVTYPE_SHOULDER = 0.7500, INVTYPE_CHEST = 1.0000,
    INVTYPE_ROBE = 1.0000, INVTYPE_WAIST = 0.7500, INVTYPE_LEGS = 1.0000,
    INVTYPE_FEET = 0.7500, INVTYPE_WRIST = 0.5625, INVTYPE_HAND = 0.7500,
    INVTYPE_FINGER = 0.5625, INVTYPE_CLOAK = 0.5625, INVTYPE_BODY = 0,
}

-- Per quality (2 uncommon .. 4 epic): itemLevel -> (level - A) / B.
local FORMULA = {
    A = { [4] = { A = 91.4500, B = 0.6500 }, [3] = { A = 81.3750, B = 0.8125 }, [2] = { A = 73.0000, B = 1.0000 } },
    B = { [4] = { A = 26.0000, B = 1.2000 }, [3] = { A = 0.7500, B = 1.8000 }, [2] = { A = 8.0000, B = 2.0000 },
          [1] = { A = 0.0000, B = 2.2500 } },
    C = { [4] = { A = 0.2500, B = 1.6275 } },
}

-- The brackets: colour = A + (score - B) * C * D per channel.
local BRACKETS = {
    [1] = { "Trash",     { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 }, { 0.55, 0, 0.00045, 1 } },
    [2] = { "Common",    { 1.00, BRACKET_SIZE, 0.00088, -1 }, { 1.00, BRACKET_SIZE, 0.00100, -1 }, { 1.00, 0, 0, 0 } },
    [3] = { "Uncommon",  { 0.12, BRACKET_SIZE * 2, 0.00012, -1 }, { 0.00, BRACKET_SIZE * 2, 0.00100, 1 },
                         { 1.00, BRACKET_SIZE * 2, 0.00050, -1 } },
    [4] = { "Superior",  { 0.00, BRACKET_SIZE * 3, 0.00069, 1 }, { 1.00, BRACKET_SIZE * 3, 0.00003, -1 },
                         { 0.50, BRACKET_SIZE * 3, 0.00022, -1 } },
    [5] = { "Epic",      { 0.69, BRACKET_SIZE * 4, 0.00025, 1 }, { 0.97, BRACKET_SIZE * 4, 0.00096, -1 },
                         { 0.28, BRACKET_SIZE * 4, 0.00019, 1 } },
    [6] = { "Legendary", { 0.94, BRACKET_SIZE * 5, 0.00006, 1 }, { 0, 0, 0, 0 }, { 0.47, BRACKET_SIZE * 5, 0.00047, -1 } },
}

-- The bracket colour and name for a score (TitanGearScore's GetScoreColor).
local function scoreColor(score)
    if score > MAX_SCORE then score = MAX_SCORE end
    for i = 0, 5 do
        if score > i * BRACKET_SIZE and score <= (i + 1) * BRACKET_SIZE then
            local q = BRACKETS[i + 1]
            local function ch(c) return c[1] + ((score - c[2]) * c[3]) * c[4] end
            return ch(q[2]), ch(q[3]), ch(q[4]), q[1]
        end
    end
    return 0.1, 0.1, 0.1, "Trash"
end

-- The bar's colour: a smooth ramp along the item-quality colours, grey to orange.
local STOPS = {
    { 0, 0.62, 0.62, 0.62 }, { BRACKET_SIZE, 1.00, 1.00, 1.00 }, { BRACKET_SIZE * 2, 0.12, 1.00, 0.00 },
    { BRACKET_SIZE * 3, 0.00, 0.44, 0.87 }, { BRACKET_SIZE * 4, 0.64, 0.21, 0.93 },
    { BRACKET_SIZE * 5, 1.00, 0.50, 0.00 },
}
local function gradient(score)
    if score <= STOPS[1][1] then return STOPS[1][2], STOPS[1][3], STOPS[1][4] end
    for i = 2, #STOPS do
        local a, b = STOPS[i - 1], STOPS[i]
        if score <= b[1] then
            local t = (score - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local last = STOPS[#STOPS]
    return last[2], last[3], last[4]
end

local function hex(r, g, b, text)
    return string.format("|cff%02x%02x%02x%s|r", floor(r * 255), floor(g * 255), floor(b * 255), text)
end

-- One item's score (TitanGearScore's ScoreItem), from plain numbers; nil
-- when the slot or quality isn't scored (a shirt-like slot, an artifact).
local function scoreItem(quality, level, equipLoc)
    local mod = SLOT_MOD[equipLoc]
    if not mod then return nil end
    local qualityScale, scale = 1, 1.8618
    if quality == 5 then            -- legendary
        qualityScale, quality = 1.3, 4
    elseif quality <= 1 then        -- poor / common
        qualityScale, quality = 0.005, 2
    elseif quality == 7 then        -- heirloom (kept from the formula; none in Vanilla)
        quality, level = 3, 187.05
    end
    local t
    if level < 100 and quality == 4 then t = FORMULA.C
    elseif level < 168 and quality == 4 then t = FORMULA.B
    elseif level < 148 and quality == 3 then t = FORMULA.B
    elseif level < 138 and quality == 2 then t = FORMULA.B
    elseif level <= 120 then t = FORMULA.B
    else t = FORMULA.A end
    local f = quality >= 2 and quality <= 4 and t[quality]
    if not f then return nil end
    local gs = floor(((level - f.A) / f.B) * mod * scale * qualityScale)
    if gs < 0 then gs = 0 end
    local r, g, b = scoreColor(floor(((level - f.A) / f.B) * scale) * 11.25)
    return gs, r, g, b
end

-- Scored slots in paper-doll order; the shirt (4) has no stats. The label
-- is the client's localized slot name when it has one.
local SLOTS = {
    { 1, "HEADSLOT", "Head" }, { 2, "NECKSLOT", "Neck" }, { 3, "SHOULDERSLOT", "Shoulder" },
    { 15, "BACKSLOT", "Back" }, { 5, "CHESTSLOT", "Chest" }, { 9, "WRISTSLOT", "Wrist" },
    { 10, "HANDSSLOT", "Hands" }, { 6, "WAISTSLOT", "Waist" }, { 7, "LEGSSLOT", "Legs" },
    { 8, "FEETSLOT", "Feet" }, { 11, "FINGER0SLOT", "Ring 1", 1, "FINGER1SLOT" },
    { 12, "FINGER1SLOT", "Ring 2", 2, "FINGER0SLOT" },
    { 13, "TRINKET0SLOT", "Trinket 1", 1, "TRINKET1SLOT" }, { 14, "TRINKET1SLOT", "Trinket 2", 2, "TRINKET0SLOT" },
    { 16, "MAINHANDSLOT", "Main Hand" }, { 17, "SECONDARYHANDSLOT", "Off Hand" }, { 18, "RANGEDSLOT", "Ranged" },
}

-- A pair (rings, trinkets) whose two client names are the same ("Finger")
-- gets its number, so the two rows can be told apart.
local function slotLabel(s)
    local name = rawget(_G, s[2])
    if type(name) ~= "string" then return s[3] end
    if s[4] and rawget(_G, s[5]) == name then return name .. " " .. s[4] end
    return name
end

-- The cache: items = { { label, link, score, level, r, g, b } } for scored
-- items; score = their total (nil: not known, never a made-up 0);
-- loading / unreadable = items left out; unscored = equipped items the
-- formula has no score for (their quality has none).
-- pending: item ids asked for and not answered; failed: ids whose load failed.
local state = { items = {}, score = nil, loading = 0, unreadable = 0, unscored = 0 }
local pending, failed = {}, {}
local stale = true

-- The load events, on our own frame, only while something of ours loads.
local LOAD_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
local loader = CreateFrame("Frame")
local listening = false
local function listen(on)
    if on == listening then return end
    listening = on
    for _, e in ipairs(LOAD_EVENTS) do
        if on then API.RegisterEvent(loader, e, "GearScore") else loader:UnregisterEvent(e) end
    end
end
loader:SetScript("OnEvent", function(_, _, rawId, success)
    local id = P(rawId)
    if id and pending[id] then
        pending[id] = nil
        if P(success) == false then failed[id] = true end
        stale = true
        GlassPanel.Refresh("gearscore")
    end
    if next(pending) == nil then listen(false) end
end)

-- Ask for an item once; its answer rescans.
local function request(id)
    if pending[id] then return end
    pending[id] = true
    C_Item.RequestLoadItemDataByID(id)
    listen(true)
end

-- One slot: "empty", "loading" (requested), "unreadable", or the item.
local function readSlot(slot)
    local rawId = GetInventoryItemID("player", slot)
    local id = P(rawId)
    if not id then return API.Returned(rawId) and "unreadable" or "empty" end
    if failed[id] then return "unreadable" end
    if pending[id] or P(C_Item.IsItemDataCachedByID(id)) ~= true then
        request(id)
        return "loading"
    end
    local link = P(GetInventoryItemLink("player", slot))
    if type(link) ~= "string" then link = nil end
    -- By id, the key the cache check used (quality and level don't depend
    -- on the link); the link is only shown.
    local _, _, rawQuality, rawLevel = C_Item.GetItemInfo(id)
    local quality, level = P(rawQuality), P(rawLevel)
    if API.IsSecret(rawQuality) or API.IsSecret(rawLevel) then return "unreadable" end
    if type(quality) ~= "number" or type(level) ~= "number" then
        request(id)   -- evicted since the cache check
        return "loading"
    end
    local _, _, _, rawLoc = C_Item.GetItemInfoInstant(id)
    local equipLoc = P(rawLoc)
    -- No slot type (secret, or nothing returned): it can't be scored honestly.
    if type(equipLoc) ~= "string" then return "unreadable" end
    return { link = link, quality = quality, level = level, equipLoc = equipLoc }
end

local function scan()
    local _, rawClass = UnitClass("player")
    local hunter = P(rawClass) == "HUNTER"
    local items, total, loading, unreadable, unscored = {}, 0, 0, 0, 0
    -- No Titan's Grip halving: it needs a two-hander in both hands, which
    -- Vanilla can't equip.
    for _, s in ipairs(SLOTS) do
        local it = readSlot(s[1])
        if it == "loading" then loading = loading + 1
        elseif it == "unreadable" then unreadable = unreadable + 1
        elseif type(it) == "table" then
            local gs, r, g, b = scoreItem(it.quality, it.level, it.equipLoc)
            if gs then
                -- Hunters: melee weapons count for little, the ranged one for a lot.
                if hunter and (s[1] == 16 or s[1] == 17) then gs = floor(gs * 0.3164)
                elseif hunter and s[1] == 18 then gs = floor(gs * 5.3224) end
                total = total + gs
                items[#items + 1] = { label = slotLabel(s), link = it.link, score = gs,
                                      level = floor(it.level), r = r, g = g, b = b }
            else
                unscored = unscored + 1
            end
        end
    end
    state.items, state.score, state.loading, state.unreadable, state.unscored =
        items, total, loading, unreadable, unscored
end

-- A scan that throws leaves the score unknown ("?"), not the old one shown
-- as current; it's retried on the next repaint.
local function ensure()
    if not stale then return end
    local ok, err = pcall(scan)
    if ok then
        stale = false
    else
        API.Fail("gearscore:scan", err)
        state.items, state.score, state.loading, state.unreadable, state.unscored = {}, nil, 0, 0, 0
    end
end

-- Blizzard's equipped average item level (a fraction), or nil.
local function avgItemLevel()
    local ok, _, equipped = pcall(GetAverageItemLevel)
    equipped = ok and P(equipped) or nil
    return type(equipped) == "number" and equipped or nil
end

local UNSURE = "|cff888888?|r"

-- The score, coloured along the ramp, with a grey "?" when items were left
-- out; just "?" when nothing could be scored but something is equipped.
local function scoreText()
    if not state.score then return UNSURE end
    local unsure = state.loading + state.unreadable > 0
    if #state.items == 0 and unsure then return UNSURE end
    local r, g, b = gradient(state.score)
    local t = hex(r, g, b, state.score)
    return unsure and t .. UNSURE or t
end

GlassPanel.RegisterBlock({
    id = "gearscore",
    label = "GearScore",
    icon = "Interface\\Icons\\Trade_Engineering",
    side = "right",
    order = 160,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
               "PLAYER_AVG_ITEM_LEVEL_UPDATE" },
    unitEvents = { UNIT_INVENTORY_CHANGED = "player" },
    onEvent = function(_, event)
        -- Blizzard's average may settle after the gear events (PaperDollFrame
        -- listens for it apart): a repaint is enough, the gear is unchanged.
        if event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then return end
        -- Gear changed: rescan, and ask again for what didn't load before.
        stale = true
        pending, failed = {}, {}
    end,
    text = function()
        ensure()
        local t = scoreText()
        local avg = avgItemLevel()
        if avg then t = t .. "|cffffd100 iLvl:|r " .. floor(avg + 0.5) end
        return t
    end,
    tooltip = function(_, tt)
        ensure()
        local name = P(UnitName("player"))
        local _, rawClass = UnitClass("player")
        local class = P(rawClass)
        local ok, c = pcall(function()
            local col = class and P(C_ClassColor.GetClassColor(class))
            if not col then return nil end
            local r, g, b = P(col.r), P(col.g), P(col.b)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
        end)
        if type(name) == "string" then
            tt:AddLine(ok and c and hex(c[1], c[2], c[3], name) or name)
        else
            tt:AddLine("GearScore")
        end
        local _, _, _, bracket = scoreColor(state.score or 0)
        local unsure = state.loading + state.unreadable > 0
        tt:AddDoubleLine("GearScore", scoreText() .. ((#state.items > 0) and ("  (" .. bracket .. ")") or ""),
            1, 0.82, 0, 1, 1, 1)
        local avg = avgItemLevel()
        tt:AddDoubleLine("Avg Item Level", avg and string.format("%.1f", avg) or UNSURE, 1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine("Items Scored", tostring(#state.items), 1, 0.82, 0, 1, 1, 1)
        if #state.items > 0 then
            tt:AddLine(" ")
            for _, it in ipairs(state.items) do
                tt:AddDoubleLine(it.label .. "  " .. (it.link or ""),
                    hex(it.r, it.g, it.b, it.score) .. "  |cffffffffiLvl " .. it.level .. "|r", 1, 0.82, 0, 1, 1, 1)
            end
        end
        if unsure or state.unscored > 0 or not state.score then tt:AddLine(" ") end
        if not state.score then
            tt:AddLine("Your gear couldn't be read (see /gpanel failures).", 0.7, 0.7, 0.7, true)
        end
        if state.loading > 0 then
            tt:AddLine(state.loading .. " item(s) still loading; not in the score yet.", 0.7, 0.7, 0.7, true)
        end
        if state.unreadable > 0 then
            tt:AddLine(state.unreadable .. " item(s) can't be read right now; not in the score.", 0.7, 0.7, 0.7, true)
        end
        if state.unscored > 0 then
            tt:AddLine(state.unscored .. " item(s) have no GearScore (their quality isn't scored).", 0.7, 0.7, 0.7, true)
        end
    end,
})
