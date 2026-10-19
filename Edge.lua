-- Edge.lua: the top edge GlassPanel occupies, for the suite (#97). Another
-- addon's frame at the screen's top centre (RestedXP's waypoint arrow, via
-- Glass UI) can keep clear of the bar: we announce, it follows, and neither
-- depends on the other. The pattern is GlassActionBars' EdgeState / EdgesChanged.
--
--   GlassPanel.EdgeState() -> { top = n }, a fresh table, or nil before the
--     first measure. `top` is in UIParent units, measured down from the
--     screen's top to the lowest bottom of what GlassPanel occupies there:
--     0 when nothing is there, Bar.HEIGHT for the bar alone.
--   EventRegistry "GlassPanel.EdgeChanged" (top): at the first measure, then
--     out of combat when `top` moved more than TOLERANCE from the last value
--     announced. A change in combat is announced at PLAYER_REGEN_ENABLED.
--     Consumers apply the latest value each time.
--
-- What counts: the bar while shown, and every frame a plugin registered with
-- API.TrackTopEdge (XP+'s zoomed bar) while it is visible and in the top
-- band: its top within MARGIN of the screen's top or of the bar's bottom (a
-- stack, as GlassActionBars' rule). A float dragged mid-screen doesn't count.
-- A frame's scale is converted to UIParent units. A rect with any unreadable
-- value is skipped, never guessed.

GlassPanel = GlassPanel or {}
local API, Bar, Engine = GlassPanel.API, GlassPanel.Bar, GlassPanel.Engine
local Edge = {}
GlassPanel.Edge = Edge

Edge.EVENT = "GlassPanel.EdgeChanged"
Edge.MARGIN = 40
Edge.TOLERANCE = 0.5

local tracked = setmetatable({}, { __mode = "k" })   -- frame -> true
local list = {}                                      -- the same frames, in order
local published                                      -- the last value announced
local measured                                       -- the latest value measured
local wanted, pending = false, false

local function num(v)
    v = API.Plain(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

-- A tracked frame's top and bottom, as distances down from the screen's top
-- in UIParent units, or nil (hidden, or anything unreadable).
local function span(frame)
    if API.Plain(frame:IsVisible()) ~= true then return nil end
    local s, ui = num(frame:GetEffectiveScale()), num(UIParent:GetEffectiveScale())
    local top, t, b = num(UIParent:GetTop()), num(frame:GetTop()), num(frame:GetBottom())
    if not (s and ui and top and t and b) or s <= 0 or ui <= 0 then return nil end
    local k = s / ui
    return top - t * k, top - b * k
end

-- The pure measure: `barBottom` (0 when the bar is hidden) and the tracked
-- frames' spans, { from = distance to the top, to = distance to the bottom }.
function Edge.Compute(barBottom, spans)
    local result = barBottom
    local line = barBottom
    local ordered = {}
    for _, s in ipairs(spans) do ordered[#ordered + 1] = s end
    table.sort(ordered, function(a, b) return a.from < b.from end)
    for _, s in ipairs(ordered) do
        if s.from <= line + Edge.MARGIN then
            if s.to > result then result = s.to end
            if s.to > line then line = s.to end
        end
    end
    return result
end

function Edge.Measure()
    if not UIParent or not num(UIParent:GetTop()) then return nil end
    local barBottom = 0
    if Bar.frame and API.Plain(Bar.frame:IsShown()) == true then barBottom = Bar.HEIGHT end
    local spans = {}
    for _, f in ipairs(list) do
        local from, to = span(f)
        if from then spans[#spans + 1] = { from = from, to = to } end
    end
    return Edge.Compute(barBottom, spans)
end

local function update()
    local top = Edge.Measure()
    if not top then return end
    measured = top
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    if published ~= nil and math.abs(top - published) <= Edge.TOLERANCE then return end
    published = top
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry:TriggerEvent(Edge.EVENT, top)
    end
end

-- The last value measured (a combat change included), as a fresh table.
function Edge.State()
    if measured == nil then return nil end
    return { top = measured }
end

local driver = CreateFrame("Frame")
local function onUpdate()
    driver:SetScript("OnUpdate", nil)
    if wanted then
        wanted = false
        local ok, err = pcall(update)
        if not ok then API.Fail("edge:update", err) end
    end
end

-- A measure on the next frame (coalesced).
function Edge.Request()
    wanted = true
    driver:SetScript("OnUpdate", onUpdate)
end

local function watch(frame)
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", Edge.Request)
        frame:HookScript("OnHide", Edge.Request)
    end
end

-- Public through the API: a plugin registers a frame that can occupy the top
-- band (once per frame), and asks for a new measure after it moved or
-- rescaled. Additive: API_VERSION is unchanged.
function API.TrackTopEdge(frame)
    if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" or tracked[frame] then return false end
    tracked[frame] = true
    list[#list + 1] = frame
    watch(frame)
    Edge.Request()
    return true
end
function API.UpdateTopEdge() Edge.Request() end
function GlassPanel.EdgeState() return Edge.State() end

local started = false
function Edge.Start()
    if started then return end
    started = true
    if Bar.frame then watch(Bar.frame) end
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then Edge.Request() end
        else
            Edge.Request()
        end
    end)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED",
                         "DISPLAY_SIZE_CHANGED" }) do
        API.RegisterEvent(driver, e, "edge")
    end
    Engine.EverySecond("edge", Edge.Request)   -- the safety net for anything not announced
    Edge.Request()
end

Edge._test = { published = function() return published end, tracked = function() return list end }
