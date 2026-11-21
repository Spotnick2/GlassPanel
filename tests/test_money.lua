-- The core's money session (Money.lua, #160): API.MoneySession and
-- API.ResetMoneySession, with no plugin loaded (Alts replaces Gold, and either
-- may be off: the session can't depend on one).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local API

GlassPanelCharDB = nil
WoW.moneySecret, WoW.money, WoW.serverTime = false, 10000, 100000
loadAddon({ plugins = false })
API = GlassPanel.API
local s = API.MoneySession()
check(s ~= nil, "a session from the first plain read, with no plugin loaded")
eq(s.start, 10000, "its start")
eq(s.delta, 0, "nothing earned yet")
eq(s.elapsed, 0, "just started")
eq(GlassPanelCharDB.moneySession.start, 10000, "saved per character")

-- Earned, then a /reload: kept.
WoW.money, WoW.serverTime = 25000, 100000 + 600
WoW.fire("PLAYER_MONEY")
s = API.MoneySession()
eq(s.delta, 15000, "earned")
eq(s.now, 25000, "the money now")
eq(s.elapsed, 600, "ten minutes in")
loadAddon({ plugins = false, reload = true })
API = GlassPanel.API
eq(API.MoneySession().start, 10000, "a /reload keeps the start")
-- A login: a new one.
loadAddon({ plugins = false })
API = GlassPanel.API
eq(API.MoneySession().start, 25000, "a login starts again")

-- A fresh table each call: a caller can't change the session.
API.MoneySession().start = 1
eq(API.MoneySession().start, 25000, "a copy each time")

-- Money hidden right now: nil, never a guess; the session itself is kept.
WoW.moneySecret = true
eq(API.MoneySession(), nil, "hidden money: no session to show")
eq(API.ResetMoneySession(), false, "a reset while hidden waits")
eq(GlassPanelCharDB.moneySession, nil, "nothing saved meanwhile")
WoW.moneySecret, WoW.money = false, 30000
WoW.fire("PLAYER_MONEY")
eq(API.MoneySession().start, 30000, "it starts at the next plain read")
WoW.money = 31000
eq(API.ResetMoneySession(), true, "a reset with money readable: now")
eq(API.MoneySession().start, 31000, "from the money now")

-- A server time that can't be read: the amount still works, no length.
GlassPanelCharDB = { moneySession = { start = 5000, at = "x" } }
loadAddon({ plugins = false, reload = true })
API = GlassPanel.API
s = API.MoneySession()
eq(s.start, 5000, "a bad time keeps the amount")
eq(s.elapsed, nil, "and no length")
check(next(GlassPanel.failures) == nil, "no failures")

GlassPanelCharDB = nil
done("test_money")
