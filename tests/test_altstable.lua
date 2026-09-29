-- The AltStable bridge plugin (#46), against AltStable's public API v1.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelAltStable" }

local function tip()
    local b = block("altstable").widget
    b._scripts.OnEnter(b)
    local text = table.concat(GameTooltip._lines, "\n")
    b._scripts.OnLeave(b)   -- closed: an open tooltip is redrawn after every repaint
    return text
end

local function char(name, realm, faction, class, level, money, extra)
    local c = { guid = "Player-" .. name, name = name, realm = realm, faction = faction,
                class = class, level = level, money = money }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

WoW.alts.characters = {
    char("Karuzo Elegia", "Doomhowl", "Horde", "PRIEST", 60, 1234567, { current = true }),
    char("Bankalt", "Doomhowl", "Horde", "MAGE", 1, 50000),
    char("Allie", "Doomhowl", "Alliance", "WARRIOR", 30, 10000),
    char("Farway", "Soulseeker", "Horde", "ROGUE", 45, 20000),
    char("Shy", "Doomhowl", "Horde", "DRUID", 20, 999999, { hidden = true }),
}

GlassPanelAltStableDB = nil
loadAddon()
check(block("altstable"), "block registered")
check(next(GlassPanel.failures) == nil, "no failures")
-- Default scope: every character, the sheet's total (hidden left out).
eq(textOf("altstable"), "131g45s67c", "total of every visible character")
eq(block("altstable").widget.caption._text, "Alts: ", "caption")

-- Tooltip: grouped by realm, class colours, level, current marked, hidden
-- ones skipped, then the total.
local t = tip()
check(t:find("^Alts\n"), "header")
local dh = t:find("\nDoomhowl\n", 1, true)
local karuzo = t:find("|cff88888860|r |cffffffffKaruzo Elegia|r |cff4dff4d(logged in)|r\t123g45s67c", 1, true)
local bank = t:find("|cff8888881|r |cff40c7ebBankalt|r\t5g0s0c", 1, true)
local ss = t:find("\nSoulseeker\n", 1, true)
local far = t:find("|cff88888845|r |cfffff569Farway|r\t2g0s0c", 1, true)
check(dh and bank and karuzo and ss and far and dh < bank and bank < karuzo and karuzo < ss and ss < far,
      "rows by realm then name, under realm headers")
check(not t:find("Shy", 1, true), "hidden character not listed")
check(t:find("Total (4)\t131g45s67c", 1, true), "total line")
check(t:find("1 hidden in AltStable, not counted.", 1, true), "hidden count said")
check(t:find("Left-click: open AltStable", 1, true), "click hint")

-- Unknown money: not counted as 0, a grey ? on the bar, said in the tooltip.
WoW.alts.characters[2].money = nil
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()
eq(textOf("altstable"), "126g45s67c |cff888888?|r", "repainted on CharactersChanged, unknown flagged")
t = tip()
check(t:find("Bankalt|r\t|cff888888?|r", 1, true), "unknown gold row")
check(t:find("1 character(s) with unknown gold, not counted.", 1, true), "unknown count said")

-- Click opens the sheet.
local w = block("altstable").widget
w._scripts.OnClick(w, "LeftButton")
eq(WoW.altsToggles, 1, "left-click toggles AltStable's sheet")
w._scripts.OnClick(w, "RightButton")
eq(WoW.altsToggles, 1, "right-click doesn't")

-- Option: this realm and faction only (the logged-in character's).
block("altstable").options[1].set(true)
WoW.tick()
eq(GlassPanelAltStableDB.realmOnly, true, "saved")
eq(textOf("altstable"), "123g45s67c |cff888888?|r", "Doomhowl Horde only (Bankalt unknown)")
t = tip()
check(t:find("^Alts: this realm and faction\n"), "scoped header")
check(not t:find("Allie", 1, true) and not t:find("Farway", 1, true), "other faction and realm left out")
check(t:find("Total (2)", 1, true), "scoped count")
check(t:find("1 hidden in AltStable", 1, true), "scoped hidden count")
-- No record of this character yet: the scope is unknown, not zero.
WoW.alts.characters[1].current = nil
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()
eq(textOf("altstable"), "|cff888888?|r", "no current record: unknown")
check(tip():find("AltStable doesn't know this character yet.", 1, true), "said in the tooltip")
WoW.alts.characters[1].current = true
block("altstable").options[1].set(false)
WoW.tick()
eq(GlassPanelAltStableDB.realmOnly, nil, "off stored as nil")
eq(textOf("altstable"), "126g45s67c |cff888888?|r", "back to every character")

-- AltStable's own icon, never a coin (a coin before "37s 81c" reads as 37 gold).
eq(block("altstable").icon, 8197123, "AltStable's icon")

-- Default scope: the bar reads only the totals, not the whole list.
local reads = 0
local get = AltStable.GetCharacters
AltStable.GetCharacters = function() reads = reads + 1; return get() end
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()
eq(reads, 0, "bar text doesn't copy the character list")
tip()
eq(reads, 1, "the tooltip does")
AltStable.GetCharacters = get

-- A burst of changes: one repaint, on the next frame, not at once.
local paints = 0
local text = block("altstable").text
block("altstable").text = function(...) paints = paints + 1; return text(...) end
WoW.altsChanged(); WoW.altsChanged(); WoW.altsChanged()
WoW.tick()
eq(paints, 0, "nothing before the callback's frame")
WoW.flushTimers(0); WoW.tick()
eq(paints, 1, "one repaint per burst")
block("altstable").text = text

-- No counted gold known: unknown, never "0c".
local saved = WoW.alts.characters
WoW.alts.characters = { char("Karuzo Elegia", "Doomhowl", "Horde", "PRIEST", 60, nil, { current = true }) }
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()
eq(textOf("altstable"), "|cff888888?|r", "only unknown gold: ?")
check(tip():find("Total (1)\t|cff888888?|r", 1, true), "tooltip total unknown too")
WoW.alts.characters = {}
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()
eq(textOf("altstable"), "|cff888888?|r", "no characters yet (before AltStable's scan): ?")

-- This realm and faction: a record with no realm or faction isn't dropped
-- silently: not counted, flagged and said.
WoW.alts.characters = {
    char("Karuzo Elegia", "Doomhowl", "Horde", "PRIEST", 60, 10000, { current = true }),
    char("Oldpeer", nil, "Horde", "MAGE", 10, 50000),
    char("Partial", "Doomhowl", nil, "MAGE", 10, 50000),
    char("Gone", nil, nil, "MAGE", 10, 50000, { hidden = true }),
}
block("altstable").options[1].set(true)
WoW.tick()
eq(textOf("altstable"), "1g0s0c |cff888888?|r", "unplaced records flagged on the bar")
t = tip()
check(t:find("2 character(s) with no realm or faction known, not counted.", 1, true), "and said (hidden ones not)")
check(t:find("Total (1)\t1g0s0c", 1, true), "total of the placed ones")
block("altstable").options[1].set(false)
WoW.alts.characters = saved
WoW.altsChanged(); WoW.flushTimers(0); WoW.tick()

-- A dead session's listener is never called (the stub's own guarantee).
check(#WoW.altsErrors == 0, "no listener errors")

-- A different public API version: no block, and it says why.
WoW.alts.version = 2
WoW.chat = {}
loadAddon()
eq(block("altstable"), nil, "incompatible API: no block")
check(GlassPanel.failures["altstable:api"], "recorded")
check(table.concat(WoW.chat, "\n"):find("public API version 1 not found (got 2)", 1, true), "printed")

-- It replaces Gold (#50), live: Gold is hidden while Alts shows, and it's
-- said once; nothing about Gold is stored until the player shows it again.
WoW.alts.version = 1
local both = { "GlassPanelAltStable", "GlassPanelGold" }
local function said() return table.concat(WoW.chat, "\n") end
loadAddon({ plugins = both })
eq(block("gold").widget._shown, false, "Gold off the bar while Alts shows")
eq(GlassPanelDB.hidden.gold, nil, "not stored as hidden")
check(said():find("Alts replaces Gold, which is hidden.", 1, true) and said():find("/gpanel show gold", 1, true),
      "said, by label, with the way back")
local db = GlassPanelDB
loadAddon({ plugins = both, db = db })
check(not said():find("replaces", 1, true), "said once")
-- Alts hidden: Gold comes back; shown again: Gold goes.
GlassPanel._test.slash("hide altstable")
eq(block("gold").widget._shown, true, "Alts hidden: Gold shows")
GlassPanel._test.slash("show altstable")
eq(block("gold").widget._shown, false, "Alts back: Gold hidden again")
-- The player shows Gold: kept, across sessions, even with Alts on.
GlassPanel._test.slash("show gold")
eq(block("gold").widget._shown, true, "shown by the player")
eq(GlassPanelDB.keep.gold, true, "kept")
loadAddon({ plugins = both, db = db })
eq(block("gold").widget._shown, true, "stays shown next session")
-- Another character without the Alts block (plugin off, or refused): Gold
-- is there, nothing to undo.
loadAddon({ plugins = { "GlassPanelGold" } })
eq(block("gold").widget._shown, true, "no Alts block: Gold shows")
WoW.alts.version = 2
loadAddon({ plugins = both })
eq(block("gold").widget._shown, true, "Alts refused: Gold shows")
WoW.alts.version = 1
-- Alts already hidden by the player: Gold shows, nothing said.
loadAddon({ plugins = both, db = { hidden = { altstable = true } } })
eq(block("gold").widget._shown, true, "Alts hidden from the start: Gold shows")
check(not said():find("replaces", 1, true), "nothing said")
-- The bar off: nothing said (and so still said once it's on, next session).
loadAddon({ plugins = both, db = { shown = false } })
check(not said():find("replaces", 1, true), "bar off: nothing said")
eq(GlassPanelDB.replaced["altstable>gold"], nil, "not recorded")
-- ... and said when the bar comes on (Codex on #51).
GlassPanel._test.slash("toggle")
check(said():find("Alts replaces Gold", 1, true), "bar toggled on: said then")
eq(block("gold").widget._shown, false, "and Gold hidden")
-- Alts hidden from the start, then shown: Gold goes, and it's said then.
loadAddon({ plugins = both, db = { hidden = { altstable = true } } })
GlassPanel._test.slash("show altstable")
eq(block("gold").widget._shown, false, "Alts shown: Gold hidden")
check(said():find("Alts replaces Gold", 1, true), "said when Alts is shown")
-- Show Gold while Alts is hidden: still the player's choice once Alts is
-- back (Codex on #51).
loadAddon({ plugins = both, db = { hidden = { altstable = true, gold = true } } })
GlassPanel._test.slash("show gold")
GlassPanel._test.slash("show altstable")
eq(block("gold").widget._shown, true, "Gold shown while Alts was hidden: kept")
-- An explicit Hide clears the keep: shown again with Alts on, Gold goes.
GlassPanel._test.slash("hide gold")
eq(GlassPanelDB.keep.gold, nil, "hide clears keep")
GlassPanelDB.hidden.gold = nil   -- (as an imported setup could)
GlassPanel.Bar.Layout()
eq(block("gold").widget._shown, false, "replaced again")

done("test_altstable")
