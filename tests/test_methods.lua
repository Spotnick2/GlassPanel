-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method walk.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSPANEL_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"
local f = io.open(DUMP, "r")
if not f then
    io.write("test_methods: SKIPPED (no API dump at " .. DUMP .. ")\n")
    os.exit(0)
end
local widget, documented = {}, {}
for line in f:lines() do
    local wm = line:match("^(%a+:%a+)%s*$")
    if wm then widget[wm] = true end
    local fn = line:match("^([%a_]+)%(")
    if fn then documented[fn] = true end
end
f:close()

-- Exercise everything so every method is recorded.
loadAddon()
for _, blk in ipairs(GlassPanel.Engine.blocks) do
    local w = blk.widget
    w._scripts.OnEnter(w); w._scripts.OnLeave(w); w._scripts.OnClick(w, "LeftButton")
end
GlassPanel._test.slash("font friz")
GlassPanel._test.slash("hide gold")
GlassPanel._test.slash("toggle")
GlassPanel._test.slash("list")
GlassPanel._test.slash("failures")
WoW.tick(1.1); WoW.tick()

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    check(widget[name] or documented[method], "method exists on Forever: " .. name)
end
check(n > 25, "recorded a realistic number of methods (" .. n .. ")")
done("test_methods")
