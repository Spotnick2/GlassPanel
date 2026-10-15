-- Plugins/RestedXP/RestedXP.lua: the RestedXP guide's waypoint arrow on the
-- bar (#80): the bar's arrow is THE arrow. Double-click it to show or hide
-- RestedXP's own arrow on the screen as well; the tooltip lists its active steps.
--
-- A bridge, like [AltStable]: "## Dependencies: GlassPanel, RXPGuides", so the
-- client never loads it without RestedXP Guides. RXP is RestedXP's whole addon
-- table ("debug purposes" in its source), not a promised API: every read is
-- guarded, a missing table means no block, and a throw blanks the block and is
-- recorded, never raised.
--
-- Measured on 1.60.1.70374 (docs/FOREVER-PROBE.md, RXPProbe):
-- - Our bearing is RestedXP's own (map.lua:123-139): HereBeDragons-2.0's
--   world position and vector, minus GetPlayerFacing(), all plain outdoors.
--   We compute it ourselves: with its arrow switched off, RestedXP's own
--   orientation and distance go stale, while its target,
--   RXP.arrowFrame.element, keeps updating (see target() for when it counts).
-- - Step titles were nil: the label falls back to "Step N", as its arrow does.
-- - GetGuideProgress's second value isn't a total: "step N of #steps" instead.
--
-- On the bar: RestedXP's arrow, turning toward the waypoint, then the step and
-- the distance. With no live target (no waypoint, or the guide switched off)
-- its logo alone. The arrow turns every frame,
-- but only while the block is on screen (its frame is a child of the block).

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass

local ID = "restedxp"
local TEXTURES = "Interface\\AddOns\\RXPGuides\\Textures\\"   -- its default theme's files
local ARROW_ART, LOGO_ART = TEXTURES .. "rxp_navigation_arrow-1", TEXTURES .. "rxp_logo-64"
local SLOT, PAD, GAP, FONT = 16, 4, 4, 12
local WIDTH_STEP = 12          -- width in steps of this, so a walk doesn't shuffle the lane
local TURN_EVERY, TEXT_EVERY = 0.03, 0.25
local MAX_TITLE = 28
local GREY = "|cffaaaaaa"

local function rxp()
    local R = rawget(_G, "RXP")
    return type(R) == "table" and R or nil
end

if not rxp() then
    -- The dependency is met, so RestedXP loaded, but not as we know it.
    API.Fail(ID .. ":missing", "RestedXP is loaded but its RXP table isn't there: no block")
    return
end

local function lib(name)
    local ls = rawget(_G, "LibStub")
    if not ls then return nil end
    local ok, l = pcall(ls, name, true)
    return ok and l or nil
end

-- A plain, finite number, or nil.
local function num(v)
    v = API.Plain(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function profile()
    local R = rxp()
    local s = R and R.settings
    return type(s) == "table" and type(s.profile) == "table" and s.profile or nil
end

--------------------------------------------------------------------------------
-- The target and our bearing to it
--------------------------------------------------------------------------------

-- Whether RestedXP would still lead to this waypoint: the test it picks a
-- target with (map.lua:1043-1045, 676-679). Its step active, the waypoint not
-- reached (skip, set on arrival: map.lua:1323-1329), its parent neither
-- completed nor skipped.
local function live(e)
    if type(e.step) ~= "table" or not e.step.active or e.skip then return false end
    local parent = e.parent
    return not (type(parent) == "table" and (parent.completed or parent.skip))
end

-- The waypoint the arrow leads to, or nil when there's none to trust. Its
-- element isn't cleared when the arrow runs out of targets (map.lua:1142-1145),
-- so it must still be live. Never while the guide is hidden (showEnabled):
-- with its arrow drawing switched off, the toggle leaves the arrow frame alone
-- (IsFeatureEnabled, map.lua:61-64). And the frame counts only when that
-- drawing is on: switched off, RestedXP keeps it hidden on every retarget
-- (map.lua:1047-1051) while the target stays live (Codex on #84).
local function target()
    local R = rxp()
    local af = R and R.arrowFrame
    if type(af) ~= "table" then return nil end
    local e = af.element
    if type(e) ~= "table" or not live(e) then return nil end
    local p = profile()
    if p and p.showEnabled == false then return nil end
    if p and p.disableArrow then return e, af end
    local ok, shown = pcall(af.IsShown, af)
    if not (ok and shown == true) then return nil end
    return e, af
end

-- orientation (radians from facing), distance (yards); nil, why otherwise.
local function bearing(e, af)
    if af.wrongContinent then return nil, "far" end
    local HBD = lib("HereBeDragons-2.0")
    if not HBD then return nil, "?" end
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    x, y = ok and num(x), ok and num(y)
    local tx, ty = num(e.wx), num(e.wy)
    if not (x and y and tx and ty) or API.IsSecret(inst) then return nil, "?" end
    -- Its HereBeDragons' GetWorldVector ignores the instance and subtracts
    -- the coordinates: across two maps (a dungeon, another continent) it
    -- answers with a meaningless vector (Codex on #82). RestedXP guards that
    -- with wrongContinent; we compare the instances.
    if num(inst) == nil or num(inst) ~= num(e.instance) then return nil, "far" end
    local okV, angle, dist = pcall(HBD.GetWorldVector, HBD, inst, x, y, tx, ty)
    local okF, facing = pcall(GetPlayerFacing)
    angle, dist, facing = okV and num(angle), okV and num(dist), okF and num(facing)
    if not (angle and dist and facing) then return nil, "?" end
    return angle - facing, dist
end

-- The step's words: its arrow text, its title, else "Step N"; RestedXP's
-- colour tokens (RXP_FRIENDLY_ and the like) dropped; kept short.
local function stepName(step)
    local t = API.Plain(step.arrowtext) or API.Plain(step.title)
    if type(t) ~= "string" or t == "" then
        local i = num(step.index)
        return i and ("Step " .. i) or "Step"
    end
    t = t:gsub("RXP_[A-Z]+_", ""):gsub("\n", " ")
    if #t > MAX_TITLE then t = t:sub(1, MAX_TITLE - 1) .. "..." end
    return t
end

--------------------------------------------------------------------------------
-- The block's own art: the arrow (or the logo) and the words after it
--------------------------------------------------------------------------------

local ui        -- { frame, art, words } on the block's widget
local shownText = ""
local failed = false

-- What the block shows now: the art ("arrow" | "logo"), the arrow's turn, and
-- the words. A throw (RestedXP changed under us) is recorded once and shows
-- the logo alone.
local function read()
    local ok, art, turn, words = pcall(function()
        local e, af = target()
        if not e then return "logo", nil, "" end
        local o, d = bearing(e, af)
        local name = stepName(e.step)
        if not o then
            return "logo", nil, name .. " " .. GREY .. (d == "far" and "~" or "?") .. "|r"
        end
        return "arrow", o, name .. " " .. GREY .. BreakUpLargeNumbers(math.floor(d)) .. " yd|r"
    end)
    if ok then return art, turn, words end
    if not failed then
        failed = true
        API.Fail(ID .. ":read", art)
    end
    return "logo", nil, ""
end

local function show(art, turn)
    if art == "arrow" then
        ui.art:SetTexture(ARROW_ART)
        ui.art:SetRotation(turn)
    else
        ui.art:SetTexture(LOGO_ART)
        ui.art:SetRotation(0)
    end
end

-- Set the words; true when the block's width moved (a relayout is due).
local lastWidth
local function setWords(words)
    if words ~= shownText then
        shownText = words
        ui.words:SetText(words)
    end
    local w = PAD + SLOT + PAD
    if words ~= "" then
        w = w + GAP + math.ceil(ui.words:GetStringWidth())
        w = math.ceil(w / WIDTH_STEP) * WIDTH_STEP
    end
    local moved = w ~= lastWidth
    lastWidth = w
    return moved, w
end

local function build(block)
    local w = block.widget
    local f = CreateFrame("Frame", nil, w)
    f:SetAllPoints(w)
    f:SetFrameLevel(w:GetFrameLevel() + 1)
    local art = f:CreateTexture(nil, "ARTWORK")
    art:SetSize(SLOT, SLOT)
    art:SetPoint("LEFT", f, "LEFT", PAD, 0)
    art:SetTexture(LOGO_ART)
    local words = Glass.Font(f, FONT, "LEFT")
    words:SetPoint("LEFT", art, "RIGHT", GAP, 0)
    ui = { frame = f, art = art, words = words }
    -- The arrow turns every frame while the block is on screen (a hidden
    -- parent stops OnUpdate); the words move less often.
    local turnAcc, textAcc = 0, 0
    f:SetScript("OnUpdate", function(_, elapsed)
        turnAcc, textAcc = turnAcc + elapsed, textAcc + elapsed
        if turnAcc < TURN_EVERY then return end
        turnAcc = 0
        local art2, turn, words2 = read()
        show(art2, turn)
        if textAcc >= TEXT_EVERY then
            textAcc = 0
            if setWords(words2) then GlassPanel.Refresh(ID) end
        end
    end)
end

--------------------------------------------------------------------------------
-- RestedXP's own arrow on the screen: shown or hidden (the double-click)
--------------------------------------------------------------------------------

-- The bar's arrow is THE arrow; RestedXP's own on-screen one is shown only
-- when asked. The switch is RestedXP's own option "Hide waypoint arrow"
-- (profile.disableArrow, saved by RestedXP): its target keeps updating while
-- the drawing is off (measured, 70374). Never the guide window or the whole
-- guide (showEnabled / hideGuideWindow): with either off at login RestedXP sets
-- isHidden and its step handlers stop (GuideWindow.lua:250), so the guide
-- would stop advancing and our arrow would go stale.
local function guideShown()
    local p = profile()
    return p == nil or p.showEnabled ~= false
end

local function theirArrowShown()
    local p = profile()
    return p ~= nil and not p.disableArrow
end

local saidToggle = false
local function toggleTheirArrow()
    local R, p = rxp(), profile()
    local ok, err = p ~= nil, "no RestedXP settings"
    if p then
        p.disableArrow = not p.disableArrow
        -- What its own options and ResetArrowPosition do next: UpdateMap(true)
        -- reruns its target pick, which shows or hides the arrow frame
        -- (map.lua:1047-1051). Without a guide it returns early: the frame
        -- is set directly then.
        if R and type(R.UpdateMap) == "function" then ok, err = pcall(R.UpdateMap, true) end
        local af = R and R.arrowFrame
        if ok and type(af) == "table" and p.disableArrow then pcall(af.Hide, af) end
    end
    if not ok then
        API.Fail(ID .. ":toggle", err)
        if not saidToggle then
            saidToggle = true
            API.Print("RestedXP: its arrow couldn't be shown or hidden (see /gpanel failures).")
        end
    end
    GlassPanel.Refresh(ID)
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local MAX_STEPS, MAX_LINES, MAX_CHARS = 4, 4, 140

-- A step line as its guide window shows it, RestedXP's colour tokens
-- (RXP_FRIENDLY_ and the like) turned into its colours. NPCs keep the names
-- the guide wrote ("npc:Name:123" -> "Name", "Name::123" -> "Name"), which is
-- RestedXP's own fallback. Never its ReplaceNpcIds: on a cache miss its
-- GetNpcName borrows the global GameTooltip (SetOwner WorldFrame,
-- ClearLines, Hide; functions.lua:891-939), the very tooltip this builds
-- (Codex on #90).
local function stepLine(R, text)
    if type(text) ~= "string" or API.IsSecret(text) or text == "" or text == " " then return nil end
    text = text:gsub("npc:(.-):%d+", "%1"):gsub("::%d+", "")
    local colours = type(R.guideTextColors) == "table" and R.guideTextColors or {}
    text = text:gsub("RXP_[A-Z]+_", function(token)
        local c = colours[token]
        return type(c) == "string" and c or ""
    end)
    text = text:gsub("\n", " ")
    if #text > MAX_CHARS then text = text:sub(1, MAX_CHARS - 3) .. "..." end
    return text
end

-- RestedXP's active steps (RXPFrame.activeSteps) as its window shows them:
-- only the shown ones (its v2:IsActiveStepShown, GuideWindow.lua:3099: active,
-- not hidewindow, not hidetip; internal looping steps are hidden), each with
-- its lines. The limit counts shown steps only (Codex on #90).
local function shownSteps(steps)
    local out = {}
    for _, step in ipairs(steps) do
        if type(step) == "table" and step.active and not step.hidewindow and not step.hidetip then
            out[#out + 1] = step
        end
    end
    return out
end

local function activeSteps(tt)
    local R = rxp()
    local frame = R and R.RXPFrame
    local all = type(frame) == "table" and frame.activeSteps
    if type(all) ~= "table" then return end
    local steps = shownSteps(all)
    if #steps == 0 then return end
    tt:AddLine(" ")
    tt:AddLine("Active steps", 1, 0.82, 0)
    for n, step in ipairs(steps) do
        if n > MAX_STEPS then
            tt:AddLine("  ...and " .. (#steps - MAX_STEPS) .. " more", 0.7, 0.7, 0.7)
            break
        end
        do
            local i = num(step.index)
            tt:AddLine((i and ("Step " .. i) or "Step"), 1, 1, 1)
            local lines = 0
            for _, el in ipairs(type(step.elements) == "table" and step.elements or {}) do
                local t = type(el) == "table" and stepLine(R, el.text)
                if t then
                    lines = lines + 1
                    if lines > MAX_LINES then break end
                    tt:AddLine("  " .. t, 0.85, 0.85, 0.85, true)
                end
            end
        end
    end
end

local function tooltip(_, tt)
    local R = rxp()
    local g = R and R.currentGuide
    local name = type(g) == "table" and API.Plain(g.name)
    tt:AddLine("RestedXP" .. (type(name) == "string" and ("  |cffffffff" .. name .. "|r") or ""))
    local e, af = target()
    if e then
        local steps = type(g) == "table" and type(g.steps) == "table" and #g.steps or nil
        local i = num(e.step.index)
        tt:AddDoubleLine("Step", (i and tostring(i) or "?") .. (steps and steps > 0 and (" of " .. steps) or ""),
            1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine("Waypoint", stepName(e.step), 1, 0.82, 0, 1, 1, 1)
        local o, d = bearing(e, af)
        local where = o and (BreakUpLargeNumbers(math.floor(d)) .. " yd")
            or (d == "far" and "on another continent" or "can't be read here")
        tt:AddDoubleLine("Distance", where, 1, 0.82, 0, 1, 1, 1)
    else
        tt:AddLine(guideShown() and "No waypoint right now." or "The guide is hidden.", 0.7, 0.7, 0.7, true)
    end
    local ok, err = pcall(activeSteps, tt)
    if not ok then API.Fail(ID .. ":steps", err) end
    tt:AddLine(" ")
    tt:AddLine(theirArrowShown() and "Double-click: hide RestedXP's own arrow"
        or "Double-click: show RestedXP's own arrow on the screen", 0.3, 1, 0.3)
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = ID,
    label = "RestedXP",
    side = "center",
    order = 50,
    -- Graphical: sized to the arrow and its words, measured by us (the logo
    -- alone when there's nothing to point at).
    width = function()
        if not ui then return nil end
        local art, turn, words = read()
        show(art, turn)
        local _, w = setWords(words)
        return w
    end,
    text = function() return "" end,
    build = build,
    tooltip = tooltip,
    onDoubleClick = function(_, button)
        if button == "LeftButton" then toggleTheirArrow() end
    end,
})

-- Its steps and guides (global AceEvent messages): repaint, so a new step's
-- words show at once. A new waypoint without a step change sends nothing; the
-- arrow's own update catches it.
if block then
    local ae = lib("AceEvent-3.0")
    local listener = {}
    if ae and pcall(ae.Embed, ae, listener) then
        for _, m in ipairs({ "RXP_STEP_ACTIVATED", "RXP_GUIDE_LOADED" }) do
            local ok, err = pcall(listener.RegisterMessage, listener, m, function() GlassPanel.Refresh(ID) end)
            if not ok then API.Fail(ID .. ":messages", err) end
        end
    end
    block._test = { read = read, target = target, toggleTheirArrow = toggleTheirArrow, ui = function() return ui end }
end
