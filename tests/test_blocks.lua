-- The built-in blocks.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelXP", "GlassPanelGold", "GlassPanelClock" }   -- the lanes these tests assert on

-- Gold: coin text, and the session delta in the tooltip.
WoW.money = 1234567
loadAddon()
eq(textOf("gold"), "123g45s67c", "gold text via C_CurrencyInfo")
eq(block("gold").icon, nil, "no block icon: it read as a gold coin before silver-only amounts")
WoW.money = 1234567 + 250
WoW.fire("PLAYER_MONEY")
WoW.tick()
eq(textOf("gold"), "123g48s17c", "repaints on PLAYER_MONEY")
local g = block("gold")
g.widget._scripts.OnEnter(g.widget)
local found = false
for _, line in ipairs(GameTooltip._lines) do
    if line == "Earned	+0g2s50c" then found = true end
end
check(found, "tooltip shows the session gain")

-- Gold while GetMoney is secret: no throw, an honest label, no failure.
WoW.moneySecret = true
loadAddon()
check(textOf("gold"):find("hidden"), "secret money shows 'hidden'")
g = block("gold")
g.widget._scripts.OnEnter(g.widget)
check(GameTooltip._lines[2]:find("hiding"), "tooltip explains")
check(next(GlassPanel.failures) == nil, "no failures while money is secret")

-- Secret -> plain -> secret -> plain: the baseline waits for the first plain
-- read, and a loss shows as a negative delta.
WoW.moneySecret = true
loadAddon()
WoW.moneySecret, WoW.money = false, 50000
WoW.fire("PLAYER_MONEY"); WoW.tick()
eq(textOf("gold"), "5g0s0c", "plain again after secret")
WoW.moneySecret = true
WoW.fire("PLAYER_MONEY"); WoW.tick()
check(textOf("gold"):find("hidden"), "secret again")
WoW.moneySecret, WoW.money = false, 40000
WoW.fire("PLAYER_MONEY"); WoW.tick()
g = block("gold")
g.widget._scripts.OnEnter(g.widget)
found = false
for _, line in ipairs(GameTooltip._lines) do
    if line:find("-1g0s0c", 1, true) then found = true end
end
check(found, "session loss measured from the first plain read")
check(next(GlassPanel.failures) == nil, "no failures across secret transitions")

