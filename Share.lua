-- Share.lua: the bar setup as a copyable string (#34), to move it from one
-- account to another, like Edit Mode's layout sharing.
--
-- What travels: the settings that describe the setup (layout, hidden,
-- labels, labelsFor, iconsFor, room, font, shown). Not plugins' own data
-- (Layer's known layers, XP's session).
--
-- Format: "GP1:" + base64 of a tiny serialisation (strings, numbers,
-- booleans, tables; keys sorted, so the same setup gives the same string).
-- Our own encoder and decoder, no libraries, and the input is NEVER run as
-- code: it's parsed with hard limits (length, depth, count), then every key
-- and type is checked against what the core expects. Unknown keys are
-- dropped; a wrong type rejects the whole string. A string that fails
-- changes nothing and says why. A good one is applied at once, no reload.
-- An export is decoded again before it's shown: the core never hands out a
-- string it would refuse.
--
-- The window: a glass frame with a multi-line EditBox (the dump has
-- SetMultiLine, HighlightText, SetFocus). Addons can't touch the
-- clipboard: the text is selected, the user copies it with Ctrl+C.

GlassPanel = GlassPanel or {}
local API, Glass, Layout, Settings = GlassPanel.API, GlassPanel.Glass, GlassPanel.Layout, GlassPanel.Settings
local Share = {}
GlassPanel.Share = Share

local PREFIX = "GP1:"
local MAX_INPUT = 16384   -- characters of a pasted string
local MAX_DEPTH = 6       -- setup > layout > lane > ids > id is 4
local MAX_NODES = 2000    -- values in one string (a 100-block setup is ~800)
local MAX_STRING = 128    -- characters in one string value (ids are short)

--------------------------------------------------------------------------------
-- Serialisation
--------------------------------------------------------------------------------

-- Keys in a fixed order: numbers ascending, then strings.
local function keyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end

local function serialize(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        assert(finite(v), "not a finite number")
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do
            assert(type(k) == "string" or type(k) == "number", "bad key type")
            keys[#keys + 1] = k
        end
        table.sort(keys, keyOrder)
        out[#out + 1] = "t"
        for _, k in ipairs(keys) do
            serialize(k, out)
            serialize(v[k], out)
        end
        out[#out + 1] = "e"
    else
        error("can't serialise a " .. t)
    end
end

-- The value in s, or nil and why. Never more than the limits allow.
local function deserialize(s)
    local pos, nodes = 1, 0
    local read
    local function value(depth)
        nodes = nodes + 1
        if nodes > MAX_NODES then return nil, "too many values" end
        local c = s:sub(pos, pos)
        if c == "s" then
            local _, e, len = s:find("^s(%d+):", pos)
            len = tonumber(len)
            if not len or len > MAX_STRING then return nil, "bad string" end
            local str = s:sub(e + 1, e + len)
            if #str ~= len then return nil, "truncated" end
            pos = e + len + 1
            return str
        elseif c == "n" then
            local _, e, num = s:find("^n([%-%+%.%deE]+);", pos)
            num = tonumber(num)
            if not num or not finite(num) then return nil, "bad number" end
            pos = e + 1
            return num
        elseif c == "T" or c == "F" then
            pos = pos + 1
            return c == "T"
        elseif c == "t" then
            if depth >= MAX_DEPTH then return nil, "nested too deep" end
            pos = pos + 1
            local tbl = {}
            while true do
                if pos > #s then return nil, "truncated" end
                if s:sub(pos, pos) == "e" then
                    pos = pos + 1
                    return tbl
                end
                local k, why = read(depth + 1)
                if k == nil then return nil, why end
                if type(k) ~= "string" and type(k) ~= "number" then return nil, "bad key" end
                local v, why2 = read(depth + 1)
                if v == nil then return nil, why2 end
                if tbl[k] ~= nil then return nil, "repeated key" end
                tbl[k] = v
            end
        end
        return nil, (pos > #s) and "truncated" or "unexpected data"
    end
    read = value
    local v, why = value(0)
    if v == nil then return nil, why end
    if pos <= #s then return nil, "trailing data" end
    return v
end

--------------------------------------------------------------------------------
-- Base64 (standard alphabet, "=" padding)
--------------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, 64 do VALUE[ALPHABET:sub(i, i)] = i - 1 end

local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144), math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
            .. (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=") .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

-- The bytes, or nil for anything that isn't clean base64.
local function b64decode(text)
    if #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local q = text:sub(i, i + 3)
        local pad = 0
        if i + 3 == #text then
            if q:sub(4) == "=" then pad = 1 end
            if q:sub(3) == "==" then pad = 2 end
        end
        local n = 0
        for j = 1, 4 do
            local ch = q:sub(j, j)
            local v = VALUE[ch]
            if not v then
                if ch == "=" and j > 4 - pad then v = 0 else return nil end
            end
            n = n * 64 + v
        end
        local a, b, c = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
        if pad == 0 then out[#out + 1] = string.char(a, b, c)
        elseif pad == 1 then out[#out + 1] = string.char(a, b)
        else out[#out + 1] = string.char(a) end
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- The setup
--------------------------------------------------------------------------------

local function copyMap(m)
    local out = {}
    for k, v in pairs(m or {}) do out[k] = v end
    return out
end

-- What an export carries: the current settings. The layout is the effective
-- one (Layout.Lanes: saved lanes plus blocks never moved), so the other
-- account sees exactly this arrangement, whatever its defaults.
function Share.Current()
    local d = GlassPanelDB
    return {
        font = d.font, shown = d.shown, room = d.room, labels = d.labels,
        hidden = copyMap(d.hidden), labelsFor = copyMap(d.labelsFor), iconsFor = copyMap(d.iconsFor),
        layout = Layout.Lanes(),
    }
end

function Share.Encode(setup)
    local out = {}
    serialize(setup, out)
    return PREFIX .. b64encode(table.concat(out))
end

-- The ids GlassPanel.RegisterBlock accepts: any non-empty string (the
-- decoder already caps its length). Anything the core can export, it must
-- be able to import; ids are only ever table keys, never shown or run.
local function validId(id)
    return type(id) == "string" and id ~= ""
end

-- A table whose keys are exactly 1..n.
local function isList(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

-- id -> value map where every value passes `ok`; nil and why otherwise.
local function cleanMap(raw, name, ok)
    if raw == nil then return {} end
    if type(raw) ~= "table" then return nil, name .. " isn't a list" end
    local out = {}
    for id, v in pairs(raw) do
        if not validId(id) then return nil, name .. ": bad block id" end
        if not ok(v) then return nil, name .. ": bad value" end
        out[id] = v
    end
    return out
end

local function isBool(v) return type(v) == "boolean" end

-- The lanes, strictly: a wrong shape rejects the string (SavedVariables are
-- forgiving, Layout.Clean; an import says what's wrong instead). Empty lanes
-- are left out.
local function cleanLayout(raw)
    if raw == nil then return {} end
    if type(raw) ~= "table" or not isList(raw) then return nil, "layout isn't a list" end
    local out, seen = {}, {}
    for i, lane in ipairs(raw) do
        if type(lane) ~= "table" or type(lane.x) ~= "number" or lane.x < 0 or lane.x > 1
            or type(lane.ids) ~= "table" or not isList(lane.ids) then
            return nil, "layout: bad lane " .. i
        end
        local ids = {}
        for _, id in ipairs(lane.ids) do
            if not validId(id) then return nil, "layout: bad block id" end
            if seen[id] then return nil, "layout: a block listed twice" end
            seen[id] = true
            ids[#ids + 1] = id
        end
        if #ids > 0 then out[#out + 1] = { x = lane.x, ids = ids } end
    end
    return out
end

-- A decoded table checked against what the core expects: a setup ready to
-- apply, or nil and why. A missing key takes the default (the string is the
-- whole setup); an unknown one is dropped.
function Share.Clean(raw)
    if type(raw) ~= "table" then return nil, "not a setup" end
    local D = Settings.DEFAULTS
    local out = {}
    local font = raw.font == nil and D.font or raw.font
    if not (type(font) == "string" and Glass.FONTS[font]) then return nil, "unknown font" end
    out.font = font
    local room = raw.room == nil and D.room or raw.room
    if room ~= "auto" and room ~= "full" then return nil, "bad room setting" end
    out.room = room
    for _, k in ipairs({ "shown", "labels" }) do
        local v = raw[k]
        if v == nil then v = D[k] end
        if not isBool(v) then return nil, k .. " isn't on/off" end
        out[k] = v
    end
    local why
    out.hidden, why = cleanMap(raw.hidden, "hidden", function(v) return v == true end)
    if not out.hidden then return nil, why end
    out.labelsFor, why = cleanMap(raw.labelsFor, "labels", isBool)
    if not out.labelsFor then return nil, why end
    out.iconsFor, why = cleanMap(raw.iconsFor, "icons", function(v) return v == false end)
    if not out.iconsFor then return nil, why end
    out.layout, why = cleanLayout(raw.layout)
    if not out.layout then return nil, why end
    return out
end

-- A pasted string -> a setup, or nil and why (for the user).
function Share.Decode(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:gsub("%s+", "")
    if text == "" then return nil, "nothing to import" end
    if #text > MAX_INPUT then return nil, "too long to be a GlassPanel setup" end
    if text:sub(1, #PREFIX) ~= PREFIX then
        if text:find("^GP%d+:") then return nil, "made by a newer GlassPanel (update this one)" end
        return nil, "not a GlassPanel setup string"
    end
    local bytes = b64decode(text:sub(#PREFIX + 1))
    if not bytes then return nil, "damaged string (incomplete copy?)" end
    local raw, why = deserialize(bytes)
    if raw == nil then return nil, "damaged string (" .. why .. ")" end
    return Share.Clean(raw)
end

-- One line saying what a setup holds.
function Share.Describe(setup)
    local blocks = 0
    for _, lane in ipairs(setup.layout) do blocks = blocks + #lane.ids end
    local hidden = 0
    for _ in pairs(setup.hidden) do hidden = hidden + 1 end
    return string.format("%d block(s) in %d lane(s), %d hidden; font %s, room %s%s", blocks, #setup.layout, hidden,
        setup.font, setup.room, setup.shown and "" or ", bar hidden")
end

-- Replace the setup with `setup` (from Share.Clean): through Settings, like
-- every other change.
function Share.Apply(setup) Settings.ApplyAll(setup) end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local win

local function preview()
    local text = win.edit:GetText() or ""
    if not text:find("%S") then
        win.pending = nil
        win.status:SetText("")
        win.action:Disable()
        return
    end
    local setup, why = Share.Decode(text)
    win.pending = setup
    if setup then
        win.status:SetText("|cff40ff40Ready:|r " .. Share.Describe(setup))
        win.action:Enable()
    else
        win.status:SetText("|cffff6060" .. why .. "|r")
        win.action:Disable()
    end
end

local function build()
    win = CreateFrame("Frame", "GlassPanelShareWindow", UIParent)
    win:SetSize(480, 260)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    win:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the Settings panel it's opened from
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    -- Escape closes it even when the text box doesn't have the focus
    -- (AltStable registers its export window the same way on Forever).
    local special = rawget(_G, "UISpecialFrames")
    if type(special) == "table" then table.insert(special, "GlassPanelShareWindow") end
    Glass.Apply(win, "small")

    win.title = Glass.Font(win, 14, "LEFT")
    win.title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
    win.hint = Glass.Font(win, 11, "LEFT")
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -6)
    win.hint:SetTextColor(0.75, 0.75, 0.75)

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -52)
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 64)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(420)
    scroll:SetScrollChild(edit)
    edit:SetScript("OnEscapePressed", function() win:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if win.mode == "export" then
            -- Read-only: typing puts the string back, selected.
            if userInput then
                self:SetText(win.exported)
                self:HighlightText()
            end
        elseif win.mode == "import" then
            preview()
        end
    end)
    win.edit = edit

    win.status = Glass.Font(win, 11, "LEFT")
    win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 40)
    win.status:SetPoint("RIGHT", win, "RIGHT", -14, 0)

    win.close = API.Button(win, "Close", 90, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    win.action = API.Button(win, "Import", 90, function()
        if not win.pending then return end
        Share.Apply(win.pending)
        API.Print("setup imported: " .. Share.Describe(win.pending))
        win:Hide()
    end)
    win.action:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
end

-- Open the window to export (the current setup, selected) or to import.
function Share.Open(mode)
    if not win then build() end
    win.mode = nil   -- no OnTextChanged work while the text is set below
    if mode == "export" then
        local setup = Share.Current()
        win.exported = Share.Encode(setup)
        win.title:SetText("Export GlassPanel setup")
        win.hint:SetText("Copy with Ctrl+C, then paste it into Import on the other account.")
        -- The string must import: never hand out one the decoder refuses
        -- (a setup grown past the limits).
        local ok, why = Share.Decode(win.exported)
        if ok then
            win.status:SetText(Share.Describe(setup))
        else
            win.status:SetText("|cffff6060This setup can't be shared: " .. why .. "|r")
        end
        win.action:Hide()
        win.edit:SetMaxLetters(0)   -- no cap on what we show
        win.edit:SetText(ok and win.exported or "")
        win.mode = "export"
    else
        win.pending = nil
        win.title:SetText("Import GlassPanel setup")
        win.hint:SetText("Paste an exported setup (Ctrl+V). It replaces this bar's layout and settings.")
        win.status:SetText("")
        win.action:Show()
        win.action:Disable()
        win.edit:SetMaxLetters(MAX_INPUT)
        win.edit:SetText("")
        win.mode = "import"
    end
    win:Show()
    win.edit:SetFocus()
    if mode == "export" then win.edit:HighlightText() end
end

Share._test = {
    serialize = function(v) local out = {}; serialize(v, out); return table.concat(out) end,
    deserialize = deserialize, b64encode = b64encode, b64decode = b64decode,
    window = function() return win end, PREFIX = PREFIX, MAX_INPUT = MAX_INPUT,
}
