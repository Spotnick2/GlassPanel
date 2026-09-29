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
-- Scope (plugin option): every character (default, the sheet's total), or
-- only this realm and faction, like Titan's gold. The realm and faction are
-- the logged-in character's own record, so they match AltStable's spelling.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local ID = "altstable"
local MAX_ROWS = 40

local function db()
    local d = rawget(_G, "GlassPanelAltStableDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelAltStableDB = d
    end
    return d
end

local function realmOnly() return db().realmOnly == true end

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

-- The characters in scope (hidden ones included, flagged) and their totals
-- ({ money, unknown, characters, hidden }), or nil when the scope can't be
-- worked out: "this realm" before AltStable has a record of this character.
local function gather()
    local chars = AltStable.GetCharacters()
    if not realmOnly() then return chars, AltStable.GetTotals() end
    local me
    for _, c in ipairs(chars) do if c.current then me = c end end
    if not (me and me.realm and me.faction) then return nil end
    local list, t = {}, { money = 0, unknown = 0, characters = 0, hidden = 0 }
    for _, c in ipairs(chars) do
        if c.realm == me.realm and c.faction == me.faction then
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
    return list, t
end

local UNKNOWN = "|cff888888?|r"

local function refresh() GlassPanel.Refresh(ID) end

local AS = rawget(_G, "AltStable")
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
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    order = 40,   -- left lane, after your own gold
    onInit = function()
        local ok, err = pcall(AltStable.RegisterCallback, "CharactersChanged", refresh)
        if not ok then API.Fail("altstable:callback", err) end
    end,
    text = function()
        local _, t = gather()
        local coins = t and API.CoinText(t.money)
        if not coins then return UNKNOWN end
        return coins .. (t.unknown > 0 and (" " .. UNKNOWN) or "")
    end,
    tooltip = function(_, tt)
        local list, t = gather()
        tt:AddLine(realmOnly() and "Alts: this realm and faction" or "Alts")
        if not list then
            tt:AddLine("AltStable doesn't know this character yet.", 0.7, 0.7, 0.7, true)
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
            tt:AddDoubleLine("Total (" .. t.characters .. ")", API.CoinText(t.money) or UNKNOWN,
                1, 0.82, 0, 1, 1, 1)
            if t.unknown > 0 then
                tt:AddLine(t.unknown .. " character(s) with unknown gold, not counted.", 0.7, 0.7, 0.7, true)
            end
            if t.hidden > 0 then
                tt:AddLine(t.hidden .. " hidden in AltStable, not counted.", 0.7, 0.7, 0.7, true)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: open AltStable", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button == "LeftButton" then AltStable.ToggleSheet() end
    end,
    options = {
        { label = "Only this realm and faction",
          note = "Off: every character AltStable knows, the total its sheet shows.",
          get = realmOnly,
          set = function(on) db().realmOnly = on and true or nil; refresh() end },
    },
})
