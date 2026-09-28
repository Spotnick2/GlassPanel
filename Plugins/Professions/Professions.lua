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
-- - Left-click opens a small palette (out of combat only) with one button
--   per profession that has a window; clicking one opens it. Opening means
--   casting the profession's spell, which needs a SecureActionButtonTemplate
--   button. Those buttons live on their OWN frame parented to UIParent and
--   placed with UIParent coordinates, never parented or anchored to the bar:
--   a secure descendant would make the bar protected and freeze its layout in
--   combat (Codex review on #15). The palette may stay open into combat; it
--   can't be moved or hidden then, and closes on its next use or click.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

-- skillID -> kind and icon. Vanilla ids, to confirm in game. The English
-- name is only a fallback for a client name that can't be read.
local ICONS = "Interface\\Icons\\"
-- opens: what opens its window: "self" = the spell named like the skill,
-- a number = that spell id (Mining opens Smelting, 2656); none: no window.
local PROFESSIONS = {
    [171] = { kind = "crafting", icon = "Trade_Alchemy", name = "Alchemy", opens = "self" },
    [164] = { kind = "crafting", icon = "Trade_BlackSmithing", name = "Blacksmithing", opens = "self" },
    [333] = { kind = "crafting", icon = "Trade_Engraving", name = "Enchanting", opens = "self" },
    [202] = { kind = "crafting", icon = "Trade_Engineering", name = "Engineering", opens = "self" },
    [165] = { kind = "crafting", icon = "Trade_LeatherWorking", name = "Leatherworking", opens = "self" },
    [197] = { kind = "crafting", icon = "Trade_Tailoring", name = "Tailoring", opens = "self" },
    [182] = { kind = "gathering", icon = "Trade_Herbalism", name = "Herbalism" },
    [186] = { kind = "gathering", icon = "Trade_Mining", name = "Mining", opens = 2656 },
    [393] = { kind = "gathering", icon = "INV_Misc_Pelt_Wolf_01", name = "Skinning" },
    [185] = { kind = "secondary", icon = "INV_Misc_Food_15", name = "Cooking", opens = "self" },
    [129] = { kind = "secondary", icon = "Spell_Holy_SealOfSacrifice", name = "First Aid", opens = "self" },
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
                    id = id,
                    name = type(name) == "string" and name ~= "" and name or prof.name,
                    -- Only the client's own name is a spell name on this client's
                    -- language: the English fallback isn't castable everywhere.
                    clientName = type(name) == "string" and name ~= "",
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

--------------------------------------------------------------------------------
-- The palette
--------------------------------------------------------------------------------

local SIZE, GAP, PAD = 30, 4, 6
local FALLBACK_TOP = 28   -- px below the screen top when the block has no position yet
local palette
local closeAfterCombat   -- it was open when combat started: close it when it ends

-- The spell that opens entry e's window, or nil.
local function spellFor(e)
    local opens = PROFESSIONS[e.id].opens
    if opens == "self" then return e.clientName and e.name or nil end
    if type(opens) == "number" and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, opens)
        name = ok and P(name) or nil
        return type(name) == "string" and name or nil
    end
    return nil
end

local function buildPalette()
    local f = CreateFrame("Frame", "GlassPanelProfessionsPalette", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:Hide()
    GlassPanel.Glass.Apply(f, "small")
    f.buttons = {}
    return f
end

local function paletteButton(i)
    local b = palette.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, palette, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    -- Both edges: the template acts on the one ActionButtonUseKeyDown picks
    -- (measured, porting guide). Never typerelease.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.label or "")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Done: close it on the UP edge, whatever ActionButtonUseKeyDown says: the
    -- spell is cast on the down edge (key-down on) or the up edge (off), and
    -- hiding on the down edge would eat the up click that casts. Only out of
    -- combat (a protected frame can't hide in combat).
    b:SetScript("PostClick", function(_, _, down)
        if not down and not InCombatLockdown() then palette:Hide() end
    end)
    palette.buttons[i] = b
    return b
end

-- Open (or close) the palette under the block. Out of combat only: secure
-- attributes, size and position can't change in combat.
local function togglePalette(block)
    if InCombatLockdown() then
        if palette and palette:IsShown() then
            closeAfterCombat = true
            API.Print("Professions: the palette closes when combat ends.")
        else
            API.Print("Professions: the palette can't open in combat.")
        end
        return
    end
    if palette and palette:IsShown() then palette:Hide() return end
    ensure()
    local list = {}
    for _, group in ipairs({ state.primary, state.secondary }) do
        for _, e in ipairs(group) do
            local spell = spellFor(e)
            if spell then list[#list + 1] = { e = e, spell = spell } end
        end
    end
    if #list == 0 then
        if state.hidden or state.unreadable > 0 then
            API.Print("Professions: your skills can't be read right now.")
        else
            API.Print("Professions: none of your professions has a window to open.")
        end
        return
    end
    palette = palette or buildPalette()
    for i, item in ipairs(list) do
        local b = paletteButton(i)
        b:SetAttribute("spell", item.spell)
        b.icon:SetTexture(item.e.icon)
        b.label = item.e.name
        b:ClearAllPoints()
        b:SetPoint("LEFT", palette, "LEFT", PAD + (i - 1) * (SIZE + GAP), 0)
        b:Show()
    end
    for i = #list + 1, #palette.buttons do palette.buttons[i]:Hide() end
    palette:SetSize(PAD * 2 + #list * SIZE + (#list - 1) * GAP, SIZE + PAD * 2)
    -- Under the block, in UIParent coordinates: a position, not an anchor
    -- (anchoring it to the block would tie the bar to a protected frame).
    local w = block.widget
    local l, bottom, width = w:GetRect()
    l, bottom, width = P(l), P(bottom), P(width)
    local ws, us = P(w:GetEffectiveScale()), P(UIParent:GetEffectiveScale())
    local s = ws and us and us > 0 and ws / us
    palette:ClearAllPoints()
    if l and bottom and width and s then
        palette:SetPoint("TOP", UIParent, "BOTTOMLEFT", (l + width / 2) * s, bottom * s - 4)
    else
        -- Not laid out yet: under the middle of the bar.
        palette:SetPoint("TOP", UIParent, "TOP", 0, -FALLBACK_TOP)
    end
    palette:Show()
end

local block = GlassPanel.RegisterBlock({
    id = "professions",
    label = "Professions",
    showLabel = false,   -- the icons say it (no caption on the TBC bar either)
    side = "right",
    order = 150,
    events = { "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
               "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    onEvent = function(_, event)
        -- Open when combat starts: it can't be hidden until combat ends, so
        -- close it then, without waiting for another click (Codex review).
        if event == "PLAYER_REGEN_DISABLED" then
            if palette and palette:IsShown() then closeAfterCombat = true end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            if closeAfterCombat and palette then palette:Hide() end
            closeAfterCombat = nil
            return
        end
        stale = true
        -- A palette listing yesterday's professions is stale: close it (out of
        -- combat; it reopens with the new list).
        if event == "SKILL_LINES_CHANGED" and palette and palette:IsShown() and not InCombatLockdown() then
            palette:Hide()
        end
    end,
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
        tt:AddLine(" ")
        tt:AddLine("Left-click: open a profession (out of combat)", 0.3, 1, 0.3)
    end,
    onClick = function(block, button)
        if button == "LeftButton" then togglePalette(block) end
    end,
})

if block then block._test = { palette = function() return palette end } end
