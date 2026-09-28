-- The block contract: registration, batching, isolation, layout.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

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

done("test_engine")
