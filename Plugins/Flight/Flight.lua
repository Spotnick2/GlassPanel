-- Plugins/Flight/Flight.lua: a flight timer (#124). On the bar, only on a
-- taxi: the flight master's icon and the time left. Zoomed (left
-- double-click, as XP+ and Combat): the bar says "Flying" and a glass bar
-- floats on the screen while you fly, with the destination, the time left and
-- a fill. It is a float of order 3 (API.RegisterFloat): its default slot
-- stacks under XP+'s zoomed bar, and a drop snaps clear of the others.
--
-- The client gives no flight duration, so times are learned: each landing at
-- the end of a flight records that exact path (GlassPanelFlightDB.routes,
-- account-wide, keyed by the node ids along the way, "6>74>71"). A path never
-- flown is estimated from its learned single hops ("~"); with neither, the
-- time flown so far shows (grey, "+"). Frequent Flier (Legacy node 110300,
-- flight paths 20% faster per EllesmereUI; unmeasured here) keeps times of its
-- own: the other kind is only an estimate, scaled by FF_FACTOR. An unreadable
-- perk learns nothing.
--
-- Lifecycle (EllesmereUI's, built on Forever): picking a node on the flight
-- map (TakeTaxiNode, hooked, never replaced) records the route;
-- PLAYER_CONTROL_LOST within BOARD seconds starts it (UnitOnTaxi may still
-- read false then); a landing is control back (PLAYER_CONTROL_GAINED) and off
-- the taxi, in either order within SETTLE seconds (Codex on #125), the one
-- landing learned from, timed at control back. A flight not picked here (a
-- quest's) is noticed a second after control is lost and counts up. While a
-- flight runs, a 1 s ticker repaints and settles landings: off the taxi for
-- SETTLE seconds without control back ends the flight, learning nothing.
-- TaxiRequestEarlyLanding (hooked) drops the time left. A /reload mid-flight
-- resumes from GlassPanelFlightDB.current (server time) and learns nothing.
--
-- Glass Unit Frames has no flight timer; should it get one, it can step aside
-- while ours floats: GlassPanel.Flight.Zoomed() is true while the zoomed bar
-- shows a flight, and EventRegistry "GlassPanel.Flight.ZoomedChanged"
-- (zoomed) says when that changes. Nothing is written to it.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local WIDTH = 72                  -- the block: icon + "~12:34"
local FLOAT_W, FLOAT_H, FLOAT_FONT = 480, 18, 12   -- XP+'s zoomed bar's, so they line up
local SCALE_MIN, SCALE_MAX, SCALE_STEP, SCALE_DEFAULT = 0.5, 2, 0.05, 1.5   -- XP+'s zoomed bar is usually 1.5
local FADE = 0.2                  -- seconds the bar takes to appear and to go
local PREVIEW = 30                -- seconds the preview flies
local BOARD = 5                   -- seconds from picking a node to losing control
local SETTLE = 3                  -- seconds a landing waits for its other half (off the taxi, control back)
local MIN_FLIGHT, MAX_FLIGHT = 5, 3600   -- a learned time outside these is noise
local FF_FACTOR = 1.2             -- Frequent Flier's speed (EllesmereUI's figure, unmeasured)
local LEGACY_TREE, FF_NODE = 1188, 110300
local SPOT_LIMIT = 4096
local GREY, GOLD = "|cff999999", "|cffffd100"

local function db()
    local d = rawget(_G, "GlassPanelFlightDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelFlightDB = d
    end
    return d
end
local function detached() return db().detached == true end

local pending      -- { route, clicked }: picked on the flight map, waiting for takeoff
local flight       -- { route, start, total, estimate, fast, early, resumed }
local lastFlight   -- { to, took }, for the tooltip
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

local function onTaxi() return P(UnitOnTaxi("player")) == true end

local function previewing() return previewUntil ~= nil and GetTime() < previewUntil end

--------------------------------------------------------------------------------
-- Routes and learned times
--------------------------------------------------------------------------------

-- A route is { keys = { node id (or name), ... }, names = { ... } }, start first.
local function pathOf(keys, from, to)
    local out = {}
    for i = from or 1, to or #keys do out[#out + 1] = tostring(keys[i]) end
    return table.concat(out, ">")
end

-- Checked whole: a saved route must be one we could have made.
local function validRoute(r)
    if type(r) ~= "table" or type(r.keys) ~= "table" or type(r.names) ~= "table" then return false end
    local n = #r.keys
    if n < 2 or n > 64 or #r.names ~= n then return false end
    for i = 1, n do
        local k = r.keys[i]
        if not ((type(k) == "number" or type(k) == "string") and type(r.names[i]) == "string") then return false end
    end
    return true
end

local function shortName(name) return name:match("^([^,]+)") or name end
local function destination(route) return route.names[#route.names] end

-- The flight map's slots to node ids, when the map says (C_TaxiMap's list).
local function nodeIds()
    local ids = {}
    local mapID = P(GetTaxiMapID())
    local T = rawget(_G, "C_TaxiMap")
    if type(mapID) ~= "number" or type(T) ~= "table" or type(T.GetAllTaxiNodes) ~= "function" then return ids end
    local ok, nodes = pcall(T.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" then return ids end
    for _, node in ipairs(nodes) do
        local slot, id = P(node.slotIndex), P(node.nodeID)
        if type(slot) == "number" and type(id) == "number" then ids[slot] = id end
    end
    return ids
end

-- The route to `slot` as the flight map draws it (Blizzard's FM_FlightPathDataProvider),
-- or nil when any part of it can't be read.
local function readRoute(slot)
    local hops = P(GetNumRoutes(slot))
    if type(hops) ~= "number" or hops < 1 then return nil end
    local ids = nodeIds()
    local route = { keys = {}, names = {} }
    local function add(s)
        s = P(s)
        local name = type(s) == "number" and P(TaxiNodeName(s))
        if type(name) ~= "string" or name == "" then return false end
        route.keys[#route.keys + 1] = ids[s] or name
        route.names[#route.names + 1] = name
        return true
    end
    if not add(TaxiGetNodeSlot(slot, 1, true)) then return nil end
    for hop = 1, hops do
        if not add(TaxiGetNodeSlot(slot, hop, false)) then return nil end
    end
    return route
end

-- Frequent Flier bought: true or false; nil when it can't be read.
local function frequentFlier()
    local T = rawget(_G, "C_Traits")
    if type(T) ~= "table" or type(T.GetConfigIDByTreeID) ~= "function" or type(T.GetNodeInfo) ~= "function" then return nil end
    local ok, config = pcall(T.GetConfigIDByTreeID, LEGACY_TREE)
    config = ok and P(config)
    if type(config) ~= "number" then return nil end
    local ok2, node = pcall(T.GetNodeInfo, config, FF_NODE)
    if not ok2 or type(node) ~= "table" or P(node.ID) ~= FF_NODE then return nil end
    local rank = P(node.activeRank)
    if type(rank) ~= "number" then return nil end
    return rank > 0
end

local function routes()
    local d = db()
    if type(d.routes) ~= "table" then d.routes = {} end
    return d.routes
end

local function kindOf(fast) return fast and "fast" or "base" end

local function stored(path, kind)
    local r = routes()[path]
    local t = type(r) == "table" and finite(r[kind])
    if t and t >= MIN_FLIGHT and t <= MAX_FLIGHT then return t end
end

-- A learned time for `path` without Frequent Flier, from either kind.
local function asBase(path)
    local t = stored(path, "base")
    if t then return t end
    t = stored(path, "fast")
    return t and t * FF_FACTOR
end

-- The flight's length in seconds and whether it is an estimate, or nil.
local function lengthOf(route, fast)
    local path = pathOf(route.keys)
    if fast ~= nil then
        local t = stored(path, kindOf(fast))
        if t then return t, false end
    end
    local base = asBase(path)
    if not base and #route.keys > 2 then   -- the sum of its learned hops
        base = 0
        for i = 1, #route.keys - 1 do
            local hop = asBase(pathOf(route.keys, i, i + 1))
            if not hop then base = nil break end
            base = base + hop
        end
    end
    if not base then return nil end
    return fast and base / FF_FACTOR or base, true
end

local function learn(fl, took)
    if fl.early or fl.resumed or not fl.route or fl.fast == nil then return end
    if took < MIN_FLIGHT or took > MAX_FLIGHT then return end
    local all, path = routes(), pathOf(fl.route.keys)
    local entry = type(all[path]) == "table" and all[path] or {}
    entry[kindOf(fl.fast)] = math.floor(took * 10 + 0.5) / 10
    all[path] = entry
end

local function learnedCount()
    local n = 0
    for _, e in pairs(routes()) do
        if type(e) == "table" and (finite(e.base) or finite(e.fast)) then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------------------
-- What shows
--------------------------------------------------------------------------------

local function previewFlight()
    return { route = { keys = { 0, 1 }, names = { "Here", "Preview flight" } }, start = previewStart, total = PREVIEW }
end

-- The flight on show: the real one, else the preview's.
local function shownFlight()
    if flight then return flight end
    if previewing() then return previewFlight() end
end

local function elapsedOf(fl) return math.max(0, GetTime() - fl.start) end

-- "1:23" exact, "~1:23" estimated, grey "+0:42" flown so far when unknown.
local function timeText(fl)
    if fl.total then
        local s = clock(fl.total - elapsedOf(fl))
        return fl.estimate and ("~" .. s) or s
    end
    return GREY .. "+" .. clock(elapsedOf(fl)) .. "|r"
end

local function whereTo(fl)
    if fl.early then return "Landing at the next stop" end
    return fl.route and shortName(destination(fl.route)) or "Flying"
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
        Glass.SetBar(bar.host, fl.total, math.min(elapsedOf(fl), fl.total), snap)
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

local function announce()
    local now = flight ~= nil and onScreen and detached()
    if now == claimed then return end
    claimed = now
    local R = rawget(_G, "EventRegistry")
    if type(R) == "table" and type(R.TriggerEvent) == "function" then
        local ok, err = pcall(R.TriggerEvent, R, "GlassPanel.Flight.ZoomedChanged", now)
        if not ok then API.Fail("flight:announce", err) end
    end
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

-- One ticker while a flight or the preview runs: the docked time, the bar,
-- and a flight found off the taxi ended (its landing was missed).
local land   -- below

local function tick()
    if flight and GetTime() - flight.start > 2 and not onTaxi() then
        local now = GetTime()
        if flight.gainedAt and now - flight.gainedAt <= SETTLE then
            land(true, flight.gainedAt)   -- control came back first: landed then
        elseif not flight.offAt then
            flight.offAt = now            -- control back may still be on its way
        elseif now - flight.offAt >= SETTLE then
            land(false)                   -- its landing was missed
        end
    end
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
-- Flights
--------------------------------------------------------------------------------

local function saveCurrent()
    local now = P(GetServerTime())
    if not flight or type(now) ~= "number" then
        db().current = nil
        return
    end
    db().current = { route = flight.route, at = now - (GetTime() - flight.start), early = flight.early or nil }
end

local function startFlight(route, startedAt, resumed, early)
    local fast = frequentFlier()
    local total, estimate
    if route then total, estimate = lengthOf(route, fast) end
    flight = { route = route, start = startedAt or GetTime(), total = total, estimate = estimate,
               fast = fast, resumed = resumed, early = early }
    if early then flight.total = nil end
    if not resumed then saveCurrent() end
    previewUntil = nil
    startTicker()
    GlassPanel.Refresh("flight")
    applyFloat()
    paintFloat(true)
end

-- `at`: when it landed (control back), else now.
function land(learnIt, at)
    if not flight then return end
    local took = (at or GetTime()) - flight.start
    if learnIt then learn(flight, took) end
    lastFlight = { to = flight.route and destination(flight.route), took = took }
    flight = nil
    db().current = nil
    GlassPanel.Refresh("flight")
    applyFloat()
end

-- After a /reload (or a login) on a taxi: the saved flight, if it is the one
-- still in the air; else a flight with nothing known about it.
local function resume()
    if flight then return end
    if not onTaxi() then
        db().current = nil
        return
    end
    local c, now = db().current, P(GetServerTime())
    local at = type(c) == "table" and finite(c.at)
    if at and type(now) == "number" and now >= at and now - at <= MAX_FLIGHT and validRoute(c.route) then
        startFlight(c.route, GetTime() - (now - at), true, c.early == true)
    else
        startFlight(nil, nil, true)
    end
end

local function onTakeTaxiNode(slot)
    pending = { route = readRoute(slot), clicked = GetTime() }
end

local function onEarlyLanding()
    if not flight or flight.early then return end
    flight.early, flight.total = true, nil
    saveCurrent()
    GlassPanel.Refresh("flight")
    paintFloat(true)
end

-- Hooked, never replaced (Blizzard's flight map calls them by name).
for name, fn in pairs({ TakeTaxiNode = onTakeTaxiNode, TaxiRequestEarlyLanding = onEarlyLanding }) do
    if type(rawget(_G, name)) == "function" then hooksecurefunc(name, guarded(fn)) end
end

local function onEvent(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        local p = pending
        pending = nil
        if flight then return end
        if p and GetTime() - p.clicked < BOARD then
            startFlight(p.route)
        else
            -- Not picked here (a quest's flight), or no flight at all (a stun): a look in a moment.
            C_Timer.After(1, guarded(function()
                if not flight and onTaxi() then startFlight(nil) end
            end))
        end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if not flight then return end
        if onTaxi() then
            flight.gainedAt = GetTime()   -- still reads on the taxi: the ticker lands it from this
        else
            land(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        resume()
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
        if lastFlight then
            tt:AddDoubleLine("Last flight", (lastFlight.to and (shortName(lastFlight.to) .. ", ") or "")
                .. clock(lastFlight.took), LABEL[1], LABEL[2], LABEL[3], WHITE[1], WHITE[2], WHITE[3])
        end
    else
        local r = fl.route
        if r then
            tt:AddDoubleLine("To", destination(r), LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            tt:AddDoubleLine("From", r.names[1], LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            for i = 2, #r.names - 1 do
                tt:AddDoubleLine(i == 2 and "Via" or " ", r.names[i], LABEL[1], LABEL[2], LABEL[3], 0.8, 0.8, 0.8)
            end
        end
        local flown = clock(elapsedOf(fl))
        if fl.early then
            tt:AddDoubleLine("Flown", flown, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            tt:AddLine("Landing at the next stop.", 0.7, 0.7, 0.7)
        elseif fl.total then
            tt:AddDoubleLine("Time left", timeText(fl) .. " (of " .. clock(fl.total) .. ")",
                LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            if fl.estimate then
                tt:AddLine("Estimated from your other flights; learned exactly when you land.", 0.7, 0.7, 0.7, true)
            end
        else
            tt:AddDoubleLine("Flown", flown, LABEL[1], LABEL[2], LABEL[3], 1, 1, 1)
            if fl.resumed and not r then
                tt:AddLine("This flight started before the UI loaded: its route is unknown.", 0.7, 0.7, 0.7, true)
            elseif r then
                tt:AddLine("First time on this route: its time is learned when you land.", 0.7, 0.7, 0.7, true)
            else
                tt:AddLine("A flight not picked on the flight map: its route is unknown.", 0.7, 0.7, 0.7, true)
            end
        end
    end
    local n = learnedCount()
    tt:AddLine(n == 1 and "1 route learned." or (n .. " routes learned."), 0.7, 0.7, 0.7)
    tt:AddLine("Double-click the icon to zoom: a glass bar on the screen while you fly.", 0.7, 0.7, 0.7, true)
end

local function forget()
    db().routes = nil
    API.Print("Flight: learned flight times forgotten.")
    if flight and flight.route and not flight.early then
        flight.total, flight.estimate = lengthOf(flight.route, flight.fast)
        GlassPanel.Refresh("flight")
        paintFloat(true)
    end
end

local block = GlassPanel.RegisterBlock({
    id = "flight",
    label = "Flight",
    icon = "Interface\\Minimap\\Tracking\\FlightMaster",   -- as EllesmereUI's flight timer on Forever
    order = 26,   -- left lane, after Combat
    width = function() return WIDTH end,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
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
        { label = "Forget learned flight times", run = forget },
    },
    -- On the bar, or on the icon left while zoomed: zoom in or out.
    onDoubleClick = function(_, button)
        if button == "LeftButton" then setDetached(not detached()) end
    end,
})

-- For Glass Unit Frames (and anything else with a flight timer of its own):
-- true while our zoomed bar shows a flight. Read-only; additive.
GlassPanel.Flight = { API = 1, Zoomed = function() return claimed end }

if block then
    block._test = { clock = clock, float = function() return float end, bar = function() return bar end,
                    flight = function() return flight end, pending = function() return pending end,
                    setDetached = setDetached, setPreview = setPreview, setScale = setScale,
                    floatScale = floatScale, resetSpot = resetSpot, forget = forget,
                    ticker = function() return ticker end, lengthOf = lengthOf, pathOf = pathOf }
end
