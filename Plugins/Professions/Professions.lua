-- Plugins/Professions/Professions.lua: your professions and their skill (#15),
-- like the TBC Titan bar's TitanProfessions: an icon and a coloured
-- "rank/max" per primary profession (crafting and gathering). Cooking, First
-- Aid and Fishing are listed in the tooltip only.
--
-- Forever notes:
-- - GetProfessions is in the dump but returns nil x7 on this client, so the
--   skill lines are read instead: C_SkillInfo.GetNumSkillLines and
--   C_SkillInfo.GetSkillLineInfo(i), which returns a TABLE here
--   (SkillLineAttributes: skillID, name, isHeader, rank, maxRank, ...), not
--   TBC's tuple.
-- - Professions are matched by skillID, never by localized name; the name
--   shown is the client's. The ids are the Vanilla ones (to confirm in game).
-- - A collapsed header in the character's skill pane may hide its rows from
--   GetNumSkillLines (to confirm in game): a profession under one wouldn't
--   be listed. We don't expand headers ourselves (it would change the pane).
-- - Honest over plausible: a skill line that can't be read (a secret row or
--   skillID) may be a profession, so the bar shows a grey "?" next to what it
--   could read; a secret rank shows "?" for that profession, never a guess.
-- - Events only mark the cache stale; it's rebuilt at most once per repaint.
-- - No click yet: opening a profession needs a secure spell button, which
--   comes in a later change.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

-- skillID -> kind and icon. Vanilla ids, to confirm in game. The English
-- name is only a fallback for a client name that can't be read.
local ICONS = "Interface\\Icons\\"
local PROFESSIONS = {
    [171] = { kind = "crafting", icon = "Trade_Alchemy", name = "Alchemy" },
    [164] = { kind = "crafting", icon = "Trade_BlackSmithing", name = "Blacksmithing" },
    [333] = { kind = "crafting", icon = "Trade_Engraving", name = "Enchanting" },
    [202] = { kind = "crafting", icon = "Trade_Engineering", name = "Engineering" },
    [165] = { kind = "crafting", icon = "Trade_LeatherWorking", name = "Leatherworking" },
    [197] = { kind = "crafting", icon = "Trade_Tailoring", name = "Tailoring" },
    [182] = { kind = "gathering", icon = "Trade_Herbalism", name = "Herbalism" },
    [186] = { kind = "gathering", icon = "Trade_Mining", name = "Mining" },
    [393] = { kind = "gathering", icon = "INV_Misc_Pelt_Wolf_01", name = "Skinning" },
    [185] = { kind = "secondary", icon = "INV_Misc_Food_15", name = "Cooking" },
    [129] = { kind = "secondary", icon = "Spell_Holy_SealOfSacrifice", name = "First Aid" },
    [356] = { kind = "secondary", icon = "Trade_Fishing", name = "Fishing" },
}

-- The cache: primary / secondary = { { name, icon, rank, max } } in skill-pane
-- order, crafting before gathering (rank/max nil when unreadable);
-- unreadable = skill lines that couldn't be read; hidden = the line count
-- itself couldn't be read.
local state = { primary = {}, secondary = {}, unreadable = 0, hidden = false }
local stale = true

-- A plain number, or nil (secret or absent).
local function num(v)
    v = P(v)
    return type(v) == "number" and v or nil
end

local function scan()
    local crafting, gathering, secondary, unreadable = {}, {}, {}, 0
    local count = num(C_SkillInfo.GetNumSkillLines())
    state.hidden = count == nil
    for i = 1, count or 0 do
        local raw = C_SkillInfo.GetSkillLineInfo(i)
        local info = P(raw)
        if type(info) ~= "table" then
            if API.Returned(raw) then unreadable = unreadable + 1 end
        elseif P(info.isHeader) ~= true then
            local id = num(info.skillID)
            local prof = id and PROFESSIONS[id]
            if not id then
                if API.Returned(info.skillID) then unreadable = unreadable + 1 end
            elseif prof then
                local name = P(info.name)
                local rank, max = num(info.rank), num(info.maxRank)
                local entry = {
                    name = type(name) == "string" and name ~= "" and name or prof.name,
                    icon = ICONS .. prof.icon,
                    rank = rank and max and rank or nil,   -- both readable, or neither
                    max = rank and max and max or nil,
                }
                local list = prof.kind == "crafting" and crafting
                    or prof.kind == "gathering" and gathering or secondary
                list[#list + 1] = entry
            end
        end
    end
    for _, e in ipairs(gathering) do crafting[#crafting + 1] = e end
    state.primary, state.secondary, state.unreadable = crafting, secondary, unreadable
end

-- A scan that throws leaves the cache stale (tried again on the next
-- repaint) and is recorded, rather than leaving an old cache marked fresh.
local function ensure()
    if not stale then return end
    local ok, err = pcall(scan)
    if ok then stale = false else API.Fail("professions:scan", err) end
end

-- TitanProfessions' colours: maxed green, >= 75% yellow, >= 50% orange,
-- >= 25% red, else grey. maxRank 0 is truthy: guarded explicitly.
local function colour(rank, max)
    if not (rank and max) or max <= 0 or rank <= 0 then return "808080" end
    if rank >= max then return "1eff00" end
    local f = rank / max
    if f >= 0.75 then return "ffff00" end
    if f >= 0.50 then return "ff8800" end
    if f >= 0.25 then return "ff2020" end
    return "808080"
end

local UNSURE = "|cff888888?|r"

local function skill(e, sep)
    if not e.rank then return UNSURE end
    return "|cff" .. colour(e.rank, e.max) .. e.rank .. sep .. e.max .. "|r"
end

local function iconText(e) return "|T" .. e.icon .. ":14:14:0:0|t" end

GlassPanel.RegisterBlock({
    id = "professions",
    label = "Professions",
    showLabel = false,   -- the icons say it (no caption on the TBC bar either)
    side = "right",
    order = 140,
    events = { "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" },
    onEvent = function() stale = true end,
    text = function()
        ensure()
        if state.hidden then return "|cff888888hidden|r" end
        local parts = {}
        for _, e in ipairs(state.primary) do parts[#parts + 1] = iconText(e) .. skill(e, "/") end
        if state.unreadable > 0 then parts[#parts + 1] = UNSURE end
        if #parts == 0 then return nil end   -- no primary profession learned
        return table.concat(parts, "  ")
    end,
    tooltip = function(_, tt)
        ensure()
        tt:AddLine("Professions")
        if state.hidden then
            tt:AddLine("Your skills can't be read right now.", 0.7, 0.7, 0.7, true)
            return
        end
        if #state.primary == 0 and #state.secondary == 0 and state.unreadable == 0 then
            tt:AddLine("No professions learned.", 0.7, 0.7, 0.7)
            return
        end
        for _, e in ipairs(state.primary) do
            tt:AddDoubleLine(iconText(e) .. " " .. e.name, skill(e, " / "), 1, 1, 1, 1, 1, 1)
        end
        if #state.secondary > 0 then
            tt:AddLine(" ")
            tt:AddLine("Secondary", 1, 0.82, 0)
            for _, e in ipairs(state.secondary) do
                tt:AddDoubleLine(iconText(e) .. " " .. e.name, skill(e, " / "), 1, 1, 1, 1, 1, 1)
            end
        end
        if state.unreadable > 0 then
            tt:AddLine(" ")
            tt:AddLine(state.unreadable .. " skill line(s) can't be read right now; a profession may be missing.",
                0.7, 0.7, 0.7, true)
        end
    end,
    -- No onClick yet: opening a profession window needs a secure spell
    -- button (blocks aren't secure); that comes in a later change.
})
