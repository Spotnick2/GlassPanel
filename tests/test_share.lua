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
rejected(pack({ labels = "on" }), "labels not a boolean", "labels")
rejected(pack({ hidden = { gold = "yes" } }), "hidden value not true", "hidden")
rejected(pack({ hidden = { "gold" } }), "hidden as a list", "hidden")
rejected(pack({ labelsFor = { ["|cffff0000x"] = true } }), "id with escape codes", "bad block id")
rejected(pack({ iconsFor = { bags = true } }), "icons: only 'off' is stored", "icons")
rejected(pack({ layout = "left" }), "layout not a list", "layout")
rejected(pack({ layout = { { x = 0, ids = { "ok", "bad id!" } } } }), "bad id in the layout", "layout")
rejected(pack("just a string"), "not a table", "not a setup")
-- A bad lane is dropped like one in SavedVariables (Layout.Clean).
local s3 = S().Decode(pack({ layout = { { x = 5, ids = { "gold" } }, { x = 0, ids = { "bags", "bags" } } } }))
check(s3 and #s3.layout == 1 and #s3.layout[1].ids == 1, "out-of-range lane and repeated id dropped")

-- Never run as code.
local src = io.open("Share.lua"):read("*a")
check(not src:find("loadstring", 1, true) and not src:find("RunScript", 1, true), "the input is never executed")

-- The window: /gpanel export shows the string, selected, read-only.
slash("export")
T = S()._test
local win = T.window()
eq(win._shown, true, "export window open")
eq(win.edit:GetText(), S().Encode(S().Current()), "the current setup's string")
eq(win.edit._highlighted, true, "selected for Ctrl+C")
eq(win.edit._focused, true, "focused")
eq(win.action._shown, false, "no Import button when exporting")
win.edit:SetText("typed over")
win.edit._scripts.OnTextChanged(win.edit, true)
eq(win.edit:GetText(), S().Encode(S().Current()), "typing puts the string back")
win.edit._scripts.OnEscapePressed(win.edit)
eq(win._shown, false, "Escape closes it")

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

check(next(GlassPanel.failures) == nil, "no failures")
done("test_share")
