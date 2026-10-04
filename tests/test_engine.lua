-- The block contract: registration, batching, isolation, layout.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelXP", "GlassPanelGold", "GlassPanelClock" }   -- the lanes these tests assert on

local function register(spec) return GlassPanel.RegisterBlock(spec) end

-- Registration: bad specs are refused with a message, never half-registered.
loadAddon()
local before = #GlassPanel.Engine.blocks
check(register({ text = function() return "x" end }) == nil, "refused: no id")
check(register({ id = "a" }) == nil, "refused: no text function")
check(register({ id = "a", text = function() end, side = "top" }) == nil, "refused: bad side")
check(register({ id = "a", text = function() end, interval = 0 }) == nil, "refused: interval < 1")
check(register({ id = "a", text = function() end, tooltip = "hi" }) == nil, "refused: tooltip not a function")
check(register({ id = "gold", text = function() end }) == nil, "refused: duplicate id")
check(register({ id = "a", text = function() end, events = "PLAYER_MONEY" }) == nil, "refused: events not a list")
check(register({ id = "a", text = function() end, events = { 42 } }) == nil, "refused: non-string event")
eq(#GlassPanel.Engine.blocks, before, "nothing half-registered")
check(#WoW.chat >= 8, "each refusal was reported")
check(block("a") == nil, "a refused id stays free")
check(register({ id = "a", text = function() end, label = true }) == nil, "refused: label not a string")
check(register({ id = "a", text = function() end, replaces = 5 }) == nil, "refused: replaces not an id")
check(register({ id = "a", text = function() end, replaces = "a" }) == nil, "refused: replaces itself")

-- replaces (#50): an early block (registered before the settings exist)
-- replaces too; two blocks can't replace each other.
loadAddon({ before = function()
    register({ id = "early", replaces = "clock", text = function() return "e" end })
end })
eq(block("clock").widget._shown, false, "early replacing block hides the other")
eq(GlassPanelDB.hidden.clock, nil, "live, not stored")
check(register({ id = "loop", replaces = "early", text = function() end }) ~= nil, "a chain is fine")
check(register({ id = "back", replaces = "back2", text = function() end }) ~= nil, "replacing an unknown id is fine")
check(register({ id = "back2", replaces = "back", text = function() end }) == nil, "refused: replaces its replacer")

-- A repeated event name runs onEvent once.
loadAddon()
local hits = 0
register({ id = "dup", events = { "PLAYER_MONEY", "PLAYER_MONEY" }, onEvent = function() hits = hits + 1 end,
           text = function() return "d" end })
WoW.fire("PLAYER_MONEY")
eq(hits, 1, "duplicate event registered once")

-- A block marked dirty during a flush, after the flush passed it, still repaints.
loadAddon()
local bText = "b1"
register({ id = "early1", text = function() return bText end })
register({ id = "late1", text = function() bText = "b2"; GlassPanel.Refresh("early1"); return "l" end })
WoW.tick()
eq(textOf("early1"), "b1", "painted before the late block ran")
eq(GlassPanel.Engine._test.flushFrame._shown, true, "the refresh keeps the flush frame awake")
WoW.tick()
eq(textOf("early1"), "b2", "and it repaints on the next frame")

-- A block registered before the bar exists (an early plugin) is attached at build.
loadAddon({ before = function()
    register({ id = "early", text = function() return "early!" end })
end })
eq(textOf("early"), "early!", "early block attached and painted")

-- One repaint per frame however many events arrive; onEvent sees every one.
loadAddon()
local texts, seen = 0, 0
register({ id = "counter", events = { "PLAYER_XP_UPDATE" },
           onEvent = function() seen = seen + 1 end,
           text = function() texts = texts + 1; return "n" .. seen end })
WoW.tick()
texts = 0
WoW.fire("PLAYER_XP_UPDATE"); WoW.fire("PLAYER_XP_UPDATE"); WoW.fire("PLAYER_XP_UPDATE")
eq(texts, 0, "no repaint before the frame renders")
WoW.tick()
eq(texts, 1, "three events, one repaint")
eq(textOf("counter"), "n3", "onEvent ran for each event before the repaint")
WoW.tick()
eq(texts, 1, "no repaint on an idle frame")
eq(GlassPanel.Engine._test.flushFrame._shown, false, "flush frame idles when nothing is dirty")

-- Isolation: a throwing block is recorded and marked; its neighbours still paint.
loadAddon()
register({ id = "boom", text = function() error("kaput") end })
register({ id = "fine", text = function() return "fine" end })
register({ id = "secret", text = function() return WoW.Secret("s") end })
register({ id = "number", text = function() return 42 end })
-- error() with a value that can't be printed must not escape the recorder.
register({ id = "secreterr", text = function() error(WoW.Secret("err")) end })
register({ id = "badtostring", text = function()
    error(setmetatable({}, { __tostring = function() error("no") end }))
end })
register({ id = "last", text = function() return "last" end })
WoW.tick()
eq(textOf("last"), "last", "blocks after unprintable errors still paint")
check(GlassPanel.failures["secreterr:text"], "secret error recorded")
check(GlassPanel.failures["badtostring:text"], "throwing __tostring recorded")

-- A secret STRING (the client's secrets keep their type) is not stored as is.
local secretMsg = "secret-error-text"
WoW.MarkSecret(secretMsg)
GlassPanel.API.Fail("plugin:secretstring", secretMsg)
eq(GlassPanel.failures["plugin:secretstring"], "(unprintable error)", "secret string error replaced")
local secretKey = "secret-key-text"
WoW.MarkSecret(secretKey)
GlassPanel.API.Fail(secretKey, "boom")
eq(GlassPanel.failures["?"], "boom", "secret key replaced")
check(GlassPanel.failures[secretKey] == nil, "secret key not stored")
eq(textOf("fine"), "fine", "neighbour still paints")
check(textOf("boom"):find("error"), "thrower shows an error mark")
check(GlassPanel.failures["boom:text"], "thrower recorded in failures")
check(GlassPanel.failures["secret:text"], "a secret return is refused and recorded")
check(GlassPanel.failures["number:text"], "a non-string return is refused and recorded")

-- Tooltip and click run under pcall too.
local b = register({ id = "tt", text = function() return "t" end,
                     tooltip = function(_, tt) tt:AddLine("hello") end,
                     onClick = function() error("click fail") end })
WoW.tick()
b.widget._scripts.OnEnter(b.widget)
eq(GameTooltip._lines[1], "hello", "tooltip lines added")
b.widget._scripts.OnClick(b.widget, "LeftButton")
check(GlassPanel.failures["tt:onClick"], "click error recorded, not thrown")

-- Interval blocks repaint on the shared clock.
loadAddon()
local n = 0
register({ id = "tick", interval = 2, text = function() n = n + 1; return "t" .. n end })
WoW.tick()
local after = n
WoW.tick(1.0); WoW.tick()
eq(n, after, "not due after 1 s")
WoW.tick(1.0); WoW.tick()
eq(n, after + 1, "due after 2 s")

-- A function interval chooses when the block is next due.
loadAddon()
local m = 0
register({ id = "fn", interval = function() return 3 end, text = function() m = m + 1; return "f" .. m end })
WoW.tick()
local base = m
WoW.tick(1.0); WoW.tick(); WoW.tick(1.0); WoW.tick()
eq(m, base, "not due before 3 s")
WoW.tick(1.0); WoW.tick()
eq(m, base + 1, "due at 3 s")

-- Layout: lanes, order, hidden and empty blocks take no space.
loadAddon()
for _, blk in ipairs(GlassPanel.Engine.blocks) do GlassPanelDB.hidden[blk.id] = true end
register({ id = "l2", order = 20, text = function() return "bbbb" end })
register({ id = "l1", order = 10, text = function() return "aa" end })
register({ id = "empty", order = 15, text = function() return "" end })
register({ id = "r1", side = "right", text = function() return "rr" end })
WoW.tick()
local x1, x2 = leftOf("l1"), leftOf("l2")
eq(x1, 8, "left lane starts at the edge")
check(x1 < x2, "lower order sits further left")
eq(block("empty").widget._shown, false, "empty block hidden")
check(leftOf("r1") > 900, "right lane packs against the right edge")
GlassPanel._test.slash("hide l1")
eq(block("l1").widget._shown, false, "/gpanel hide")
eq(leftOf("l2"), x1, "the next block takes the hidden one's place")
GlassPanel._test.slash("show l1")
eq(block("l1").widget._shown, true, "/gpanel show")

-- A block whose event the client refuses is reported, and the rest still works.
loadAddon()
WoW.KNOWN_EVENTS.NOT_A_REAL_EVENT = false   -- unknown even without the dump (which accepts every name)
register({ id = "badevent", events = { "NOT_A_REAL_EVENT" }, text = function() return "ok" end })
WoW.tick()
check(GlassPanel.failures["event:NOT_A_REAL_EVENT"], "unknown event recorded")
eq(textOf("badevent"), "ok", "block still painted")

-- A block registered after startup whose first text is nil: hidden on its
-- first flush, and told so, with built content hidden too (Codex, PR #5).
loadAddon()
WoW.tick(); WoW.tick()   -- everything clean
local shownCalls = {}
local late = register({ id = "latenil", text = function() return nil end,
                        onShown = function(_, v) shownCalls[#shownCalls + 1] = v end })
local content
local lateG = register({ id = "lategraph", width = 80, text = function() return nil end,
                         build = function(blk) content = CreateFrame("Frame", nil, blk.widget) end })
WoW.tick()
eq(late.widget._shown, false, "late nil-text block hidden on its first flush")
eq(shownCalls[1], false, "and its onShown heard it")
eq(lateG.widget._shown, false, "late graphical block with nil text hidden")
eq(content:IsVisible(), false, "its built content isn't visible")

-- Graphical blocks: width, build, paint.
loadAddon()
check(register({ id = "w1", text = function() end, width = 5 }) == nil, "refused: width too small")
check(register({ id = "w3", text = function() end, width = 0 / 0 }) == nil, "refused: width NaN")
check(register({ id = "w2", text = function() end, build = true }) == nil, "refused: build not a function")
local builds, paints, txt = 0, 0, ""
local g = register({ id = "graph", width = 120, text = function() return txt end,
                     build = function(blk) builds = builds + 1; check(blk.widget ~= nil, "build sees the widget") end,
                     paint = function() paints = paints + 1 end })
WoW.tick()
eq(builds, 1, "build runs once")
eq(paints, 1, "paint runs after the repaint")
eq(g.widget._shown, true, "fixed-width block with empty text shows")
eq(g.widget._width, 120, "fixed width used")
txt = nil
GlassPanel.Refresh("graph"); WoW.tick()
eq(g.widget._shown, false, "nil text hides it")
eq(paints, 1, "no paint while hidden")
register({ id = "badpaint", width = 50, text = function() return "" end, paint = function() error("p") end })
WoW.tick()
check(GlassPanel.failures["badpaint:paint"], "paint error recorded")
-- A graphical block's error mark is drawn above whatever it built.
local covered
register({ id = "badgraph", width = 60, text = function() error("t") end,
           build = function(blk)
               covered = CreateFrame("Frame", nil, blk.widget)
               covered:SetFrameLevel(blk.widget:GetFrameLevel() + 6)
           end })
WoW.tick()
check(textOf("badgraph"):find("error"), "error text set")
check(block("badgraph").widget.label._parent._level > covered._level, "error label above the block's own frames")
register({ id = "badbuild", width = 50, text = function() return "" end, build = function() error("b") end })
WoW.tick()
check(GlassPanel.failures["badbuild:build"], "build error recorded, block still registered")

-- Captions (#23): a gold "Label: " before the value, Titan-style.
loadAddon()
check(register({ id = "badlabel", text = function() end, showLabel = "yes" }) == nil, "refused: showLabel not a boolean")
local cap = register({ id = "dura", label = "Durability", text = function() return "97%" end })
WoW.tick()
local w = cap.widget
eq(w.caption._text, "Durability: ", "caption shown by default")
eq(w._width, w.textX + #"Durability: " * 6 + #"97%" * 6 + 4, "the block's width includes the caption")
eq(block("gold").widget.caption._text, "", "Gold opts out (showLabel = false)")
eq(block("clock").widget.caption._text, "", "Clock opts out")
eq(block("xp").widget.caption._text, "", "graphical blocks never show one")
GlassPanel._test.slash("labels off")
eq(w.caption._text, "", "/gpanel labels off")
eq(w._width, w.textX + #"97%" * 6 + 4, "and the width shrinks")
GlassPanel._test.slash("label dura on")
eq(w.caption._text, "Durability: ", "a per-block 'on' beats the global off")
GlassPanel._test.slash("labels on")
GlassPanel._test.slash("label dura off")
eq(w.caption._text, "", "a per-block 'off' beats the global on")
GlassPanel._test.slash("label gold on")
eq(block("gold").widget.caption._text, "Gold: ", "an opted-out block can be turned on")
GlassPanel._test.slash("label dura default")
eq(w.caption._text, "Durability: ", "default: back to the block's own choice")
GlassPanel._test.slash("label xp on")
eq(block("xp").widget.caption._text, "", "never on a graphical block, even when asked")

-- Plugin options: validated; a malformed list drops the options (recorded),
-- never the block.
local function badOptions(id, options, what)
    local b = register({ id = id, text = function() end, options = options })
    check(b ~= nil, what .. ": the block still registers")
    eq(b and b.options, nil, what .. ": its options dropped")
    check(GlassPanel.failures[id .. ":options"] ~= nil, what .. ": recorded")
    GlassPanel.failures[id .. ":options"] = nil
end
badOptions("o1", "yes", "options not a list")
badOptions("o2", { { label = 1, get = print, set = print } }, "label not a string")
badOptions("o3", { { label = "x", get = print } }, "no set")
badOptions("o4", { { label = "x", get = print, set = print, note = 5 } }, "note not a string")
local o5 = register({ id = "o5", text = function() end, options = { { label = "x", get = print, set = print } } })
check(o5 ~= nil and o5.options ~= nil, "a valid option list is kept")

-- Icons (#24): shown by default; turned off per block, the text moves left.
local ic = register({ id = "iconic", label = "Iconic", icon = "Interface\Icons\INV_Misc_Bag_08",
                      text = function() return "12" end })
WoW.tick()
local iw = ic.widget
eq(iw.icon._shown, true, "icon shown by default")
eq(iw.textX, 4 + 14 + 4, "text starts after the icon")
local wide = iw._width
GlassPanel._test.slash("icon iconic off")
eq(iw.icon._shown, false, "/gpanel icon off hides it")
eq(iw.textX, 4, "the text starts at the edge")
eq(iw.caption._points[1][4], 4, "the caption is re-anchored there")
eq(iw._width, wide - 18, "and the block narrows by the icon")
eq(GlassPanelDB.iconsFor.iconic, false, "saved as false")
GlassPanel._test.slash("icon iconic on")
eq(iw.icon._shown, true, "back on")
eq(GlassPanelDB.iconsFor.iconic, nil, "on is the default: nothing stored")
eq(iw._width, wide, "full width again")
WoW.chat = {}
GlassPanel._test.slash("icon dura off")
check((WoW.chat[1] or ""):find("has no icon", 1, true), "a block without an icon says so")
eq(GlassPanelDB.iconsFor.dura, nil, "and stores nothing")
-- Saved off before the block registers: it comes up without its icon.
GlassPanelDB.iconsFor.late = false
local late = register({ id = "late", icon = "x", text = function() return "1" end })
WoW.tick()
eq(late.widget.icon._shown, false, "saved setting honoured at attach")
eq(late.widget.textX, 4, "and the text starts at the edge")

done("test_engine")