-- The session survives a /reload and starts again at a login (#161).
local function tipLines()
    local lines = {}
    for _, line in ipairs(GameTooltip._lines) do
        local l, r = line:match("^(.-)	(.*)$")
        if l then lines[l] = r end
    end
    return lines
end
local function goldTip()
    local b = block("gold")
    b.widget._scripts.OnEnter(b.widget)
    return tipLines()
end
GlassPanelGoldDB = nil
WoW.moneySecret, WoW.money, WoW.serverTime = false, 10000, 100000
loadAddon()
eq(GlassPanelGoldDB.session.start, 10000, "the session is saved per character")
eq(GlassPanelGoldDB.session.at, 100000, "with its start time")
WoW.money, WoW.serverTime = 30000, 100000 + 2 * 3600
loadAddon({ reload = true })
local tip = goldTip()
eq(tip["Started with"], "1g0s0c", "a /reload keeps the session's start")
eq(tip["Earned"], "+2g0s0c", "and what was earned before it")
eq(tip["This session"], "2h 00m", "and how long it has run")
eq(tip["Per hour"], "+1g0s0c", "per hour over the whole session")
WoW.money = 5000
tip = goldTip()
eq(tip["Spent"], "-0g50s0c", "a loss is 'Spent'")
eq(tip["Earned"], nil, "not 'Earned'")
eq(tip["Per hour"], "-0g25s0c", "and a negative rate")

loadAddon()   -- a login (or a character switch, or a reconnect)
tip = goldTip()
eq(tip["Started with"], "0g50s0c", "a login starts a new session")
eq(tip["Earned"], "0g0s0c", "with nothing earned yet")
eq(tip["Per hour"], nil, "no rate for a session under 5 minutes")
eq(GlassPanelGoldDB.session.start, 5000, "and saves it")

-- A login while money is secret drops the old session at once, so a /reload
-- before the first plain read doesn't bring an earlier login's back.
WoW.moneySecret = true
loadAddon()
eq(GlassPanelGoldDB.session, nil, "a login forgets the earlier session even before a plain read")
loadAddon({ reload = true })
WoW.moneySecret, WoW.money = false, 70000
WoW.fire("PLAYER_MONEY"); WoW.tick()
tip = goldTip()
eq(tip["Started with"], "7g0s0c", "the session starts at the first plain read")
check(next(GlassPanel.failures) == nil, "no failures across reloads")

-- A corrupt save is no session.
GlassPanelGoldDB = { session = { start = "lots", at = 1 } }
WoW.money = 20000
loadAddon({ reload = true })
eq(goldTip()["Started with"], "2g0s0c", "a corrupt saved session is replaced")
GlassPanelGoldDB = { session = { start = 1.5 } }
loadAddon({ reload = true })
eq(GlassPanelGoldDB.session.start, 20000, "a fractional start isn't copper")
GlassPanelGoldDB = { session = { start = 40000, at = "x" } }
loadAddon({ reload = true })
tip = goldTip()
eq(tip["Started with"], "4g0s0c", "a bad time keeps the amount")
eq(tip["This session"], "", "but no length")
eq(tip["Per hour"], nil, "and no rate")

-- An open tooltip moves on by itself (Codex on #162): the length, and the rate
-- once the session is 5 minutes old, without another event or hover.
GlassPanelGoldDB = nil
WoW.money, WoW.serverTime = 10000, 100000
loadAddon()
WoW.money = 70000
WoW.serverTime = 100000 + 299
tip = goldTip()
eq(tip["This session"], "4m", "4 minutes in")
eq(tip["Per hour"], nil, "no rate yet")
check(block("gold")._test.ticker() ~= nil, "the open tooltip ticks")
WoW.serverTime = 100000 + 360
WoW.fireTickers(); WoW.tick()
tip = tipLines()
eq(tip["This session"], "6m", "the length moved on while open")
eq(tip["Per hour"], "+60g0s0c", "and the rate appeared")
GameTooltip:Hide()
WoW.fireTickers(); WoW.tick()
eq(block("gold")._test.ticker(), nil, "a closed tooltip stops the ticker")

-- A flat session past 5 minutes has a known rate: zero, with no sign.
WoW.money = 10000
tip = goldTip()
eq(tip["Earned"], "0g0s0c", "no change")
eq(tip["Per hour"], "0g0s0c", "a zero rate, unsigned")
GameTooltip:Hide()
WoW.fireTickers()

-- The plugin's option: reset the session now.
WoW.money, WoW.serverTime = 20000, 100000
loadAddon()
WoW.money, WoW.serverTime = 90000, 101000
block("gold")._test.reset()
eq(GlassPanelGoldDB.session.start, 90000, "reset starts the session again")
eq(GlassPanelGoldDB.session.at, 101000, "now")
check(WoW.chat[#WoW.chat]:find("starts again now"), "and says so")
WoW.moneySecret = true
block("gold")._test.reset()
eq(GlassPanelGoldDB.session, nil, "a reset while money is secret waits for a plain read")
check(WoW.chat[#WoW.chat]:find("hiding"), "and says why")
WoW.moneySecret = false
eq(block("gold")._test.duration(59), "under a minute", "duration under a minute")
eq(block("gold")._test.duration(3599), "59m", "minutes")
eq(block("gold")._test.duration(3660), "1h 01m", "hours")
GlassPanelGoldDB = nil

-- Clock: local time on the bar, realm time in the tooltip.
loadAddon()
eq(textOf("clock"), os.date("%H:%M"), "clock shows local time")
eq(block("clock").side, "right", "clock sits on the right")
local c = block("clock")
c.widget._scripts.OnEnter(c.widget)
eq(GameTooltip._lines[3], "Realm\t18:03", "realm time in tooltip")

-- Blizzard's minimap clock: hidden while ours shows, back when ours goes.
local function blizzardClock()
    local f = CreateFrame("Button", "TimeManagerClockButton", UIParent)
    return f
end
local bc
loadAddon({ before = function() bc = blizzardClock() end })
eq(bc._shown, false, "Blizzard clock hidden while ours shows")
bc:Show()
eq(bc._shown, false, "stays hidden when Blizzard re-shows it")
GlassPanel._test.slash("hide clock")
eq(bc._shown, true, "back when our clock is hidden")
GlassPanel._test.slash("show clock")
eq(bc._shown, false, "hidden again when ours returns")
GlassPanel._test.slash("toggle")
eq(bc._shown, true, "back when the whole bar is toggled off")
GlassPanel._test.slash("toggle")
eq(bc._shown, false, "hidden again with the bar")

-- Blizzard_TimeManager loading after us.
rawset(_G, "TimeManagerClockButton", nil)
loadAddon()
bc = blizzardClock()
WoW.fire("ADDON_LOADED", "Blizzard_TimeManager")
eq(bc._shown, false, "late-loaded Blizzard clock hidden")

-- The user turns Blizzard's clock on while ours shows: hidden, and given back later.
rawset(_G, "TimeManagerClockButton", nil)
loadAddon({ before = function() bc = blizzardClock(); bc._shown = false end })
bc:Show()
eq(bc._shown, false, "shown by the user while ours is up: hidden")
GlassPanel._test.slash("hide clock")
eq(bc._shown, true, "and given back when ours goes")
GlassPanel._test.slash("show clock")

-- A Blizzard clock the user had off stays off when ours is hidden.
rawset(_G, "TimeManagerClockButton", nil)
loadAddon({ before = function() bc = blizzardClock(); bc._shown = false end })
GlassPanel._test.slash("hide clock")
eq(bc._shown, false, "never shows a clock we did not hide")
rawset(_G, "TimeManagerClockButton", nil)

-- The clock wakes on the minute, not every second.
loadAddon()
eq(GlassPanel.Engine.NextInterval(block("clock")), 60 - tonumber(os.date("%S")), "next repaint at the minute")

-- /gpanel font is case-insensitive.
GlassPanel._test.slash("font Friz")
eq(GlassPanelDB.font, "friz", "font name lowercased")

check(next(GlassPanel.failures) == nil, "no failures recorded")
done("test_blocks")
