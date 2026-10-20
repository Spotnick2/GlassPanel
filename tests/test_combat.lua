-- The Combat plugin (#108): the timer on the bar, the zoomed pill, Glass Unit Frames' timer.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelCombat" }

local function C() return block("combat")._test end
local function widget() return block("combat").widget end
local function enter() WoW.combat = true; WoW.fire("PLAYER_REGEN_DISABLED"); WoW.tick() end
local function leave() WoW.combat = false; WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick() end
local function dbl() widget()._scripts.OnDoubleClick(widget(), "LeftButton"); WoW.tick() end

-- The format is Glass Unit Frames': 00:07, 12:34, 1:00:05; floored, never below 0.
loadAddon()
local f = C().format
eq(f(0), "00:00", "zero")
eq(f(7.9), "00:07", "seconds are floored")
eq(f(754), "12:34", "minutes")
eq(f(3599.9), "59:59", "just under an hour")
eq(f(3605), "1:00:05", "from an hour on")
eq(f(-3), "00:00", "never below 0")

-- Out of combat: "Out of Combat", the block fixed at its width, crossed swords.
eq(textOf("combat"), "Out of Combat", "idle text")
eq(block("combat").icon, "Interface\\Icons\\Ability_DualWield", "crossed swords")
eq(widget()._width, 104, "docked: a fixed width")
eq(widget()._shown, true, "shown")
eq(C().pill(), nil, "no pill is built before it's needed")

-- In combat: the fight's time, counted from our own stamp, once a second.
WoW.now = 1000
enter()
eq(textOf("combat"), "00:00", "a fight starts at 00:00")
WoW.now = 1007.4
GlassPanel.Refresh("combat"); WoW.tick()
eq(textOf("combat"), "00:07", "seven seconds in")
eq(block("combat").interval(), 1, "ticking each second while it counts")
WoW.now = 4700
GlassPanel.Refresh("combat"); WoW.tick()
eq(textOf("combat"), "1:01:40", "past an hour")
-- Entering the world again inside the same fight keeps its start.
WoW.now = 4710
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
eq(textOf("combat"), "1:01:50", "a loading screen inside a fight keeps its start")
leave()
eq(textOf("combat"), "Out of Combat", "back to idle")
eq(block("combat").interval(), 30, "no fast clock when idle")
local tipLines = {}
widget()._scripts.OnEnter(widget())
for _, l in ipairs(GameTooltip._lines) do tipLines[#tipLines + 1] = l end
check(table.concat(tipLines, "\n"):find("1:01:50", 1, true), "the tooltip remembers the last fight")
GameTooltip:Hide()

-- A /reload mid-fight counts from the reload; entering the world out of combat is idle.
WoW.now = 5000
loadAddon({ before = function() WoW.combat = true end })
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
eq(textOf("combat"), "00:00", "reloaded in a fight: counts from now")
WoW.combat = false
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
eq(textOf("combat"), "Out of Combat", "no longer in lockdown: idle")

-- Zoomed: the bar keeps the icon alone; the pill is shown only in combat.
GlassPanelCombatDB = nil
WoW.combat = false
loadAddon()
dbl()
eq(GlassPanelCombatDB.detached, true, "double-click zooms, and saves")
eq(textOf("combat"), "", "the bar keeps only the icon")
eq(widget()._width, 4 + 14 + 4 + 4, "the panel keeps the icon alone")
eq(C().pill(), nil, "zoomed but out of combat: no pill built")
WoW.now = 100
enter()
local pill = C().pill()
check(pill ~= nil and pill._shown, "in combat: the pill shows")
eq(pill._parent, UIParent, "on UIParent")
eq(pill._width .. "x" .. pill._height, "92x26", "a pill")
eq(C().pillText()._text, "00:00", "its time")
check(C().ticker() ~= nil, "a ticker runs while it shows")
WoW.now = 112
WoW.fireTickers()
eq(C().pillText()._text, "00:12", "the ticker updates it")
leave()
eq(pill._shown, false, "combat over: the pill is gone")
eq(C().ticker(), nil, "and the ticker stops")
enter()
check(pill._shown, "the next fight shows it again")
dbl()
eq(pill._shown, false, "docking hides it")
check(textOf("combat") ~= "", "docked in combat: the bar shows the time")
leave()

-- Moving: shift-drag, saved from UIParent's centre; never a plain drag.
dbl(); enter()
pill = C().pill()
pill._scripts.OnDragStart(pill)
eq(pill._moving, nil, "a plain drag doesn't move it")
WoW.shift = true; pill._scripts.OnDragStart(pill); WoW.shift = false
eq(pill._moving, true, "shift-drag moves it")
pill._center = { 600.3, 700 }
pill._scripts.OnDragStop(pill)
check(GlassPanelCombatDB.spot and GlassPanelCombatDB.spot.x == 100.5 and GlassPanelCombatDB.spot.y == 316, "saved, rounded to 0.5")
local p = pill._points[1]
check(#pill._points == 1 and p[1] == "CENTER" and p[4] == 100.5 and p[5] == 316, "anchored on the saved spot")
-- Hidden mid-move (the fight ends): stopped, the last good spot kept.
WoW.shift = true; pill._scripts.OnDragStart(pill); WoW.shift = false
leave()
eq(pill._moving, false, "hidden mid-move: stopped")
eq(GlassPanelCombatDB.spot.x, 100.5, "the saved spot is untouched")
C().resetSpot()
eq(GlassPanelCombatDB.spot, nil, "reset position")
-- A corrupt saved spot: the default slot.
GlassPanelCombatDB.spot = { x = "a", y = 1 }
C().resetSpot()
GlassPanelCombatDB.spot = { x = 1e9, y = 0 }
enter()
p = pill._points[1]
eq(p[1], "TOP", "an out-of-range spot: the default slot")
leave()

-- Right-click menu, and the fallback without MenuUtil (docks).
WoW.now = WoW.now + 5   -- past the release that ended a move
enter()
WoW.menu = nil
pill._scripts.OnClick(pill, "RightButton")
check(WoW.menu ~= nil, "right-click opens the menu")
leave()

-- The preview: shows the pill out of combat for a while, only when zoomed.
GlassPanelCombatDB = { detached = true }
loadAddon()
C().setPreview()
check(C().pill() and C().pill()._shown, "preview shows the pill")
WoW.now = WoW.now + 31
WoW.flushTimers()
eq(C().pill()._shown, false, "...and it ends")
dbl()   -- docked
WoW.chat = {}
C().setPreview()
check((WoW.chat[1] or ""):find("zoom the timer first", 1, true), "docked: says to zoom first")

-- Pill and XP+'s zoomed bar never overlap: default slots stack.
PLUGINS = { "GlassPanelCombat", "GlassPanelXP" }
WoW.player = { level = 30, maxLevel = 60, xp = 12000, maxXP = 45000, rested = 0, xpDisabled = false }
WoW.quests = {}
GlassPanelCombatDB = { detached = true }
GlassPanelXPDB = { detached = true }
loadAddon()
enter()
local xpF = block("xp")._test.float()
local cp = C().pill()
check(xpF and xpF._shown and cp and cp._shown, "both zoomed floats are up")
eq(xpF._points[1][5], -40, "XP+ takes the first slot")
eq(cp._points[1][5], -40 - 46 - 8, "the pill sits under it")
-- A drop snaps clear of the other float, for both.
local snaps = {}
local realSnap = GlassPanel.API.SnapFloat
GlassPanel.API.SnapFloat = function(fr) snaps[#snaps + 1] = fr; return realSnap(fr) end
WoW.shift = true; xpF._scripts.OnDragStart(xpF); WoW.shift = false
xpF._center = { 600, 700 }
xpF._scripts.OnDragStop(xpF)
WoW.now = WoW.now + 5
WoW.shift = true; cp._scripts.OnDragStart(cp); WoW.shift = false
cp._center = { 600, 700 }
cp._scripts.OnDragStop(cp)
eq(snaps[1] == xpF and snaps[2] == cp, true, "a drop snaps both XP+'s bar and the pill")
GlassPanel.API.SnapFloat = realSnap
-- A float of a higher order is placed again when the pill shows or hides.
local third, thirdPlaces = CreateFrame("Frame", nil, UIParent), 0
third:SetSize(10, 10); third:Show()
GlassPanel.API.RegisterFloat(third, { order = 3, placed = function() return false end, place = function() thirdPlaces = thirdPlaces + 1 end })
leave(); thirdPlaces = 0
enter()
check(thirdPlaces > 0, "the pill showing places the floats after it")
GlassPanelCombatDB.spot, GlassPanelXPDB.spot = nil, nil
GlassPanelXPDB.detached = nil
block("xp")._test.setDetached(false)
WoW.tick()
eq(cp._points[1][5], -40, "XP+ docked: the pill moves up to the first slot")
PLUGINS = { "GlassPanelCombat" }

-- Glass Unit Frames' timer: a click's choice, read again, never copied.
GlassUF = nil
loadAddon()
eq(C().usingOurs(), false, "no Glass Unit Frames: not using ours")
WoW.chat = {}
C().useOurs(true)
check((WoW.chat[1] or ""):find("isn't loaded", 1, true), "asking without it says so, changes nothing")
local sets = {}
GlassUF = { Timer = { enabled = true }, Settings = { SetCombatTimer = function(on) sets[#sets + 1] = on; GlassUF.Timer.enabled = on; return true end } }
eq(C().usingOurs(), false, "its timer is on: not using ours")
C().useOurs(true)
eq(sets[1], false, "using ours turns theirs off")
eq(C().usingOurs(), true, "read back from its own state")
GlassUF.Timer.enabled = true   -- the player turns it on in GUF's options
eq(C().usingOurs(), false, "re-read, never a copy")
C().useOurs(false)
eq(sets[2], true, "off gives theirs back")
GlassUF.Settings.SetCombatTimer = function() return false end
WoW.chat = {}
C().useOurs(true)
check((WoW.chat[1] or ""):find("isn't ready", 1, true), "a refusal (before its build) is said")
GlassUF.Settings.SetCombatTimer = function() error("boom") end
C().useOurs(true)
check(GlassPanel.failures["combat:guf"] ~= nil, "a throw is recorded")
GlassPanel.failures["combat:guf"] = nil
-- Nothing is applied automatically; one hint, once.
sets = {}
GlassUF = { Timer = { enabled = true }, Settings = { SetCombatTimer = function(on) sets[#sets + 1] = on; return true end } }
GlassPanelCombatDB = nil
WoW.chat = {}
loadAddon()
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
eq(#sets, 0, "never touches its timer by itself")
local hinted = 0
for _, l in ipairs(WoW.chat) do if l:find("shows a combat timer too", 1, true) then hinted = hinted + 1 end end
eq(hinted, 1, "the hint is said")
WoW.chat = {}
loadAddon()
WoW.fire("PLAYER_ENTERING_WORLD"); WoW.tick()
hinted = 0
for _, l in ipairs(WoW.chat) do if l:find("shows a combat timer too", 1, true) then hinted = hinted + 1 end end
eq(hinted, 0, "...once ever")
GlassUF = nil

check(next(GlassPanel.failures) == nil, "no failures")
done("test_combat")
