-- Export / import of the bar setup (#34).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelGold", "GlassPanelClock", "GlassPanelBags", "GlassPanelDurability" }

local function deepEq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local slash = function(s) GlassPanel._test.slash(s); WoW.tick() end

-- The codecs.
local S = function() return GlassPanel.Share end
loadAddon()
local T = S()._test
for len = 0, 7 do
    local bytes = {}
    for i = 1, len do bytes[i] = string.char((i * 97 + len * 31) % 256) end
    local raw = table.concat(bytes)
    eq(T.b64decode(T.b64encode(raw)), raw, "base64 round trip, " .. len .. " byte(s)")
end
local all = {}
for i = 0, 255 do all[#all + 1] = string.char(i) end
all = table.concat(all)
eq(T.b64decode(T.b64encode(all)), all, "base64: every byte value")
eq(T.b64encode("Man"), "TWFu", "base64: standard alphabet")
eq(T.b64encode("Ma"), "TWE=", "base64: one pad")
eq(T.b64decode("TWE*"), nil, "base64: foreign character refused")
eq(T.b64decode("TW=u"), nil, "base64: padding in the middle refused")
eq(T.b64decode("TWE"), nil, "base64: length not a multiple of 4 refused")
local v = { a = "x:y", [1] = 0.25, [2] = true, n = { false, -3 } }
check(deepEq(T.deserialize(T.serialize(v)), v), "serialisation round trip")
eq(T.serialize({ b = 1, a = 2, [2] = 3, [1] = 4 }), "tn1;n4;n2;n3;s1:an2;s1:bn1;e", "keys in a fixed order")

-- An account that never dragged anything still exports every block's place
-- (the effective lanes, not an empty saved layout).
do
    local n = 0
    for _, lane in ipairs(S().Current().layout) do n = n + #lane.ids end
    eq(n, #GlassPanel.Engine.blocks, "untouched layout: every block exported")
    eq(GlassPanelDB.layout, nil, "(nothing was saved)")
end

-- A real setup: changed every way it can be.
slash("hide durability")
slash("labels off")
slash("label bags on")
slash("icon bags off")
slash("font friz")
slash("room full")
slash("glass smoked")
slash("tint class")
slash("window smoked")
slash("move gold 40")
local before = S().Current()
local exported = S().Encode(before)
check(exported:find("^GP1:[%w%+/=]+$"), "a GP1: string of base64")
eq(S().Encode(S().Current()), exported, "the same setup gives the same string")
-- The effective layout travels, not only what was dragged: a block never
-- moved lands in the same lane on the other account.
local ids = 0
for _, lane in ipairs(before.layout) do ids = ids + #lane.ids end
eq(ids, #GlassPanel.Engine.blocks, "every loaded block is in the exported layout")

-- Another account: nothing set yet. The import rebuilds it all at once.
GlassPanelDB = nil
loadAddon()
T = S()._test
local setup, why = S().Decode(exported)
check(setup ~= nil, "decoded (" .. tostring(why) .. ")")
S().Apply(setup)
WoW.tick()
check(deepEq(S().Current(), before), "import gives the same setup")
eq(block("durability").widget._shown, false, "hidden block hidden at once")
eq(block("bags").widget.caption._text, "Bags: ", "per-block caption applied")
eq(block("bags").widget.icon._shown, false, "per-block icon applied")
eq(block("clock").widget.caption._text, "", "global captions off applied")
eq(GlassPanelDB.font, "friz", "font applied")
eq(GlassPanelDB.room, "full", "room applied")
eq(GlassPanelDB.glass, "smoked", "glass applied")
eq(GlassPanelDB.glassTint, "class", "glass tint applied")
eq(GlassPanelDB.windowGlass, "smoked", "window glass applied")
eq(GlassPanel.Bar.glass.tint._color[4], 0.62, "smoked glass painted at once (its alpha)")
check(block("gold").widget.left > 300, "moved block placed where it was")

-- Whitespace and line breaks from a paste don't matter.
local wrapped = exported:sub(1, 20) .. "\n  " .. exported:sub(21, 60) .. "\r\n" .. exported:sub(61)
check(S().Decode(wrapped) ~= nil, "line breaks and spaces ignored")

-- Missing keys take the defaults; unknown keys are dropped.
local function pack(tbl) return T.PREFIX .. T.b64encode(T.serialize(tbl)) end
local s2 = S().Decode(pack({ font = "arial", extra = "ignored", future = { 1, 2 } }))
check(s2 ~= nil, "unknown keys: accepted")
eq(s2 and s2.extra, nil, "unknown key dropped")
eq(s2 and s2.room, "auto", "missing room: default")
eq(s2 and s2.shown, true, "missing shown: default")
eq(s2 and s2.glass, "clear", "missing glass: default (clear)")
eq(s2 and s2.glassTint, "neutral", "missing glass tint: default (neutral)")
eq(s2 and s2.windowGlass, "reflective", "missing window glass: default (reflective)")
check(s2 and next(s2.hidden) == nil and #s2.layout == 0, "missing lists: empty")

-- Anything wrong changes nothing and says why.
local function rejected(text, what, reason)
    local snapshot = S().Current()
    local ok, err = S().Decode(text)
    eq(ok, nil, what .. ": rejected")
    check(type(err) == "string" and err ~= "", what .. ": says why")
    if reason then check(err and err:find(reason, 1, true), what .. ": " .. reason .. " (got " .. tostring(err) .. ")") end
    check(deepEq(S().Current(), snapshot), what .. ": nothing changed")
end
GlassPanel.Settings.SetFont("friz")
rejected("", "empty", "nothing to import")
rejected("hello there", "garbage", "not a GlassPanel setup string")
rejected("GP2:AAAA", "a newer version", "newer GlassPanel")
rejected(exported:sub(1, #exported - 8), "truncated", "damaged")
rejected("GP1:!!!!", "not base64", "damaged")
rejected(string.rep("A", T.MAX_INPUT + 1), "too long", "too long")
rejected(T.PREFIX .. T.b64encode(T.serialize({ font = "arial" }) .. "junk"), "trailing data", "trailing")
local deep = { font = "arial" }
local cur = deep
for _ = 1, 10 do cur.layout = {}; cur = cur.layout end
rejected(pack(deep), "nested too deep", "too deep")
rejected(T.PREFIX .. T.b64encode("s999999:x"), "huge string", "bad string")
rejected(T.PREFIX .. T.b64encode("n1e999;"), "infinite number", "bad number")
local many = { font = "arial", hidden = {} }
for i = 1, 1100 do many.hidden["b" .. i] = true end
rejected(T.PREFIX .. T.b64encode(T.serialize(many)), "too many values", "too many")
rejected(T.PREFIX .. T.b64encode("ts1:as1:bs1:as1:ce"), "repeated key", "repeated")
rejected(pack({ font = 5 }), "font not a string", "font")
rejected(pack({ font = "comic" }), "unknown font", "font")
rejected(pack({ room = "half" }), "bad room", "room")
rejected(pack({ glass = "frosted" }), "unknown glass", "unknown glass")
rejected(pack({ glass = true }), "glass not a string", "unknown glass")
rejected(pack({ glassTint = "red" }), "unknown glass tint", "glass tint")
rejected(pack({ glassTint = 1 }), "glass tint not a string", "glass tint")
rejected(pack({ windowGlass = "red" }), "unknown window glass", "window glass")
rejected(pack({ windowGlass = 1 }), "window glass not a string", "window glass")
rejected(pack({ labels = "on" }), "labels not a boolean", "labels")
rejected(pack({ hidden = { gold = "yes" } }), "hidden value not true", "hidden")
rejected(pack({ hidden = { "gold" } }), "hidden as a list", "hidden")
rejected(pack({ labelsFor = { [""] = true } }), "empty id", "bad block id")
rejected(pack({ iconsFor = { bags = true } }), "icons: only 'off' is stored", "icons")
rejected(pack({ layout = "left" }), "layout not a list", "layout")
rejected(pack({ layout = { { x = 0, ids = { "ok", "" } } } }), "empty id in the layout", "layout")
rejected(pack({ layout = { { x = "0.5", ids = { "gold" } } } }), "lane x not a number", "bad lane 1")
rejected(pack({ layout = { { x = 0, ids = { "a" } }, { x = 5, ids = { "gold" } } } }), "lane x out of range", "bad lane 2")
rejected(pack({ layout = { { x = 0, ids = { 42 } } } }), "id not a string", "bad block id")
rejected(pack({ layout = { { x = 0, ids = { "bags" } }, { x = 1, ids = { "bags" } } } }), "a block twice", "twice")
rejected(pack({ layout = { { x = 0, ids = { a = "gold" } } } }), "ids not a list", "bad lane 1")
rejected(pack({ layout = { x = 0 } }), "layout not a list of lanes", "layout")
-- Sparse lists padded to fool #t: rejected, never half-read (Codex review).
rejected(pack({ layout = { { x = 0, ids = { [1] = "gold", [3] = "bags", [4] = false, extra = "padding" } } } }),
    "sparse ids with an extra key", "bad lane 1")
rejected(pack({ layout = { [1] = { x = 0, ids = { "gold" } }, [3] = { x = 1, ids = { 5 } }, [4] = true, pad = 1 } }),
    "sparse lanes with an extra key", "layout")
rejected(pack({ layout = { { x = 0, ids = { [1] = "gold", [1.5] = "bags", [3] = "clock" } } } }),
    "fractional index in range", "bad lane 1")
rejected(pack("just a string"), "not a table", "not a setup")
-- Empty lanes are left out (nothing wrong, nothing to place).
local s3 = S().Decode(pack({ layout = { { x = 0, ids = {} }, { x = 1, ids = { "bags" } } } }))
check(s3 and #s3.layout == 1 and s3.layout[1].ids[1] == "bags", "empty lane left out")
-- Any id RegisterBlock accepts travels (a ported plugin may use spaces or
-- colons): what the core exports, it imports.
local odd = { font = "arial", hidden = { ["titan xpp"] = true }, labelsFor = { ["xpp:rested"] = false },
              layout = { { x = 0, ids = { "titan xpp", "|cffff0000odd" } } } }
local s4, why4 = S().Decode(pack(odd))
check(s4 and s4.hidden["titan xpp"] and s4.layout[1].ids[2] == "|cffff0000odd", "unusual ids accepted (" .. tostring(why4) .. ")")

-- Never run as code.
local src = io.open("Share.lua"):read("*a")
check(not src:find("loadstring", 1, true) and not src:find("RunScript", 1, true), "the input is never executed")

-- An import lays the bar out once, not once per setting.
do
    local Bar = GlassPanel.Bar
    local real, n = Bar.Layout, 0
    Bar.Layout = function(...) n = n + 1; return real(...) end
    S().Apply(S().Decode(exported))
    Bar.Layout = real
    eq(n, 1, "one layout pass per import")
end

-- A setup grown past the limits (ids of plugins long gone pile up) is never
-- handed out as a string the import would refuse.
do
    local saved = GlassPanelDB.hidden
    GlassPanelDB.hidden = {}
    for i = 1, 1100 do GlassPanelDB.hidden["gone" .. i] = true end
    slash("export")
    local w = S()._test.window()
    eq(w.edit:GetText(), "", "oversized: no string shown")
    check(w.status._text:find("can't be shared", 1, true), "oversized: says why")
    w:Hide()
    GlassPanelDB.hidden = saved
end

-- The window: /gpanel export shows the string, selected, read-only.
GlassPanelDB = nil   -- a window is built once per session: a fresh one, reflective by default
loadAddon()
slash("export")
T = S()._test
local win = T.window()
eq(win._shown, true, "export window open")
-- Readable over the Settings panel: a backing under the glass tint, inside its
-- corners (#36), and the reflective shell (#93) with a reading region under
-- the hint; no scroll bar for a string that fits.
local bk = T.backing()
check(bk and bk._color and bk._color[4] >= 0.5, "backing")
check(win.pane and win.pane._color and win.pane._color[4] >= 0.9, "reading region under the hint")
eq(win.pane._layer, "BACKGROUND", "reading region: background layer")
check(win.pane._masks and #win.pane._masks == 1, "reading region: rounded mask")
check(win.reflect and win.reflect.rim and win.reflect.top and win.reflect.header, "the reflective shell: lit rim, top highlight, header reflection")
eq(bk._layer, "BACKGROUND", "backing: background layer")
eq(bk._sublevel, -7, "backing: above the shadow (-8), under the tint (-6)")
eq(bk._masks and bk._masks[1], T.glass().mask, "backing: clipped by the glass's own rounded mask")
local ssc = T.scroll()
eq(ssc.ScrollBar._shown, false, "no scroll bar while the string fits")
ssc._scripts.OnScrollRangeChanged(ssc, 0, 80)
eq(ssc.ScrollBar._shown, true, "a string taller than the box: scroll bar")
ssc._scripts.OnScrollRangeChanged(ssc, 0, 0)
local listed = false
for _, name in ipairs(UISpecialFrames) do if name == "GlassPanelShareWindow" then listed = true end end
check(listed, "Escape closes it (UISpecialFrames)")
eq(win.edit:GetText(), S().Encode(S().Current()), "the current setup's string")
eq(win.edit._highlighted, true, "selected for Ctrl+C")
eq(win.edit._focused, true, "focused")
eq(win.action._shown, false, "no Import button when exporting")
win.edit:SetText("typed over")
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.edit:GetText(), S().Encode(S().Current()), "typing puts the string back")
win.edit._scripts.OnEscapePressed(win.edit)
eq(win._shown, false, "Escape closes it")

-- "Smoked" windows (#93): the earlier look, an opaque backing and no reading region.
GlassPanelDB = nil
loadAddon()
slash("window smoked")
slash("export")
T = S()._test
win = T.window()
check(T.backing()._color[4] >= 0.9, "smoked window: opaque backing")
eq(win.pane, nil, "smoked window: no reading region")
eq(win.reflect, nil, "smoked window: no reflective layers")

-- /gpanel import: Import is off until a valid string is pasted.
GlassPanelDB = nil
loadAddon()
slash("import")
T = S()._test
win = T.window()
eq(win._shown, true, "import window open")
eq(win.edit:GetText(), "", "empty box")
eq(win.action._shown, true, "Import button shown")
eq(win.action:IsEnabled(), false, "disabled while empty")
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.status._text, "", "empty: no complaint")
win.edit:SetText("not a setup")
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.action:IsEnabled(), false, "disabled for a bad string")
check(win.status._text:find("not a GlassPanel setup string", 1, true), "says why")
win.edit:SetText(exported)
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.action:IsEnabled(), true, "enabled for a good one")
check(win.status._text:find("Ready:", 1, true) and win.status._text:find("1 hidden", 1, true), "says what it holds")
eq(GlassPanelDB.font, "arial", "nothing applied before Import is clicked")
WoW.chat = {}
win.action._scripts.OnClick(win.action)
WoW.tick()
eq(win._shown, false, "closed after import")
check(deepEq(S().Current(), before), "imported through the window")
check((WoW.chat[1] or ""):find("setup imported", 1, true), "one line in chat")


--------------------------------------------------------------------------------
-- Audit (#131): the parser against a hostile paste. The number edge pinned
-- (G5), a raw-length bound (G2), a seeded malformed-input sweep (G3), and the
-- two places an import's content reached the player unescaped or untrue (G1,
-- G7). docs/AUDIT.md has the trace.
--------------------------------------------------------------------------------

-- G5: the number pattern can't match what tonumber would turn into NaN, inf or
-- a hex value, and 1 and 1.0 are one key.
rejected(T.PREFIX .. T.b64encode("nnan;"), "nan", "bad number")
rejected(T.PREFIX .. T.b64encode("ninf;"), "inf", "bad number")
rejected(T.PREFIX .. T.b64encode("n0x10;"), "hex", "bad number")
rejected(T.PREFIX .. T.b64encode("n-;"), "a lone sign", "bad number")
rejected(T.PREFIX .. T.b64encode("tn1;Tn1.0;Te"), "1 and 1.0 as keys", "repeated")

-- G2: a paste padded with whitespace past twice the cap is refused by its raw
-- length, before the whitespace strip walks it (the box caps raw text at
-- MAX_INPUT; ordinary line wrapping of a full-size export stays under twice).
rejected(exported .. string.rep(" ", 2 * T.MAX_INPUT + 1), "whitespace past twice the cap", "too long")

-- G3: a seeded sweep (its own generator, so every platform tries the same
-- inputs). Decode never throws, and whatever it accepts satisfies Clean's
-- invariants. A sweep, not a witness: it pins "no crash", nothing else.
do
    local seed = 20261031
    local function rnd(n) seed = (seed * 48271) % 2147483647; return seed % n + 1 end
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    local function pick(t) return t[rnd(#t)] end
    local function mutate(s)
        local kind, i = rnd(5), rnd(#s)
        if kind == 1 then return s:sub(1, i - 1) .. s:sub(i + 1) end
        if kind == 2 then local c = rnd(65); return s:sub(1, i) .. alphabet:sub(c, c) .. s:sub(i + 1) end
        if kind == 3 then return s:sub(1, i - 1) .. string.char(rnd(256) - 1) .. s:sub(i + 1) end
        if kind == 4 then return s:sub(1, i) end
        return s:sub(1, i) .. s:sub(i, i + 7) .. s:sub(i + 1)
    end
    local KEYS = { "font", "room", "glass", "glassTint", "windowGlass", "shown", "labels", "hidden", "labelsFor",
                   "iconsFor", "layout", "x", "ids", 1, 2, 3, "" }
    local STRINGS = { "arial", "friz", "gold", "", "|T", "auto", "clear", "class", "reflective", "x" }
    local function randomValue(depth)
        local k = rnd(depth > 3 and 3 or 4)
        if k == 1 then return pick(STRINGS) end
        if k == 2 then return (rnd(7) - 4) * 0.5 end
        if k == 3 then return rnd(2) == 1 end
        local t = {}
        for _ = 1, rnd(4) do t[pick(KEYS)] = randomValue(depth + 1) end
        return t
    end
    local function sound(setup)
        local Bar, Settings = GlassPanel.Bar, GlassPanel.Settings
        if not GlassPanel.Glass.FONTS[setup.font] or (setup.room ~= "auto" and setup.room ~= "full")
            or not Bar.GLASS[setup.glass] or not Bar.GLASS_TINTS[setup.glassTint]
            or not Settings.WINDOW_GLASS[setup.windowGlass]
            or type(setup.shown) ~= "boolean" or type(setup.labels) ~= "boolean" then return false end
        for id, v in pairs(setup.hidden) do if type(id) ~= "string" or id == "" or v ~= true then return false end end
        for id, v in pairs(setup.labelsFor) do if type(id) ~= "string" or id == "" or type(v) ~= "boolean" then return false end end
        for id, v in pairs(setup.iconsFor) do if type(id) ~= "string" or id == "" or v ~= false then return false end end
        local seen = {}
        for _, lane in ipairs(setup.layout) do
            if type(lane.x) ~= "number" or lane.x < 0 or lane.x > 1 or #lane.ids == 0 then return false end
            for _, id in ipairs(lane.ids) do
                if type(id) ~= "string" or id == "" or seen[id] then return false end
                seen[id] = true
            end
        end
        return true
    end
    local inputs = {}
    for _ = 1, 300 do inputs[#inputs + 1] = mutate(exported) end
    for _ = 1, 150 do
        local bytes = {}
        for i = 1, rnd(64) do bytes[i] = string.char(rnd(256) - 1) end
        inputs[#inputs + 1] = T.PREFIX .. T.b64encode(table.concat(bytes))
    end
    for _ = 1, 150 do inputs[#inputs + 1] = pack(randomValue(0)) end
    local throws, unsound, accepted, first = 0, 0, 0
    for _, input in ipairs(inputs) do
        local ok, setup, why = pcall(S().Decode, input)
        if not ok then throws = throws + 1; first = first or tostring(setup)
        elseif setup then
            accepted = accepted + 1
            if not sound(setup) then unsound = unsound + 1 end
        elseif type(why) ~= "string" or why == "" then throws = throws + 1; first = first or "no reason" end
    end
    eq(throws, 0, "sweep: Decode never throws and always says why (" .. #inputs .. " inputs; first: " .. tostring(first) .. ")")
    eq(unsound, 0, "sweep: every accepted setup satisfies Clean's invariants (" .. accepted .. " accepted)")
    check(accepted > 0, "sweep: the random structures do hit accepted setups")
end

-- G1: an imported id carrying chat markup is escaped wherever /gpanel list
-- prints an id, so a pasted setup can't paint chat with textures, links or
-- colours. Ids stay any string (what the core exports, it imports); a loaded
-- block's odd id is a plugin's choice and is escaped the same way.
do
    local evil = "|TInterface\\Icons\\INV_Misc_QuestionMark:16|t evil"
    GlassPanelDB = nil
    loadAddon()
    T = S()._test
    local s = S().Decode(pack({ font = "arial", hidden = { [evil] = true },
                                layout = { { x = 0, ids = { evil, "bags" } } } }))
    check(s ~= nil, "G1: the id imports")
    S().Apply(s)
    GlassPanel.RegisterBlock({ id = "odd|cff00ff00id", label = "Odd", text = function() return "1" end })
    WoW.tick()
    WoW.chat = {}
    slash("list")
    local all = table.concat(WoW.chat, "\n")
    check(all:find("||TInterface", 1, true), "G1: the unloaded id is escaped")
    check(all:find("odd||cff00ff00id", 1, true), "G1: a loaded id is escaped")
    local bare = all:gsub("||", "")
    eq(bare:find("|T", 1, true), nil, "G1: no bare texture escape reaches chat")
    eq(bare:find("|cff00ff00", 1, true), nil, "G1: no bare colour escape reaches chat")
end

-- G7: following Glass UI, the import keeps our glass, tint and window glass
-- (Settings.ApplyAll, #96): the preview and the chat line say so instead of
-- reporting the imported ones as applied. Describe itself, which also labels
-- an export, is unchanged.
do
    GlassUI = { Suite = { API = 1, Theme = function() return { name = "pearl", preset = "pearl" } end,
                          Report = function() end } }
    GlassPanelDB = nil
    loadAddon()
    T = S()._test
    eq(GlassPanel.Suite.Following(), true, "G7: following Glass UI")
    slash("import")
    local w = T.window()
    w.edit:SetText(exported)   -- smoked glass, class tint, smoked windows
    w.edit._scripts.OnTextChanged(w.edit, true)
    check(w.status._text:find("kept", 1, true) and w.status._text:find("Glass UI", 1, true),
        "G7: the preview says glass, tint and window glass are kept (got " .. tostring(w.status._text) .. ")")
    WoW.chat = {}
    w.action._scripts.OnClick(w.action)
    WoW.tick()
    check((WoW.chat[1] or ""):find("kept", 1, true), "G7: the chat line says so too")
    eq(GlassPanelDB.glass, "clear", "G7: our glass kept")
    eq(GlassPanelDB.glassTint, "neutral", "G7: our tint kept")
    eq(GlassPanelDB.windowGlass, "reflective", "G7: our window glass kept")
    eq(GlassPanelDB.font, "friz", "G7: the rest of the setup applied")
    check(not S().Describe(S().Decode(exported)):find("kept", 1, true), "G7: Describe itself unchanged")
    GlassUI = nil
end

check(next(GlassPanel.failures) == nil, "no failures")
done("test_share")
