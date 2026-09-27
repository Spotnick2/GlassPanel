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

-- Layout: lanes, order, hidden and empty blocks take no space.
loadAddon()
for _, blk in ipairs(GlassPanel.Engine.blocks) do GlassPanelDB.hidden[blk.id] = true end
register({ id = "l2", order = 20, text = function() return "bbbb" end })
register({ id = "l1", order = 10, text = function() return "aa" end })
register({ id = "empty", order = 15, text = function() return "" end })
register({ id = "r1", side = "right", text = function() return "rr" end })
WoW.tick()
local function x(id) local p = block(id).widget._points[1]; return p[1], p[4] end
local p1, x1 = x("l1")
local _, x2 = x("l2")
eq(p1, "LEFT", "left lane anchors LEFT")
check(x1 < x2, "lower order sits further left")
eq(block("empty").widget._shown, false, "empty block hidden")
eq((x("r1")), "RIGHT", "right lane anchors RIGHT")
GlassPanel._test.slash("hide l1")
eq(block("l1").widget._shown, false, "/gpanel hide")
eq(select(2, x("l2")), x1, "the next block takes the hidden one's place")
GlassPanel._test.slash("show l1")
eq(block("l1").widget._shown, true, "/gpanel show")

-- A block whose event the client refuses is reported, and the rest still works.
loadAddon()
register({ id = "badevent", events = { "NOT_A_REAL_EVENT" }, text = function() return "ok" end })
WoW.tick()
check(GlassPanel.failures["event:NOT_A_REAL_EVENT"], "unknown event recorded")
eq(textOf("badevent"), "ok", "block still painted")

done("test_engine")
