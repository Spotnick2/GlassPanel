-- Room.lua: the bar makes room for Blizzard's top frames (#2), without moving
-- any of them.
--
-- Researched and reviewed (#2 comments): no reference addon shifts Blizzard's
-- top frames for a top bar any more (Titan removed it when Edit Mode arrived),
-- moving Edit Mode systems from addon code is a standing taint/combat
-- obligation, and the top-centre widget container can't be moved safely on
-- Forever. So by default the BAR adapts: it measures a short list of
-- Blizzard frames that reach into its band and ends short of them (a glass
-- pill between, say, the screen's left edge and the buffs). A user who moved
-- those frames down in Edit Mode gets the full width back automatically.
-- Writing a GlassPanel Edit Mode layout with them lowered is opt-in (#10).
--
-- Which frames count: one hidden ON ITS OWN (no target, no focus) still
-- counts where Edit Mode put it, so the bar's width doesn't jump every time
-- you target something (buffs and debuffs follow their own rule, below); one whose PARENT is hidden has been replaced by
-- another addon (GlassUnitFrames reparents Blizzard's unit frames to a hidden
-- frame) and doesn't count. A frame centred in the middle fifth of the screen
-- is ignored: the bar's two ends can't route around it.
--
-- Buffs and debuffs (#33) are measured by the icons shown, not by the frame:
-- BuffFrame's rect is Edit Mode's whole buff grid, and on a default layout
-- the bar stopped ~350 px short of a lone buff. Measured on 70009: the
-- icons hang off BuffFrame.AuraContainer (DebuffFrame.AuraContainer too), a
-- 1x1 anchor at the grid's corner that does NOT size to them; BuffFrame also
-- holds a CollapseAndExpandButton (15x30, visible, clickable) and a hidden
-- Selection box. So the icons are the visible frames under AuraContainer
-- between ICON_MIN and ICON_MAX units a side (bigger ones are containers and
-- smaller ones anchors: both looked into, up to DEPTH levels), plus the
-- collapse button while it shows (the bar mustn't sit on a live button);
-- never the rest of the frame. Their union only GROWS within a session: the bar steps in
-- once as buffs appear and doesn't jiggle as they come and go (it does step,
-- unlike a frame hidden on its own, which holds its place from the start). A
-- new session measures afresh: a reload, zoning, an Edit Mode, scale or
-- display change, Edit Mode closing, or the aura frame itself moving or
-- resizing (its whole rect is compared). While
-- Edit Mode is open (EditModeManagerFrame shown) its example auras aren't
-- recorded. No icon seen yet: the frame takes no room.
--
-- Read-only on Blizzard frames: GetRect/IsShown/IsVisible/GetChildren only,
-- under pcall, every number through API.Plain. Checked on layout/scale/
-- display events and on the engine's once-a-second clock.
-- /gpanel room why lists what each watched frame measured.

GlassPanel = GlassPanel or {}
local API, Engine = GlassPanel.API, GlassPanel.Engine
local Room = {}
GlassPanel.Room = Room

-- Blizzard frames the bar gives way to when they reach into its band. The
-- list comes from /gpanel covered measurements (#2); a frame not on it is
-- simply drawn over, as before.
Room.WATCH = { "MinimapCluster", "BuffFrame", "DebuffFrame", "TicketStatusFrame",
               "PlayerFrame", "TargetFrame", "FocusFrame", "DamageMeter" }
Room.MARGIN = 6        -- px between the bar's end and the frame it gives way to
Room.MIN_WIDTH = 300   -- px: narrower than this, the bar keeps the full width
Room.MIDDLE = 0.2      -- a frame centred in this middle fraction of the screen is ignored
Room.AURAS = { BuffFrame = true, DebuffFrame = true }   -- measured by their icons (#33)
Room.ICON_MIN = 8      -- UI units: smaller is an anchor (AuraContainer is 1x1), not an icon
Room.ICON_MAX = 100    -- UI units: bigger than any aura icon, smaller than the grid box
Room.DEPTH = 4         -- levels under AuraContainer looked into for icons

-- Pure. W: the screen width; bandTop/bandBottom: the bar's band (screen px,
-- y up); rects: { l, r, top, bottom } in screen px. A rect in the band sits on
-- the left or the right by its centre, and pushes that end of the bar in.
-- Returns the left and right insets in screen px.
function Room.Insets(W, bandTop, bandBottom, rects)
    local left, right = 0, 0
    local midL, midR = W * (0.5 - Room.MIDDLE / 2), W * (0.5 + Room.MIDDLE / 2)
    for _, r in ipairs(rects) do
        if r.bottom < bandTop and r.top > bandBottom and r.r > r.l then
            local c = (r.l + r.r) / 2
            if c < midL then
                left = math.max(left, r.r + Room.MARGIN)
            elseif c > midR then
                right = math.max(right, W - r.l + Room.MARGIN)
            end
        end
    end
    if W - left - right < Room.MIN_WIDTH then return 0, 0 end
    return left, right
end

-- One rect table per watched frame, reused every check (no per-second garbage).
local rects, pool = {}, {}
-- Aura frames: the widest extent of their icons seen this session, and
-- where the aura frame itself was then (it moving starts over), by name.
local seen, anchor = {}, {}
local fresh = {}   -- a reused accumulator per aura frame until its first icon
-- Why each watched frame counted or not, and how many icons were read, for
-- /gpanel room why.
local why, icons = {}, {}
local editWasOpen = false
local editOpen = false   -- this check's reading, taken once in update()
local measured = "not yet"   -- "yes", "full" (room full: nothing measured), "not yet"

-- A frame's screen rect (l, r, top, bottom in screen px, then its own width
-- and height in its units), or nil when unreadable. Shared with /gpanel
-- covered, so both place a frame the same way.
function Room.ScreenRect(f)
    local l, b, w, h = f:GetRect()
    l, b, w, h = API.Plain(l), API.Plain(b), API.Plain(w), API.Plain(h)
    local s = API.Plain(f:GetEffectiveScale())
    if not (l and b and w and h and s) then return nil end
    return l * s, (l + w) * s, (b + h) * s, b * s, w, h
end
local screenRect = Room.ScreenRect

-- f's children into a reused table per depth: one GetChildren call, no
-- per-second garbage.
local scratch = {}
local function fill(t, ...)
    local n = select("#", ...)
    for i = 1, n do t[i] = (select(i, ...)) end
    for i = n + 1, #t do t[i] = nil end
    return t, n
end
local function children(f, depth)
    local t = scratch[depth] or {}
    scratch[depth] = t
    return fill(t, f:GetChildren())
end

local function grow(acc, l, r, top, bottom)
    if acc.l == nil then
        acc.l, acc.r, acc.top, acc.bottom = l, r, top, bottom
    else
        acc.l, acc.r = math.min(acc.l, l), math.max(acc.r, r)
        acc.top, acc.bottom = math.max(acc.top, top), math.min(acc.bottom, bottom)
    end
end

local function isIcon(w, h)
    return w >= Room.ICON_MIN and h >= Room.ICON_MIN and w <= Room.ICON_MAX and h <= Room.ICON_MAX
end

-- Add the outermost visible icon-sized frames under f to acc, and return
-- how many: a frame within ICON_MIN..ICON_MAX is taken whole (an aura
-- button, whatever small frames it holds); a bigger one (a container) or a
-- smaller one (an anchor the icons hang off, like AuraContainer itself) is
-- looked into.
local function addIcons(f, acc, depth)
    local found = 0
    local kids, n = children(f, depth)
    for i = 1, n do
        local c = kids[i]
        if not c:IsForbidden() and c:IsVisible() then
            local l, r, top, bottom, w, h = screenRect(c)
            if l and isIcon(w, h) then
                grow(acc, l, r, top, bottom)
                found = found + 1
            elseif l and depth < Room.DEPTH then
                found = found + addIcons(c, acc, depth + 1)
            end
        end
    end
    return found
end

-- Whether Edit Mode is open (its example auras fill the grids then).
local function editModeOpen()
    local m = rawget(_G, "EditModeManagerFrame")
    return type(m) == "table" and m.IsShown ~= nil and API.Plain(m:IsShown()) == true
end

-- Frames the player can switch off outright take no room while hidden
-- (one hidden for now keeps its place). A SHOWN frame always counts: Blizzard
-- decides what shows (Edit Mode shows a switched-off meter), not a copy of
-- its rules here.
-- DamageMeter (#40): Blizzard's built-in meter, TOPLEFT of UIParent at 0,0
-- in both presets (measured). Its ShouldBeShown (wow-ui-source forever:
-- Blizzard_DamageMeter/DamageMeter.lua) hides it while the damageMeterEnabled
-- CVar isn't true (nil too) and for Visibility Hidden: those count as off.
-- "Not available" doesn't: it's re-checked on PLAYER_LEVEL_CHANGED, so the
-- meter may appear on a level-up, and keeping its place avoids a jump. Each
-- probe runs under pcall; a probe that throws or reads secret means "not off".
local function damageMeterOff(f)
    local ok, enabled = pcall(function() return C_CVar.GetCVarBool("damageMeterEnabled") end)
    if ok and not API.IsSecret(enabled) and enabled ~= true then
        return "switched off (damageMeterEnabled)"
    end
    local okV, hidden = pcall(function()
        local vis = Enum.DamageMeterVisibility
        return vis ~= nil and vis.Hidden ~= nil and API.Plain(f.visibility) == vis.Hidden
    end)
    if okV and hidden then return "switched off (Visibility: Hidden)" end
end
Room.OFF = { DamageMeter = damageMeterOff }

-- The meter's windows (DamageMeterSessionWindow1..3, MAX_DAMAGE_METER_SESSION_WINDOWS
-- in its code) are its children, but the secondary ones anchor to UIParent
-- and can sit anywhere: their shown rects join the meter's.
Room.EXTRA = { DamageMeter = { "DamageMeterSessionWindow1", "DamageMeterSessionWindow2",
                               "DamageMeterSessionWindow3" } }

-- Fill `out` with f's screen rect; false when it doesn't count (absent,
-- replaced, switched off, unreadable). Called under pcall: never throws out
-- of Room.
local function readRect(f, out, name)
    icons[name] = nil
    if f:IsForbidden() then why[name] = "forbidden" return false end
    if Room.OFF[name] and not f:IsShown() then
        local off = Room.OFF[name](f)
        if off then why[name] = off return false end
    end
    if not f:IsVisible() then
        -- Hidden on its own (it comes back) counts; hidden with its parent doesn't.
        local p = f:GetParent()
        if f:IsShown() or not (p and p:IsVisible()) then why[name] = "replaced (parent hidden)" return false end
    end
    if Room.AURAS[name] then
        -- The aura frame moved or resized (Edit Mode, another addon): start over.
        local fl, fr, ftop, fbottom = screenRect(f)
        local at = anchor[name]
        if not at then
            at = {}
            anchor[name] = at
        elseif at[1] ~= fl or at[2] ~= fr or at[3] ~= ftop or at[4] ~= fbottom then
            seen[name] = nil
        end
        at[1], at[2], at[3], at[4] = fl, fr, ftop, fbottom
        local acc = seen[name]
        if not acc then
            -- Still empty whenever it's here: one icon makes it the session's.
            acc = fresh[name] or {}
            fresh[name] = acc
        end
        icons[name] = 0
        if not editOpen and f:IsVisible() then
            local container = f.AuraContainer
            if type(container) == "table" and container.GetChildren then
                -- One child throwing mustn't drop the extent already known.
                local ok, n = pcall(addIcons, container, acc, 1)
                if ok then icons[name] = n else API.Fail("room:" .. name, n) end
            end
            local button = f.CollapseAndExpandButton
            if type(button) == "table" and button.IsVisible and button:IsVisible() then
                local l, r, top, bottom = screenRect(button)
                if l then grow(acc, l, r, top, bottom) end
            end
        end
        if acc.l == nil then why[name] = "no icons seen this session" return false end
        seen[name], fresh[name] = acc, nil
        out.l, out.r, out.top, out.bottom = acc.l, acc.r, acc.top, acc.bottom
        why[name] = "icons"
        return true
    end
    local l, r, top, bottom = screenRect(f)
    if not l then why[name] = "unreadable" return false end
    out.l, out.r, out.top, out.bottom = l, r, top, bottom
    for _, extra in ipairs(Room.EXTRA[name] or {}) do
        local x = rawget(_G, extra)
        if type(x) == "table" and x.IsShown and x:IsShown() then
            local xl, xr, xtop, xbottom = screenRect(x)
            if xl then grow(out, xl, xr, xtop, xbottom) end
        end
    end
    why[name] = "frame"
    return true
end

function Room.Measure()
    local n = 0
    for i, name in ipairs(Room.WATCH) do
        local f = rawget(_G, name)
        if type(f) == "table" then
            pool[i] = pool[i] or {}
            local ok, counts = pcall(readRect, f, pool[i], name)
            if ok and counts then
                n = n + 1
                rects[n] = pool[i]
            elseif not ok then
                why[name] = "error (see /gpanel failures)"
                API.Fail("room:" .. name, counts)
            end
        else
            why[name] = "absent"
        end
    end
    for i = #rects, n + 1, -1 do rects[i] = nil end
    return rects
end

local current = { 0, 0 }

-- Recompute and, if the insets changed, hand them to the bar.
local function update()
    -- Edit Mode just closed: its examples are gone, the icons may have moved.
    editOpen = editModeOpen()
    if editWasOpen and not editOpen then seen = {} end
    editWasOpen = editOpen
    local Bar = GlassPanel.Bar
    if not (Bar and Bar.frame) then return end
    local left, right = 0, 0
    if GlassPanelDB and GlassPanelDB.room == "full" then
        measured = "full"
    else
        local s = API.Plain(UIParent:GetEffectiveScale())
        local w, top = API.Plain(UIParent:GetWidth()), API.Plain(UIParent:GetTop())
        if not (s and w and top) then return end   -- not laid out yet: next check
        local W, T = w * s, top * s
        left, right = Room.Insets(W, T, T - Bar.HEIGHT * s, Room.Measure())
        left, right = left / s, right / s   -- back to UIParent units for SetPoint
        measured = "yes"
    end
    if left ~= current[1] or right ~= current[2] then
        current[1], current[2] = left, right
        Bar.SetInsets(left, right)
    end
end

-- Never throws: a failure is recorded (/gpanel failures) and the bar stays
-- as it is.
function Room.Update()
    local ok, err = pcall(update)
    if not ok then API.Fail("room", err) end
end

-- A new session: aura frames are measured afresh (the icons may sit
-- elsewhere after a reload, zoning, an Edit Mode or scale change).
function Room.NewSession()
    seen = {}
    Room.Update()
end

-- One line per watched frame from the last check: how it was measured and
-- where it reaches (screen px), for /gpanel room why. Reads only: asking
-- never changes what the bar measures.
function Room.Explain()
    if measured == "full" then return { "room is full: nothing is measured (/gpanel room auto)" } end
    if measured ~= "yes" then return { "not measured yet (the bar isn't laid out)" } end
    local lines = {}
    for i, name in ipairs(Room.WATCH) do
        local w, r = why[name] or "absent", pool[i]
        if (w == "icons" or w == "frame") and r and r.l then
            w = string.format("%s: x %d-%d, top %d, bottom %d", w, r.l, r.r, r.top, r.bottom)
        end
        if Room.AURAS[name] and icons[name] then w = w .. string.format(" (%d icon(s) now)", icons[name]) end
        if Room.AURAS[name] and editOpen then w = w .. " [Edit Mode open: not recording]" end
        lines[#lines + 1] = name .. ": " .. w
    end
    return lines
end

local watcher = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED",
                     "DISPLAY_SIZE_CHANGED" }) do
    API.RegisterEvent(watcher, e, "room")
end
-- Next frame: Edit Mode applies positions after its event. Each of these
-- starts a new session.
watcher:SetScript("OnEvent", function() C_Timer.After(0, Room.NewSession) end)
Engine.EverySecond("room", Room.Update)
