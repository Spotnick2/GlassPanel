-- Making room for the bar (#2).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelXP", "GlassPanelGold", "GlassPanelClock" }   -- the lanes these tests assert on

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
for _, l in ipairs(WoW.chat) do if l:find("under   BuffFrame  MEDIUM PROTECTED", 1, true) then found = true end end
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

-- Hidden ON ITS OWN still counts (the width doesn't jump when a target frame
-- or the buffs come and go); hidden with its parent (replaced by an addon)
-- doesn't; unreadable (secret) geometry doesn't, and nothing throws.
mc._rect = { 800, 560, 200, 208 }
mc._shown = false
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 800 + R.MARGIN), "hidden on its own: still counts")
mc._shown = true
local hiddenParent = CreateFrame("Frame", nil, UIParent); hiddenParent._shown = false
mc._parent = hiddenParent
R.Update()
eq(point("TOPRIGHT")[4], 0, "reparented to a hidden frame (replaced): ignored")
mc._parent = UIParent
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

-- Lanes follow the narrower bar (the stub fires OnSizeChanged like the client).
R.Update()
eq(bar._width, 1000 - (1000 - 800 + R.MARGIN), "bar narrowed")
check(block("clock").widget.left + block("clock").widget._width <= bar._width - 8 + 0.5,
      "the right lane packs against the bar's new right end")

-- A target frame appearing doesn't change the width: it counted while hidden.
local tf = blizzard("TargetFrame", { 20, 600, 200, 168 }); tf._shown = false
R.Update()
local l0 = point("TOPLEFT")[4]
eq(l0, 220 + R.MARGIN, "target frame's spot reserved while there is no target")
tf._shown = true
R.Update()
eq(point("TOPLEFT")[4], l0, "and nothing moves when a target appears")
rawset(_G, "TargetFrame", nil)

-- A frame centred in the middle fifth is ignored (the ends can't route around it).
local l2, r2 = R.Insets(1000, 768, 744, { rect(420, 560, 768, 700) })
eq(l2 + r2, 0, "centred frame ignored")
l2, r2 = R.Insets(1000, 768, 744, { rect(300, 440, 768, 700) })
eq(l2, 440 + R.MARGIN, "just left of the middle fifth still counts")

-- An error in Room is recorded, never thrown out of the clock.
R.Update()
local realGetTop = UIParent.GetTop
UIParent.GetTop = function() error("boom") end
check(pcall(R.Update), "Room.Update itself never throws (the event path calls it bare)")
check(GlassPanel.failures["room"], "room failure recorded")
UIParent.GetTop = nil   -- back to the stub's method
GlassPanel.failures["room"] = nil

-- /gpanel covered: frames in the band are "under" the bar or "beside" it.
R.Update()   -- bar stops short of the minimap cluster
local e2 = GlassPanel._test.coveredFrames()
local mark = {}
for _, e in ipairs(e2) do mark[e.name] = e.under end
eq(mark.MinimapCluster, false, "the cluster is beside the narrowed bar")
-- The full-screen cutoff uses the SCREEN width, not the narrowed bar's.
local wide = blizzard("WideTopThing", { 20, 700, 750, 60 })   -- 75% of the screen, 94% of the narrowed bar
e2 = GlassPanel._test.coveredFrames()
local seen = false
for _, e in ipairs(e2) do if e.name == "WideTopThing" then seen = true end end
check(seen, "a 750 px frame isn't mistaken for a full-screen layer on a narrowed bar")
rawset(_G, "WideTopThing", nil)

-- Buffs (#33): measured by the icons shown, not Edit Mode's whole grid box.
-- The structure measured on 70009: BuffFrame (the grid box, x 400-760 here)
-- holds a 1x1 AuraContainer anchor at its top-right corner that does NOT
-- size to the icons, the icons under it, a visible CollapseAndExpandButton
-- (15x30) and a hidden Selection box.
rawset(_G, "MinimapCluster", nil)
loadAddon()
R = GlassPanel.Room
bar = GlassPanel.Bar.frame
local buffs = blizzard("BuffFrame", { 400, 700, 360, 64 })
local container = CreateFrame("Frame", nil, buffs); container._rect = { 759, 763, 1, 1 }
buffs.AuraContainer = container
local collapse = CreateFrame("Button", nil, buffs); collapse._rect = { 761, 734, 15, 30 }
local selection = CreateFrame("Frame", nil, buffs); selection._rect = { 400, 700, 360, 64 }; selection._shown = false
local function aura(x)
    local b = CreateFrame("Button", nil, container); b._rect = { x, 730, 30, 30 }
    local cd = CreateFrame("Cooldown", nil, b); cd._rect = { x + 2, 732, 26, 26 }   -- the icon's own child frame
    b.cd = cd
    return b
end
local a1, a2 = aura(720), aura(680)
a1._shown, a2._shown = false, false
-- A 1x1 anchor under the container (private-aura style): a point, not an icon.
local pin = CreateFrame("Frame", nil, container); pin._rect = { 700, 740, 1, 1 }
R.NewSession()
eq(point("TOPRIGHT")[4], 0, "no buffs up: the empty grid box takes no room (nor the collapse button, nor the 1x1 anchor)")
a1._shown = true
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 720 + R.MARGIN), "one buff: the bar stops at the icon (720, not its 722 cooldown, not the box's 400)")
a2._shown = true
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 680 + R.MARGIN), "a second buff to its left: pushed further")
a2._shown = false
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 680 + R.MARGIN), "it expires: the bar doesn't jiggle back this session")
-- A new session (Edit Mode layout saved, zoning, reload) measures afresh.
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED"); WoW.flushTimers(0)
eq(point("TOPRIGHT")[4], -(1000 - 720 + R.MARGIN), "new session: only the icons up now")

