-- Plugins/Flight/Flight.lua: a flight timer (#124). On the bar, only on a
-- taxi: the flight master's icon and the time left. Zoomed (left
-- double-click, as XP+ and Combat): the bar says "Flying" and a glass bar
-- floats on the screen while you fly, with the destination, the time left and
-- a bar that empties as you fly, like a channel's (an option fills it up
-- instead). It is a float of order 3 (API.RegisterFloat): its default slot
-- stacks under XP+'s zoomed bar, and a drop snaps clear of the others.
--
-- The timing is LibTaxiTime-1.0's (#127), embedded in the core's Libs/ and
-- shared with Glass Unit Frames: the route lengths, the tracker (takeoff,
-- landing, early landing, a /reload mid-flight), the learned times. This file
-- is the UI. GlassPanelFlightDB is the plugin's store (lib:AddStore at our
-- ADDON_LOADED): the library owns its `routes` and `current` keys; the rest
-- (detached, spot, scale, fillUp) is ours. The time shows "1:23" (learned or
-- from the route's length), "~1:23" (an estimate), an orange "+0:07" past the
-- prediction, or a grey "+0:42" flown so far when nothing is known.
--
-- For Glass Unit Frames (GUF #148), read-only and additive, GlassPanel.Flight
-- (API 1):
--   Current() -> the library's Current(): nil off a flight, else a fresh
--     { to, from, stops, start, total, source, early, resumed }. EventRegistry
--     "GlassPanel.Flight.Changed" () re-fires the library's "LibTaxiTime.Changed".
--   Zoomed() -> true while our zoomed bar shows a flight; EventRegistry
--     "GlassPanel.Flight.ZoomedChanged" (zoomed) on a change. (GUF no longer
--     uses them: its bar shows alongside ours.)
-- Nothing is written to it.

local ADDON = ...
GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local LibStub = rawget(_G, "LibStub")
local LTT = LibStub and LibStub("LibTaxiTime-1.0", true)

local WIDTH = 72                  -- the block: icon + "~12:34"
local FLOAT_W, FLOAT_H, FLOAT_FONT = 480, 18, 12   -- XP+'s zoomed bar's, so they line up
local SCALE_MIN, SCALE_MAX, SCALE_STEP, SCALE_DEFAULT = 0.5, 2, 0.05, 1.5   -- XP+'s zoomed bar is usually 1.5
local FADE = 0.2                  -- seconds the bar takes to appear and to go
local PREVIEW = 30                -- seconds the preview flies
local SPOT_LIMIT = 4096
local GREY, LATE = "|cff999999", "|cffff9900"

local function db()
    local d = rawget(_G, "GlassPanelFlightDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelFlightDB = d
    end
    return d
end
local function detached() return db().detached == true end

local flight       -- the library's Current(), read again at every change
local onScreen = false
local float, bar, ticker, previewUntil, previewStart
local moving, lastMoveStop = false, -1
local fadeTarget   -- 1 while appearing, 0 while going; nil at rest
local claimed = false   -- GlassPanel.Flight.Zoomed()

local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then API.Fail("flight", err) end
    end
end

local function finite(v)
    v = P(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- 0:42, 12:05, 1:02:03; rounded, never below 0.
local function clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function previewing() return previewUntil ~= nil and GetTime() < previewUntil end

local function shortName(name) return name:match("^([^,]+)") or name end

--------------------------------------------------------------------------------
-- What shows
--------------------------------------------------------------------------------

local function previewFlight()
    return { to = "Preview flight", from = "Here", stops = { "Here", "Preview flight" }, start = previewStart,
             total = PREVIEW, source = "route" }
end

-- The flight on show: the real one, else the preview's.
local function shownFlight()
    if flight then return flight end
    if previewing() then return previewFlight() end
end

local function elapsedOf(fl) return math.max(0, GetTime() - fl.start) end

-- Past the time it was given: the flight runs longer than predicted.
local function overdue(fl) return fl.total ~= nil and elapsedOf(fl) > fl.total end

-- "1:23" exact, "~1:23" estimated, orange "+0:07" past the prediction (the
-- bar stays at its end), grey "+0:42" flown so far when unknown.
local function timeText(fl)
    if fl.total then
        local left = fl.total - elapsedOf(fl)
        if left < 0 then return LATE .. "+" .. clock(-left) .. "|r" end
        local s = clock(left)
        return fl.source == "estimate" and ("~" .. s) or s
    end
    return GREY .. "+" .. clock(elapsedOf(fl)) .. "|r"
end

local function whereTo(fl)
    if fl.early then return "Landing at the next stop" end
    return fl.to and shortName(fl.to) or "Flying"
end

--------------------------------------------------------------------------------
-- The zoomed bar
--------------------------------------------------------------------------------

local function savedSpot()
    local s = db().spot
    if type(s) ~= "table" then return nil end
    local x, y = finite(s.x), finite(s.y)
    if not (x and y and math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT) then return nil end
    return x, y
end

-- The saved scale, or the default when unset or out of range.
local function floatScale()
    local s = finite(db().scale)
    if not s or s < SCALE_MIN or s > SCALE_MAX then return SCALE_DEFAULT end
    return s
end

local function placeFloat()
    local scale = floatScale()
    float:SetScale(scale)
    float:ClearAllPoints()
    local x, y = savedSpot()
    if x then
        float:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
    else
        local dy, dx = API.FloatDefaultY(float)
        float:SetPoint("TOP", UIParent, "TOP", (dx or 0) / scale, dy / scale)
    end
    API.UpdateTopEdge()
end

-- Where the bar was let go, saved when it reads plainly and is in bounds;
-- anchored on our point again either way (the last good spot when it isn't).
local function saveSpot()
    local fx, fy = float:GetCenter()
    local ux, uy = UIParent:GetCenter()
    fx, fy, ux, uy = finite(fx), finite(fy), finite(ux), finite(uy)
    if fx and fy and ux and uy then
        local scale = floatScale()
        fx, fy = fx * scale, fy * scale
        local x, y = math.floor((fx - ux) * 2 + 0.5) / 2, math.floor((fy - uy) * 2 + 0.5) / 2
        if math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT then db().spot = { x = x, y = y } end
    end
    placeFloat()
end

local function resetSpot()
    db().spot = nil
    if float then placeFloat() end
    API.PlaceFloats()
end

-- The slider: clamped, in steps; live around the spot.
local function setScale(v)
    v = finite(v)
    if not v then return end
    v = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(v / SCALE_STEP + 0.5) * SCALE_STEP))
    db().scale = v
    if float then placeFloat() end
    API.PlaceFloats()
end

-- `snap`: no easing (a new flight, or the bar just shown).
local function paintFloat(snap)
    if not (float and float:IsShown()) then return end
    local fl = shownFlight()
    if not fl then return end
    bar.left:SetText(whereTo(fl))
    bar.right:SetText(timeText(fl))
    if fl.total and not fl.early then
        -- A channel's bar by default: full at takeoff, empty on landing; or filling up (the option).
        local flown = math.min(elapsedOf(fl), fl.total)
        Glass.SetBar(bar.host, fl.total, db().fillUp == true and flown or fl.total - flown, snap)
    else
        Glass.SetBar(bar.host, 1, 0, true)
    end
end

local tooltip   -- below: the float shows the block's

local function showFloatTooltip(f)
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", f, "BOTTOM", 0, -4)
    GameTooltip:ClearLines()
    tooltip(nil, GameTooltip)
    GameTooltip:Show()
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
        API.Fail("flight:menu", err)
        API.Print("Flight: the menu couldn't open (see /gpanel failures).")
    end
end

local function buildFloat()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(FLOAT_W, FLOAT_H)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:Hide()
    float = f
    -- A glass bar on XP+'s zoomed bar's clean surfaces; the texts are the panel's font.
    local glass = GlassPanel.CleanGlass() or Glass
    local host = glass.Bar(f, FLOAT_H)
    host:SetFrameLevel(f:GetFrameLevel() + 1)
    host:SetPoint("LEFT", f, "LEFT", 0, 0)
    host:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    host:SetStatusBarColor(0.25, 0.6, 1, 0.9)
    local tf = CreateFrame("Frame", nil, host)
    tf:SetAllPoints(host)
    tf:SetFrameLevel(host:GetFrameLevel() + 5)
    local left = Glass.Font(tf, FLOAT_FONT, "LEFT")
    left:SetPoint("LEFT", host, "LEFT", 6, 0)
    local right = Glass.Font(tf, FLOAT_FONT, "RIGHT")
    right:SetPoint("RIGHT", host, "RIGHT", -6, 0)
    bar = { host = host, left = left, right = right }
    -- Order 3: under XP+'s bar (1) and the combat pill (2) when they show unplaced.
    API.RegisterFloat(f, { order = 3, placed = function() return savedSpot() ~= nil end,
                           place = function() placeFloat() end })

    f:SetScript("OnEnter", guarded(showFloatTooltip))
    f:SetScript("OnLeave", guarded(function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end))
    f:SetScript("OnDragStart", guarded(function(self)
        if not IsShiftKeyDown() then return end
        moving = true
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
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
        if moving then   -- hidden mid-move (landed): stopped where it was saved last
            moving = false
            self:StopMovingOrSizing()
            placeFloat()
        end
        self:SetScript("OnUpdate", nil)
        fadeTarget = nil
        self:SetAlpha(1)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end))
    placeFloat()
end

-- Fades the bar in or out (a real Hide at the end of the way out). Only while it
-- is fading does it carry an OnUpdate.
local function fadeTo(target)
    fadeTarget = target
    float:SetScript("OnUpdate", guarded(function(self, dt)
        local a = self:GetAlpha() + (fadeTarget == 1 and dt or -dt) / FADE
        if fadeTarget == 1 and a >= 1 then a = 1 elseif fadeTarget == 0 and a <= 0 then a = 0 end
        self:SetAlpha(a)
        if a == fadeTarget then
            self:SetScript("OnUpdate", nil)
            local gone = fadeTarget == 0
            fadeTarget = nil
            if gone then self:Hide() end
        end
    end))
end

-- EventRegistry, when the client has it; a throw from a listener is recorded.
local function trigger(event, ...)
    local R = rawget(_G, "EventRegistry")
    if type(R) == "table" and type(R.TriggerEvent) == "function" then
        local ok, err = pcall(R.TriggerEvent, R, event, ...)
        if not ok then API.Fail("flight:announce", err) end
    end
end

local function announce()
    local now = flight ~= nil and onScreen and detached()
    if now == claimed then return end
    claimed = now
    trigger("GlassPanel.Flight.ZoomedChanged", now)
end

-- Shown while zoomed and flying with the block on screen, or previewing.
local function applyFloat()
    local want = detached() and ((flight ~= nil and onScreen) or previewing())
    if want and not float then buildFloat() end
    announce()
    if not float then return end
    if want then
        if not float:IsShown() then
            float:SetAlpha(0)
            float:Show()
            paintFloat(true)
            fadeTo(1)
        elseif fadeTarget == 0 then
            fadeTo(1)   -- flying again while it was going
        end
    elseif float:IsShown() and fadeTarget ~= 0 then
        if moving then
            float:Hide()   -- OnHide stops the move
        else
            fadeTo(0)
        end
    end
    API.PlaceFloats()
end

-- One ticker while a flight or the preview runs: the docked time and the bar
-- (the library has its own for landings).
local function tick()
    if not (flight or previewing()) then
        if ticker then ticker:Cancel() end
        ticker = nil
        applyFloat()
        return
    end
    GlassPanel.Refresh("flight")
    paintFloat(false)
    if float and GameTooltip:GetOwner() == float and GameTooltip:IsShown() then showFloatTooltip(float) end
end

local function startTicker()
    if not ticker then ticker = C_Timer.NewTicker(1, guarded(tick)) end
end

local function setPreview()
    if not detached() then
        API.Print("Flight: zoom the timer first (double-click its icon, or the option above).")
        return
    end
    previewStart, previewUntil = GetTime(), GetTime() + PREVIEW
    applyFloat()
    paintFloat(true)
    startTicker()
end

function setDetached(on)
    db().detached = on and true or nil
    local owner = GameTooltip:GetOwner()
    if owner ~= nil and owner == float then GameTooltip:Hide() end
    GlassPanel.Refresh("flight")
    applyFloat()
end

--------------------------------------------------------------------------------
-- The library
--------------------------------------------------------------------------------

-- A flight started, landed, landed early or changed its total.
local function onChanged()
    flight = LTT:Current()
    if flight then
        previewUntil = nil
        startTicker()
    end
    GlassPanel.Refresh("flight")
    applyFloat()
    paintFloat(true)
    trigger("GlassPanel.Flight.Changed")
end

if LTT then
    local R = rawget(_G, "EventRegistry")
    if type(R) == "table" and type(R.RegisterCallback) == "function" then
        R:RegisterCallback("LibTaxiTime.Changed", guarded(onChanged), {})
    end
end

local function onEvent(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        if not LTT then
            API.Fail("flight:library", "LibTaxiTime-1.0 isn't loaded")
            return
        end
        local ok, why = LTT:AddStore(db())   -- GlassPanelFlightDB is loaded now
        if not ok then API.Fail("flight:store", why) end
    end
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }
local LABEL = { 1, 0.82, 0 }

function tooltip(_, tt)
    tt:AddLine("Flight")
    local fl = shownFlight()
    if not fl then
        tt:AddLine("Not on a flight.", 0.7, 0.7, 0.7)
        local last = LTT and LTT:Last()
        if last then
            tt:AddDoubleLine("Last flight", (last.to and (shortName(last.to) .. ", ") or "") .. clock(last.took),
                LABEL[1], LABEL[2], LABEL[3], WHITE[1], WHITE[2], WHITE[3])
        end
    else
        local stops = fl.stops
        if stops then
            tt:AddDoubleLine("To", fl.to, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            tt:AddDoubleLine("From", fl.from, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            for i = 2, #stops - 1 do
                tt:AddDoubleLine(i == 2 and "Via" or " ", stops[i], LABEL[1], LABEL[2], LABEL[3], 0.8, 0.8, 0.8)
            end
        end
        local flown = clock(elapsedOf(fl))
        if fl.early then
            tt:AddDoubleLine("Flown", flown, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            tt:AddLine("Landing at the next stop.", 0.7, 0.7, 0.7)
        elseif fl.total then
            tt:AddDoubleLine("Time left", timeText(fl) .. " (of " .. clock(fl.total) .. ")",
                LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            if overdue(fl) then
                tt:AddLine("Longer than predicted: learned when you land.", 1, 0.6, 0, true)
            elseif fl.source == "route" then
                tt:AddLine("From the route's length; learned exactly when you land.", 0.7, 0.7, 0.7, true)
            elseif fl.source == "estimate" then
                tt:AddLine("Estimated; learned exactly when you land.", 0.7, 0.7, 0.7, true)
            end
        else
            tt:AddDoubleLine("Flown", flown, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            if fl.resumed and not stops then
                tt:AddLine("This flight started before the UI loaded: its route is unknown.", 0.7, 0.7, 0.7, true)
            elseif stops then
                tt:AddLine("First time on this route: its time is learned when you land.", 0.7, 0.7, 0.7, true)
            else
                tt:AddLine("A flight not picked on the flight map: its route is unknown.", 0.7, 0.7, 0.7, true)
            end
        end
    end
    local n = LTT and LTT:LearnedCount() or 0
    tt:AddLine(n == 1 and "1 route learned." or (n .. " routes learned."), 0.7, 0.7, 0.7)
    tt:AddLine("Double-click the icon to zoom: a glass bar on the screen while you fly.", 0.7, 0.7, 0.7, true)
end

local function forget()
    if not LTT then return end
    LTT:Forget()   -- every store's; "Changed" repaints
    API.Print("Flight: learned flight times forgotten.")
end

local block = GlassPanel.RegisterBlock({
    id = "flight",
    label = "Flight",
    icon = "Interface\\Minimap\\Tracking\\FlightMaster",   -- as EllesmereUI's flight timer on Forever
    order = 26,   -- left lane, after Combat
    width = function() return WIDTH end,
    events = { "ADDON_LOADED" },
    onEvent = onEvent,
    -- Only on a flight; zoomed, the bar on the screen has the time.
    text = function()
        if not flight then return nil end
        return detached() and "Flying" or timeText(flight)
    end,
    tooltip = tooltip,
    onShown = function(_, visible)
        onScreen = visible
        applyFloat()
    end,
    options = {
        { label = "Zoomed: a glass bar on the screen while you fly",
          note = "Double-click the icon to zoom in or out. Shift-drag the bar to move it.",
          get = detached,
          set = function(on) setDetached(on) end },
        { label = "Bar's scale", min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
          get = floatScale, set = setScale },
        { label = "Preview the bar for 30 s (to place it)", run = setPreview },
        { label = "Reset the bar's position", run = resetSpot },
        { label = "The bar fills up as you fly",
          note = "Off: it starts full and empties as you fly, like a channelled spell's bar.",
          get = function() return db().fillUp == true end,
          set = function(on) db().fillUp = on and true or nil; paintFloat(true) end },
        { label = "Forget learned flight times", run = forget },
    },
    -- On the bar, or on the icon left while zoomed: zoom in or out.
    onDoubleClick = function(_, button)
        if button == "LeftButton" then setDetached(not detached()) end
    end,
})

-- For Glass Unit Frames (see the header): the library's fresh copy.
GlassPanel.Flight = { API = 1, Zoomed = function() return claimed end,
                      Current = function() return LTT and LTT:Current() or nil end }

if block then
    block._test = { clock = clock, float = function() return float end, bar = function() return bar end,
                    flight = function() return flight end, lib = LTT,
                    setDetached = setDetached, setPreview = setPreview, setScale = setScale,
                    floatScale = floatScale, resetSpot = resetSpot, forget = forget,
                    ticker = function() return ticker end }
end
