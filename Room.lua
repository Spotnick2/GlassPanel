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
-- Which frames count: one hidden ON ITS OWN (no target, no buffs, no focus)
-- still counts where Edit Mode put it, so the bar's width doesn't jump every
-- time you target something; one whose PARENT is hidden has been replaced by
-- another addon (GlassUnitFrames reparents Blizzard's unit frames to a hidden
-- frame) and doesn't count. A frame centred in the middle fifth of the screen
-- is ignored: the bar's two ends can't route around it.
--
-- Read-only on Blizzard frames: GetRect/IsShown/IsVisible only, under pcall,
-- every number through API.Plain. Checked on layout/scale/display events and
-- on the engine's once-a-second clock.

GlassPanel = GlassPanel or {}
local API, Engine = GlassPanel.API, GlassPanel.Engine
local Room = {}
GlassPanel.Room = Room

-- Blizzard frames the bar gives way to when they reach into its band. The
-- list comes from /gpanel covered measurements (#2); a frame not on it is
-- simply drawn over, as before.
Room.WATCH = { "MinimapCluster", "BuffFrame", "DebuffFrame", "TicketStatusFrame",
               "PlayerFrame", "TargetFrame", "FocusFrame" }
Room.MARGIN = 6        -- px between the bar's end and the frame it gives way to
Room.MIN_WIDTH = 300   -- px: narrower than this, the bar keeps the full width
Room.MIDDLE = 0.2      -- a frame centred in this middle fraction of the screen is ignored

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

-- Fill `out` with f's screen rect; false when it doesn't count (absent,
-- replaced, unreadable). Called under pcall: never throws out of Room.
local function readRect(f, out)
    if f:IsForbidden() then return false end
    if not f:IsVisible() then
        -- Hidden on its own (it comes back) counts; hidden with its parent doesn't.
        local p = f:GetParent()
        if f:IsShown() or not (p and p:IsVisible()) then return false end
    end
    local l, b, w, h = f:GetRect()
    l, b, w, h = API.Plain(l), API.Plain(b), API.Plain(w), API.Plain(h)
    local s = API.Plain(f:GetEffectiveScale())
    if not (l and b and w and h and s) then return false end
    out.l, out.r, out.top, out.bottom = l * s, (l + w) * s, (b + h) * s, b * s
    return true
end

function Room.Measure()
    local n = 0
    for i, name in ipairs(Room.WATCH) do
        local f = rawget(_G, name)
        if type(f) == "table" then
            pool[i] = pool[i] or {}
            local ok, counts = pcall(readRect, f, pool[i])
            if ok and counts then
                n = n + 1
                rects[n] = pool[i]
            end
        end
    end
    for i = #rects, n + 1, -1 do rects[i] = nil end
    return rects
end

local current = { 0, 0 }

-- Recompute and, if the insets changed, hand them to the bar.
local function update()
    local Bar = GlassPanel.Bar
    if not (Bar and Bar.frame) then return end
    local left, right = 0, 0
    if not (GlassPanelDB and GlassPanelDB.room == "full") then
        local s = API.Plain(UIParent:GetEffectiveScale())
        local w, top = API.Plain(UIParent:GetWidth()), API.Plain(UIParent:GetTop())
        if not (s and w and top) then return end   -- not laid out yet: next check
        local W, T = w * s, top * s
        left, right = Room.Insets(W, T, T - Bar.HEIGHT * s, Room.Measure())
        left, right = left / s, right / s   -- back to UIParent units for SetPoint
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

local watcher = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED",
                     "DISPLAY_SIZE_CHANGED" }) do
    API.RegisterEvent(watcher, e, "room")
end
-- Next frame: Edit Mode applies positions after its event.
watcher:SetScript("OnEvent", function() C_Timer.After(0, Room.Update) end)
Engine.EverySecond("room", Room.Update)