-- /gpanel room why: from the last check, and asking changes nothing.
a2._shown = true   -- appears, but no check has run yet
WoW.chat = {}
GlassPanel._test.slash("room why")
local out = table.concat(WoW.chat, " | ")
check(out:find("BuffFrame: icons: x 720-750", 1, true), "why: buffs measured by icons (" .. out .. ")")
check(out:find("(1 icon(s) now)", 1, true), "why: how many icons")
check(out:find("MinimapCluster: absent", 1, true), "why: absent frames say so")
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 680 + R.MARGIN), "(the next check sees the new icon)")
a2._shown = false
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED"); WoW.flushTimers(0)

-- Edit Mode open: its example auras fill the grid and aren't recorded;
-- closing it starts a new session (dropping what this one had grown to).
a2._shown = true
R.Update()
a2._shown = false
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 680 + R.MARGIN), "(grown to 680 this session)")
local editMode = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
local examples = {}
for i = 1, 8 do examples[i] = aura(400 + (i - 1) * 40) end
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 680 + R.MARGIN), "Edit Mode open: examples not recorded")
for _, e in ipairs(examples) do e._shown = false end
editMode._shown = false
R.Update()
eq(point("TOPRIGHT")[4], -(1000 - 720 + R.MARGIN), "Edit Mode closed: measured afresh")
check(select(1, R.Explain()[2]:find("icons", 1, true)), "(still icons)")

-- The aura frame itself moves (dragged in Edit Mode, another addon): the
-- old extent is dropped at once.
buffs._rect = { 400, 400, 360, 64 }
a1._rect = { 720, 430, 30, 30 }; a1.cd._rect = { 722, 432, 26, 26 }
R.Update()
eq(point("TOPRIGHT")[4], 0, "buffs moved below the band: full width at once")
buffs._rect = { 400, 700, 360, 64 }
a1._rect = { 720, 730, 30, 30 }; a1.cd._rect = { 722, 732, 26, 26 }
R.Update()
-- A big visible frame with nothing in it is a container, not an icon.
a1._shown = false
local empty = CreateFrame("Frame", nil, container); empty._rect = { 620, 700, 140, 60 }
R.NewSession()
eq(point("TOPRIGHT")[4], 0, "a visible but empty container isn't an icon")
-- An icon inside a bigger sub-frame is found (containers are looked into).
local nested = aura(640); nested._parent = empty
R.NewSession()
eq(point("TOPRIGHT")[4], -(1000 - 640 + R.MARGIN), "an icon inside a sub-container is found")
nested._shown = false
empty._shown = false
a1._shown = true
-- Replaced by an addon (reparented to a hidden frame): ignored, as before.
local hider = CreateFrame("Frame", nil, UIParent); hider._shown = false
buffs._parent = hider
R.NewSession()
eq(point("TOPRIGHT")[4], 0, "buff frame replaced: ignored")
buffs._parent = UIParent
-- No AuraContainer (another build): no icons, nothing thrown.
buffs.AuraContainer = nil
R.NewSession()
eq(point("TOPRIGHT")[4], 0, "no AuraContainer: takes no room")
buffs.AuraContainer = container
-- Unreadable icon geometry: skipped, nothing thrown.
a1._rect = { WoW.Secret("x"), 730, 30, 30 }
R.NewSession()
eq(point("TOPRIGHT")[4], 0, "secret icon rect skipped")
a1._rect = { 720, 730, 30, 30 }
R.NewSession()
eq(point("TOPRIGHT")[4], -(1000 - 720 + R.MARGIN), "back")
-- /gpanel room why never throws out of the command.
local realExplain = R.Explain
R.Explain = function() error("explain broke") end
WoW.chat = {}
GlassPanel._test.slash("room why")
R.Explain = realExplain
check(GlassPanel.failures["room:why"] ~= nil, "a failing why is recorded")
GlassPanel.failures["room:why"] = nil
rawset(_G, "BuffFrame", nil)
rawset(_G, "EditModeManagerFrame", nil)

check(next(GlassPanel.failures) == nil, "no failures")
done("test_room")
