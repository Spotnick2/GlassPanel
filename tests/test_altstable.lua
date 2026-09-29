-- The AltStable bridge plugin (#46), against AltStable's public API v1.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelAltStable" }

local function tip()
    local b = block("altstable").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
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
WoW.altsChanged(); WoW.tick()
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
WoW.altsChanged(); WoW.tick()
eq(textOf("altstable"), "|cff888888?|r", "no current record: unknown")
check(tip():find("AltStable doesn't know this character yet.", 1, true), "said in the tooltip")
WoW.alts.characters[1].current = true
block("altstable").options[1].set(false)
WoW.tick()
eq(GlassPanelAltStableDB.realmOnly, nil, "off stored as nil")
eq(textOf("altstable"), "126g45s67c |cff888888?|r", "back to every character")

-- A different public API version: no block, and it says why.
WoW.alts.version = 2
WoW.chat = {}
loadAddon()
eq(block("altstable"), nil, "incompatible API: no block")
check(GlassPanel.failures["altstable:api"], "recorded")
check(table.concat(WoW.chat, "\n"):find("public API version 1 not found (got 2)", 1, true), "printed")

done("test_altstable")
