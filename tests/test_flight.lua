-- The Flight plugin (#124): learned flight times, the block, the zoomed bar, GUF's claim.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelFlight" }

local function F() return block("flight")._test end
local function widget() return block("flight").widget end
local function dbl() widget()._scripts.OnDoubleClick(widget(), "LeftButton"); WoW.tick() end

-- Ironforge (slot 1, node 6) -> Thorium Point (2, 74) -> Morgan's Vigil (3, 71).
WoW.taxi.nodes = {
    [1] = { id = 6, name = "Ironforge, Dun Morogh" },
    [2] = { id = 74, name = "Thorium Point, Searing Gorge" },
    [3] = { id = 71, name = "Morgan's Vigil, Burning Steppes" },
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
eq(F().pathOf(fl.route.keys), "6>74", "keyed by node ids")
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
eq(GlassPanelFlightDB.routes["6>74"].base, 90, "the time is learned, to a tenth")
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
eq(GlassPanelFlightDB.routes["6>74"].base, 89.6, "the newest landing is kept")

-- A path never flown: the sum of its learned hops, as an estimate.
GlassPanelFlightDB.routes["74>71"] = { base = 60 }
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
eq(GlassPanelFlightDB.routes["6>74>71"].base, 140, "the whole path is learned on its own")
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
eq(GlassPanelFlightDB.routes["6>74"].fast, 72, "learned as its own kind")
eq(GlassPanelFlightDB.routes["6>74"].base, 89.6, "...the other kept")
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
eq(GlassPanelFlightDB.routes["6>74>71"].base, 140, "...and nothing learned")
eq(GlassPanelFlightDB.routes["6>74>71"].fast, nil, "...of either kind")
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
check(fl ~= nil and fl.route == nil, "on the taxi a second later: a flight, route unknown")
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
GlassPanelFlightDB.routes["6>74"] = nil
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
eq(GlassPanelFlightDB.routes["6>74"].base, 51, "...and learned, timed at control back")
-- Control back while the taxi still reads on, then off the taxi at a later tick.
GlassPanelFlightDB.routes["6>74"] = nil
WoW.now = 6200
takeOff(2)
WoW.now = 6260
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
check(F().flight() ~= nil, "control back still on the taxi: not landed yet")
WoW.now = 6261
WoW.layer.taxi = false
repaint()
eq(F().flight(), nil, "off the taxi at the next tick: landed")
eq(GlassPanelFlightDB.routes["6>74"].base, 60, "...and learned, timed at control back")
GlassPanelFlightDB.routes["6>74"] = { base = 89.6 }   -- as the tests below expect

-- Early landing: the time left goes, nothing learned.
WoW.now = 7000
takeOff(3)
TaxiRequestEarlyLanding(); WoW.tick()
eq(WoW.taxi.early, 1, "the request still reaches the client")
eq(F().flight().early, true, "marked early")
eq(textOf("flight"), "|cff999999+0:00|r", "the time flown instead")
WoW.now = 7050
landNow()
eq(GlassPanelFlightDB.routes["6>74>71"].base, 140, "an early landing teaches nothing")
repaint()

-- A /reload mid-flight resumes the saved flight from server time, learning nothing.
WoW.now, WoW.serverTime = 8000, 500000
takeOff(2)
eq(GlassPanelFlightDB.current.at, 500000, "the flight is saved for a reload")
F().ticker():Cancel()   -- the old session's (a test-only leftover)
WoW.now, WoW.serverTime = 9000, 500030
loadAddon()
fl = F().flight()
check(fl ~= nil and fl.resumed, "reloaded on the taxi: resumed")
eq(textOf("flight"), "1:00", "30 s in, the right time left")
WoW.now = 9060
landNow()
eq(GlassPanelFlightDB.routes["6>74"].base, 89.6, "a resumed flight teaches nothing")
-- Saved too long ago, or not on a taxi: no resume.
GlassPanelFlightDB.current = { route = { keys = { 6, 74 }, names = { "A", "B" } }, at = WoW.serverTime - 99999 }
WoW.layer.taxi = true
loadAddon()
fl = F().flight()
check(fl ~= nil and fl.route == nil, "a stale save: a flight, route unknown")
WoW.layer.taxi = false
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
GlassPanelFlightDB.current = { route = { keys = { 6 }, names = { "A" } }, at = WoW.serverTime }
loadAddon()
eq(F().flight(), nil, "off the taxi: none")
eq(GlassPanelFlightDB.current, nil, "...and the save is dropped")

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
eq(GlassPanelFlightDB.routes, nil, "forgotten")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_flight")
