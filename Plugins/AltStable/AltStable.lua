-- Plugins/AltStable/AltStable.lua: your characters' gold from AltStable (#46),
-- with every character in the tooltip. Left-click opens AltStable's sheet.
--
-- A bridge, not a character store: GlassPanel keeps no list of its own, so
-- forgetting and hiding stay AltStable's. Read ONLY through AltStable's
-- public API (..\AltStable\docs\PUBLIC-API.md, version 1), never AltStableDB:
-- - GetCharacters(): copies sorted by realm then name; money is copper or nil
--   (unknown, never 0); hidden ones flagged; current = logged in now.
-- - GetTotals(): the sheet footer's own figures (hidden left out, unknown
--   money counted apart), so "every character" shows the sheet's number.
-- - RegisterCallback("CharactersChanged", fn): one call per burst of changes,
--   the only repaint trigger we need (AltStable rescans the logged-in
--   character about 2 s after login and calls it then).
-- - ToggleSheet(): what a block click should do.
-- A different PUBLIC_API_VERSION means an incompatible change: no block, and
-- one line saying why, rather than reading fields whose meaning moved.
--
-- Scope (#163): "this side" is the logged-in character's faction and ruleset
-- (Forever's realms are its rulesets, and gold moves by mail only within a
-- faction and a ruleset: AltStable #386, #403), from the public API's ruleset
-- field (PUBLIC_API_FEATURES.ruleset). An AltStable without it: this realm and
-- faction, as before. The faction, realm and ruleset are the logged-in
-- character's own record, so they match AltStable's spelling. The tooltip
-- shows both totals; the bar shows this side (default) or everyone (option).

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local ID = "altstable"
local AS = rawget(_G, "AltStable")   -- every call goes through this, the table whose version was checked
local MAX_ROWS = 40

local function db()
    local d = rawget(_G, "GlassPanelAltStableDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelAltStableDB = d
    end
    return d
end

-- The bar's scope: "side" (default) or "all". The old realmOnly option (#46)
-- is gone; either of its values means the new default.
local function showAll() return db().scope == "all" end

local function byRuleset()
    local F = AS.PUBLIC_API_FEATURES
    return type(F) == "table" and F.ruleset == true
end

-- "|cffrrggbb" for a class file ("WARRIOR"), or nil.
local function classColour(classFile)
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local ok, c = pcall(C_ClassColor.GetClassColor, classFile)
    c = ok and P(c) or nil
    if type(c) ~= "table" then return nil end
    local r, g, b = P(c.r), P(c.g), P(c.b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(r), byte(g), byte(b))
end

-- What places a character on a side: its ruleset (when AltStable says) or its
-- realm, and its faction. nil when the record doesn't say.
local function place(c, rulesets)
    local where = c.realm
    if rulesets then where = c.ruleset end   -- not `and/or`: a nil ruleset must not fall back to the realm
    if type(where) ~= "string" or type(c.faction) ~= "string" then return nil end
    return where
end

-- This side's name for the tooltip: "Horde, PvP", or "this realm and faction".
local function sideName(me, rulesets)
    if not rulesets then return "this realm and faction" end
    local r = type(me.rulesetName) == "string" and me.rulesetName or me.ruleset
    return me.faction .. ", " .. r
end

-- This side's totals ({ money, unknown, characters, hidden, unplaced, name })
-- and its characters (hidden ones included, flagged), from chars (a
-- GetCharacters copy). nil when the side can't be worked out: before AltStable
-- has a record of this character, or one with no faction or ruleset.
local function side(chars)
    local rulesets = byRuleset()
    local me
    for _, c in ipairs(chars) do if c.current then me = c end end
    if not me then return nil, nil, "AltStable doesn't know this character yet." end
    local mine = place(me, rulesets)
    if not mine then
        return nil, nil, "AltStable can't tell this character's " .. (rulesets and "ruleset" or "realm")
            .. " or faction yet."
    end
    local list, t = {}, { money = 0, unknown = 0, characters = 0, hidden = 0, unplaced = 0,
                          name = sideName(me, rulesets), rulesets = rulesets }
    for _, c in ipairs(chars) do
        local at = place(c, rulesets)
        -- A record with no faction or ruleset (too old or partial, the API
        -- allows it) may belong here: not counted, but said, never dropped.
        if not at then
            if not c.hidden then t.unplaced = t.unplaced + 1 end
        elseif at == mine and c.faction == me.faction then
            list[#list + 1] = c
            if c.hidden then
                t.hidden = t.hidden + 1
            else
                t.characters = t.characters + 1
                local m = P(c.money)
                if type(m) == "number" then t.money = t.money + m else t.unknown = t.unknown + 1 end
            end
        end
    end
    return t, list
end

-- The bar's totals and, when withList, the tooltip's: the scope's totals and
-- characters, and the other scope's totals. Everyone: AltStable's own totals
-- (the sheet's figure), and the list only when asked (the bar text doesn't
-- need it, unless it shows this side).
local function gather(withList)
    if showAll() and not withList then return AS.GetTotals() end
    local chars = AS.GetCharacters()
    local st, slist, why = side(chars)
    if not showAll() then return st, slist, AS.GetTotals(), why end
    return AS.GetTotals(), chars, st
end

-- The total as coin text, or nil when no counted character's gold is known:
-- unknown, never "0c".
local function totalText(t)
    if t.characters - t.unknown <= 0 then return nil end
    return API.CoinText(t.money)
end

local UNKNOWN = "|cff888888?|r"

local function refresh() GlassPanel.Refresh(ID) end

if not (type(AS) == "table" and AS.PUBLIC_API_VERSION == 1) then
    local why = "AltStable's public API version 1 not found (got "
        .. tostring(type(AS) == "table" and AS.PUBLIC_API_VERSION or nil) .. ")"
    API.Fail("altstable:api", why)
    API.Print("|cffff6060[AltStable] block off:|r " .. why .. ". Update both addons.")
    return
end

GlassPanel.RegisterBlock({
    id = ID,
    label = "Alts",
    -- AltStable's own icon (its TOC's IconTexture), never a coin: the coin
    -- text drops zero denominations, so a coin icon made "37s 81c" read as
    -- 37 gold (Gold.lua's reason).
    icon = 8197123,
    -- The logged-in character's gold is in the total already: Gold is hidden
    -- while this block shows, until the player shows it again (#50).
    replaces = "gold",
    order = 40,   -- left lane, right after Gold
    onInit = function() AS.RegisterCallback("CharactersChanged", refresh) end,
    text = function()
        local t = gather(false)
        local coins = t and totalText(t)
        if not coins then return UNKNOWN end
        return coins .. ((t.unknown > 0 or (t.unplaced or 0) > 0) and (" " .. UNKNOWN) or "")
    end,
    tooltip = function(_, tt)
        local t, list, other, why = gather(true)
        local all = showAll()
        tt:AddLine(all and "Alts" or ("Alts: " .. (t and t.name or "this side")))
        if not list then
            tt:AddLine(why or "AltStable doesn't know this character yet.", 0.7, 0.7, 0.7, true)
        else
            local shown, realm = 0, false
            for _, c in ipairs(list) do
                if not c.hidden then
                    shown = shown + 1
                    if shown <= MAX_ROWS then
                        if c.realm ~= realm then
                            realm = c.realm
                            tt:AddLine(realm or "Unknown realm", 0.5, 0.8, 0.8)
                        end
                        local colour = classColour(c.class)
                        local left = "|cff888888" .. (P(c.level) or "?") .. "|r "
                            .. (colour and (colour .. c.name .. "|r") or c.name)
                            .. (c.current and " |cff4dff4d(logged in)|r" or "")
                        tt:AddDoubleLine(left, API.CoinText(c.money) or UNKNOWN, 1, 1, 1, 1, 1, 1)
                    end
                end
            end
            if shown > MAX_ROWS then
                tt:AddLine("+" .. (shown - MAX_ROWS) .. " more", 0.7, 0.7, 0.7)
            end
            tt:AddLine(" ")
            tt:AddDoubleLine("Total (" .. t.characters .. ")", totalText(t) or UNKNOWN,
                1, 0.82, 0, 1, 1, 1)
            -- The other figure: everyone under this side, this side under everyone.
            if other then
                local label = all and other.name or "Everyone"
                tt:AddDoubleLine(label .. " (" .. other.characters .. ")", totalText(other) or UNKNOWN,
                    0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
            end
            if t.unknown > 0 then
                tt:AddLine(t.unknown .. " character(s) with unknown gold, not counted.", 0.7, 0.7, 0.7, true)
            end
            if (t.unplaced or 0) > 0 then
                tt:AddLine(t.unplaced .. " character(s) with no " .. (t.rulesets and "ruleset" or "realm")
                    .. " or faction known, not counted.",
                    0.7, 0.7, 0.7, true)
            end
            if t.hidden > 0 then
                tt:AddLine(t.hidden .. " hidden in AltStable, not counted.", 0.7, 0.7, 0.7, true)
            end
        end
        if not list and other then
            tt:AddDoubleLine("Everyone (" .. other.characters .. ")", totalText(other) or UNKNOWN,
                0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: open AltStable", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button == "LeftButton" then AS.ToggleSheet() end
    end,
    options = {
        { label = "The bar shows every character's gold",
          note = "Off: this character's faction and ruleset. The tooltip shows both totals.",
          get = showAll,
          set = function(on)
              local d = db()
              d.scope, d.realmOnly = on and "all" or nil, nil
              refresh()
          end },
    },
})
