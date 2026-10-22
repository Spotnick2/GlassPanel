-- The Flight plugin (#124): learned flight times, the block, the zoomed bar, GUF's claim.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelFlight" }

local function F() return block("flight")._test end
local function widget() return block("flight").widget end
local function dbl() widget()._scripts.OnDoubleClick(widget(), "LeftButton"); WoW.tick() end

-- Three nodes with ids the client's paths (Routes.lua) don't have, so only landings time them:
WoW.taxi.nodes = {
    [1] = { id = 901, name = "Ironforge, Dun Morogh" },
    [2] = { id = 902, name = "Thorium Point, Searing Gorge" },
    [3] = { id = 903, name = "Morgan's Vigil, Burning Steppes" },
}
WoW.taxi.routes = { [2] = { 1, 2 }, [3] = { 1, 2, 3 } }

-- Pick `slot` on the flight map and take off; the flight runs from WoW.now.
local function takeOff(slot)
    TakeTaxiNode(slot)
    WoW.layer.taxi = false   -- still false when control goes (EllesmereUI's note)
    WoW.fire("PLAYER_CONTROL_LOST"); WoW.tick()
    WoW.layer.taxi = true
end
local function landNow()
    WoW.layer.taxi = false
    WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
end
local function repaint() WoW.fireTickers(); WoW.tick() end

loadAddon()
local c = F().clock
eq(c(0), "0:00", "zero")
eq(c(42.4), "0:42", "seconds, rounded")
eq(c(725), "12:05", "minutes")
eq(c(3723), "1:02:03", "from an hour on")
eq(c(-5), "0:00", "never below 0")

-- Not flying: no block.
eq(widget()._shown, false, "not on a flight: the block takes no space")
eq(block("flight").icon, "Interface\\Minimap\\Tracking\\FlightMaster", "the flight master icon")
eq(F().float(), nil, "no bar is built before it's needed")

-- A first flight on a route: the time flown, grey, counting up; learned on landing.
WoW.now = 1000
takeOff(2)
local fl = F().flight()
check(fl ~= nil, "control lost right after a pick: a flight")
eq(table.concat(GlassPanelFlightDB.current.route.keys, ">"), "901>902", "keyed by node ids (the library saves it in our store)")
eq(widget()._shown, true, "on a flight: the block shows")
eq(textOf("flight"), "|cff999999+0:00|r", "unknown: the time flown, grey")
eq(widget()._width, 72, "a fixed width")
WoW.now = 1042
repaint()
eq(textOf("flight"), "|cff999999+0:42|r", "the ticker counts it up")
WoW.now = 1090.04
landNow()
eq(F().flight(), nil, "landed")
eq(widget()._shown, false, "landed: the block goes")
eq(GlassPanelFlightDB.routes["901>902"].base, 90, "the time is learned, to a tenth")
eq(GlassPanelFlightDB.current, nil, "nothing left to resume")
repaint()
eq(F().ticker(), nil, "the ticker stops at its next tick")

-- The same route again: the exact time left.
WoW.now = 2000
takeOff(2)
eq(textOf("flight"), "1:30", "learned: the time left")
WoW.now = 2030
repaint()
eq(textOf("flight"), "1:00", "counting down")
WoW.now = 2089.6
landNow()
eq(GlassPanelFlightDB.routes["901>902"].base, 89.6, "the newest landing is kept")

-- A path never flown: the sum of its learned hops, as an estimate.
GlassPanelFlightDB.routes["902>903"] = { base = 60 }
WoW.now = 3000
takeOff(3)
eq(textOf("flight"), "~2:30", "estimated from its hops (89.6 + 60)")
local tips = {}
widget()._scripts.OnEnter(widget())
for _, l in ipairs(GameTooltip._lines) do tips[#tips + 1] = l end
local tip = table.concat(tips, "\n")
check(tip:find("Morgan's Vigil, Burning Steppes", 1, true), "the tooltip names the destination")
check(tip:find("Thorium Point", 1, true), "...and the stop on the way")
check(tip:find("Estimated", 1, true), "...and says it's an estimate")
GameTooltip:Hide()
WoW.now = 3140
landNow()
eq(GlassPanelFlightDB.routes["901>902>903"].base, 140, "the whole path is learned on its own")
WoW.now = 3200
takeOff(3)
eq(textOf("flight"), "2:20", "and is exact next time")
landNow()
repaint()

-- Frequent Flier keeps its own times; the other kind is an estimate, scaled.
WoW.frequentFlier = 1
WoW.now = 4000
takeOff(2)
eq(textOf("flight"), "~1:15", "with the perk, a time learned without it is 1.2 times shorter, estimated")
WoW.now = 4072
landNow()
eq(GlassPanelFlightDB.routes["901>902"].fast, 72, "learned as its own kind")
eq(GlassPanelFlightDB.routes["901>902"].base, 89.6, "...the other kept")
takeOff(2)
eq(textOf("flight"), "1:12", "exact for its kind")
landNow()
-- An unreadable perk learns nothing.
WoW.frequentFlier = "secret"
WoW.now = 5000
takeOff(3)
check(textOf("flight"):find("~", 1, true), "unreadable perk: only an estimate")
WoW.now = 5100
landNow()
eq(GlassPanelFlightDB.routes["901>902>903"].base, 140, "...and nothing learned")
eq(GlassPanelFlightDB.routes["901>902>903"].fast, nil, "...of either kind")
WoW.frequentFlier = 0
repaint()

-- A refused pick and a later loss of control (a stun): no flight from the stale pick.
WoW.now = 6000
TakeTaxiNode(2)
WoW.now = 6010
WoW.layer.taxi = false
WoW.fire("PLAYER_CONTROL_LOST"); WoW.tick()
eq(F().flight(), nil, "a pick 10 s old doesn't start a flight")
WoW.flushTimers(); WoW.tick()
eq(F().flight(), nil, "...and off the taxi a second later, still none")
WoW.fire("PLAYER_CONTROL_GAINED")
-- A flight not picked here (a quest's): noticed a second later, counting up, its route unknown.
WoW.fire("PLAYER_CONTROL_LOST"); WoW.tick()
WoW.layer.taxi = true
WoW.flushTimers(); WoW.tick()
fl = F().flight()
check(fl ~= nil and fl.to == nil, "on the taxi a second later: a flight, route unknown")
eq(textOf("flight"), "|cff999999+0:00|r", "counting up")
-- Its landing missed: off the taxi with no control back, the ticker ends it after SETTLE s.
WoW.layer.taxi = false
WoW.now = 6030
repaint()
check(F().flight() ~= nil, "just found off the taxi: control back may still come")
WoW.now = 6033
repaint()
eq(F().flight(), nil, "off the taxi for 3 s without control back: ended")

-- A normal landing is learned whichever half the client says first (Codex on #125).
GlassPanelFlightDB.routes["901>902"] = nil
-- Off the taxi first, the ticker in between, then control back.
WoW.now = 6100
takeOff(2)
WoW.now = 6150
WoW.layer.taxi = false
repaint()
check(F().flight() ~= nil, "off the taxi before control back: still pending")
WoW.now = 6151
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
eq(F().flight(), nil, "control back: landed")
eq(GlassPanelFlightDB.routes["901>902"].base, 51, "...and learned, timed at control back")
-- Control back while the taxi still reads on, then off the taxi at a later tick.
GlassPanelFlightDB.routes["901>902"] = nil
WoW.now = 6200
takeOff(2)
WoW.now = 6260
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
check(F().flight() ~= nil, "control back still on the taxi: not landed yet")
WoW.now = 6261
WoW.layer.taxi = false
repaint()
eq(F().flight(), nil, "off the taxi at the next tick: landed")
eq(GlassPanelFlightDB.routes["901>902"].base, 60, "...and learned, timed at control back")
GlassPanelFlightDB.routes["901>902"] = { base = 89.6 }   -- as the tests below expect

-- Early landing: the time left goes, nothing learned.
WoW.now = 7000
takeOff(3)
TaxiRequestEarlyLanding(); WoW.tick()
eq(WoW.taxi.early, 1, "the request still reaches the client")
eq(F().flight().early, true, "marked early")
eq(textOf("flight"), "|cff999999+0:00|r", "the time flown instead")
WoW.now = 7050
landNow()
eq(GlassPanelFlightDB.routes["901>902>903"].base, 140, "an early landing teaches nothing")
repaint()

-- A /reload mid-flight resumes the saved flight from server time, learning nothing.
WoW.now, WoW.serverTime = 8000, 500000
takeOff(2)
eq(GlassPanelFlightDB.current.at, 500000, "the flight is saved for a reload")
F().ticker():Cancel()   -- the old session's (test-only leftovers: its UI ticker and its library's)
F().lib.state.ticker:Cancel()
WoW.now, WoW.serverTime = 9000, 500030
loadAddon()
fl = F().flight()
check(fl ~= nil and fl.resumed, "reloaded on the taxi: resumed")
eq(textOf("flight"), "1:00", "30 s in, the right time left")
WoW.now = 9060
landNow()
eq(GlassPanelFlightDB.routes["901>902"].base, 89.6, "a resumed flight teaches nothing")
-- Saved too long ago, or not on a taxi: no resume.
GlassPanelFlightDB.current = { route = { keys = { 901, 902 }, names = { "A", "B" } }, at = WoW.serverTime - 99999 }
WoW.layer.taxi = true
loadAddon()
fl = F().flight()
check(fl ~= nil and fl.to == nil, "a stale save: a flight, route unknown")
WoW.layer.taxi = false
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
GlassPanelFlightDB.current = { route = { keys = { 901 }, names = { "A" } }, at = WoW.serverTime }
loadAddon()
eq(F().flight(), nil, "off the taxi: none")
eq(GlassPanelFlightDB.current, nil, "...and the save is dropped")

-- From the first flight: the client's path lengths (Routes.lua) at 30 yd/s.
-- Orgrimmar (23) > Crossroads (25), 3304 yd; on to Camp Taurajo (77), 2705 yd.
local savedTaxi = WoW.taxi.nodes
WoW.taxi.nodes = {
    [1] = { id = 23, name = "Orgrimmar, Durotar" },
    [2] = { id = 25, name = "Crossroads, The Barrens" },
    [3] = { id = 77, name = "Camp Taurajo, The Barrens" },
}
WoW.now = 7500
takeOff(2)
eq(textOf("flight"), "1:50", "never flown: the route's length gives the time (3304 / 30)")
eq(F().flight().source, "route", "...from the client's paths")
WoW.now = 7600
landNow()
eq(GlassPanelFlightDB.routes["23>25"].base, 100, "the landing is still learned")
takeOff(2)
eq(textOf("flight"), "1:40", "...and wins next time")
landNow()
takeOff(3)
eq(textOf("flight"), "3:20", "two hops: their lengths added ((3304 + 2705) / 30)")
landNow()
WoW.frequentFlier = 1
GlassPanelFlightDB.routes["23>25>77"] = nil
takeOff(3)
eq(textOf("flight"), "2:47", "Frequent Flier: 20% faster")
landNow()
WoW.frequentFlier = "secret"
takeOff(3)
eq(textOf("flight"), "~3:20", "an unreadable perk: the route's time is an estimate")
landNow()
WoW.frequentFlier = 0
-- A path newer than Routes.lua (a new zone's): landed once, then mixed with known hops.
WoW.taxi.nodes[3] = { id = 904, name = "Riverlands Post, The Riverlands" }
GlassPanelFlightDB.routes["25>904"] = { base = 40 }
takeOff(3)
eq(textOf("flight"), "~2:30", "a known hop's length plus a new hop's landed time (3304 / 30 + 40)")
landNow()
WoW.taxi.nodes = savedTaxi
repaint()

-- A moment off the taxi mid-flight doesn't shorten the real landing's wait (Codex on #125).
GlassPanelFlightDB.routes["901>902"] = nil
WoW.now = 7800
takeOff(2)
WoW.now = 7810
WoW.layer.taxi = false
repaint()   -- off the taxi for a moment
WoW.now = 7811
WoW.layer.taxi = true
repaint()   -- back on
WoW.now = 7870
WoW.layer.taxi = false
repaint()   -- the real landing: off the taxi, control back not yet
check(F().flight() ~= nil, "the earlier moment off the taxi doesn't count: still waiting")
WoW.now = 7871
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
eq(GlassPanelFlightDB.routes["901>902"].base, 71, "...and the landing is learned")
GlassPanelFlightDB.routes["901>902"] = { base = 89.6 }
repaint()

-- Zoomed: "Flying" on the bar, the glass bar on the screen only while flying.
local claims = {}
EventRegistry:RegisterCallback("GlassPanel.Flight.ZoomedChanged", function(_, z) claims[#claims + 1] = z end)
dbl()
eq(GlassPanelFlightDB.detached, true, "double-click zooms, and saves")
eq(F().float(), nil, "zoomed, not flying: nothing built")
eq(GlassPanel.Flight.API, 1, "the public table")
eq(GlassPanel.Flight.Zoomed(), false, "not flying: not claimed")
WoW.now = 10000
takeOff(2)
local fb = F().float()
check(fb ~= nil and fb._shown, "flying: the bar shows")
eq(textOf("flight"), "Flying", "the block says Flying")
eq(fb._parent, UIParent, "on UIParent")
eq(fb._width .. "x" .. fb._height, "480x18", "XP+'s zoomed bar's size")
eq(F().bar().left._text, "Thorium Point", "the destination, short")
eq(F().bar().right._text, "1:30", "the time left")
eq(GlassPanel.Flight.Zoomed(), true, "claimed for Glass Unit Frames")
eq(claims[#claims], true, "...and said")
WoW.tick(0.3)
eq(fb._alpha, 1, "faded in")
WoW.now = 10045
repaint()
eq(F().bar().right._text, "0:45", "the ticker repaints it")
local host = F().bar().host
eq(host._max, 89.6, "the bar spans the flight")
check(math.abs(host._value - 44.6) < 1e-6, "by default it empties as you fly, like a channel")
local fillOpt
for _, o in ipairs(block("flight").options) do if o.label:find("fills up", 1, true) then fillOpt = o end end
eq(fillOpt.get(), false, "the fill-up option is off by default")
fillOpt.set(true)
eq(host._value, 45, "on: it fills up instead, at once")
eq(GlassPanelFlightDB.fillUp, true, "...saved")
fillOpt.set(false)
eq(GlassPanelFlightDB.fillUp, nil, "off is stored as nothing")
WoW.now = 10089.6
landNow()
WoW.tick(0.3)
eq(fb._shown, false, "landed: it goes")
eq(GlassPanel.Flight.Zoomed(), false, "no longer claimed")
eq(claims[#claims], false, "...and said")
dbl()
WoW.now = 11000
takeOff(2)
eq(fb._shown, false, "docked: no bar")
eq(GlassPanel.Flight.Zoomed(), false, "docked: never claimed")
eq(textOf("flight"), "1:30", "docked: the time on the block")
landNow(); repaint()

-- The preview: the bar out of a flight for 30 s, only when zoomed.
WoW.chat = {}
F().setPreview()
check((WoW.chat[1] or ""):find("zoom the timer first", 1, true), "docked: says to zoom first")
dbl()
F().setPreview()
check(fb._shown, "preview shows the bar")
eq(F().bar().left._text, "Preview flight", "a sample flight")
eq(GlassPanel.Flight.Zoomed(), false, "a preview claims nothing")
WoW.now = WoW.now + 31
repaint(); WoW.tick(0.3)
eq(fb._shown, false, "...and it ends")

-- Overtime: past the prediction the time counts on in orange; the bar stays at its end.
GlassPanelFlightDB.detached = true
WoW.now = 12500
takeOff(2)   -- 901>902: 89.6 s learned
WoW.now = 12500 + 89.6 + 7
repaint()
eq(textOf("flight"), "Flying", "zoomed: the block says Flying")
eq(F().bar().right._text, "|cffff9900+0:07|r", "seven seconds past the prediction, in orange")
eq(F().bar().host._value, 0, "the drained bar stays empty")
local tipLines = {}
F().float()._scripts.OnEnter(F().float())
for _, l in ipairs(GameTooltip._lines) do tipLines[#tipLines + 1] = l end
check(table.concat(tipLines, "\n"):find("Longer than predicted", 1, true), "the tooltip says so")
GameTooltip:Hide()
GlassPanelFlightDB.detached = nil
GlassPanel.Refresh("flight"); WoW.tick()
eq(textOf("flight"), "|cffff9900+0:07|r", "docked: the block shows it too")
WoW.now = 12500 + 100
landNow()
eq(GlassPanelFlightDB.routes["901>902"].base, 100, "the landing teaches the longer time")
GlassPanelFlightDB.routes["901>902"] = { base = 89.6 }
repaint(); WoW.tick(0.3)
GlassPanelFlightDB.detached = true

-- Current(): the flight for Glass Unit Frames' cast bar, a copy, with "Changed" said.
local changes = 0
EventRegistry:RegisterCallback("GlassPanel.Flight.Changed", function() changes = changes + 1 end)
eq(GlassPanel.Flight.Current(), nil, "off a flight: nil")
WoW.now = 13000
local before = changes
takeOff(3)
check(changes > before, "takeoff is said")
local cur = GlassPanel.Flight.Current()
eq(cur.to, "Morgan's Vigil, Burning Steppes", "the destination")
eq(cur.from, "Ironforge, Dun Morogh", "where from")
eq(cur.start, 13000, "start in GetTime() seconds")
eq(cur.total, 140, "the total")
eq(cur.source, "learned", "where the total comes from")
eq(cur.early, false, "not landing early")
cur.total = 1
eq(GlassPanel.Flight.Current().total, 140, "a copy: changing it changes nothing here")
-- (Dead test sessions keep their callbacks, so the count may run over.)
before = changes
TaxiRequestEarlyLanding(); WoW.tick()
check(changes > before, "an early landing is said")
cur = GlassPanel.Flight.Current()
check(cur.early and cur.total == nil, "landing early: no total")
before = changes
landNow()
check(changes > before, "the landing is said")
eq(GlassPanel.Flight.Current(), nil, "landed: nil")
repaint()

-- Moving: shift-drag, saved in screen units; the slider; reset.
F().setPreview()
WoW.shift = true; fb._scripts.OnDragStart(fb); WoW.shift = false
fb._center = { 400, 700 }
fb._scripts.OnDragStop(fb)
local sc = F().floatScale()
eq(sc, 1.5, "XP+'s usual scale by default")
check(GlassPanelFlightDB.spot.x == 400 * sc - 500 and GlassPanelFlightDB.spot.y == 700 * sc - 384, "saved from UIParent's centre")
F().setScale(9)
eq(F().floatScale(), 2, "clamped")
F().setScale(1.5)
F().resetSpot()
eq(GlassPanelFlightDB.spot, nil, "reset position")
WoW.now = WoW.now + 31
repaint(); WoW.tick(0.3)

-- Under XP+'s zoomed bar: the default slots stack.
PLUGINS = { "GlassPanelFlight", "GlassPanelXP" }
WoW.player = { level = 30, maxLevel = 60, xp = 12000, maxXP = 45000, rested = 0, xpDisabled = false }
WoW.quests = {}
GlassPanelXPDB = { detached = true }
GlassPanelFlightDB.detached = true
loadAddon()
WoW.now = 12000
takeOff(2)
local xpF = block("xp")._test.float()
fb = F().float()
check(xpF and xpF._shown and fb and fb._shown, "both zoomed bars are up")
eq(xpF._points[1][5], -40, "XP+ takes the first slot")
eq(fb._points[1][5] * F().floatScale(), -40 - 46 - 8, "the flight bar stacks right under it")
block("xp")._test.setDetached(false); WoW.tick()
eq(fb._points[1][5] * F().floatScale(), -40, "XP+ docked: it moves up to the first slot")
landNow(); repaint()
PLUGINS = { "GlassPanelFlight" }

-- Forgetting.
F().forget()
eq(next(GlassPanelFlightDB.routes), nil, "forgotten")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_flight")
