-- Making room for the bar (#2).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- /gpanel covered: what the bar sits on, outermost frames only.
loadAddon()
local function frame(name, rect, opts)
    local f = CreateFrame("Frame", name, UIParent)
    f._rect = rect
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end
local minimap = frame("MinimapCluster", { 800, 560, 200, 208 }, { _strata = "LOW", _mouse = true })
frame("MinimapZoneText", { 820, 750, 120, 14 })._parent = minimap   -- nested: implied by the cluster
frame("BuffFrame", { 500, 700, 280, 60 }, { _protected = true })
frame("ChatFrame1", { 20, 40, 400, 200 })                             -- far below
frame("FullscreenLayer", { 0, 0, 1000, 768 })                         -- full-screen: ignored
local hidden = frame("HiddenThing", { 10, 750, 50, 10 }); hidden._shown = false

local names = {}
for _, e in ipairs(GlassPanel._test.coveredFrames()) do names[#names + 1] = e.name end
table.sort(names)
eq(table.concat(names, ","), "BuffFrame,MinimapCluster", "covered frames: outermost, visible, not full-screen, not ours")

GlassPanel._test.slash("covered")
local found = false
for _, l in ipairs(WoW.chat) do if l:find("BuffFrame  MEDIUM PROTECTED", 1, true) then found = true end end
check(found, "/gpanel covered prints strata and protection")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_room")
