-- Plugins/Currencies/Currencies.lua: the currencies you pick, in your order
-- (#47), like TitanCurrenciesMulti in WotLK Classic, but from the client's
-- own list rather than hardcoded per-expansion tables.
--
-- Forever (70009 dump): C_CurrencyInfo.GetCurrencyListSize / GetCurrencyListInfo
-- (the currency tab: headers and currencies; a collapsed header hides its
-- currencies, and we never expand the player's tab), GetCurrencyListLink +
-- GetCurrencyIDFromLink for the id, GetCurrencyInfo(id) for one currency,
-- CURRENCY_DISPLAY_UPDATE. Forever's currencies (Wowhead's Forever
-- database, owner, 2026-09-29) are offered even before the character owns
-- any, when the client resolves them to a name: Merchant's Favor 3402,
-- Tarnished Undermine Real 3469, Honor Points 1792, Rank Points 3468,
-- Darkmoon Prize Ticket 515.
--
-- Picks are per character (## SavedVariablesPerCharacter). Never configured:
-- the currencies it has some of. Every number through API.Plain: a secret
-- amount is a grey "?", never a guess. Unmeasured: whether amounts are plain.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local KNOWN = { 3402, 3469, 1792, 3468, 515 }   -- Forever's currencies, offered before the character has any
local DEFAULT_MAX = 3                 -- first-run picks: up to this many owned

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
        if ok and type(row) == "table" and P(row.isHeader) ~= true then
            local okL, link = pcall(C_CurrencyInfo.GetCurrencyListLink, i)
            local okI, id = false, nil
            if okL and type(P(link)) == "string" then okI, id = pcall(C_CurrencyInfo.GetCurrencyIDFromLink, link) end
            id = okI and P(id) or nil
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                list[#list + 1] = info(id)
            end
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

-- The picked ids, in order. First run: the ones the character has some of.
local function picks()
    local d = db()
    if d.order then return d.order end
    local out = {}
    for _, c in ipairs(available()) do
        if c.quantity and c.quantity > 0 and #out < DEFAULT_MAX then out[#out + 1] = c.id end
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
    return BreakUpLargeNumbers and BreakUpLargeNumbers(c.quantity) or tostring(c.quantity)
end

--------------------------------------------------------------------------------
-- The chooser window: every currency, a checkbox to show it, up/down to
-- order the shown ones.
--------------------------------------------------------------------------------

local win, rows = nil, {}
local ROW_H = 26

local refreshWindow

local function move(id, step)
    local order = {}
    for i, v in ipairs(picks()) do order[i] = v end
    for i, v in ipairs(order) do
        if v == id then
            local j = i + step
            if j >= 1 and j <= #order then order[i], order[j] = order[j], order[i] end
            break
        end
    end
    setPicks(order)
    refreshWindow()
end

local function toggle(id, on)
    local order = {}
    for _, v in ipairs(picks()) do
        if v ~= id then order[#order + 1] = v end
    end
    if on then order[#order + 1] = id end
    setPicks(order)
    refreshWindow()
end

local function row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, win.content)
    r:SetSize(360, ROW_H)
    r:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self) toggle(r.id, self:GetChecked() and true or false) end)
    r.text = Glass.Font(r, 12, "LEFT")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.up = API.Button(r, "Up", 44, function() move(r.id, -1) end)
    r.up:SetPoint("RIGHT", r, "RIGHT", -50, 0)
    r.down = API.Button(r, "Down", 48, function() move(r.id, 1) end)
    r.down:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    rows[i] = r
    return r
end

-- Shown ones first, in their order; then the rest by name.
local function entries()
    local byId, list, used = {}, {}, {}
    for _, c in ipairs(available()) do byId[c.id] = c end
    for _, id in ipairs(picks()) do
        local c = byId[id] or info(id)
        if c then list[#list + 1] = c; used[id] = true end
    end
    for _, c in ipairs(available()) do
        if not used[c.id] then list[#list + 1] = c end
    end
    return list, used
end

refreshWindow = function()
    if not win then return end
    local list, used = entries()
    local shownCount = 0
    for _ in pairs(used) do shownCount = shownCount + 1 end
    local pos = {}
    for i, id in ipairs(picks()) do pos[id] = i end
    for i, c in ipairs(list) do
        local r = row(i)
        r.id = c.id
        r.check:SetChecked(used[c.id] == true)
        r.text:SetText(icon(c, 16) .. " " .. c.name .. "  |cffaaaaaa" .. amount(c) .. "|r")
        r.up:SetShown(used[c.id] == true)
        r.down:SetShown(used[c.id] == true)
        r.up:SetEnabled(pos[c.id] ~= nil and pos[c.id] > 1)
        r.down:SetEnabled(pos[c.id] ~= nil and pos[c.id] < shownCount)
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    win.content:SetHeight(math.max(#list, 1) * ROW_H)
    win.empty:SetShown(#list == 0)
end

local function openWindow()
    if not win then
        win = CreateFrame("Frame", "GlassPanelCurrenciesWindow", UIParent)
        win:SetSize(400, 320)
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        win:SetFrameStrata("FULLSCREEN_DIALOG")
        win:SetClampedToScreen(true)
        win:EnableMouse(true)
        local glass = Glass.Apply(win, "small")
        local backing = win:CreateTexture(nil, "BACKGROUND", nil, -7)
        backing:SetAllPoints(win)
        backing:SetColorTexture(0.05, 0.06, 0.08, 0.96)
        backing:AddMaskTexture(glass.mask)
        local special = rawget(_G, "UISpecialFrames")
        if type(special) == "table" then table.insert(special, "GlassPanelCurrenciesWindow") end
        local title = Glass.Font(win, 14, "LEFT")
        title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
        title:SetText("Currencies on the bar")
        local hint = Glass.Font(win, 11, "LEFT")
        hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        hint:SetTextColor(0.75, 0.75, 0.75)
        hint:SetText("Tick to show, Up/Down to order. Expand headers in the currency tab to see more.")
        local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -48)
        scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 42)
        win.content = CreateFrame("Frame", nil, scroll)
        win.content:SetSize(360, ROW_H)
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
    onEvent = function() if win and win:IsShown() then refreshWindow() end end,
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
                if c.max and c.quantity then right = right .. " / " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(c.max) or c.max) end
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
