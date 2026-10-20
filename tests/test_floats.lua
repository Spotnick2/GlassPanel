-- Floats (#108): zoomed floats stack in default slots and snap apart on a drop.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ plugins = false })
local F = GlassPanel.Floats
local API = GlassPanel.API

-- Pure: Snap(rect, others) -> the smallest shift that clears every other rect, GAP apart.
local function r(l, b, w, h) return { l = l, r = l + w, b = b, t = b + h } end
local dx, dy = F.Snap(r(0, 0, 100, 20), {})
eq(dx .. "," .. dy, "0,0", "nothing around: stays")
dx, dy = F.Snap(r(0, 0, 100, 20), { r(200, 0, 50, 20) })
eq(dx .. "," .. dy, "0,0", "clear of the other: stays")
dx, dy = F.Snap(r(0, 0, 100, 20), { r(0, 10, 100, 20) })
eq(dx .. "," .. dy, "0,-" .. (20 - 10 + F.GAP), "overlapping from below: moves down by the overlap + GAP")
dx, dy = F.Snap(r(0, 15, 100, 20), { r(0, 10, 100, 20) })
eq(dx .. "," .. dy, "0," .. (30 - 15 + F.GAP), "mostly above: moves up (the smaller shift)")
dx, dy = F.Snap(r(90, 0, 100, 20), { r(0, 0, 100, 20) })
eq(dx .. "," .. dy, (100 - 90 + F.GAP) .. ",0", "overlapping at its side: moves sideways")
-- Two others in the way: clear of both.
dx, dy = F.Snap(r(0, 0, 100, 20), { r(0, 0, 100, 20), r(0, 28, 100, 20) })
local out = r(dx, dy, 100, 20)
for _, o in ipairs({ r(0, 0, 100, 20), r(0, 28, 100, 20) }) do
    check(not (out.l < o.r and out.r > o.l and out.b < o.t and out.t > o.b), "a stack of two: clear of both")
end

-- Registration.
local function frame(w, h)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(w, h)
    return f
end
local placedA, placedB = false, false
local placesA, placesB = 0, 0
local a, b = frame(480, 46), frame(92, 26)
check(API.RegisterFloat(a, { order = 1, placed = function() return placedA end, place = function() placesA = placesA + 1 end }), "registered")
eq(API.RegisterFloat(a, { order = 1, placed = function() return false end, place = function() end }), false, "a frame registers once")
eq(API.RegisterFloat(b, { order = "x", placed = function() return false end, place = function() end }), false, "order must be a number")
check(API.RegisterFloat(b, { order = 2, placed = function() return placedB end, place = function() placesB = placesB + 1 end }), "second registered")
check(#GlassPanel.Edge._test.tracked() >= 2, "floats are tracked for the top edge too")

-- Default slots: below every shown, unplaced float of lower order.
a:Hide(); b:Show()
eq(API.FloatDefaultY(a), F.TOP, "the first slot")
eq(API.FloatDefaultY(b), F.TOP, "alone, the second float takes the first slot")
a:Show()
eq(API.FloatDefaultY(a), F.TOP, "order 1 never moves for a later float")
eq(API.FloatDefaultY(b), F.TOP - 46 - F.GAP, "the second sits under the first's height + GAP")
placedA = true
eq(API.FloatDefaultY(b), F.TOP, "a saved spot takes no slot: the pill goes back up")
placedA = false

-- PlaceFloats: every shown unplaced float, once.
placesA, placesB = 0, 0
API.PlaceFloats()
eq(placesA .. "," .. placesB, "1,1", "shown and unplaced: placed")
placedA = true
API.PlaceFloats()
eq(placesA .. "," .. placesB, "1,2", "a saved one is left where it is")
b:Hide()
API.PlaceFloats()
eq(placesA .. "," .. placesB, "1,2", "a hidden one isn't placed")
placedA = false
-- A throwing place is recorded, never raised.
local bad = frame(10, 10)
API.RegisterFloat(bad, { order = 3, placed = function() return false end, place = function() error("boom") end })
bad:Show()
API.PlaceFloats()
check(GlassPanel.failures["float:place"] ~= nil, "a throwing place is recorded")
GlassPanel.failures["float:place"] = nil
bad:Hide()

-- SnapFloat: a frame dropped on another is moved clear, anchored from the screen's corner.
UIParent._rect = UIParent._rect or { 0, 0, UIParent._width or 1920, UIParent._height or 1080 }
a._rect, b._rect = { 500, 800, 480, 46 }, { 600, 820, 92, 26 }
a:Show(); b:Show()
eq(API.SnapFloat(b), true, "overlapping: it moves")
local pt = b._points[#b._points]
eq(pt[1], "CENTER", "anchored by its centre")
eq(pt[3], "BOTTOMLEFT", "...from the screen's bottom left")
local cx, cy = pt[4], pt[5]
local mine = r(cx - 46, cy - 13, 92, 26)
check(not (mine.l < 980 and mine.r > 500 and mine.b < 846 and mine.t > 800), "now clear of the other float")
b._rect = { 1200, 300, 92, 26 }
eq(API.SnapFloat(b), false, "clear of everything: untouched")
eq(API.SnapFloat(frame(5, 5)), false, "an unregistered frame: untouched")
a:Hide()
b._rect = { 600, 820, 92, 26 }
eq(API.SnapFloat(b), false, "a hidden float is not an obstacle")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_floats")
