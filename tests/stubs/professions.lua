-- Professions stubs (Plugins/Professions). WoW.skills = the skill pane's rows,
-- { skillID, name, rank, maxRank, isHeader }; a field set to "secret" comes
-- back secret, and secretRow = true returns the whole row as a real table
-- marked secret (a client secret keeps its type). WoW.skillCount = "secret"
-- makes the line count secret.
table.insert(WoW.resetHooks, function()
    WoW.skills = {}
    WoW.skillCount = nil
    WoW.skillScans = 0
end)

local function field(row, k)
    local v = row[k]
    if v == "secret" then return WoW.Secret("skills." .. k) end
    return v
end

-- C_SkillInfo.GetNumSkillLines() -> numSkillLines:number
-- C_SkillInfo.GetSkillLineInfo(index:luaIndex) -> optional skillLineAttributes:SkillLineAttributes
C_SkillInfo = {
    GetNumSkillLines = function()
        WoW.skillScans = WoW.skillScans + 1
        if WoW.skillCount == "secret" then return WoW.Secret("skills.count") end
        return #WoW.skills
    end,
    GetSkillLineInfo = function(index)
        local row = WoW.skills[index]
        if not row then return nil end
        local t = {
            skillID = field(row, "skillID"), name = field(row, "name"),
            isHeader = row.isHeader or false, isCollapsed = false,
            rank = field(row, "rank"), maxRank = field(row, "maxRank"),
        }
        if row.secretRow then WoW.MarkSecret(t) end
        return t
    end,
}

-- C_Spell.GetSpellName(spellIdentifier) -> name. Smelting (2656) opens Mining.
C_Spell = rawget(_G, "C_Spell") or {}
C_Spell.GetSpellName = function(id) return ({ [2656] = "Smelting" })[id] end
