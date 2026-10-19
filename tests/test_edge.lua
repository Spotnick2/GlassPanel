-- The top edge GlassPanel occupies (#97): EdgeState and "GlassPanel.EdgeChanged".
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelXP" }

local E = nil
local function edgeEvents()
    local out = {}
    for _, t in ipairs(WoW.triggered) do if t[1] == "GlassPanel.EdgeChanged" then out[#out + 1] = t[2] end end
    return out
end

-- Pure: Compute(barBottom, spans), distances down from the screen's top.
loadAddon()
E = GlassPanel.Edge
eq(E.Compute(0, {}), 0, "nothing there: 0")
eq(E.Compute(24, {}), 24, "the bar alone: its height")
eq(E.Compute(24, { { from = 30, to = 90 } }), 90, "a float under the bar (30 < 24 + 40): counts")
eq(E.Compute(24, { { from = 200, to = 260 } }), 24, "a float dragged mid-screen: not counted")
eq(E.Compute(0, { { from = 10, to = 50 } }), 50, "no bar, a float near the top: counts")
eq(E.Compute(24, { { from = 30, to = 90 }, { from = 100, to = 150 } }), 150, "a stack: the second starts within MARGIN of the first")
eq(E.Compute(24, { { from = -5, to = 40 } }), 40, "a float poking above the screen: counts")

-- Before the first measure: nil. At the first measure: the value, announced once.
WoW.reset()
local before
loadAddon({ before = function() before = GlassPanel.EdgeState() end })
E = GlassPanel.Edge
eq(before, nil, "before the first measure: nil")
eq(GlassPanel.EdgeState().top, 24, "the bar alone: 24 (Bar.HEIGHT)")
local ev = edgeEvents()
eq(#ev, 1, "announced once at the first measure")
eq(ev[1], 24, "with the value")
check(GlassPanel.EdgeState() ~= GlassPanel.EdgeState(), "a fresh table each call")

-- A subscriber registered before the first measure gets it.
WoW.reset()
local got
EventRegistry:RegisterCallback("GlassPanel.EdgeChanged", function(_, top) got = top end, {})
loadAddon({ before = function() EventRegistry:RegisterCallback("GlassPanel.EdgeChanged", function(_, top) got = top end, {}) end })
WoW.tick()
eq(got, 24, "a consumer that registered first receives the first measure")

-- The bar hidden: 0; shown: 24 again.
GlassPanel.Settings.SetShown(false); WoW.tick()
eq(GlassPanel.EdgeState().top, 0, "bar hidden: 0")
local n = #edgeEvents()
GlassPanel.Settings.SetShown(true); WoW.tick()
eq(GlassPanel.EdgeState().top, 24, "bar shown: 24")
eq(#edgeEvents(), n + 1, "announced on the change")
WoW.tick(); WoW.tick()
eq(#edgeEvents(), n + 1, "not announced again while it doesn't move")

-- A tracked frame in the band, moved: announced; scale converted.
local f = CreateFrame("Frame", nil, UIParent)
f._rect = { 400, 668, 200, 60 }   -- top at 768 - 768 = 0 from the screen's top, bottom 60 down
eq(GlassPanel.API.TrackTopEdge(f), true, "a frame is tracked")
eq(GlassPanel.API.TrackTopEdge(f), false, "once per frame")
WoW.tick()
eq(GlassPanel.EdgeState().top, 100, "the frame is 100 units tall from the top (668 .. 768)")
f._rect = { 400, 100, 200, 60 }   -- mid-screen
GlassPanel.API.UpdateTopEdge(); WoW.tick()
eq(GlassPanel.EdgeState().top, 24, "dragged mid-screen: back to the bar")
f._rect = { 400, 300, 200, 60 }   -- its own units: top 360, bottom 300
f.GetEffectiveScale = function() return 2 end   -- twice UIParent's: x2 -> 720 and 600, i.e. 48 and 168 down
GlassPanel.API.UpdateTopEdge(); WoW.tick()
eq(GlassPanel.EdgeState().top, 168, "scaled: converted to UIParent units")
f.GetEffectiveScale = nil
f:Hide(); WoW.tick()
eq(GlassPanel.EdgeState().top, 24, "hidden: not counted")

-- Unreadable values: skipped, never guessed.
f:Show()
f.GetTop = function() return WoW.Secret("top") end
GlassPanel.API.UpdateTopEdge(); WoW.tick()
eq(GlassPanel.EdgeState().top, 24, "a secret rect value: skipped")
f.GetTop = nil

-- Combat: measured, announced at PLAYER_REGEN_ENABLED.
f._rect = { 400, 668, 200, 60 }
GlassPanel.API.UpdateTopEdge(); WoW.tick()
n = #edgeEvents()
WoW.combat = true
f._rect = { 400, 600, 200, 168 }   -- bottom 168 down
GlassPanel.API.UpdateTopEdge(); WoW.tick()
eq(#edgeEvents(), n, "in combat: not announced")
eq(GlassPanel.EdgeState().top, 168, "(but EdgeState has it)")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick()
eq(#edgeEvents(), n + 1, "announced at PLAYER_REGEN_ENABLED")
eq(edgeEvents()[#edgeEvents()], 168, "with the latest value")

-- Below the tolerance: not announced.
f._rect = { 400, 600, 200, 167.7 }
GlassPanel.API.UpdateTopEdge(); WoW.tick()
eq(#edgeEvents(), n + 1, "a move under half a unit: not announced")
done("test_edge")
