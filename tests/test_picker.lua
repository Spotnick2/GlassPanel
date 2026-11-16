-- API.Picker (#74): the chooser window shared by Currencies and Reagents. Their
-- own tests cover how each fills it; this is the helper's contract, on a
-- stand-in spec.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ plugins = false })
local API = GlassPanel.API

-- Offered: a, b, c (listed in that order when not picked). Saved: the order.
local items = { { id = "a", n = "Alpha" }, { id = "b", n = "Bravo" }, { id = "c", n = "Charlie" } }
local saved = { "b", "x" }   -- x: saved, not resolvable now
local extra = {}             -- ids resolve() knows although items() doesn't offer them
local saves = 0
local p = API.Picker({
    name = "TestPickerWindow", title = "Pick", hint = "Tick to show.", empty = "Nothing here.",
    items = function() return items end,
    picks = function(offered)
        check(offered == items, "picks() gets the items")
        return saved
    end,
    resolve = function(id) return extra[id] end,
    save = function(order) saves = saves + 1; saved = order end,
    label = function(e) return "[" .. e.n .. "]" end,
})

local function visibleRows()
    local out = {}
    for _, r in ipairs(p.rows) do
        if r._shown then out[#out + 1] = r.id .. (r.check:GetChecked() and "+" or "") end
    end
    return table.concat(out, " ")
end
local function rowOf(id)
    for _, r in ipairs(p.rows) do if r._shown and r.id == id then return r end end
end

eq(p.Window(), nil, "not built until opened")
p.Refresh()   -- before the window exists: nothing to do
p.Open()
local win = p.Window()
check(win ~= nil and win:IsShown(), "Open builds and shows it")
eq(win.title:GetText(), "Pick", "its title")
eq(win.hint:GetText(), "Tick to show.", "its hint")
eq(visibleRows(), "b+ a c", "the picked first (resolvable ones), then the rest in items() order")
eq(rowOf("b").text:GetText(), "[Bravo]", "label(entry) is the row's text")
eq(rowOf("b").up:IsShown(), true, "a picked row has Up/Down")
eq(rowOf("a").up:IsShown(), false, "an unpicked one doesn't")

-- Tick: appended to the picks; the unresolved saved id kept at the end, untouched.
rowOf("c").check:SetChecked(true)
rowOf("c").check._scripts.OnClick(rowOf("c").check)
eq(table.concat(saved, " "), "b c x", "ticked: appended, the unresolved id kept at the end")
eq(visibleRows(), "b+ c+ a", "and the window follows at once")
eq(rowOf("b").up:IsEnabled(), false, "the first can't move up")
eq(rowOf("c").down:IsEnabled(), false, "the last can't move down")
eq(rowOf("b").down:IsEnabled(), true, "the first can move down")

-- Up/Down swap neighbours, never past an end.
rowOf("c").up._scripts.OnClick(rowOf("c").up)
eq(table.concat(saved, " "), "c b x", "Up swaps with the one above")
rowOf("c").up._scripts.OnClick(rowOf("c").up)
eq(table.concat(saved, " "), "c b x", "Up on the first: no move")
rowOf("b").down._scripts.OnClick(rowOf("b").down)
eq(table.concat(saved, " "), "c b x", "Down on the last: no move")

-- Untick: out of the picks.
rowOf("c").check:SetChecked(false)
rowOf("c").check._scripts.OnClick(rowOf("c").check)
eq(table.concat(saved, " "), "b x", "unticked: removed")

-- A saved id resolve() knows comes back in its place.
extra.x = { id = "x", n = "X-ray" }
p.Refresh()
eq(visibleRows(), "b+ x+ a c", "resolved again: shown in its saved place")
extra.x = nil

-- Fewer entries: the rows left over are hidden.
items = { { id = "a", n = "Alpha" } }
saved = {}
p.Refresh()
eq(visibleRows(), "a", "rows beyond the list are hidden")
eq(win.empty:IsShown(), false, "not empty")
items = {}
p.Refresh()
eq(visibleRows(), "", "no entries: no rows")
eq(win.empty:IsShown(), true, "the empty text shows")
eq(win.empty:GetText(), "Nothing here.", "the spec's")

-- RefreshSoon: one refresh per frame, and only while the window is shown.
items = { { id = "a", n = "Alpha" }, { id = "b", n = "Bravo" } }
WoW.timers = {}
p.RefreshSoon(); p.RefreshSoon()
eq(#WoW.timers, 1, "a burst queues one refresh")
eq(visibleRows(), "", "not yet")
WoW.flushTimers()
eq(visibleRows(), "a b", "on the next frame")
win:Hide()
p.RefreshSoon()
eq(#WoW.timers, 0, "hidden: nothing queued")
p.Open()
eq(visibleRows(), "a b", "reopened: refreshed")

eq(saves, 5, "every tick, untick and move wrote the order once")
check(next(GlassPanel.failures) == nil, "no failures")
done("test_picker")
