-- Plugins/Combat/Combat.lua: a combat timer (#108). On the bar, crossed
-- swords and "Out of Combat", or the fight's time. Zoomed (left double-click,
-- as XP+): the bar says "In Combat" (the pill has the time), and a glass pill floats on the screen
-- while you are in combat, and only then.
--
-- The clock is our own GetTime() stamp at PLAYER_REGEN_DISABLED (plain, never
-- secret), as Glass Unit Frames' timer: the format matches it (00:07, then
-- 1:00:05 from an hour), and a /reload mid-fight counts from the reload.
-- The pill is a float: it registers with the core (API.RegisterFloat, so it
-- never overlaps XP+'s zoomed bar), is moved with shift-drag, and keeps its
-- spot in GlassPanelCombatDB. A preview (the plugin's option) shows it for a
-- while out of combat, to place it.
--
-- Glass Unit Frames has a timer of its own over the portrait. The plugin's
-- option "Use this timer instead of Glass Unit Frames'" turns that one off
-- through GlassUF.Settings.SetCombatTimer, from the player's click only, and
-- reads GlassUF.Timer.enabled again every time the options page opens: the
-- state is never copied here. The one automatic thing is a single printed
-- hint the first time both would show.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local WIDTH = 104                 -- the block docked: icon + "Out of Combat"
local PILL_W, PILL_H, PILL_FONT = 92, 26, 12   -- the text about XP+'s zoomed bar's
local SCALE_MIN, SCALE_MAX, SCALE_STEP, SCALE_DEFAULT = 0.5, 2, 0.05, 1.5   -- XP+'s zoomed bar is usually 1.5
local PREVIEW = 30                -- seconds the preview shows the pill
local SPOT_LIMIT = 4096

local function db()
    local d = rawget(_G, "GlassPanelCombatDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelCombatDB = d
    end
    return d
end
local function detached() return db().detached == true end

local inCombat, startedAt, lastFight = false, 0, nil
local onScreen = false
local pill, pillText, ticker, previewUntil
local moving, lastMoveStop = false, -1

local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then API.Fail("combat:pill", err) end
    end
end

-- Glass Unit Frames' own format: 00:07, 12:34, 1:00:05; seconds floored, never below 0.
local function format(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function elapsed() return inCombat and GetTime() - startedAt or 0 end

local function previewing() return previewUntil ~= nil and GetTime() < previewUntil end

--------------------------------------------------------------------------------
-- The pill
--------------------------------------------------------------------------------

local function finite(v)
    v = P(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function savedSpot()
    local s = db().spot
    if type(s) ~= "table" then return nil end
    local x, y = finite(s.x), finite(s.y)
    if not (x and y and math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT) then return nil end
    return x, y
end

-- The saved scale, or the default when unset or out of range.
local function pillScale()
    local s = finite(db().scale)
    if not s or s < SCALE_MIN or s > SCALE_MAX then return SCALE_DEFAULT end
    return s
end

local function placePill()
    local scale = pillScale()
    pill:SetScale(scale)
    pill:ClearAllPoints()
    local x, y = savedSpot()
    if x then
        pill:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
    else
        pill:SetPoint("TOP", UIParent, "TOP", 0, API.FloatDefaultY(pill) / scale)
    end
    API.UpdateTopEdge()
end

-- Where the pill was let go, saved when it reads plainly and is in bounds;
-- anchored on our point again either way (the last good spot when it isn't).
local function saveSpot()
    local fx, fy = pill:GetCenter()
    local ux, uy = UIParent:GetCenter()
    fx, fy, ux, uy = finite(fx), finite(fy), finite(ux), finite(uy)
    if fx and fy and ux and uy then
        local scale = pillScale()
        fx, fy = fx * scale, fy * scale
        local x, y = math.floor((fx - ux) * 2 + 0.5) / 2, math.floor((fy - uy) * 2 + 0.5) / 2
        if math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT then db().spot = { x = x, y = y } end
    end
    placePill()
end

local function resetSpot()
    db().spot = nil
    if pill then placePill() end
    API.PlaceFloats()
end

-- The slider: clamped, in steps; live around the spot.
local function setScale(v)
    v = finite(v)
    if not v then return end
    v = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(v / SCALE_STEP + 0.5) * SCALE_STEP))
    db().scale = v
    if pill then placePill() end
    API.PlaceFloats()
end

local function paintPill()
    if pill and pill:IsShown() then pillText:SetText(format(elapsed())) end
end

local setDetached   -- below: the menu docks through it

-- Role's pattern: a menu that throws changes nothing, it's reported; a client
-- with no MenuUtil docks on the right-click instead.
local function openMenu(owner)
    local menu = rawget(_G, "MenuUtil")
    if not (menu and menu.CreateContextMenu) then
        setDetached(false)
        return
    end
    local ok, err = pcall(menu.CreateContextMenu, owner, function(_, root)
        root:CreateButton("Back to the panel", guarded(function() setDetached(false) end))
        root:CreateButton("Reset position", guarded(resetSpot))
    end)
    if not ok then
        API.Fail("combat:menu", err)
        API.Print("Combat: the menu couldn't open (see /gpanel failures).")
    end
end

local function buildPill()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(PILL_W, PILL_H)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:Hide()
    pill = f
    -- The glass pill, painted like the panel (Clear or Smoked, Neutral or Class colour).
    local glass = GlassPanel.CleanGlass() or Glass
    local g = glass.Apply(f, "small")
    API.MatchPanelGlass(g, glass ~= Glass and glass or nil)
    local tf = CreateFrame("Frame", nil, f)
    tf:SetAllPoints(f)
    tf:SetFrameLevel(f:GetFrameLevel() + 12)   -- over the glass's rims
    pillText = Glass.Font(tf, PILL_FONT, "CENTER")
    pillText:SetPoint("CENTER", f, "CENTER", 0, 0)
    API.RegisterFloat(f, { order = 2, placed = function() return savedSpot() ~= nil end,
                           place = function() placePill() end })

    f:SetScript("OnDragStart", guarded(function(self)
        if not IsShiftKeyDown() then return end
        moving = true
        self:StartMoving()
    end))
    f:SetScript("OnDragStop", guarded(function(self)
        if not moving then return end
        moving = false
        lastMoveStop = GetTime()
        self:StopMovingOrSizing()
        API.SnapFloat(self)
        saveSpot()
        API.UpdateTopEdge()
    end))
    f:SetScript("OnClick", guarded(function(self, button)
        if moving or GetTime() - lastMoveStop < 0.2 then return end
        if button == "RightButton" then openMenu(self) end
    end))
    f:SetScript("OnHide", guarded(function(self)
        if moving then   -- hidden mid-move (the fight is over): stopped where it was saved last
            moving = false
            self:StopMovingOrSizing()
            placePill()
        end
        if ticker then ticker:Cancel() end
        ticker = nil
    end))
    placePill()
end

-- Shown while zoomed, the block on screen, and in combat (or previewing).
local function applyPill()
    local want = onScreen and detached() and (inCombat or previewing())
    if want and not pill then buildPill() end
    if not pill then return end
    if want and not pill:IsShown() then
        pill:Show()
        paintPill()
        if not ticker then ticker = C_Timer.NewTicker(1, guarded(paintPill)) end
    elseif not want then
        pill:Hide()   -- OnHide stops the ticker
    end
    API.PlaceFloats()
end

local function setPreview()
    if not detached() then
        API.Print("Combat: zoom the timer first (double-click its icon).")
        return
    end
    previewUntil = GetTime() + PREVIEW
    local mine = previewUntil
    applyPill()
    C_Timer.After(PREVIEW + 0.1, guarded(function() if previewUntil == mine then applyPill() end end))
end

function setDetached(on)
    db().detached = on and true or nil
    GlassPanel.Refresh("combat")
    applyPill()
end

--------------------------------------------------------------------------------
-- Glass Unit Frames' timer: the player's choice, from a click, never copied here
--------------------------------------------------------------------------------

local function guf()
    local G = rawget(_G, "GlassUF")
    local S = type(G) == "table" and rawget(G, "Settings")
    local T = type(G) == "table" and rawget(G, "Timer")
    if type(S) == "table" and type(rawget(S, "SetCombatTimer")) == "function" and type(T) == "table" then return S, T end
end

local function usingOurs()
    local _, T = guf()
    return T ~= nil and T.enabled == false
end

local function useOurs(on)
    local S = guf()
    if not S then
        API.Print("Combat: Glass Unit Frames isn't loaded (or isn't ready), so its timer is left alone.")
        return
    end
    local ok, applied = pcall(S.SetCombatTimer, not on)
    if not ok then
        API.Fail("combat:guf", applied)
    elseif applied == false then
        API.Print("Combat: Glass Unit Frames isn't ready yet; try again in a moment.")
    end
end

-- Once ever: both timers would show, say so (the choice is in the plugin's options).
local function hintOnce()
    local _, T = guf()
    if not (T and T.enabled == true) or db().hinted then return end
    db().hinted = true
    API.Print("Combat: Glass Unit Frames shows a combat timer too. To use this one instead: "
        .. "Options > AddOns > Glass Panel > Plugin options > Combat.")
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local function onEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat, startedAt = true, GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if inCombat then lastFight = GetTime() - startedAt end
        inCombat = false
    elseif P(InCombatLockdown()) == true then   -- PLAYER_ENTERING_WORLD: a reload mid-fight counts from now
        if not inCombat then inCombat, startedAt = true, GetTime() end
    else
        inCombat = false
    end
    if event == "PLAYER_ENTERING_WORLD" then hintOnce() end
    applyPill()
end

local block = GlassPanel.RegisterBlock({
    id = "combat",
    label = "Combat",
    icon = "Interface\\Icons\\Ability_DualWield",   -- crossed swords
    order = 25,
    width = function() return WIDTH end,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
    onEvent = onEvent,
    -- Docked, the time ticks once a second while it counts. Always 1: the engine only
    -- re-asks a function when its countdown ends, so a 30 would delay the first tick.
    interval = 1,
    text = function()
        if inCombat then return detached() and "In Combat" or format(elapsed()) end
        return "Out of Combat"
    end,
    tooltip = function(_, tt)
        tt:AddLine("Combat timer")
        if inCombat then
            tt:AddDoubleLine("In combat for", format(elapsed()), 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddLine("Out of combat.", 0.7, 0.7, 0.7)
            if lastFight then tt:AddDoubleLine("Last fight", format(lastFight), 1, 0.82, 0, 1, 1, 1) end
        end
        tt:AddLine("Double-click the icon to zoom: a glass pill on the screen, only in combat.", 0.7, 0.7, 0.7, true)
    end,
    onShown = function(_, visible)
        onScreen = visible
        applyPill()
    end,
    options = {
        { label = "Zoomed: a pill on the screen, only in combat",
          note = "Double-click the icon to zoom in or out. Shift-drag the pill to move it.",
          get = detached,
          set = function(on) setDetached(on) end },
        { label = "Pill's scale", min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
          get = pillScale, set = setScale },
        { label = "Preview the pill for 30 s (to place it)", run = setPreview },
        { label = "Reset the pill's position", run = resetSpot },
        { label = "Use this timer instead of Glass Unit Frames'",
          note = "Turns the one over your portrait off (and back on). Needs Glass Unit Frames.",
          get = usingOurs,
          set = useOurs },
    },
    -- On the bar, or on the icon left while zoomed: zoom in or out.
    onDoubleClick = function(_, button)
        if button == "LeftButton" then setDetached(not detached()) end
    end,
})

if block then
    block._test = { format = format, pill = function() return pill end, pillText = function() return pillText end,
                    setDetached = setDetached, setPreview = setPreview, state = function() return inCombat, startedAt, lastFight end,
                    ticker = function() return ticker end, usingOurs = usingOurs, useOurs = useOurs,
                    resetSpot = resetSpot, setScale = setScale, pillScale = pillScale, moving = function() return moving end }
end
