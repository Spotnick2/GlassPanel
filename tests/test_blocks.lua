-- The built-in blocks.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

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
    if line:find("This session") and line:find("+0g2s50c", 1, true) then found = true end
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
