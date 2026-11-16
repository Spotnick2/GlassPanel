-- Plugins/Currencies/Currencies.lua: the currencies you pick, in your order
-- (#47), like TitanCurrenciesMulti in WotLK Classic, but from the client's
-- own list rather than hardcoded per-expansion tables.
--
-- Forever (70009 dump): C_CurrencyInfo.GetCurrencyListSize / GetCurrencyListInfo
-- (the currency tab: headers and currencies, each with its currencyID; a
-- collapsed header hides its currencies, and we never expand the player's
-- tab), GetCurrencyInfo(id) for one currency, CURRENCY_DISPLAY_UPDATE.
-- Forever's currencies (Wowhead's Forever database, owner, 2026-09-29) are
-- offered even before the character owns any, when the client resolves them
-- to a name: Merchant's Favor 3402, Tarnished Undermine Real 3469, Honor
-- Points 1792, Rank Points 3468, Darkmoon Prize Ticket 515.
--
-- Picks are per character (## SavedVariablesPerCharacter). Never chosen:
-- up to 3 owned currencies, saved the first time they're found so the bar
-- doesn't change by itself as currencies are gained. Every number through
-- API.Plain: a secret amount is a grey "?", never a guess. Measured on 70009
-- (owner): Honor Points' quantity and cap come back plain.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local KNOWN = { 3402, 3469, 1792, 3468, 515 }   -- Forever's currencies, offered before the character has any
local DEFAULT_MAX = 3                            -- first-run picks: up to this many owned

local function db()
    local d = rawget(_G, "GlassPanelCurrenciesDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelCurrenciesDB = d
    end
    if d.order ~= nil and type(d.order) ~= "table" then d.order = nil end
    return d
end

-- One currency by id: { id, name, quantity (nil = unreadable), max, icon,
-- weekly, weeklyMax }, or nil when the client doesn't know it.
local function info(id)
    local ok, c = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or type(c) ~= "table" then return nil end
    local name = P(c.name)
    if type(name) ~= "string" or name == "" then return nil end
    local q = P(c.quantity)
    local max, wk, wkMax = P(c.maxQuantity), P(c.quantityEarnedThisWeek), P(c.maxWeeklyQuantity)
    return { id = id, name = name, quantity = type(q) == "number" and q or nil,
             max = type(max) == "number" and max > 0 and max or nil,
             weekly = type(wk) == "number" and wk or nil,
             weeklyMax = type(wkMax) == "number" and wkMax > 0 and wkMax or nil,
             icon = P(c.iconFileID) }
end

-- The currencies to choose from: the tab's (as far as it's expanded), then
-- the known ones, each once; sorted by name.
local function available()
    local seen, list = {}, {}
    local okN, n = pcall(C_CurrencyInfo.GetCurrencyListSize)
    n = okN and P(n) or 0
    for i = 1, (type(n) == "number" and n or 0) do
        local ok, row = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        local id = ok and type(row) == "table" and P(row.isHeader) ~= true and P(row.currencyID) or nil
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            list[#list + 1] = info(id)
        end
    end
    for _, id in ipairs(KNOWN) do
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = info(id)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- The picked ids, in order (each once). Never chosen: the owned ones,
-- saved now so they stay put.
local function picks(avail)
    local d = db()
    if not d.order then
        local out = {}
        for _, c in ipairs(avail or available()) do
            if c.quantity and c.quantity > 0 and #out < DEFAULT_MAX then out[#out + 1] = c.id end
        end
        if #out == 0 then return out end   -- nothing yet: decide when there is
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
    GlassPanel.Refresh("currencies")
end

local function icon(c, size)
    if type(c.icon) ~= "number" and type(c.icon) ~= "string" then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(c.icon), size, size)
end

local function amount(c)
    if c.quantity == nil then return "|cff888888?|r" end
    return BreakUpLargeNumbers(c.quantity)
end

--------------------------------------------------------------------------------
-- The chooser window (API.Picker, #74): every currency, a checkbox to show
-- it, Up/Down to order the shown ones; the unpicked ones by name.
--------------------------------------------------------------------------------

local picker = API.Picker({
    name = "GlassPanelCurrenciesWindow",
    title = "Currencies on the bar",
    hint = "Tick to show, Up/Down to order. Expanded a header in the currency tab? Reopen this"
        .. " window to see what it holds.",
    empty = "|cffaaaaaaNo currencies yet on this character.|r",
    items = available,
    picks = picks,
    resolve = info,
    save = setPicks,
    label = function(c) return icon(c, 16) .. " " .. c.name .. "  |cffaaaaaa" .. amount(c) .. "|r" end,
})
local openWindow = picker.Open

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = "currencies",
    label = "Currencies",
    showLabel = false,   -- each currency carries its own icon
    side = "right",
    order = 120,
    events = { "PLAYER_ENTERING_WORLD", "CURRENCY_DISPLAY_UPDATE" },
    onEvent = function() picker.RefreshSoon() end,
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
        tt:AddLine("Currencies")
        for _, id in ipairs(picks()) do
            local c = info(id)
            if c then
                local right = amount(c)
                if c.max and c.quantity then right = right .. " / " .. BreakUpLargeNumbers(c.max) end
                tt:AddDoubleLine(icon(c, 14) .. " " .. c.name, right, 1, 0.82, 0, 1, 1, 1)
                if c.weeklyMax and c.weekly then
                    tt:AddDoubleLine("   this week", c.weekly .. " / " .. c.weeklyMax, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
                end
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: choose currencies", 0.3, 1, 0.3)
    end,
    onClick = function(_, button) if button == "LeftButton" then openWindow() end end,
    options = {
        { label = "Choose currencies...", run = openWindow,
          note = "Which currencies the bar shows, and in what order (this character)." },
    },
})

if block then
    block._test = { available = available, picks = picks, window = picker.Window, rows = picker.rows }
end
