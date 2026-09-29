-- Setup.lua: opt-in Edit Mode layout for a full-width bar (#10).
--
-- By default the bar makes room for Blizzard's top frames (Room.lua). This
-- is for players who'd rather have the bar full width with those frames just
-- below it: it writes an Edit Mode layout, Blizzard's own mechanism, and
-- never moves a frame itself.
--
-- Measured on 70009 (owner, /gpanel covered): in the Modern and Classic
-- presets the damage meter (top left), the minimap and the buffs (top right)
-- reach into the bar's band; a customised layout may need nothing.
--
-- Built from the forever UI source (C:\Projects\wow-ui-source) and reviewed
-- by Codex before any code (issue #10):
-- - The source is the ACTIVE layout, copied whole (keeping interfaceStyle,
--   which Edit Mode's selection uses; dropping the preset-only layoutIndex).
--   Never while an override layout is active (GetActiveLayoutInfo returns
--   the override then).
-- - Moved: only systems anchored to UIParent top-to-top (point and
--   relativePoint both TOP*), by clamping the SAVED offsetY to
--   -(bar height + MARGIN), and isInDefaultPosition = false (a default-
--   position BuffFrame is re-anchored by StatusTrayManager, ignoring its
--   anchor). Clamping the saved value, not measuring live frames, makes a
--   second run a no-op. Anything else is listed as not moved (the adaptive
--   bar still makes room); a system snapped to another follows it.
-- - The layout: a new CHARACTER layout "GlassPanel", inserted where
--   Blizzard's MakeNewLayout puts one (after this character's last Character
--   layout, else after the last Account layout, else after the presets),
--   saved with C_EditMode.SaveLayouts (the whole merged list, the active
--   index as it was) then C_EditMode.OnLayoutAdded(index, true, false):
--   Blizzard's own order. Not an Account layout: measured on 70009 (owner,
--   two characters), a new Account layout goes before every character's own
--   layouts, and characters remember their active layout BY INDEX, so
--   another character on a Character layout found itself on GlassPanel.
--   OnLayoutAdded doesn't repair other characters. A Character layout is in
--   this character's list only, and last: nobody else's index moves.
--   An existing "GlassPanel" is never written to: saving from outside Edit
--   Mode doesn't refresh Blizzard's in-memory copy (EditModeManagerFrame.
--   layoutInfo), whose next save would put the old offsets back, and
--   re-activating the active layout may not re-apply it. If GlassPanel is
--   active with a system back in the bar's band, the player moves it in
--   Edit Mode (or deletes GlassPanel and runs setup again). Nothing to move:
--   nothing saved.
-- - Only out of combat, with Edit Mode closed and its layouts loaded, and
--   the plan is rebuilt at Apply: a changed plan is shown again, not applied.
-- - pcall is no transaction: "saved" and "activated" are reported apart, and
--   the state is read again after.
-- - "Switch back" returns this character to the layout it came from (a
--   preset by its enum, a saved one by name and type). The record is written
--   only after a new GlassPanel layout is saved, replacing any older one
--   (GlassPanel didn't exist, so an older record is stale), and kept after
--   switching back, so selecting GlassPanel again still has a way back. It
--   doesn't undo edits.
-- - A reload is recommended afterwards (reference addons reload to clear
--   Edit Mode taint). Measured on 70009 (owner): the Modern preset result,
--   switching back and two characters, with no taint or blocked-action
--   reports.

GlassPanel = GlassPanel or {}
local API, Glass, Bar = GlassPanel.API, GlassPanel.Glass, GlassPanel.Bar
local P = API.Plain
local Setup = {}
GlassPanel.Setup = Setup

Setup.NAME = "GlassPanel"
Setup.MARGIN = 2   -- UI units below the bar

-- The systems that can reach into the bar's band, and their names here.
local function watched()
    local S = rawget(_G, "Enum") and Enum.EditModeSystem
    local A = rawget(_G, "Enum") and Enum.EditModeAuraFrameSystemIndices
    if type(S) ~= "table" or type(A) ~= "table" then return nil end
    return {
        { system = S.Minimap, label = "Minimap" },
        { system = S.AuraFrame, index = A.BuffFrame, label = "Buffs" },
        { system = S.AuraFrame, index = A.DebuffFrame, label = "Debuffs" },
        { system = S.DamageMeter, label = "Damage meter" },
    }
end

local function layoutTypes()
    local T = rawget(_G, "Enum") and Enum.EditModeLayoutType
    return type(T) == "table" and T or nil
end

local function maxPerType()
    local C = rawget(_G, "Constants") and Constants.EditModeConsts
    local n = type(C) == "table" and P(C.EditModeMaxLayoutsPerType)
    return type(n) == "number" and n or 5
end

-- A deep copy (the tables we get are Blizzard's; we never edit them).
local function copy(v) return CopyTable(v) end

-- Why setup can't run right now, or nil.
function Setup.Blocked()
    if P(InCombatLockdown()) ~= false then return "not in combat" end
    local em = rawget(_G, "EditModeManagerFrame")
    if type(em) ~= "table" then return "Edit Mode isn't available" end
    if P(em:IsShown()) == true then return "close Edit Mode first" end
    if em.accountSettings == nil then return "Edit Mode hasn't loaded its layouts yet" end
    if em.overrideLayoutInfo ~= nil then return "an override layout is active" end
    local em2 = rawget(_G, "C_EditMode")
    local pm = rawget(_G, "EditModePresetLayoutManager")
    if type(em2) ~= "table" or not (em2.GetLayouts and em2.SaveLayouts and em2.SetActiveLayout and em2.OnLayoutAdded)
        or type(pm) ~= "table" or not pm.GetCopyOfPresetLayouts or not watched() or not layoutTypes() then
        return "this client's Edit Mode isn't the one GlassPanel knows"
    end
    return nil
end

-- The presets and saved layouts as Blizzard indexes them (presets first).
local function readLayouts()
    local saved = C_EditMode.GetLayouts()
    local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
    if type(saved) ~= "table" or type(saved.layouts) ~= "table" or type(presets) ~= "table" then return nil end
    local merged = {}
    for _, l in ipairs(presets) do merged[#merged + 1] = copy(l) end
    for _, l in ipairs(saved.layouts) do merged[#merged + 1] = copy(l) end
    local active = P(saved.activeLayout)
    if type(active) ~= "number" or not merged[active] then return nil end
    return { merged = merged, presets = #presets, active = active }
end

local function findSystem(layout, system, index)
    for _, s in ipairs(layout.systems or {}) do
        if s.system == system and s.systemIndex == index then return s end
    end
end

local function isTop(p) return type(p) == "string" and p:sub(1, 3) == "TOP" end
local function topToTop(a)
    return type(a) == "table" and a.relativeTo == "UIParent" and isTop(a.point) and isTop(a.relativePoint)
        and type(a.offsetY) == "number"
end

-- What to move in `layout`, in place: { moves = {...}, skipped = {...} }.
-- Pure (no client calls but the Enum lookups), so it can be tested.
local function planMoves(layout)
    local limit = -(Bar.HEIGHT + Setup.MARGIN)
    local moves, skipped = {}, {}
    for _, w in ipairs(watched()) do
        local s = findSystem(layout, w.system, w.index)
        if s then
            local a, a2 = s.anchorInfo, s.anchorInfo2
            -- The highest of its anchors decides (two anchors move together).
            local top = type(a) == "table" and a.offsetY
            if a2 ~= nil and topToTop(a2) and type(top) == "number" then top = math.max(top, a2.offsetY) end
            if type(a) == "table" and a.relativeTo ~= "UIParent" then
                skipped[#skipped + 1] = { label = w.label, why = "follows " .. tostring(a.relativeTo) }
            elseif not topToTop(a) or (a2 ~= nil and not topToTop(a2)) then
                skipped[#skipped + 1] = { label = w.label, why = "not anchored to the top of the screen" }
            elseif top > limit then
                local delta = limit - top
                moves[#moves + 1] = { label = w.label, from = top, to = limit, system = s }
                a.offsetY = a.offsetY + delta
                if a2 then a2.offsetY = a2.offsetY + delta end
                s.isInDefaultPosition = false
            end
        else
            skipped[#skipped + 1] = { label = w.label,
                why = "not in this layout yet (Blizzard may add it later at its default place)" }
        end
    end
    return moves, skipped
end

-- Where a new Character layout goes (MakeNewLayout's rule): after the last
-- Character layout, else after the last Account layout, else right after
-- the presets.
local function insertIndex(L, T)
    local lastCharacter, lastAccount
    for i, l in ipairs(L.merged) do
        if l.layoutType == T.Character then lastCharacter = i end
        if l.layoutType == T.Account then lastAccount = i end
    end
    return (lastCharacter or lastAccount or L.presets) + 1
end

local function countType(L, t)
    local n = 0
    for i = L.presets + 1, #L.merged do
        if L.merged[i].layoutType == t then n = n + 1 end
    end
    return n
end

-- The plan: { mode = "new" | "none" | "refuse", why, moves,
-- skipped, source (name), index (where it goes / is), layouts (to save) }.
function Setup.Plan()
    local blocked = Setup.Blocked()
    if blocked then return { mode = "refuse", why = blocked, moves = {}, skipped = {} } end
    local L = readLayouts()
    if not L then return { mode = "refuse", why = "couldn't read the layouts", moves = {}, skipped = {} } end
    local T = layoutTypes()
    local source = L.merged[L.active]
    local plan = { source = source.layoutName, sourceType = source.layoutType, L = L }
    local target
    if source.layoutName == Setup.NAME and source.layoutType ~= T.Preset then
        -- Never written to (see the header): check it, say what to do.
        local check = copy(source)
        local moves = planMoves(check)
        if #moves > 0 then
            plan.mode = "refuse"
            plan.why = "your GlassPanel layout has something back under the bar: move it down in Edit Mode, or"
                .. " delete GlassPanel and run this again"
        else
            plan.mode = "none"
        end
        plan.moves, plan.skipped = {}, {}
        return plan
    else
        for i = L.presets + 1, #L.merged do
            if L.merged[i].layoutName == Setup.NAME then
                plan.mode = "refuse"
                plan.why = "a layout named " .. Setup.NAME .. " already exists: select it in Edit Mode (then run"
                    .. " this again), or rename it"
            end
        end
        if plan.mode ~= "refuse" and countType(L, T.Character) >= maxPerType() then
            plan.mode = "refuse"
            plan.why = "this character already has " .. maxPerType() .. " character layouts (delete one in Edit Mode)"
        end
        if plan.mode ~= "refuse" then
            plan.mode = "new"
            target = copy(source)
            target.layoutIndex = nil
            target.layoutName, target.layoutType = Setup.NAME, T.Character
            plan.index = insertIndex(L, T)
        end
    end
    plan.moves, plan.skipped = {}, {}
    if target then
        plan.moves, plan.skipped = planMoves(target)
        if #plan.moves == 0 then plan.mode = "none" end
        plan.target = target
    end
    return plan
end

-- The same plan twice? (Apply rebuilds it and refuses a changed one.)
local function samePlan(a, b)
    if a.mode ~= b.mode or a.source ~= b.source or a.index ~= b.index or #a.moves ~= #b.moves then return false end
    for i, m in ipairs(a.moves) do
        if m.label ~= b.moves[i].label or m.from ~= b.moves[i].from then return false end
    end
    return true
end

-- This character's key for the switch-back record.
local function charKey()
    local g = P(UnitGUID("player"))
    return type(g) == "string" and g or nil
end

-- Record where this character came from (`src`, the layout it was on),
-- replacing any older record: a new GlassPanel means GlassPanel didn't
-- exist, so an older record is stale.
local function recordReturn(src)
    local key = charKey()
    if not key then return end
    if type(GlassPanelDB.editModeReturn) ~= "table" then GlassPanelDB.editModeReturn = {} end
    local T = layoutTypes()
    if src.layoutType == T.Preset then
        if src.layoutIndex ~= nil then GlassPanelDB.editModeReturn[key] = { preset = src.layoutIndex } end
    else
        GlassPanelDB.editModeReturn[key] = { name = src.layoutName, layoutType = src.layoutType }
    end
end

-- Apply `plan` (from Plan, shown to the player). Returns ok, lines.
function Setup.Apply(shown)
    local plan = Setup.Plan()
    if plan.mode == "refuse" then return false, { plan.why } end
    if not samePlan(shown, plan) then return false, { "Something changed since the preview: review it again." } end
    if plan.mode == "none" then return true, { "Nothing to move: this layout already leaves the bar's strip free." } end
    local L, out = plan.L, {}
    local layouts = L.merged
    local source = copy(L.merged[L.active])   -- before the insert shifts indices
    table.insert(layouts, plan.index, plan.target)
    -- Blizzard's order: save the whole list with the active index as it
    -- was, then announce the new layout (which activates it).
    local okSave, err = pcall(C_EditMode.SaveLayouts, { layouts = layouts, activeLayout = L.active })
    if not okSave then
        API.Fail("setup:save", err)
        return false, { "Saving the layout failed (see /gpanel failures). Nothing was switched." }
    end
    out[#out + 1] = "Saved the " .. Setup.NAME .. " layout."
    recordReturn(source)
    local okAct, err2 = pcall(C_EditMode.OnLayoutAdded, plan.index, true, false)
    if not okAct then
        API.Fail("setup:activate", err2)
        out[#out + 1] = "Saved, but switching to it failed (see /gpanel failures): pick it in Edit Mode."
        return false, out
    end
    -- Read back what the client now has.
    local after = readLayouts()
    local now = after and after.merged[after.active]
    if now and now.layoutName == Setup.NAME then
        out[#out + 1] = "It's your active layout now. A /reload is recommended."
    else
        out[#out + 1] = "Saved, but it isn't the active layout: pick " .. Setup.NAME .. " in Edit Mode."
        return false, out
    end
    return true, out
end

-- Back to the layout this character came from. Returns ok, message.
function Setup.SwitchBack()
    local blocked = Setup.Blocked()
    if blocked then return false, "Can't switch now: " .. blocked .. "." end
    local key = charKey()
    local all = GlassPanelDB.editModeReturn
    local rec = key and type(all) == "table" and all[key]
    if type(rec) ~= "table" or (rec.preset == nil and rec.name == nil) then
        return false, "No earlier layout recorded for this character."
    end
    local L = readLayouts()
    if not L then return false, "Couldn't read the layouts." end
    local found, n = nil, 0
    for i, l in ipairs(L.merged) do
        if rec.preset ~= nil and i <= L.presets and l.layoutIndex == rec.preset then found, n = i, n + 1
        elseif rec.name ~= nil and i > L.presets and l.layoutName == rec.name and l.layoutType == rec.layoutType then
            found, n = i, n + 1
        end
    end
    if n ~= 1 then
        return false, n == 0 and "The earlier layout is gone (renamed or deleted): pick one in Edit Mode."
            or "More than one layout matches the earlier one: pick it in Edit Mode."
    end
    local ok, err = pcall(C_EditMode.SetActiveLayout, found)
    if not ok then
        API.Fail("setup:switchback", err)
        return false, "Switching failed (see /gpanel failures)."
    end
    -- The record stays: selecting GlassPanel again later still has a way back.
    return true, "Switched back to " .. tostring(L.merged[found].layoutName) .. ". A /reload is recommended."
end

-- The plan as lines for the window.
function Setup.Describe(plan)
    local lines = {}
    if plan.mode == "refuse" then
        lines[1] = "|cffff6060Can't set up now:|r " .. plan.why .. "."
        return lines
    end
    if plan.mode == "new" then
        lines[#lines + 1] = "Copies your layout |cffffd100" .. tostring(plan.source) .. "|r into a new layout for this character, |cffffd100"
            .. Setup.NAME .. "|r and switches to it."
    else
        lines[#lines + 1] = "Nothing to move: this layout already leaves the bar's strip free."
    end
    for _, m in ipairs(plan.moves) do
        lines[#lines + 1] = string.format("  %s: moved down to %d below the top (was %d)", m.label, -m.to, -m.from)
    end
    for _, s in ipairs(plan.skipped) do
        lines[#lines + 1] = "  " .. s.label .. ": not moved, " .. s.why .. " (the bar still makes room for it)"
    end
    if plan.mode ~= "none" then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "The layout stays after uninstalling GlassPanel: switch back in Edit Mode, or with"
            .. " \"Switch back\" here. A /reload afterwards is recommended."
    end
    return lines
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local win, shownPlan

local function build()
    win = API.Window("GlassPanelSetupWindow", 520, 260)
    win.title:SetText("Make room in Edit Mode")
    win.body = Glass.Font(win, 12, "LEFT")
    win.body:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -10)
    win.body:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.body:SetJustifyV("TOP")

    win.close = API.Button(win, "Close", 90, function() win:Hide() end)
    win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    win.apply = API.Button(win, "Apply", 90, function()
        local ok, lines = Setup.Apply(shownPlan)
        if ok then
            win.body:SetText(table.concat(lines, "\n"))
            win.apply:Hide()
            win.reload:Show()
        else
            -- Refused or changed: show why, then the plan as it is now.
            Setup.Open()
            win.body:SetText(table.concat(lines, "\n") .. "\n\n" .. win.body:GetText())
        end
    end)
    win.apply:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
    win.reload = API.Button(win, "Reload", 90, function() ReloadUI() end)
    win.reload:SetPoint("RIGHT", win.close, "LEFT", -8, 0)
end

-- Show the plan, with Apply when there's something to do.
function Setup.Open()
    if not win then build() end
    shownPlan = Setup.Plan()
    win.body:SetText(table.concat(Setup.Describe(shownPlan), "\n"))
    win.reload:Hide()
    win.apply:SetShown(shownPlan.mode == "new")
    win:Show()
end

Setup._test = { planMoves = planMoves, insertIndex = insertIndex, window = function() return win end }
