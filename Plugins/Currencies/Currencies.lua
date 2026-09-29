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
-- The chooser window: every currency, a checkbox to show it, Up/Down to
-- order the shown ones.
--------------------------------------------------------------------------------

local win, rows = nil, {}
local ROW_W, ROW_H = 340, 26

-- The rows: the shown ones first, in order (only those the client resolves),
-- then the rest by name. `shown` is that first part, as ids.
local function entries()
    local avail = available()
    local byId = {}
    for _, c in ipairs(avail) do byId[c.id] = c end
    local list, shown, used = {}, {}, {}
    for _, id in ipairs(picks(avail)) do
        local c = byId[id] or info(id)
        if c then
            list[#list + 1] = c
            shown[#shown + 1] = id
            used[id] = true
        end
    end
    for _, c in ipairs(avail) do
        if not used[c.id] then list[#list + 1] = c end
    end
    return list, shown, used
end

local refreshWindow

-- Write `shown` (the visible order) back, keeping saved ids the client
-- doesn't resolve right now at the end, untouched.
local function saveShown(shown)
    local keep, inShown = {}, {}
    for _, id in ipairs(shown) do inShown[id] = true; keep[#keep + 1] = id end
    for _, id in ipairs(picks()) do
        if not inShown[id] and not info(id) then keep[#keep + 1] = id end
    end
    setPicks(keep)
    refreshWindow()
end

local function move(id, step)
    local _, shown = entries()
    for i, v in ipairs(shown) do
        if v == id then
            local j = i + step
            if j >= 1 and j <= #shown then shown[i], shown[j] = shown[j], shown[i] end
            break
        end
    end
    saveShown(shown)
end

local function toggle(id, on)
    local _, shown = entries()
    local out = {}
    for _, v in ipairs(shown) do
        if v ~= id then out[#out + 1] = v end
    end
    if on then out[#out + 1] = id end
    saveShown(out)
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win.content)
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self) toggle(r.id, self:GetChecked() and true or false) end)
    r.text = Glass.Font(r, 12, "LEFT")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.up = API.Button(r, "Up", 44, function() move(r.id, -1) end)
    r.up:SetPoint("RIGHT", r, "RIGHT", -52, 0)
    r.down = API.Button(r, "Down", 48, function() move(r.id, 1) end)
    r.down:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    rows[i] = r
    return r
end

refreshWindow = function()
    if not win then return end
    local list, shown, used = entries()
    local pos = {}
    for i, id in ipairs(shown) do pos[id] = i end
    for i, c in ipairs(list) do
        local r = row(i)
        r.id = c.id
        r.check:SetChecked(used[c.id] == true)
        r.text:SetText(icon(c, 16) .. " " .. c.name .. "  |cffaaaaaa" .. amount(c) .. "|r")
        r.up:SetShown(used[c.id] == true)
        r.down:SetShown(used[c.id] == true)
        r.up:SetEnabled(pos[c.id] ~= nil and pos[c.id] > 1)
        r.down:SetEnabled(pos[c.id] ~= nil and pos[c.id] < #shown)
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    win.content:SetHeight(math.max(#list, 1) * ROW_H)
    win.empty:SetShown(#list == 0)
end

-- Currency events come in bursts (login, loot): one refresh per frame.
local refreshQueued = false
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if win and win:IsShown() then refreshWindow() end
    end)
end

local function openWindow()
    if not win then
        win = API.Window("GlassPanelCurrenciesWindow", 400, 320)
        win.title:SetText("Currencies on the bar")
        win.hint:SetText("Tick to show, Up/Down to order. Expanded a header in the currency tab? Reopen this"
            .. " window to see what it holds.")
        local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, -8)
        scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 42)
        win.content = CreateFrame("Frame", nil, scroll)
        win.content:SetSize(ROW_W, ROW_H)
        scroll:SetScrollChild(win.content)
        API.AutoHideScrollBar(scroll)
        win.empty = Glass.Font(win.content, 12, "LEFT")
        win.empty:SetPoint("TOPLEFT", win.content, "TOPLEFT", 4, -4)
        win.empty:SetText("|cffaaaaaaNo currencies yet on this character.|r")
        local close = API.Button(win, "Close", 90, function() win:Hide() end)
        close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    end
    refreshWindow()
    win:Show()
end

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
    onEvent = function() if win and win:IsShown() then queueRefresh() end end,
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
    block._test = { available = available, picks = picks, window = function() return win end, rows = rows }
end
