-- Plugins/Reagents/Reagents.lua: your class reagents, the ones you pick, in
-- your order (#68). The chooser is Currencies' (#47); the list is a table
-- per class, since nothing in the client says which items a class uses.
--
-- Forever (70338 dump): C_Item.GetItemCount(id) for the count (bags only),
-- C_Item.GetItemIconByID(id) for the icon (nil: the client doesn't know the
-- id, and it's left out), C_Item.GetItemNameByID(id) for the name (nil until
-- the item's data is loaded: requested once, on our own frame, as GearScore
-- does). The global GetItemInfo is absent.
--
-- Ammo (#66) and the warlock's shards and stones (#67) have their own
-- plugins and aren't listed here. Picks are per character
-- (## SavedVariablesPerCharacter). Never chosen: up to 3 of the class's
-- reagents the character carries, saved the first time they're found so the
-- bar doesn't change by itself. Every number through API.Plain: a secret
-- count is a grey "?", never a guess.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

-- Item ids by class file name, in the chooser's order. Poisons are in the
-- client's own consumables list (70009); the rest are Vanilla's reagents
-- (Informant's item data says class Reagent), not yet seen on this client:
-- an id it doesn't know is left out at runtime.
local CLASS = {
    ROGUE = {
        5140,                                       -- Flash Powder
        5530,                                       -- Blinding Powder (unverified)
        6947, 6949, 6950, 8926, 8927, 8928,         -- Instant Poison I-VI
        2892, 2893, 8984, 8985, 20844,              -- Deadly Poison I-V
        3775, 3776,                                 -- Crippling Poison I-II
        5237, 6951, 9186,                           -- Mind-numbing Poison I-III
        10918, 10920, 10921, 10922,                 -- Wound Poison I-IV
    },
    MAGE    = { 17020, 17031, 17032, 17056 },       -- Arcane Powder, Runes of Teleportation and Portals, Light Feather
    PRIEST  = { 17028, 17029, 17056 },              -- Holy Candle, Sacred Candle, Light Feather
    SHAMAN  = { 17030 },                            -- Ankh
    PALADIN = { 17033, 21177 },                     -- Symbol of Divinity, Symbol of Kings
    DRUID   = { 17021, 17026,                       -- Wild Berries, Wild Thornroot
                17034, 17035, 17036, 17037, 17038 }, -- Maple, Stranglethorn, Ashwood, Hornbeam, Ironwood Seed
    WARLOCK = { 5565, 16583 },                      -- Infernal Stone, Demonic Figurine
}
local DEFAULT_MAX = 3   -- first-run picks: up to this many carried

local function db()
    local d = rawget(_G, "GlassPanelReagentsDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelReagentsDB = d
    end
    if d.order ~= nil and type(d.order) ~= "table" then d.order = nil end
    return d
end

local function classList()
    local _, file = UnitClass("player")
    file = P(file)
    return type(file) == "string" and CLASS[file] or {}
end

--------------------------------------------------------------------------------
-- Names load late: requested once, answered on our own frame, which listens
-- only while one of ours is pending (the load events fire for every item).
--------------------------------------------------------------------------------

local pending = {}
local LOAD_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
local loader = CreateFrame("Frame")
local listening = false
local refreshWindowSoon
local function listen(on)
    if on == listening then return end
    listening = on
    for _, e in ipairs(LOAD_EVENTS) do
        if on then API.RegisterEvent(loader, e, "Reagents") else loader:UnregisterEvent(e) end
    end
end
loader:SetScript("OnEvent", function(_, _, rawId)
    local id = P(rawId)
    if id and pending[id] then
        pending[id] = nil
        GlassPanel.Refresh("reagents")
        refreshWindowSoon()
    end
    if next(pending) == nil then listen(false) end
end)

local function request(id)
    if pending[id] then return end
    pending[id] = true
    C_Item.RequestLoadItemDataByID(id)
    listen(true)
end

-- One item by id: { id, name (nil while loading), count (nil = unreadable),
-- icon }, or nil when the client doesn't know the id.
local function info(id)
    local okI, icon = pcall(C_Item.GetItemIconByID, id)
    icon = okI and P(icon) or nil
    if type(icon) ~= "number" and type(icon) ~= "string" then return nil end
    local okN, name = pcall(C_Item.GetItemNameByID, id)
    name = okN and P(name) or nil
    if type(name) ~= "string" or name == "" then
        name = nil
        request(id)
    end
    local okC, count = pcall(C_Item.GetItemCount, id)
    count = okC and P(count) or nil
    return { id = id, name = name, count = type(count) == "number" and count or nil, icon = icon }
end

-- The class's reagents the client knows, in the table's order.
local function available()
    local list = {}
    for _, id in ipairs(classList()) do list[#list + 1] = info(id) end
    return list
end

-- The picked ids, in order (each once). Never chosen: the carried ones,
-- saved now so they stay put.
local function picks(avail)
    local d = db()
    if not d.order then
        local out = {}
        for _, c in ipairs(avail or available()) do
            if c.count and c.count > 0 and #out < DEFAULT_MAX then out[#out + 1] = c.id end
        end
        if #out == 0 then return out end   -- nothing carried yet: decide when there is
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
    GlassPanel.Refresh("reagents")
end

local function icon(c, size)
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", tostring(c.icon), size, size)
end

-- None left is red: the spell won't cast.
local function amount(c)
    if c.count == nil then return "|cff888888?|r" end
    if c.count == 0 then return "|cffff40400|r" end
    return BreakUpLargeNumbers(c.count)
end

local function name(c)
    return c.name or ("|cff888888item " .. c.id .. "|r")
end

--------------------------------------------------------------------------------
-- The chooser window: the class's reagents, a checkbox to show each, Up/Down
-- to order the shown ones. (A copy of Currencies' chooser; a shared one is a
-- possible follow-up once a third plugin wants it.)
--------------------------------------------------------------------------------

local win, rows = nil, {}
local ROW_W, ROW_H = 340, 26

-- The rows: the shown ones first, in order (only those the client resolves),
-- then the rest in the class's order. `shown` is that first part, as ids.
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
        r.text:SetText(icon(c, 16) .. " " .. name(c) .. "  |cffaaaaaa" .. amount(c) .. "|r")
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

-- Bag and item-load events come in bursts: one refresh per frame.
local refreshQueued = false
refreshWindowSoon = function()
    if refreshQueued or not (win and win:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if win and win:IsShown() then refreshWindow() end
    end)
end

local function openWindow()
    if not win then
        win = API.Window("GlassPanelReagentsWindow", 400, 320)
        win.title:SetText("Reagents on the bar")
        win.hint:SetText("Tick to show, Up/Down to order. Counts are what your bags hold.")
        local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, -8)
        scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 42)
        win.content = CreateFrame("Frame", nil, scroll)
        win.content:SetSize(ROW_W, ROW_H)
        scroll:SetScrollChild(win.content)
        API.AutoHideScrollBar(scroll)
        win.empty = Glass.Font(win.content, 12, "LEFT")
        win.empty:SetPoint("TOPLEFT", win.content, "TOPLEFT", 4, -4)
        win.empty:SetText("|cffaaaaaaNo class reagents for this character.|r")
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
    id = "reagents",
    label = "Reagents",
    showLabel = false,   -- each reagent carries its own icon
    side = "right",
    order = 125,
    events = { "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
    onEvent = function() refreshWindowSoon() end,
    -- nil hides the block: nothing picked (a hunter or warrior has no list).
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
        tt:AddLine("Reagents")
        for _, id in ipairs(picks()) do
            local c = info(id)
            if c then tt:AddDoubleLine(icon(c, 14) .. " " .. name(c), amount(c), 1, 0.82, 0, 1, 1, 1) end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: choose reagents", 0.3, 1, 0.3)
    end,
    onClick = function(_, button) if button == "LeftButton" then openWindow() end end,
    options = {
        { label = "Choose reagents...", run = openWindow,
          note = "Which of your class's reagents the bar shows, and in what order (this character)." },
    },
})

if block then
    block._test = { CLASS = CLASS, available = available, picks = picks, rows = rows,
                    window = function() return win end, pending = function() return pending end }
end
