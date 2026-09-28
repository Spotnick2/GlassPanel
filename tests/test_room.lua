-- Making room for the bar (#2).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- /gpanel covered: what the bar sits on, outermost frames only.
loadAddon()
local function frame(name, rect, opts)
    local f = CreateFrame("Frame", name, UIParent)
    f._rect = rect
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end
local minimap = frame("MinimapCluster", { 800, 560, 200, 208 }, { _strata = "LOW", _mouse = true })
frame("MinimapZoneText", { 820, 750, 120, 14 })._parent = minimap   -- nested: implied by the cluster
frame("BuffFrame", { 500, 700, 280, 60 }, { _protected = true })
frame("ChatFrame1", { 20, 40, 400, 200 })                             -- far below
frame("FullscreenLayer", { 0, 0, 1000, 768 })                         -- full-screen: ignored
local hidden = frame("HiddenThing", { 10, 750, 50, 10 }); hidden._shown = false

local names = {}
for _, e in ipairs(GlassPanel._test.coveredFrames()) do names[#names + 1] = e.name end
table.sort(names)
eq(table.concat(names, ","), "BuffFrame,MinimapCluster", "covered frames: outermost, visible, not full-screen, not ours")

GlassPanel._test.slash("covered")
local found = false
for _, l in ipairs(WoW.chat) do if l:find("BuffFrame  MEDIUM PROTECTED", 1, true) then found = true end end
check(found, "/gpanel covered prints strata and protection")

-- Room.Insets, pure: which end of the bar each frame in the band pushes in.
local R = GlassPanel.Room
local function rect(l, r, top, bottom) return { l = l, r = r, top = top, bottom = bottom } end
local l, r = R.Insets(1000, 768, 744, { rect(800, 1000, 768, 560) })
eq(l, 0, "minimap (right half) leaves the left end alone")
eq(r, 1000 - 800 + R.MARGIN, "and pulls the right end in to its left edge")
l, r = R.Insets(1000, 768, 744, { rect(800, 1000, 768, 560), rect(620, 780, 760, 700), rect(0, 230, 766, 690) })
eq(r, 1000 - 620 + R.MARGIN, "buffs left of the minimap pull it further")
eq(l, 230 + R.MARGIN, "a frame in the left half pushes the left end")
l, r = R.Insets(1000, 768, 744, { rect(800, 1000, 740, 560) })
eq(r, 0, "a frame below the band (moved down in Edit Mode) is left alone")
l, r = R.Insets(1000, 768, 744, { rect(0, 450, 768, 700), rect(560, 1000, 768, 700) })
eq(l + r, 0, "too little room left: keep the full width")

-- Room.Update on real (stub) frames. Clear the probe section's globals first.
for _, n in ipairs({ "MinimapCluster", "MinimapZoneText", "BuffFrame", "ChatFrame1", "FullscreenLayer", "HiddenThing" }) do
    rawset(_G, n, nil)
end
local function blizzard(name, rect4)
    local f = CreateFrame("Frame", name, UIParent)
    f._rect = rect4
    return f
end
loadAddon()
R = GlassPanel.Room
local mc = blizzard("MinimapCluster", { 800, 560, 200, 208 })
R.Update()
local bar = GlassPanel.Bar.frame
local function point(name)
    for _, p in ipairs(bar._points) do if p[1] == name then return p end end
end
eq(point("TOPRIGHT")[4], -(1000 - 800 + R.MARGIN), "bar ends left of the minimap cluster")
eq(point("TOPLEFT")[4], 0, "left end at the screen edge")

-- The user moves it down in Edit Mode: full width again (within a second).
mc._rect = { 800, 400, 200, 208 }
WoW.tick(1.1)
eq(point("TOPRIGHT")[4], 0, "full width once the cluster is out of the band")

-- Hidden, unreadable (secret) and absent frames are ignored.
mc._rect = { 800, 560, 200, 208 }
mc._shown = false
R.Update()
eq(point("TOPRIGHT")[4], 0, "hidden cluster ignored")
mc._shown = true
mc._rect = { WoW.Secret("left"), 560, 200, 208 }
R.Update()
eq(point("TOPRIGHT")[4], 0, "secret geometry ignored, nothing thrown")
mc._rect = { 800, 560, 200, 208 }

-- /gpanel room full: always the full width.
GlassPanel._test.slash("room full")
eq(point("TOPRIGHT")[4], 0, "room full")
GlassPanel._test.slash("room auto")
eq(point("TOPRIGHT")[4], -(1000 - 800 + R.MARGIN), "room auto")
eq(GlassPanelDB.room, "auto", "saved")

-- Scale: rects are compared in screen pixels, insets set in UIParent units.
WoW.uiScale = 0.5   -- every frame's effective scale in the stub
R.Update()
-- MARGIN is in screen px: 6 px at half scale is 12 UIParent units.
eq(point("TOPRIGHT")[4], -(1000 - 800 + R.MARGIN / 0.5), "same frame position in UIParent units at another scale")
WoW.uiScale = 1

-- Lanes follow the narrower bar (OnSizeChanged).
bar._width = 1000 - (1000 - 800 + R.MARGIN)
bar._scripts.OnSizeChanged(bar)
check(block("clock").widget.left + block("clock").widget._width <= bar._width - 8 + 0.5,
      "the right lane packs against the bar's new right end")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_room")
