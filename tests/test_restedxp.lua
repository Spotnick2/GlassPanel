-- Glass Panel [RestedXP] (#80): never there without RestedXP; RestedXP's
-- waypoint arrow on the bar from our own bearing; double-click shows or hides
-- the guide; every read guarded.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelRestedXP", "GlassPanelGold", "GlassPanelClock" }

local ARROW = "Interface\\AddOns\\RXPGuides\\Textures\\rxp_navigation_arrow-1"
local LOGO = "Interface\\AddOns\\RXPGuides\\Textures\\rxp_logo-64"
local function rx() return block("restedxp") end
local function ui() return rx()._test.ui() end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
local function tooltip()
    local b = rx().widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function frame(dt) WoW.tick(dt or 0.3) end   -- an OnUpdate pass long enough for the words too

-- Not installed: the client doesn't load the plugin (## Dependencies), and
-- neither does the harness.
loadAddon()
eq(rx(), nil, "no RestedXP: no block")
check(next(GlassPanel.failures) == nil, "and nothing recorded")

-- Installed, but without its RXP table: no block, recorded.
loadAddon({ before = function() WoW.installRXP({ noTable = true }) end })
eq(rx(), nil, "RestedXP without its table: no block")
check(GlassPanel.failures["restedxp:missing"] ~= nil, "recorded")
WoW.removeRXP()

-- Installed: the arrow, turned by our own bearing.
loadAddon({ before = function() WoW.installRXP() end })
local b = rx()
check(b ~= nil, "a block with RestedXP")
eq(b.icon, nil, "its art is its own (no core icon)")
local w = b.widget
eq(w._shown, true, "on the bar")
eq(ui().art._file, ARROW, "an arrow")
-- From (0, 0) to (30, 40) facing 0: HereBeDragons' angle, 50 yd.
local angle = math.atan2(-30, 40); angle = angle > 0 and (2 * math.pi - angle) or -angle
check(near(ui().art._rotation, angle - 0), "turned by our bearing")
eq(ui().words._text, "Step 14 |cffaaaaaa50 yd|r", "\"Step N\" when the step has no title, and the distance")
eq(w._width, math.ceil((4 + 16 + 4 + 4 + #"Step 14 50 yd" * 6) / 12) * 12, "sized to the arrow and its words, in steps")
eq(w.label._text, "", "the core's own text stays empty")
WoW.facing = 1
frame()
check(near(ui().art._rotation, angle - 1), "turning follows facing, every frame")

-- The words: a title, RestedXP's colour tokens dropped, kept short.
local e = RXP.arrowFrame.element
e.step.arrowtext = "Talk to RXP_FRIENDLY_Thork"
frame()
eq(ui().words._text, "Talk to Thork |cffaaaaaa50 yd|r", "its arrow text, tokens dropped")
e.step.arrowtext = string.rep("x", 40)
frame()
eq(ui().words._text, string.rep("x", 27) .. "... |cffaaaaaa50 yd|r", "kept short")
e.step.arrowtext = nil

-- Moving changes the words; a new width relays out.
local relayouts = 0
local realLayout = GlassPanel.Bar.Layout
GlassPanel.Bar.Layout = function(...) relayouts = relayouts + 1; return realLayout(...) end
WoW.rxp.player.x, WoW.rxp.player.y = -3000, -3000
frame(); WoW.tick()
eq(ui().words._text, "Step 14 |cffaaaaaa4,292 yd|r", "the distance updates")   -- sqrt(3030^2 + 3040^2)
check(relayouts >= 1, "a wider text relaid out")
GlassPanel.Bar.Layout = realLayout
WoW.rxp.player.x, WoW.rxp.player.y = 0, 0
frame(); WoW.tick()

-- No bearing: other map, other continent, secrets. The logo, and why.
e.instance = 2
frame()
eq(ui().art._file, LOGO, "a target on another map: no arrow (HereBeDragons would still answer)")
eq(ui().words._text, "Step 14 |cffaaaaaa~|r", "~, as RestedXP says")
e.instance = 1
RXP.arrowFrame.wrongContinent = true
frame()
eq(ui().words._text, "Step 14 |cffaaaaaa~|r", "wrongContinent: ~")
RXP.arrowFrame.wrongContinent = nil
WoW.facing = "secret"
frame()
eq(ui().art._file, LOGO, "secret facing: no arrow")
eq(ui().words._text, "Step 14 |cffaaaaaa?|r", "and ?")
WoW.facing = 0
WoW.rxp.player.x = "secret"
frame()
eq(ui().words._text, "Step 14 |cffaaaaaa?|r", "secret position: ?")
WoW.rxp.player.x = 0
frame()
eq(ui().art._file, ARROW, "readable again: the arrow")

-- No live target: the logo alone.
e.step.active = nil
frame(); WoW.tick()
eq(ui().art._file, LOGO, "a deactivated step (its element left behind): the logo")
eq(ui().words._text, "", "and nothing else")
eq(w._width, 4 + 16 + 4, "the width of the logo")
e.step.active = true
RXP.arrowFrame:Hide()
frame()
eq(ui().words._text, "", "the arrow hidden by RestedXP: no target")
RXP.settings.profile.disableArrow = true
frame()
eq(ui().art._file, ARROW, "its arrow drawing switched off: the target still counts (it stays live)")
RXP.settings.profile.disableArrow = nil
RXP.arrowFrame:Show()
frame(); WoW.tick()

-- The tooltip.
local t = tooltip()
check(t:find("RestedXP  |cffffffff12-17 The Barrens|r", 1, true), "the guide's name")
check(t:find("Step\t14 of 196", 1, true), "step N of the guide's steps")
check(t:find("Distance\t50 yd", 1, true), "the distance")
check(t:find("Double-click: hide the guide", 1, true), "how to hide it")

-- Double-click: the guide, through its own launcher.
w._scripts.OnDoubleClick(w, "LeftButton"); frame(); WoW.tick()
eq(WoW.rxpToggles, 1, "double-click: the launcher's left-click")
eq(RXP.settings.profile.showEnabled, false, "the guide hidden")
eq(ui().art._file, LOGO, "the block shows the logo (the guide's arrow is hidden)")
check(tooltip():find("Double-click: show the guide", 1, true), "and how to show it again")
w._scripts.OnDoubleClick(w, "RightButton")
eq(WoW.rxpToggles, 1, "a right double-click does nothing")
w._scripts.OnDoubleClick(w, "LeftButton"); frame()
eq(RXP.settings.profile.showEnabled, true, "shown again")
eq(ui().art._file, ARROW, "and the arrow is back")

-- A toggle that throws: recorded, said once.
local realToggle = RXP.settings.ToggleActive
RXP.settings.ToggleActive = function() error("toggle broke") end
WoW.chat = {}
w._scripts.OnDoubleClick(w, "LeftButton")
w._scripts.OnDoubleClick(w, "LeftButton")
check(GlassPanel.failures["restedxp:toggle"] ~= nil, "a throwing toggle is recorded")
eq(#WoW.chat, 1, "and said once")
GlassPanel.failures["restedxp:toggle"] = nil
RXP.settings.ToggleActive = realToggle

-- Messages repaint.
local dirty = GlassPanel.Engine._test.dirty
dirty[rx()] = nil
WoW.rxpSend("RXP_STEP_ACTIVATED", e.step, RXP.currentGuide)
eq(dirty[rx()], true, "a new step repaints")
WoW.tick()

-- RestedXP's table changing shape under us: the logo, recorded once.
local realArrow = RXP.arrowFrame
RXP.arrowFrame = setmetatable({}, { __index = function() error("moved") end })
frame()
eq(ui().art._file, LOGO, "a throwing read: the logo")
check(GlassPanel.failures["restedxp:read"] ~= nil, "recorded")
GlassPanel.failures["restedxp:read"] = nil
RXP.arrowFrame = realArrow
frame()
eq(ui().art._file, ARROW, "back when it reads again")

check(next(GlassPanel.failures) == nil, "no failures")

-- Without a launcher (no LibDataBroker): RestedXP's ToggleActive directly.
WoW.removeRXP()
loadAddon({ before = function() WoW.installRXP({ noLauncher = true }) end })
local w2 = rx().widget
w2._scripts.OnDoubleClick(w2, "LeftButton")
eq(WoW.rxpToggles, 1, "no launcher: ToggleActive")
WoW.removeRXP()

done("test_restedxp")
