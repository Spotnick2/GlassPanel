-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any method call (a no-op for ones it does not implement),
-- so a call to a method Forever lacks would otherwise pass silently. This
-- checks each recorded "Type:Method" against the API dump's widget-method walk.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = WoW.DUMP
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
    w._scripts.OnDragStart(w); WoW.tick(); w._scripts.OnDragStop(w)
end
do
    -- XP+ zoomed (#78): its own frame, built on the first zoom, so driven here.
    local xp = GlassPanel.Engine.byId.xp
    local w = xp.widget
    WoW.now = WoW.now + 1   -- past the drags above: a click right after one is ignored
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    local f = xp._test.float()
    f._scripts.OnEnter(f); f._scripts.OnLeave(f)
    WoW.shift = true; f._scripts.OnDragStart(f); WoW.shift = false
    f._center = { 600, 600 }; f._scripts.OnDragStop(f)
    WoW.now = WoW.now + 1
    f._scripts.OnClick(f, "RightButton")
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
end
GlassPanel._test.slash("font friz")
GlassPanel._test.slash("hide gold")
GlassPanel._test.slash("toggle")
GlassPanel._test.slash("list")
GlassPanel._test.slash("move gold 40")
GlassPanel._test.slash("layout reset")
GlassPanel._test.slash("failures")
GlassPanel._test.slash("covered")
GlassPanel._test.slash("icon bags off")
GlassPanel._test.slash("export")
GlassPanel._test.slash("import")
do
    local win = GlassPanel.Share._test.window()
    win.edit._scripts.OnTextChanged(win.edit, true)
    win.action._scripts.OnClick(win.action)
    win.close._scripts.OnClick(win.close)
end
do
    local o = GlassPanel.Options._test
    o.panel:Hide(); o.panel:Show()
    local r = o.rows.gold
    r.shown._scripts.OnClick(r.shown); r.caption._scripts.OnClick(r.caption)
    o.controls.labels._scripts.OnClick(o.controls.labels)
    o.controls.font[2]._scripts.OnClick(o.controls.font[2])
    GlassPanel._test.slash("options")
end
do
    local cb = GlassPanel.Engine.byId.currencies
    if cb and cb.options then cb.options[1].run() end
end
do
    -- The ammo thresholds window (a hunter, so it opens), saved and reset.
    local ab = GlassPanel.Engine.byId.ammo
    if ab then
        WoW.playerClass = { "Hunter", "HUNTER", 3 }
        ab.options[1].run()
        local win = ab._test.window()
        win.save._scripts.OnClick(win.save)
        win.reset._scripts.OnClick(win.reset)
    end
end
GlassPanel._test.slash("setup")
GlassPanel._test.slash("setup back")
WoW.tick(1.1); WoW.tick()

local ANIMATION_TYPES = { Animation = true, Alpha = true, Translation = true, Scale = true, Rotation = true }
local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local wtype, method = name:match("^(%a+):(%a+)$")
    -- The dump's widget walk has no animation subtypes (Alpha:SetToAlpha,
    -- Translation:SetOffset): for those alone, a documented function will do.
    check(widget[name] or (ANIMATION_TYPES[wtype] and documented[method]), "method exists on Forever: " .. name)
end
check(n > 25, "recorded a realistic number of methods (" .. n .. ")")
done("test_methods")
