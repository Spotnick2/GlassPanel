-- Plugins/Broker/Broker.lua: other addons' LibDataBroker-1.1 data sources on
-- the bar (#179), each one a block of its own, the ones the player picks.
--
-- Titan Panel's TitanLDB.lua is the data reference (what a data object
-- holds and in which order a display honours its tooltip fields); its
-- structure is not reused. What a data object gives us:
-- - text (else value and suffix): the block's value. A secret is a grey ?.
--   Only one given at creation reaches us: LibDataBroker's setter compares
--   the old value with the new before storing it, which throws on a secret on
--   the client, so a broker assigning one later errors in its own code and
--   its block keeps the last value (Codex on #180; the library is unmodified).
-- - label (else the broker's name): the caption, read at every repaint.
-- - icon and iconCoords: the icon, read at every repaint (an icon function).
--   No iconCoords: the whole texture, as Titan draws it (our own blocks trim
--   the stock icon border; a broker's art may have none).
-- - OnClick(frame, button), OnDoubleClick (undocumented, Titan honours it;
--   without it a double-click's second click goes to OnClick).
-- - The hover, Titan's priority: a `tooltip` frame (placed and shown here,
--   filled by the broker), then OnEnter/OnLeave (the broker does it all),
--   then OnTooltipShow(tt) filling the GameTooltip the core owns and shows.
--   A broker with none of them gets its name and text.
--
-- Data sources only (type "data source"): launchers are minimap buttons,
-- which GlassMiniMapBar collects; a picked broker that turns launcher leaves
-- the bar, its pick kept. A broker a Glass Panel plugin already shows
-- is not offered (COVERED). Every broker is off until the player ticks it in
-- the chooser (the plugin's option button); the picks are account-wide
-- (GlassPanelBrokerDB.picks, broker names). A broker can register before or
-- after us: blocks are made at PLAYER_LOGIN for those already there (every
-- addon's files have run, so COVERED's check is sure), then as they arrive
-- (LibDataBroker_DataObjectCreated, or a type given after creation). Any
-- change to a picked broker's attributes repaints its block, once a frame
-- (GlassPanel.Refresh). Un-ticked, a block's text is nil: off the bar at
-- once; it stays registered (the engine has no unregister), so its row in the
-- options' plugin list goes at the next /reload.
--
-- LibDataBroker-1.1 and CallbackHandler-1.0 are bundled in Libs\ (LibStub
-- comes with the core, from LibGlass): the newest copy loaded wins, and every
-- display shares the one registry.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local PREFIX = "ldb:"   -- block ids: "ldb:" .. the broker's name
local UNKNOWN = "|cffaaaaaa?|r"
local FULL = { 0, 1, 0, 1 }
-- Brokers a Glass Panel plugin shows better: not offered while that plugin is
-- loaded. AltStable's gold: [AltStable] has this side's scope and the session.
local COVERED = { AltStable = "GlassPanelAltStable" }

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

local function db()
    local d = rawget(_G, "GlassPanelBrokerDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelBrokerDB = d
    end
    if type(d.picks) ~= "table" then d.picks = {} end
    return d
end

-- The picks as a list of names (each once) and as a set.
local picked = {}
local function picks()
    local seen, out = {}, {}
    for _, name in ipairs(db().picks) do
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end
local function loadPicks()
    picked = {}
    for _, name in ipairs(picks()) do picked[name] = true end
end

-- A value a data object holds, as text: a string, a number written out, or
-- nil. Secret: nil and true (never compared, concatenated or measured).
local function asText(v)
    if API.IsSecret(v) then return nil, true end
    if type(v) == "string" then return v end
    if type(v) == "number" then return tostring(v) end
    return nil
end

local function isSource(obj)
    local t = obj.type
    return not API.IsSecret(t) and t == "data source"
end

local function covered(name)
    local addon = COVERED[name]
    if not addon then return false end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, addon)
    return ok and P(loaded) == true
end

local function objOf(name) return LDB and LDB:GetDataObjectByName(name) end

local function labelOf(name, obj)
    local l = obj and asText(obj.label)
    if l and l ~= "" then return l end
    return name
end

-- The block's value: text, else value and suffix; nil while not picked.
local function textOf(name)
    if not picked[name] then return nil end
    local obj = objOf(name)
    -- A broker that turned launcher leaves the bar (its pick is kept: a data
    -- source again, it comes back).
    if not (obj and isSource(obj)) then return nil end
    local text, secret = asText(obj.text)
    if secret then return UNKNOWN end
    if text == nil or text == "" then
        local value, vSecret = asText(obj.value)
        if vSecret then return UNKNOWN end
        if value and value ~= "" then
            local suffix = asText(obj.suffix)
            text = (suffix and suffix ~= "") and (value .. " " .. suffix) or value
        end
    end
    return text
end

-- A `tooltip` frame, below the block, on the side of the screen the block is on.
local function placeTip(tip, frame)
    tip:ClearAllPoints()
    local ok, x = pcall(frame.GetCenter, frame)
    x = ok and P(x) or nil
    local w = P(UIParent:GetWidth())
    if type(x) == "number" and type(w) == "number" and x > w / 2 then
        tip:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
    else
        tip:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
    end
end

local blocks = {}    -- name -> its block, or false when RegisterBlock refused it
local hover = {}     -- block -> the hover path that ran: a `tooltip` frame, or "enter"
local listener = {}  -- our CallbackHandler key

local function spec(name, obj)
    return {
        id = PREFIX .. name,
        label = labelOf(name, obj),
        side = "right",
        order = 200,   -- after Glass Panel's own blocks
        text = function() return textOf(name) end,
        caption = function()
            local o = objOf(name)
            return o and labelOf(name, o) or nil
        end,
        icon = function()
            local o = objOf(name)
            if not o then return nil end
            local tex = P(o.icon)
            if type(tex) ~= "number" and (type(tex) ~= "string" or tex == "") then return nil end
            local coords = o.iconCoords
            return tex, type(coords) == "table" and coords or FULL
        end,
        onEnter = function(block, frame)
            local o = objOf(name)
            if not o then return false end
            local tip = o.tooltip
            if type(tip) == "table" and type(tip.Show) == "function" then
                placeTip(tip, frame)
                tip:Show()
                hover[block] = tip
                return true
            end
            if type(o.OnEnter) == "function" then
                hover[block] = "enter"
                o.OnEnter(frame)
                return true
            end
            return false   -- OnTooltipShow, or nothing: the core's tooltip
        end,
        -- The cleanup of the path that ran: our `tooltip` frame hidden, or the
        -- broker's OnLeave (its tooltip is its own: it may keep it open while
        -- the pointer moves into it). The core's tooltip: the core hides it.
        onLeave = function(block, frame)
            local path = hover[block]
            hover[block] = nil
            if path == "enter" then
                local o = objOf(name)
                if o and type(o.OnLeave) == "function" then o.OnLeave(frame) end
            elseif path then
                path:Hide()
            end
        end,
        tooltip = function(_, tt)
            local o = objOf(name)
            if o and type(o.OnTooltipShow) == "function" then
                o.OnTooltipShow(tt)
                return
            end
            tt:AddLine(labelOf(name, o))
            local t = textOf(name)
            if t and t ~= "" then tt:AddLine(t, 1, 1, 1) end
        end,
        onClick = function(block, button)
            local o = objOf(name)
            if o and type(o.OnClick) == "function" then o.OnClick(block.widget, button) end
        end,
        onDoubleClick = function(block, button)
            local o = objOf(name)
            if not o then return end
            local fn = o.OnDoubleClick
            if type(fn) ~= "function" then fn = o.OnClick end
            if type(fn) == "function" then fn(block.widget, button) end
        end,
    }
end

-- A block for a picked data source, once.
local ready = false   -- PLAYER_LOGIN: every addon's files have run
local function ensure(name)
    if not (ready and picked[name]) or blocks[name] ~= nil then return end
    local obj = objOf(name)
    if not (obj and isSource(obj)) or covered(name) then return end
    local b = GlassPanel.RegisterBlock(spec(name, obj))
    blocks[name] = b or false
    if not b then return end
    -- Any attribute (text, icon, label, a script): repaint on the next frame.
    LDB.RegisterCallback(listener, "LibDataBroker_AttributeChanged_" .. name, function()
        GlassPanel.Refresh(b.id)
    end)
end

local function ensureAll()
    for _, name in ipairs(picks()) do ensure(name) end
end

-- The data sources on offer, by label.
local function available()
    local list = {}
    if not LDB then return list end
    for name, obj in LDB:DataObjectIterator() do
        if type(name) == "string" and isSource(obj) and not covered(name) then
            local tex = P(obj.icon)
            list[#list + 1] = { id = name, label = labelOf(name, obj),
                                icon = (type(tex) == "number" or type(tex) == "string") and tex or nil }
        end
    end
    table.sort(list, function(a, b)
        local la, lb = a.label:lower(), b.label:lower()
        if la ~= lb then return la < lb end
        return a.id < b.id
    end)
    return list
end

local function save(order)
    db().picks = order
    loadPicks()
    ensureAll()
    for _, b in pairs(blocks) do
        if b then GlassPanel.Refresh(b.id) end
    end
end

local picker = API.Picker({
    name = "GlassPanelBrokerWindow",
    title = "Data brokers on the bar",
    hint = "Tick a broker to give it a block of its own; drag it on the bar like any other. A broker"
        .. " a Glass Panel plugin already shows (AltStable's) isn't listed.",
    empty = "|cffaaaaaaNone of your addons offers a data source.|r",
    ordered = false,
    items = available,
    picks = function() return picks() end,
    resolve = function() return nil end,   -- a pick whose addon isn't loaded now: kept
    save = save,
    label = function(e)
        local icon = e.icon and string.format("|T%s:16:16|t ", tostring(e.icon)) or ""
        local text = icon .. e.label
        if e.label ~= e.id then text = text .. "  |cffaaaaaa" .. e.id .. "|r" end
        return text
    end,
})

local options = GlassPanel.RegisterOptions({
    id = "broker",
    label = "Data brokers",
    options = {
        { label = "Choose data brokers...", run = picker.Open,
          note = "Other addons' LibDataBroker data sources, each a block of its own. Off until you tick them." },
    },
})

if LDB then
    -- Late brokers, and a broker that says it's a data source after creation.
    local function arrived(_, name)
        if type(name) == "string" then ensure(name) end
        picker.RefreshSoon()
    end
    LDB.RegisterCallback(listener, "LibDataBroker_DataObjectCreated", arrived)
    LDB.RegisterCallback(listener, "LibDataBroker_AttributeChanged__type", arrived)
end

local f = CreateFrame("Frame")
API.RegisterEvent(f, "ADDON_LOADED", "broker")
API.RegisterEvent(f, "PLAYER_LOGIN", "broker")
f:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon ~= "GlassPanelBroker" then return end
        self:UnregisterEvent("ADDON_LOADED")
        loadPicks()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        ready = true
        local ok, err = pcall(ensureAll)
        if not ok then API.Fail("broker:login", err) end
    end
end)

if options then
    options._test = { picker = picker, blocks = blocks, available = available, textOf = textOf, picks = picks }
end
