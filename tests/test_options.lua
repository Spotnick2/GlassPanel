-- The options panel (#24): Options > AddOns > Glass Panel.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelGold", "GlassPanelClock", "GlassPanelBags", "GlassPanelXP" }

local function O() return GlassPanel.Options._test end
local function open() local p = O().panel; p:Hide(); p:Show() end
local function click(cb, checked)
    if checked ~= nil then cb:SetChecked(checked) end
    cb._scripts.OnClick(cb, "LeftButton")
    WoW.tick()
end

loadAddon()
-- Registered with the Settings framework at login.
eq(WoW.settings.canvas and WoW.settings.canvas.frame, O().panel, "canvas category for the panel")
eq(WoW.settings.canvas and WoW.settings.canvas.name, "Glass Panel", "named Glass Panel")
eq(WoW.settings.addon, WoW.settings.canvas, "listed under AddOns")
GlassPanel._test.slash("options")
eq(WoW.settings.opened, 4242, "/gpanel options opens it")

open()
local rows, c = O().rows, O().controls
-- The scroll bar shows only when there's something to scroll (#36).
local sc = O().scroll
eq(sc.ScrollBar._shown, false, "nothing to scroll: no scroll bar")
sc._scripts.OnScrollRangeChanged(sc, 0, 120)
eq(sc.ScrollBar._shown, true, "taller content: scroll bar")
sc._scripts.OnScrollRangeChanged(sc, 0, 0)
eq(sc.ScrollBar._shown, false, "fits again: hidden")
sc._scripts.OnScrollRangeChanged(sc, 0, 0.4)
eq(sc.ScrollBar._shown, false, "under a unit (fractional scale): nothing to scroll, as the template rounds")
-- One row per loaded plugin, in name order.
check(rows.gold and rows.clock and rows.bags and rows.xp, "a row per plugin")
local order = {}
for id, r in pairs(rows) do order[#order + 1] = { id = id, y = r.name._points[1][5] } end
table.sort(order, function(a, b) return a.y > b.y end)
local ids = {}
for _, o in ipairs(order) do ids[#ids + 1] = o.id end
eq(table.concat(ids, ","), "bags,clock,gold,xp", "sorted by name (Bags, Clock, Gold, XP+)")

-- The rows read the current state.
eq(rows.bags.shown:GetChecked(), true, "shown")
eq(rows.bags.caption:GetChecked(), true, "Bags: caption on by default")
eq(rows.gold.caption:GetChecked(), false, "Gold: off by default (showLabel = false)")
eq(rows.bags.icon:GetChecked(), true, "Bags: icon on")
eq(rows.xp.caption._disabled, true, "graphical block: caption greyed out")
eq(rows.gold.icon._disabled, true, "no icon: icon greyed out")
eq(rows.bags.icon._disabled, false, "an icon: toggle live")

-- Each toggle changes the bar, through the same setters as /gpanel.
click(rows.bags.shown, false)
eq(GlassPanelDB.hidden.bags, true, "Shown off: hidden")
eq(block("bags").widget._shown, false, "and off the bar")
click(rows.bags.shown, true)
eq(GlassPanelDB.hidden.bags, nil, "Shown on: back")
click(rows.bags.icon, false)
eq(GlassPanelDB.iconsFor.bags, false, "Icon off")
eq(block("bags").widget.icon._shown, false, "icon hidden on the bar")
click(rows.gold.caption, true)
eq(block("gold").widget.caption._text, "Gold: ", "Caption on for Gold")

-- Bar settings.
click(c.shown, false)
eq(GlassPanelDB.shown, false, "Show the bar: off")
eq(GlassPanel.Bar.frame._shown, false, "bar hidden")
click(c.shown, true)
click(c.labels, false)
eq(GlassPanelDB.labels, false, "captions off everywhere")
eq(block("clock").widget.caption._text, "", "clock follows the global setting")
eq(rows.gold.caption:GetChecked(), true, "Gold's own 'on' still wins (and the row says so)")
eq(rows.bags.caption:GetChecked(), false, "Bags follows the global: the row updated at once")
click(c.labels, true)
click(c.font[2])
eq(GlassPanelDB.font, "friz", "font radio")
eq(c.font[1]:GetChecked(), false, "the other radio unchecked")
eq(c.font[2]:GetChecked(), true, "this one checked")
click(c.room[2])
eq(GlassPanelDB.room, "full", "width radio")

-- A change made with /gpanel shows the next time the panel opens.
GlassPanel._test.slash("hide gold")
GlassPanel._test.slash("font arial")
open()
eq(rows.gold.shown:GetChecked(), false, "slash change reflected: hidden")
eq(c.font[1]:GetChecked(), true, "slash change reflected: font")

-- Layout reset.
GlassPanel._test.slash("move gold 40")
check(GlassPanelDB.layout ~= nil, "(a layout was saved)")
c.reset._scripts.OnClick(c.reset)
eq(GlassPanelDB.layout, nil, "Reset layout")

-- Share buttons open the export / import window.
c.export._scripts.OnClick(c.export)
local win = GlassPanel.Share._test.window()
eq(win._shown and win.mode, "export", "Export... opens the export window")
c.import._scripts.OnClick(c.import)
eq(win.mode, "import", "Import... opens the import window")
win:Hide()

-- Plugins that register later get rows the next time the panel opens,
-- where their names sort among all the others.
GlassPanel.RegisterBlock({ id = "zed", label = "Zed", text = function() return "x" end })
GlassPanel.RegisterBlock({ id = "late", label = "Alpha", text = function() return "x" end })
eq(rows.late, nil, "(no row yet)")
open()
check(rows.late ~= nil and rows.zed ~= nil, "late plugins' rows added")
local yXp, yAlpha, yZed = rows.xp.name._points[1][5], rows.late.name._points[1][5], rows.zed.name._points[1][5]
check(yAlpha > rows.bags.name._points[1][5], "Alpha sorts first, above Bags")
check(yXp > yZed, "Zed sorts last, below XP+")

-- While the panel is open, any change shows at once: a /gpanel command,
-- an import. A stale box would write the opposite of what the user meant.
open()
eq(rows.gold.shown:GetChecked(), false, "(gold hidden)")
GlassPanel._test.slash("show gold")
eq(rows.gold.shown:GetChecked(), true, "slash change shown at once while open")
local setup = GlassPanel.Share.Current()
setup.shown, setup.font = false, "friz"
GlassPanel.Share.Apply(setup)
eq(c.shown:GetChecked(), false, "import shown at once: bar off")
eq(c.font[2]:GetChecked(), true, "import shown at once: font")
GlassPanel.Settings.SetShown(true)
-- Closed: nothing to refresh (and nothing runs).
O().panel:Hide()
local before = rows.gold.shown:GetChecked()
GlassPanel._test.slash("hide gold")
eq(rows.gold.shown:GetChecked(), before, "closed panel isn't touched")

-- Plugin options (spec.options): a checkbox per option under "Plugin
-- options"; a throwing get or set is recorded, never raised.
local flag = false
GlassPanel.RegisterBlock({ id = "opty", label = "Opty", text = function() return "o" end,
    options = { { label = "Do the thing", note = "A note.", get = function() return flag end,
                  set = function(v) flag = v end },
                { label = "Broken", get = function() error("get broke") end,
                  set = function() error("set broke") end } } })
open()
local ob = c["options:opty:1"]
check(ob ~= nil and ob.label._text == "Do the thing", "plugin option on the panel")
eq(ob:GetChecked(), false, "reads get()")
click(ob, true)
eq(flag, true, "click calls set()")
local bad = c["options:opty:2"]
click(bad, true)
check(GlassPanel.failures["options:opty:2"] ~= nil, "a throwing set is recorded")
check(next(GlassPanel.failures) ~= nil, "(a throwing get too)")
for k in pairs(GlassPanel.failures) do GlassPanel.failures[k] = nil end

-- A category whose GetID throws: /gpanel options falls back to the hint.
do
    local cat = O().category()
    local realGetID = cat.GetID
    cat.GetID = function() error("no id on this build") end
    eq(GlassPanel.Options.Open(), false, "GetID throwing: Open says false")
    cat.GetID = realGetID
end

-- No Settings framework: nothing throws, the slash says where it would be.
local realSettings = Settings
Settings = nil
loadAddon()
Settings = realSettings
eq(GlassPanel.Options.Open(), false, "can't open without the framework")
WoW.chat = {}
GlassPanel._test.slash("options")
check((WoW.chat[1] or ""):find("Options > AddOns > Glass Panel", 1, true), "says where to find it")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_options")
