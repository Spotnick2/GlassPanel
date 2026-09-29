-- The Currencies plugin (#47).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelCurrencies" }

local function B() return block("currencies") end
local function T() return B()._test end
local function tip()
    local w = B().widget
    w._scripts.OnEnter(w)
    return table.concat(GameTooltip._lines, "\n")
end
local function forever()
    WoW.currencies = {
        [3402] = { name = "Merchant's Favor", icon = 1001 },
        [3469] = { name = "Tarnished Undermine Real", icon = 1002 },
        [1792] = { name = "Honor Points", icon = 1003, max = 75000 },
        [3468] = { name = "Rank Points", icon = 1004 },
        [515]  = { name = "Darkmoon Prize Ticket", icon = 1005 },
    }
end

-- Nothing owned, never configured: the block stays off the bar.
forever()
GlassPanelCurrenciesDB = nil
loadAddon()
eq(B().widget._shown, false, "no currencies owned: hidden")
-- Forever's five are still offered (by id), sorted by name.
local names = {}
for _, c in ipairs(T().available()) do names[#names + 1] = c.name end
eq(table.concat(names, ","), "Darkmoon Prize Ticket,Honor Points,Merchant's Favor,Rank Points,Tarnished Undermine Real",
   "Forever's currencies offered before owning any")

-- First run with honor owned: honor shown by default.
forever()
WoW.currencies[1792].quantity = 1234
WoW.currencyTab = { { header = "Player vs. Player" }, 1792 }
GlassPanelCurrenciesDB = nil
loadAddon()
eq(textOf("currencies"), "|T1003:14:14:0:0:64:64:5:59:5:59|t 1,234", "owned honor shown by default, icon from the client")
check(tip():find("Honor Points\t1,234 / 75,000", 1, true), "tooltip: name, amount and cap")
eq(GlassPanelCurrenciesDB.order, nil, "(defaults aren't saved until the player chooses)")

-- The chooser: from the plugin's option button, and a left-click on the block.
local panel = GlassPanel.Options._test.panel
panel:Hide(); panel:Show()
local btn = GlassPanel.Options._test.controls["options:currencies:1"]
check(btn ~= nil, "a 'Choose currencies...' button under Plugin options")
btn._scripts.OnClick(btn)
local win = T().window()
eq(win and win._shown, true, "opens the chooser")
local rows = T().rows
eq(rows[1].id, 1792, "shown currency first")
eq(rows[1].check:GetChecked(), true, "ticked")
eq(rows[2].check:GetChecked(), false, "the rest unticked")
-- Tick Tarnished Undermine Real: added at the end.
local tar
for _, r in ipairs(rows) do if r.id == 3469 then tar = r end end
tar.check:SetChecked(true); tar.check._scripts.OnClick(tar.check)
WoW.tick()
eq(table.concat(GlassPanelCurrenciesDB.order, ","), "1792,3469", "picked, in order, saved")
eq(textOf("currencies"), "|T1003:14:14:0:0:64:64:5:59:5:59|t 1,234  |T1002:14:14:0:0:64:64:5:59:5:59|t 0",
   "both on the bar, in order")
-- Up moves it before honor.
eq(rows[2].id, 3469, "(now the second row)")
eq(rows[1].up:IsEnabled(), false, "the first can't go up")
rows[2].up._scripts.OnClick(rows[2].up)
WoW.tick()
eq(table.concat(GlassPanelCurrenciesDB.order, ","), "3469,1792", "reordered")
check(textOf("currencies"):find("^|T1002"), "the bar follows the order")
-- Untick: removed.
rows[1].check:SetChecked(false); rows[1].check._scripts.OnClick(rows[1].check)
WoW.tick()
eq(table.concat(GlassPanelCurrenciesDB.order, ","), "1792", "unticked: removed")
-- Nothing picked at all: hidden (an empty choice is kept, not reset to defaults).
rows[1].check:SetChecked(false); rows[1].check._scripts.OnClick(rows[1].check)
WoW.tick()
eq(B().widget._shown, false, "nothing picked: hidden")
eq(#GlassPanelCurrenciesDB.order, 0, "the empty choice is kept")
win:Hide()

-- Amounts follow CURRENCY_DISPLAY_UPDATE.
GlassPanelCurrenciesDB.order = { 1792 }
WoW.currencies[1792].quantity = 1300
WoW.fire("CURRENCY_DISPLAY_UPDATE", 1792, 1300, 66); WoW.tick()
check(textOf("currencies"):find("1,300", 1, true), "updated on the event")

-- A secret amount: a grey ?, never a guess.
WoW.currencies[1792].quantity = "secret"
WoW.fire("CURRENCY_DISPLAY_UPDATE", 1792); WoW.tick()
check(textOf("currencies"):find("|cff888888?|r", 1, true), "secret amount: ?")
WoW.currencies[1792].quantity = 1300

-- A picked id the client no longer knows is skipped, nothing thrown.
GlassPanelCurrenciesDB.order = { 99999, 1792 }
GlassPanel.Refresh("currencies"); WoW.tick()
check(textOf("currencies"):find("1,300", 1, true), "unknown id skipped")
-- Corrupt saved data: back to defaults.
GlassPanelCurrenciesDB.order = "junk"
GlassPanel.Refresh("currencies"); WoW.tick()
check(textOf("currencies"):find("1,300", 1, true), "corrupt order: defaults")

-- The tab lists only what isn't collapsed; a header isn't a currency.
WoW.currencyTab = { { header = "Misc" } }
local ids = {}
for _, c in ipairs(T().available()) do ids[c.id] = true end
check(ids[1792] and ids[515], "known ids offered even when the tab is collapsed")

-- Left-click on the block opens the chooser too.
local w = B().widget
w._scripts.OnClick(w, "LeftButton")
eq(T().window()._shown, true, "left-click opens the chooser")
-- The open chooser follows amounts as they change.
WoW.currencies[1792].quantity = 1450
WoW.fire("CURRENCY_DISPLAY_UPDATE", 1792); WoW.tick()
local hon
for _, r in ipairs(T().rows) do if r.id == 1792 then hon = r end end
check(hon.text._text:find("1,450", 1, true), "chooser updated on the event")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_currencies")
