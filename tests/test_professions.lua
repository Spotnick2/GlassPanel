-- The Professions plugin (#15).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tip()
    local b = block("professions").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function icon(path) return "|TInterface\\Icons\\" .. path .. ":14:14:0:0|t" end
local function changed() WoW.fire("SKILL_LINES_CHANGED"); WoW.tick() end

-- Nothing learned: the block hides.
loadAddon()
eq(block("professions").widget._shown, false, "no professions: hidden")
check(tip():find("No professions learned.", 1, true), "tooltip says so")

-- Primary professions on the bar (crafting before gathering), matched by
-- skillID; secondary ones and other skills only in the tooltip / nowhere.
WoW.skills = {
    { name = "Professions", isHeader = true },
    { skillID = 186, name = "Mining", rank = 150, maxRank = 225 },          -- 67%: orange
    { skillID = 164, name = "Forge", rank = 300, maxRank = 300 },           -- maxed: green, client's name
    { name = "Secondary Skills", isHeader = true },
    { skillID = 185, name = "Cooking", rank = 60, maxRank = 75 },
    { skillID = 129, name = "First Aid", rank = 10, maxRank = 75 },
    { name = "Weapon Skills", isHeader = true },
    { skillID = 43, name = "Swords", rank = 280, maxRank = 300 },
}
changed()
eq(textOf("professions"),
    icon("Trade_BlackSmithing") .. "|cff1eff00300/300|r  " .. icon("Trade_Mining") .. "|cffff8800150/225|r",
    "primary professions, coloured, two spaces apart")
local t = tip()
check(t:find(icon("Trade_BlackSmithing") .. " Forge\t|cff1eff00300 / 300|r", 1, true), "tooltip: client's name")
check(t:find("Secondary", 1, true), "secondary section")
check(t:find(icon("INV_Misc_Food_15") .. " Cooking\t|cffffff0060 / 75|r", 1, true), "cooking in the tooltip, yellow")
check(t:find("First Aid\t|cff80808010 / 75|r", 1, true), "first aid under 25%: grey")
check(not textOf("professions"):find("Food", 1, true), "secondary not on the bar")
check(not t:find("Swords", 1, true), "weapon skills ignored")

-- The colour steps, and maxRank 0 (truthy) doesn't divide by zero.
WoW.skills = {
    { skillID = 171, name = "Alchemy", rank = 30, maxRank = 75 },    -- 40%: red
    { skillID = 393, name = "Skinning", rank = 5, maxRank = 0 },     -- no max: grey
}
changed()
eq(textOf("professions"),
    icon("Trade_Alchemy") .. "|cffff202030/75|r  " .. icon("INV_Misc_Pelt_Wolf_01") .. "|cff8080805/0|r",
    "red at 40%, grey with max 0")

-- Only secondary professions: nothing on the bar.
WoW.skills = { { skillID = 356, name = "Fishing", rank = 1, maxRank = 75 } }
changed()
eq(block("professions").widget._shown, false, "secondary only: hidden")

-- A secret rank: that profession shows "?", never a guess.
WoW.skills = {
    { skillID = 197, name = "Tailoring", rank = "secret", maxRank = 150 },
    { skillID = 182, name = "Herbalism", rank = 100, maxRank = 150 },
}
changed()
eq(textOf("professions"),
    icon("Trade_Tailoring") .. "|cff888888?|r  " .. icon("Trade_Herbalism") .. "|cffff8800100/150|r",
    "secret rank: ?")
check(tip():find("Tailoring\t|cff888888?|r", 1, true), "tooltip: ?")

-- A secret maxRank that keeps its number type (as on the client): "?".
WoW.MarkSecret(313)
WoW.skills = { { skillID = 202, name = "Engineering", rank = 100, maxRank = 313 } }
changed()
eq(textOf("professions"), icon("Trade_Engineering") .. "|cff888888?|r", "secret-but-number max: ?")

-- A secret name: the English fallback, the rank still shown.
WoW.skills = { { skillID = 333, name = "secret", rank = 75, maxRank = 75 } }
changed()
check(tip():find("Enchanting\t|cff1eff0075 / 75|r", 1, true), "secret name: fallback")

-- An unreadable row (a secret table) or skillID may be a profession: a grey
-- "?" beside what could be read, and the tooltip says why.
WoW.skills = {
    { skillID = 165, name = "Leatherworking", rank = 50, maxRank = 75 },
    { skillID = 186, name = "Mining", rank = 50, maxRank = 75, secretRow = true },
    { skillID = "secret", name = "?", rank = 1, maxRank = 1 },
}
changed()
eq(textOf("professions"), icon("Trade_LeatherWorking") .. "|cffff880050/75|r  |cff888888?|r",
    "unreadable rows: flagged, not dropped silently")
check(tip():find("2 skill line(s) can't be read", 1, true), "tooltip says why")
WoW.skills = { { skillID = 186, secretRow = true } }
changed()
eq(textOf("professions"), "|cff888888?|r", "only unreadable rows: ?, not hidden")

-- A secret line count: hidden, honestly.
WoW.skillCount = "secret"
changed()
eq(textOf("professions"), "|cff888888hidden|r", "secret count: hidden")
check(tip():find("can't be read right now", 1, true), "tooltip says so")
WoW.skillCount = nil

-- A burst of events is one scan, on the next repaint.
WoW.skills = { { skillID = 186, name = "Mining", rank = 51, maxRank = 75 } }
WoW.skillScans = 0
for _ = 1, 10 do WoW.fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 51.") end
WoW.tick()
eq(WoW.skillScans, 1, "10 events, one scan")
tip()
eq(WoW.skillScans, 1, "the tooltip reuses the fresh cache")

-- A scan that throws is recorded and retried, not marked fresh with old data.
local real = C_SkillInfo.GetSkillLineInfo
C_SkillInfo.GetSkillLineInfo = function() error("client hiccup") end
WoW.skills[1].rank = 60
changed()
check(GlassPanel.failures["professions:scan"], "failed scan recorded")
C_SkillInfo.GetSkillLineInfo = real
GlassPanel.failures["professions:scan"] = nil
GlassPanel.Refresh("professions"); WoW.tick()
eq(textOf("professions"), icon("Trade_Mining") .. "|cffffff0060/75|r", "retried on the next repaint")

-- No click yet (a secure spell button comes later): no caption, no handler.
eq(block("professions").showLabel, false, "no caption by default")
eq(block("professions").onClick, nil, "no click handler yet")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_professions")
