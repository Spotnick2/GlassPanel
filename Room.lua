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
-- Writing a GlassPanel Edit Mode layout with them lowered is a separate,
-- opt-in setup.
--
-- Read-only on Blizzard frames: GetRect/IsVisible only, under pcall, secrets
-- skipped. Checked on layout/scale/display events and once a second (buffs
-- come and go without an event we'd want to hook on their frames).

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local Room = {}
GlassPanel.Room = Room

-- Blizzard frames the bar gives way to when they reach into its band. The
-- list comes from /gpanel covered measurements (#2); a frame not on it is
-- simply drawn over, as before.
Room.WATCH = { "MinimapCluster", "BuffFrame", "DebuffFrame", "TicketStatusFrame",
               "PlayerFrame", "TargetFrame", "FocusFrame" }
Room.MARGIN = 6        -- px between the bar's end and the frame it gives way to
Room.MIN_WIDTH = 300   -- px: narrower than this, the bar keeps the full width

-- Pure. W: the screen width; bandTop/bandBottom: the bar's band (screen px,
-- y up); rects: { l, r, top, bottom } in screen px. A rect in the band sits on
-- the left or the right by its centre, and pushes that end of the bar in.
-- Returns the left and right insets in screen px.
function Room.Insets(W, bandTop, bandBottom, rects)
    local left, right = 0, 0
    for _, r in ipairs(rects) do
        if r.bottom < bandTop and r.top > bandBottom and r.r > r.l then
            if (r.l + r.r) / 2 < W / 2 then
                left = math.max(left, r.r + Room.MARGIN)
            else
                right = math.max(right, W - r.l + Room.MARGIN)
            end
        end
    end
    if W - left - right < Room.MIN_WIDTH then return 0, 0 end
    return left, right
end

-- The screen rect of a named Blizzard frame, or nil (absent, hidden,
-- unreadable). Never throws, never compares a secret.
local function rectOf(name)
    local f = rawget(_G, name)
    if type(f) ~= "table" then return nil end
    local ok, r = pcall(function()
        if f:IsForbidden() or not f:IsVisible() then return nil end
        local l, b, w, h = f:GetRect()
        l, b, w, h = API.Plain(l), API.Plain(b), API.Plain(w), API.Plain(h)
        if not (l and b and w and h) then return nil end
        local s = API.Plain(f:GetEffectiveScale())
        if not s then return nil end
        return { l = l * s, r = (l + w) * s, top = (b + h) * s, bottom = b * s }
    end)
    return ok and r or nil
end

function Room.Measure()
    local rects = {}
    for _, name in ipairs(Room.WATCH) do
        local r = rectOf(name)
        if r then rects[#rects + 1] = r end
    end
    return rects
end

local current = { 0, 0 }

-- Recompute and, if the insets changed, hand them to the bar.
function Room.Update()
    local Bar = GlassPanel.Bar
    if not (Bar and Bar.frame) then return end
    local left, right = 0, 0
    if not (GlassPanelDB and GlassPanelDB.room == "full") then
        local s = UIParent:GetEffectiveScale()
        local W, top = UIParent:GetWidth() * s, UIParent:GetTop() * s
        left, right = Room.Insets(W, top, top - Bar.HEIGHT * s, Room.Measure())
        left, right = left / s, right / s   -- back to UIParent units for SetPoint
    end
    if left ~= current[1] or right ~= current[2] then
        current[1], current[2] = left, right
        Bar.SetInsets(left, right)
    end
end

function Room.Current() return current[1], current[2] end

local watcher = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "UI_SCALE_CHANGED",
                     "DISPLAY_SIZE_CHANGED" }) do
    API.RegisterEvent(watcher, e, "room")
end
-- Next frame: Edit Mode applies positions after its event.
watcher:SetScript("OnEvent", function() C_Timer.After(0, Room.Update) end)
local acc = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 1 then return end
    acc = 0
    Room.Update()
end)
