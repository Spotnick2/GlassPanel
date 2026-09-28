-- Engine.lua: the block registry and who gets repainted when.
--
-- A block is a declarative table (see RegisterBlock below and docs/PLUGINS.md).
-- The engine owns every event registration, so a plugin never creates a frame
-- to listen with:
--   - one event frame for all blocks; an event runs each listener's onEvent
--     immediately (state updates), then marks the block dirty;
--   - dirty blocks are repainted once per rendered frame, however many events
--     arrived in it (the flush frame shows itself only while work is pending);
--   - blocks with an `interval` are marked dirty by one shared 1 s clock;
--   - every call into a block runs under pcall. A block that throws is recorded
--     in GlassPanel.failures and shows an error mark; the others still paint.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local Engine = {}
GlassPanel.Engine = Engine

-- Bumped when the block contract changes incompatibly. Plugins may check it.
GlassPanel.API_VERSION = 1

Engine.blocks = {}      -- in registration order
Engine.byId = {}
local listeners = {}    -- event -> { block, ... }
local dirty = {}        -- block -> true
local seq = 0

local ERROR_TEXT = "|cffff6060error|r"

local eventFrame = CreateFrame("Frame")
local flushFrame = CreateFrame("Frame")
flushFrame:Hide()

-- Run fn(...) for block; record and swallow a throw. Returns ok, result.
local function call(block, what, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then API.Fail(block.id .. ":" .. what, res) end
    return ok, res
end
Engine.Call = call

function Engine.MarkDirty(block)
    dirty[block] = true
    flushFrame:Show()
end

function Engine.MarkAllDirty()
    for _, b in ipairs(Engine.blocks) do dirty[b] = true end
    flushFrame:Show()
end

-- Ask the block for its text and hand it to the bar; true if the text
-- changed. The contract is a plain string, or nil for "not on the bar": a
-- secret would reach the width measurement and the layout arithmetic, so it
-- is refused here, at the boundary. Then the block's own paint hook, if any,
-- draws whatever it built: only while its text is valid and non-nil and it
-- is on screen.
local function paint(block)
    local text
    local ok, res = call(block, "text", block.text, block)
    if not ok then
        text = ERROR_TEXT
    elseif API.IsSecret(res) then
        API.Fail(block.id .. ":text", "returned a secret value; format it or return nil")
        text = ERROR_TEXT
    elseif res ~= nil and type(res) ~= "string" then
        API.Fail(block.id .. ":text", "returned a " .. type(res) .. ", not a string")
        text = ERROR_TEXT
    else
        text = res
    end
    local changed = GlassPanel.Bar ~= nil and GlassPanel.Bar.SetText(block, text)
    -- Not while hidden (the user's /gpanel hide, or the bar toggled off):
    -- Bar.Layout marks the block dirty again when it comes back on screen.
    if block.paint and text ~= nil and text ~= ERROR_TEXT and GlassPanel.Bar.OnScreen(block) then
        call(block, "paint", block.paint, block)
    end
    return changed
end

function Engine.Flush()
    -- Idle first: a callback below that marks a block dirty shows the frame
    -- again, and that repaint happens next frame instead of being lost.
    flushFrame:Hide()
    local changed = false
    for _, block in ipairs(Engine.blocks) do
        if dirty[block] then
            dirty[block] = nil
            if block.widget and paint(block) then changed = true end
        end
    end
    -- Widths follow text, so only a changed text can move anything.
    if changed then GlassPanel.Bar.Layout() end
end
flushFrame:SetScript("OnUpdate", Engine.Flush)

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for _, block in ipairs(list) do
        if block.onEvent then call(block, "onEvent", block.onEvent, block, event, ...) end
        Engine.MarkDirty(block)
    end
end)

-- One shared clock for interval blocks. Always running, but it does nothing
-- more than add `elapsed` until a second has passed.
-- Core code that needs a once-a-second check (Room.lua) hooks in here, so
-- there is one clock. Each runs under pcall; a throw is recorded by key.
Engine.everySecond = {}   -- { { key, fn } }
function Engine.EverySecond(key, fn)
    Engine.everySecond[#Engine.everySecond + 1] = { key = key, fn = fn }
end

local clockFrame = CreateFrame("Frame")
local acc = 0
clockFrame:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    local step = acc
    acc = 0
    for _, block in ipairs(Engine.blocks) do
        if block.interval then
            block._due = (block._due or 0) - step
            if block._due <= 0 then
                block._due = Engine.NextInterval(block)
                Engine.MarkDirty(block)
            end
        end
    end
    for _, e in ipairs(Engine.everySecond) do
        local ok, err = pcall(e.fn)
        if not ok then API.Fail(e.key, err) end
    end
end)

-- Seconds until an interval block is next due. A function interval lets a
-- block wake exactly when its text changes (the clock: on the minute).
function Engine.NextInterval(block)
    if type(block.interval) ~= "function" then return block.interval end
    local ok, s = call(block, "interval", block.interval, block)
    if ok and type(s) == "number" and not API.IsSecret(s) and s >= 1 then return s end
    return 1
end

local function listen(block, event)
    if not listeners[event] then
        if not API.RegisterEvent(eventFrame, event, block.id) then return end
        listeners[event] = {}
    end
    table.insert(listeners[event], block)
end

local function invalid(spec, why)
    local id = type(spec) == "table" and type(spec.id) == "string" and spec.id or "?"
    API.Print("|cffff6060RegisterBlock refused|r " .. id .. ": " .. why)
    return nil
end

-- The public entry point. Returns the block (the spec itself) or nil.
-- Required: id (unique string), text = function(block) -> string|nil.
-- Optional: label (also the gold caption before the value, unless
--   showLabel = false), icon, side ("left"|"center"|"right": the default lane),
--   order (number, default 100),
--   events = { "EVENT", ... }, onEvent(block, event, ...),
--   interval (seconds, or function(block) -> seconds until the next repaint),
--   tooltip(block, GameTooltip), onClick(block, mouseButton), onInit(block),
--   onShown(block, visible) when it appears on or leaves the screen.
-- For a block that draws more than text (the XP bar):
--   width (fixed, px), build(block) once its widget exists (block.widget),
--   paint(block) after every repaint while its text is non-nil. With a width,
--   text "" still shows the block; nil hides it.
function GlassPanel.RegisterBlock(spec)
    if type(spec) ~= "table" then return invalid(spec, "not a table") end
    if type(spec.id) ~= "string" or spec.id == "" then return invalid(spec, "id must be a non-empty string") end
    if Engine.byId[spec.id] then return invalid(spec, "id already registered") end
    if type(spec.text) ~= "function" then return invalid(spec, "text must be a function") end
    if spec.side ~= nil and spec.side ~= "left" and spec.side ~= "center" and spec.side ~= "right" then
        return invalid(spec, "side must be \"left\", \"center\" or \"right\"")
    end
    if spec.interval ~= nil and type(spec.interval) ~= "function"
        and (type(spec.interval) ~= "number" or spec.interval < 1) then
        return invalid(spec, "interval must be seconds (at least 1) or a function returning them")
    end
    if spec.label ~= nil and type(spec.label) ~= "string" then return invalid(spec, "label must be a string") end
    if spec.showLabel ~= nil and type(spec.showLabel) ~= "boolean" then return invalid(spec, "showLabel must be a boolean") end
    if spec.events ~= nil then
        if type(spec.events) ~= "table" then return invalid(spec, "events must be a list of event names") end
        for _, e in ipairs(spec.events) do
            if type(e) ~= "string" then return invalid(spec, "events must be a list of event names") end
        end
    end
    if spec.width ~= nil and (type(spec.width) ~= "number" or spec.width ~= spec.width or spec.width < 16) then
        return invalid(spec, "width must be a number of pixels, at least 16")
    end
    for _, key in ipairs({ "onEvent", "tooltip", "onClick", "onInit", "onShown", "build", "paint" }) do
        if spec[key] ~= nil and type(spec[key]) ~= "function" then return invalid(spec, key .. " must be a function") end
    end

    seq = seq + 1
    spec.side = spec.side or "left"
    spec.order = type(spec.order) == "number" and spec.order or 100
    spec.label = spec.label or spec.id
    spec._seq = seq
    spec._due = Engine.NextInterval(spec)
    table.insert(Engine.blocks, spec)
    Engine.byId[spec.id] = spec

    local seen = {}
    for _, event in ipairs(spec.events or {}) do
        if not seen[event] then seen[event] = true; listen(spec, event) end   -- a repeat would run onEvent twice
    end
    if spec.onInit then call(spec, "onInit", spec.onInit, spec) end
    -- Plugins may load before or after the bar is built: attach now if it is.
    if GlassPanel.Bar and GlassPanel.Bar.frame then GlassPanel.Bar.Attach(spec) end
    Engine.MarkDirty(spec)
    return spec
end

-- For a plugin whose data changed without an event: repaint on the next frame.
function GlassPanel.Refresh(id)
    local block = Engine.byId[id]
    if block then Engine.MarkDirty(block) end
end

GlassPanel.Engine._test = { listeners = listeners, dirty = dirty, flushFrame = flushFrame, clockFrame = clockFrame }
