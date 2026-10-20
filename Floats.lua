-- Floats.lua: zoomed plugins that float on the screen (XP+'s bar, the combat
-- timer's pill, #108) must not overlap each other. The rule:
--   * a float with no saved spot sits in a DEFAULT slot, stacked down from the
--     top by `order` below every float of lower order that is shown and unplaced
--     (so the pill starts under XP+'s bar, and moves up when that is docked);
--   * a float the player drops onto another SNAPS to the nearest free side;
--   * a saved spot otherwise stays exactly where the player put it.
-- Plugins reach it only through the API (additive; API_VERSION unchanged):
--   API.RegisterFloat(frame, { order = n, placed = fn() -> bool, place = fn() })
--     once per frame. `placed` says whether the player saved a spot; `place`
--     puts the frame where it belongs (it asks API.FloatDefaultY when unplaced).
--     The frame is tracked for the top-edge announcement too (API.TrackTopEdge).
--   API.FloatDefaultY(frame) -> the y offset from UIParent's top, in UIParent
--     units (negative), for an unplaced float.
--   API.PlaceFloats() -> after a float shows, hides or rescales: every shown
--     unplaced float is placed again.
--   API.SnapFloat(frame) -> after a drop, before saving the spot: moves the
--     frame out of any overlap; true when it moved.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local Floats = {}
GlassPanel.Floats = Floats

Floats.TOP = -40     -- the first default slot, from UIParent's top (XP+'s own default since #3)
Floats.GAP = 8

local list = {}      -- { frame, order, placed, place }, in registration order

local function num(v)
    v = API.Plain(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

-- The frame's rect in UIParent units ({ l, r, b, t }), or nil for anything unreadable.
local function rect(frame)
    local s, ui = num(frame:GetEffectiveScale()), num(UIParent:GetEffectiveScale())
    local l, r, b, t = num(frame:GetLeft()), num(frame:GetRight()), num(frame:GetBottom()), num(frame:GetTop())
    if not (s and ui and l and r and b and t) or s <= 0 or ui <= 0 then return nil end
    local k = s / ui
    return { l = l * k, r = r * k, b = b * k, t = t * k }
end

-- Pure: the smallest shift (dx, dy) that takes `r` clear of every rect in
-- `others` (with GAP between), trying each overlapped one's four sides.
function Floats.Snap(r, others)
    local x, y = 0, 0
    for _ = 1, #others + 1 do
        local cur = { l = r.l + x, r = r.r + x, b = r.b + y, t = r.t + y }
        local hit
        for _, o in ipairs(others) do
            if cur.l < o.r and cur.r > o.l and cur.b < o.t and cur.t > o.b then hit = o break end
        end
        if not hit then return x, y end
        local cands = {
            { hit.r - cur.l + Floats.GAP, 0 }, { hit.l - cur.r - Floats.GAP, 0 },
            { 0, hit.t - cur.b + Floats.GAP }, { 0, hit.b - cur.t - Floats.GAP },
        }
        local best = cands[1]
        for _, c in ipairs(cands) do
            if math.abs(c[1]) + math.abs(c[2]) < math.abs(best[1]) + math.abs(best[2]) then best = c end
        end
        x, y = x + best[1], y + best[2]
    end
    return x, y
end

local function entryOf(frame)
    for _, e in ipairs(list) do if e.frame == frame then return e end end
end

local function shown(e) return API.Plain(e.frame:IsShown()) == true end
local function isPlaced(e)
    local ok, v = pcall(e.placed)
    return ok and v == true
end

function API.RegisterFloat(frame, opts)
    if type(frame) ~= "table" or type(opts) ~= "table" or entryOf(frame) then return false end
    if type(opts.order) ~= "number" or type(opts.placed) ~= "function" or type(opts.place) ~= "function" then return false end
    list[#list + 1] = { frame = frame, order = opts.order, placed = opts.placed, place = opts.place }
    API.TrackTopEdge(frame)
    return true
end

function API.FloatDefaultY(frame)
    local me = entryOf(frame)
    local y = Floats.TOP
    if not me then return y end
    local ui = num(UIParent:GetEffectiveScale()) or 1
    local before = {}
    for _, e in ipairs(list) do
        if e ~= me and e.order < me.order and shown(e) and not isPlaced(e) then before[#before + 1] = e end
    end
    table.sort(before, function(a, b) return a.order < b.order end)
    for _, e in ipairs(before) do
        local h = num(e.frame:GetHeight()) or 0
        local s = num(e.frame:GetEffectiveScale()) or ui
        y = y - h * s / ui - Floats.GAP
    end
    return y
end

function API.PlaceFloats()
    for _, e in ipairs(list) do
        if shown(e) and not isPlaced(e) then
            local ok, err = pcall(e.place)
            if not ok then API.Fail("float:place", err) end
        end
    end
end

function API.SnapFloat(frame)
    local me = entryOf(frame)
    if not me then return false end
    local mine = rect(frame)
    if not mine then return false end
    local others = {}
    for _, e in ipairs(list) do
        if e ~= me and shown(e) then
            local r = rect(e.frame)
            if r then others[#others + 1] = r end
        end
    end
    local dx, dy = Floats.Snap(mine, others)
    if dx == 0 and dy == 0 then return false end
    -- In the frame's own units, from UIParent's bottom left (the centre moves by the shift).
    local ui = num(UIParent:GetEffectiveScale()) or 1
    local fs = num(frame:GetEffectiveScale()) or ui
    local k = fs / ui
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ((mine.l + mine.r) / 2 + dx) / k, ((mine.b + mine.t) / 2 + dy) / k)
    return true
end

Floats._test = { rect = rect, list = list }
