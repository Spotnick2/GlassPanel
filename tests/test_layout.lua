-- Free lanes and drag and drop (#6).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local L
local function lanes()
    local out = {}
    for _, lane in ipairs(L.Lanes()) do
        out[#out + 1] = string.format("%g:%s", lane.x, table.concat(lane.ids, ","))
    end
    return table.concat(out, " | ")
end

-- Defaults come from each block's side and order.
loadAddon()
L = GlassPanel.Layout
eq(lanes(), "0:xp,gold | 1:clock", "default lanes")
eq(leftOf("xp"), 8, "xp starts at the left edge")
eq(leftOf("gold"), 8 + 360 + 8, "gold follows xp")
check(leftOf("clock") > 900, "clock at the right edge")
eq(GlassPanelDB.layout, nil, "nothing saved until the user moves something")

-- /gpanel move: xp to the right lane, next to the edge.
GlassPanel._test.slash("move xp right")
eq(lanes(), "0:gold | 1:clock,xp", "xp joined the right lane")
eq(leftOf("xp"), 1000 - 8 - 360, "xp against the right edge")
check(leftOf("clock") < leftOf("xp"), "clock now left of xp")
eq(leftOf("gold"), 8, "gold slid to the edge")

-- Drag gold onto empty space: a new lane, centred where it was dropped.
dragTo("gold", 500)
eq(lanes(), "0.5:gold | 1:clock,xp", "new lane at 50%; the emptied left lane is gone")
local gw = block("gold").widget._width
eq(leftOf("gold"), 500 - gw / 2, "centred on the anchor")
eq(#GlassPanelDB.layout, 2, "no empty lane saved")

-- Drag near a gap: joins that lane at that spot.
dragTo("clock", leftOf("xp") + 360 + 6)          -- just right of xp
eq(lanes(), "0.5:gold | 1:xp,clock", "clock dropped after xp")
dragTo("clock", leftOf("xp") - 4)                -- just left of xp
eq(lanes(), "0.5:gold | 1:clock,xp", "and back before it")

-- Near the ends snaps to the edge lanes.
dragTo("gold", 20)
eq(lanes(), "0:gold | 1:clock,xp", "a drop near the left end makes an edge lane")

-- Shift-drag moves the whole lane.
GlassPanel._test.slash("move clock 30")
eq(lanes(), "0:gold | 0.3:clock | 1:xp", "clock in its own lane at 30%")
dragTo("clock", 700, true)
eq(lanes(), "0:gold | 0.7:clock | 1:xp", "shift-drag moved the lane")
dragTo("clock", 995, true)
eq(lanes(), "0:gold | 1:xp,clock", "a lane moved onto another's anchor merges into it")

-- The release that ends a drag is not a click; a later click is.
local clicks = 0
block("gold").onClick = function() clicks = clicks + 1 end
local gb = block("gold").widget
dragTo("gold", 20)
gb._scripts.OnClick(gb, "LeftButton")
eq(clicks, 0, "click right after a drag ignored")
WoW.now = WoW.now + 1
gb._scripts.OnClick(gb, "LeftButton")
eq(clicks, 1, "a later click goes through")

-- The drop marker follows the cursor while dragging.
gb._scripts.OnDragStart(gb)
eq(gb._alpha, 0.4, "dragged block dimmed")
WoW.cursor = { leftOf("gold") + 3, 0 }; WoW.tick()
eq(GlassPanel.Bar.marker._shown, false, "no marker over the block's own spot")
WoW.cursor = { 500, 0 }; WoW.tick()
eq(GlassPanel.Bar.marker._shown, true, "marker shown away from it")
eq(GlassPanel.Bar.marker._points[1][4], 500, "marker at the cursor for a new lane")
gb._scripts.OnDragStop(gb)
eq(GlassPanel.Bar.marker._shown, false, "marker hidden after the drop")
eq(gb._alpha, 1, "block opaque again")

-- UI scale: the cursor comes in screen pixels.
GlassPanel._test.slash("layout reset")
eq(lanes(), "0:xp,gold | 1:clock", "layout reset")
eq(GlassPanelDB.layout, nil, "reset clears the saved layout")
WoW.uiScale = 0.64
dragTo("gold", 600)
eq(lanes(), "0:xp | 0.6:gold | 1:clock", "cursor scaled into bar units")
WoW.uiScale = 1

-- Hidden blocks keep their slot: drop indexes count them.
GlassPanelDB.layout = { { x = 0, ids = { "xp", "gold", "clock" } } }
GlassPanelDB.hidden.gold = true
GlassPanel.Bar.Layout()
eq(leftOf("clock"), 8 + 360 + 8, "clock takes the hidden gold's space")
-- Drop a new block between xp and clock (the gap where gold would be).
GlassPanel.RegisterBlock({ id = "extra", text = function() return "x" end, side = "right" })
WoW.tick()
dragTo("extra", 8 + 360 + 4)
eq(lanes(), "0:xp,gold,extra,clock", "inserted before the next visible block, after the hidden one")
GlassPanelDB.hidden.gold = nil

-- Ids of blocks that aren't loaded stay in the layout, invisible.
GlassPanelDB.layout = { { x = 0, ids = { "layer", "xp" } }, { x = 1, ids = { "gold", "clock" } } }
GlassPanel.Bar.Layout()
eq(leftOf("xp"), 8, "a missing module takes no space")
GlassPanel._test.slash("move xp right")
eq(lanes(), "0:layer | 1:extra,gold,clock,xp", "its id keeps its lane; the unplaced extra joins its default lane, far from the edge")
local listed = false
GlassPanel._test.slash("list")
for _, l in ipairs(WoW.chat) do if l:find("layer (not loaded)", 1, true) then listed = true end end
check(listed, "/gpanel list shows it as not loaded")

-- A malformed saved layout is ignored, not fatal.
GlassPanelDB.layout = { { x = "left", ids = { "xp" } }, { x = 2, ids = {} }, "junk", { x = 0.5, ids = { 42, "gold" } } }
eq(lanes(), "0:xp | 0.5:gold | 1:extra,clock", "bad entries dropped, good ones kept")

-- Pure model: a centred lane stays on screen.
local geo = L.Place({ { x = 0.95, ids = { "a" } } }, 1000, function() return 360 end)
eq(geo[1].items[1].left, 1000 - 8 - 360, "clamped at the right end")
geo = L.Place({ { x = 0.05, ids = { "a" } } }, 1000, function() return 360 end)
eq(geo[1].items[1].left, 8, "clamped at the left end")

-- Review fixes (#8). A fresh session: no leftover test blocks.
loadAddon()
L = GlassPanel.Layout
GlassPanelDB.hidden.xp = true
GlassPanel.Bar.Layout()
eq(lanes(), "0:xp,gold | 1:clock", "gold alone on screen in the left lane (xp hidden)")
-- A click that wobbles a pixel is a drag onto the block's own spot: no move.
dragTo("gold", leftOf("gold") + 30)
eq(GlassPanelDB.layout, nil, "a drag onto its own spot changes nothing")
eq(leftOf("gold"), 8, "gold still at the edge")
GlassPanelDB.hidden.xp = nil

-- A drag whose block is hidden mid-drag ends cleanly: no stuck marker or clicks.
GlassPanel.Bar.Layout()
clicks = 0
block("gold").onClick = function() clicks = clicks + 1 end
gb = block("gold").widget
gb._scripts.OnDragStart(gb)
WoW.cursor = { 500, 0 }; WoW.tick()
GlassPanel._test.slash("hide gold")
eq(GlassPanel.Bar.marker._shown, false, "marker gone when the dragged block hides")
eq(gb._alpha, 1, "block restored")
GlassPanel._test.slash("show gold")
WoW.now = WoW.now + 1
gb._scripts.OnClick(gb, "LeftButton")
eq(clicks, 1, "clicks work again")
-- Same when the whole bar is toggled off mid-drag.
gb._scripts.OnDragStart(gb)
GlassPanel._test.slash("toggle")
GlassPanel._test.slash("toggle")
WoW.now = WoW.now + 1
gb._scripts.OnClick(gb, "LeftButton")
eq(clicks, 2, "clicks work after the bar was hidden mid-drag")

-- /gpanel move with a rounded % reaches a dragged lane.
dragTo("clock", 637)
local x = L.Lanes()[2].x
check(x > 0.63 and x < 0.64, "clock lane at a fractional anchor (" .. x .. ")")
GlassPanel._test.slash("move gold 64 1")
eq(#L.Lanes(), 2, "joined the lane /gpanel list showed as 64%, not a new one")
check(L.Lanes()[2].ids[1] == "gold", "gold first in that lane")

-- Shift-dragging a lane near an edge snaps like a drop does (48 px, not 2%).
GlassPanel._test.slash("layout reset")
GlassPanel._test.slash("move clock 50")
dragTo("clock", 1000 - 45, true)
eq(lanes(), "0:xp,gold | 1:clock", "lane snapped to the right edge")

-- Bad /gpanel move arguments print the usage, not "no block 'nil'".
WoW.chat = {}
GlassPanel._test.slash("move gold")
check(WoW.chat[1] and WoW.chat[1]:find("usage"), "usage shown")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_layout")
