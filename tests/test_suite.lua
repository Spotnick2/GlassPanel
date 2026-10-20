-- Glass UI's suite theme (#96): the contract of Glass UI's docs/SUITE.md, step 7.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelGold" }

local reports, themeCalls, opened
local function fakeSuite(over)
    reports, themeCalls, opened = {}, {}, 0
    local suite = {
        API = 1,
        Ready = function() return true end,
        Theme = function(addon)
            themeCalls[#themeCalls + 1] = addon
            return { name = "pearl", preset = "pearl" }
        end,
        Report = function(addon, state) reports[#reports + 1] = { addon = addon, state = state } end,
        Open = function() opened = opened + 1; return true end,
        Accent = function() return { 0.65, 0.835, 0.905 } end,
    }
    for k, v in pairs(over or {}) do suite[k] = v end
    GlassUI = { Suite = suite }
    return suite
end
local function noSuite() GlassUI = nil end
local function failed(key) return GlassPanel.failures[key] end
local function bodyIsBuilt()   -- the bar's tint is the built surface's, not smoked's
    local c = GlassPanel.Bar.glass.tint._color
    local st = GlassPanel.Glass.STYLE
    return math.abs(c[1] - st.tint[1]) < 1e-6 and math.abs(c[2] - st.tint[2]) < 1e-6
        and math.abs(c[3] - st.tint[3]) < 1e-6 and math.abs(c[4] - st.tint[4]) < 1e-6
end

-- No Glass UI: our own look, Pearl by default; nothing asked, nothing reported.
noSuite()
loadAddon()
eq(GlassPanel.Suite.Following(), false, "no Glass UI: not following")
eq(GlassPanel.Glass.STYLE.grain, 0, "an empty profile builds Pearl (no grain)")
check(GlassPanel.Glass.STYLE.wash > 0 and GlassPanel.Glass.STYLE.wash < 0.15, "...with its softer wash")
eq(failed("glass:pearl"), nil, "nothing recorded")
eq(GlassPanel.Suite._test.built(), "pearl", "built: pearl")

-- Anything but a Suite speaking API 1 counts as absent, and Theme isn't called.
local function absent(label, make)
    fakeSuite()
    make()
    loadAddon()
    eq(GlassPanel.Suite.Following(), false, label .. ": not following")
    eq(#themeCalls, 0, label .. ": Theme not called")
    eq(#reports, 0, label .. ": nothing reported")
end
absent("Suite missing", function() GlassUI.Suite = nil end)
absent("Suite not a table", function() GlassUI.Suite = "x" end)
absent("a wrong API", function() GlassUI.Suite.API = 2 end)
absent("API 0", function() GlassUI.Suite.API = 0 end)
absent("API as text", function() GlassUI.Suite.API = "1" end)
absent("no Theme", function() GlassUI.Suite.Theme = nil end)
absent("Theme not a function", function() GlassUI.Suite.Theme = {} end)
absent("no Report", function() GlassUI.Suite.Report = nil end)
GlassUI = "not a table"
loadAddon()
eq(GlassPanel.Suite.Following(), false, "GlassUI not a table: absent")

-- Theme says no, throws, or returns junk: the local look.
local function notFollowing(label, theme)
    fakeSuite({ Theme = theme })
    loadAddon()
    eq(GlassPanel.Suite.Following(), false, label .. ": not following")
    eq(#reports, 1, label .. ": still reports what it built")
    eq(reports[1].state.built, nil, label .. ": built = nil (the local look)")
    eq(reports[1].state.reason, nil, label .. ": no failure reason")
    eq(GlassPanel.Glass.STYLE.grain, 0, label .. ": Pearl is our own default")
end
notFollowing("not-following", function() return nil, "not-following" end)
notFollowing("not-ready", function() return nil, "not-ready" end)
notFollowing("unknown", function() return nil, "unknown" end)
notFollowing("Theme throws", function() error("boom") end)
notFollowing("a string", function() return "pearl" end)
notFollowing("another preset", function() return { name = "x", preset = "clean" } end)
notFollowing("no preset", function() return {} end)

-- Following: Pearl, reported once with plain values.
fakeSuite()
loadAddon()
eq(GlassPanel.Suite.Following(), true, "following")
eq(themeCalls[1], "GlassPanel", "asked by name")
eq(#themeCalls, 1, "asked once")
eq(#reports, 1, "reported once")
local st = reports[1].state
eq(reports[1].addon, "GlassPanel", "reported by name")
eq(st.api, 1, "api 1")
eq(st.built, "pearl", "built pearl")
eq(st.reason, nil, "no reason")
check(type(st.minor) == "number" and st.minor >= 11, "the library's MINOR")
eq(type(st.options), "function", "options is a function")
st.options()   -- under pcall in Glass UI; ours must not throw
eq(failed("suite:report"), nil, "no report failure")
eq(GlassPanel.CleanGlass().STYLE.grain, 0, "the clean-surface instance is Pearl too")

-- An older LibGlass (before r11): the earlier look, said and reported. The copy that
-- wins LibStub reports MINOR 6 (and, like r6-r10, knows no "pearl").
local function oldLibrary(label, follow)
    if follow then fakeSuite() else noSuite() end
    loadAddon({ afterLibrary = function()
        local real = LibStub
        LibStub = setmetatable({}, { __index = real, __call = function(_, name, silent)
            local lib, minor = real(name, silent)
            if name == "LibGlass-1.0" then minor = 6 end
            return lib, minor
        end })
    end })
    check(failed("glass:pearl") and failed("glass:pearl"):find("library-too-old", 1, true), label .. ": recorded")
    eq(GlassPanel.Suite._test.built(), nil, label .. ": built the earlier look")
    check(GlassPanel.Glass.STYLE.grain > 0, label .. ": it has the earlier grain")
    if follow then
        eq(reports[1].state.built, nil, label .. ": reports built = nil")
        eq(reports[1].state.reason, "library-too-old", label .. ": reports why")
        eq(reports[1].state.minor, 6, label .. ": and the MINOR at the attempt")
    end
    check(GlassPanel.CleanGlass() ~= nil, label .. ": (a minor-6 library still has a clean instance)")
end
oldLibrary("older library", false)
oldLibrary("older library, following", true)

-- New errors: build-failed.
fakeSuite()
loadAddon({ afterLibrary = function()
    local lib = LibStub("LibGlass-1.0")
    local new = lib.New
    lib.New = function(self, o) if o and o.preset == "pearl" then error("boom") end return new(self, o) end
end })
eq(reports[1].state.reason, "build-failed", "New errors: build-failed")
eq(reports[1].state.built, nil, "...built = nil")
check(GlassPanel.Glass ~= nil, "...the glass is still there")

-- The accent (#106): the stock UI's gold (bar captions, window titles) follows Glass UI's accent while following.
local function col(fs) local c = fs._textColor; return c and string.format("%.3f,%.3f,%.3f", c[1], c[2], c[3]) end
noSuite()
loadAddon()
local cap = block("gold").widget.caption
eq(col(cap), "1.000,0.820,0.000", "not following: captions are Blizzard's gold")
fakeSuite()
loadAddon()
cap = block("gold").widget.caption
eq(col(cap), "0.650,0.835,0.905", "following: captions wear the suite's accent")
GlassPanel._test.slash("export")
eq(col(GlassPanel.Share._test.window().title), "0.650,0.835,0.905", "...and so do window titles")
local function lookChanged() local l = WoW.callbacks["GlassUI.Suite.LookChanged"]; l[#l][1]() end   -- this session's listener
local gold = { 1, 0.82, 0 }
GlassUI.Suite.Accent = function() return gold end   -- Glass UI changes it
lookChanged()
eq(col(cap), "1.000,0.820,0.000", "LookChanged repaints live")
for _, bad in ipairs({ "x", {}, { 2, 0, 0 }, { 1, 1 } }) do
    GlassUI.Suite.Accent = function() return bad end
    lookChanged()
    eq(col(cap), "1.000,0.820,0.000", "a bad accent answer: gold")
end
GlassUI.Suite.Accent = function() error("boom") end
lookChanged()
eq(col(cap), "1.000,0.820,0.000", "a throwing Accent: gold")
fakeSuite(); GlassUI.Suite.Accent = nil
loadAddon()
eq(col(block("gold").widget.caption), "1.000,0.820,0.000", "an older Glass UI without Accent: gold")
eq(WoW.callbacks["GlassUI.Suite.LookChanged"] ~= nil, true, "(still listening)")
noSuite()
WoW.callbacks = {}
loadAddon()
eq(WoW.callbacks["GlassUI.Suite.LookChanged"], nil, "not following: no listener")

-- Following suspends the saved body and windows, and keeps them.
fakeSuite()
loadAddon({ db = { glass = "smoked", windowGlass = "smoked", glassTint = "class" } })
eq(GlassPanelDB.glass, "smoked", "the saved body is kept")
eq(GlassPanelDB.glassTint, "class", "the saved tint is kept")
eq(GlassPanelDB.windowGlass, "smoked", "the saved window look is kept")
check(bodyIsBuilt(), "following: the bar wears the built body, not Smoked")
eq(GlassPanel.Settings.SetGlass("clear"), false, "SetGlass refused while following")
eq(GlassPanel.Settings.SetWindowGlass("reflective"), false, "SetWindowGlass refused while following")
eq(GlassPanelDB.glass, "smoked", "(still smoked)")
GlassPanel._test.slash("glass clear")
check(WoW.chat[#WoW.chat]:find("set in Glass UI", 1, true), "/gpanel glass says it is set in Glass UI")
eq(GlassPanelDB.glass, "smoked", "...and wrote nothing")
GlassPanel._test.slash("window reflective")
check(WoW.chat[#WoW.chat]:find("set in Glass UI", 1, true), "/gpanel window says so too")
eq(GlassPanelDB.windowGlass, "smoked", "...and wrote nothing")
eq(GlassPanel.Settings.SetGlassTint("neutral"), false, "SetGlassTint refused while following")
GlassPanel._test.slash("tint neutral")
check(WoW.chat[#WoW.chat]:find("set in Glass UI", 1, true), "/gpanel tint says it is set in Glass UI")
eq(GlassPanelDB.glassTint, "class", "...and wrote nothing")
GlassPanel._test.slash("font friz")
eq(GlassPanelDB.font, "friz", "and so does the font")
-- An import changes neither.
GlassPanel.Settings.ApplyAll(GlassPanel.Share.Clean({ glass = "clear", glassTint = "neutral", windowGlass = "reflective", font = "arial" }))
eq(GlassPanelDB.glass, "smoked", "an import keeps the saved body")
eq(GlassPanelDB.windowGlass, "smoked", "an import keeps the saved window look")
eq(GlassPanelDB.glassTint, "class", "an import keeps the saved tint")
-- The windows are Reflective while following, whatever was saved.
GlassPanel._test.slash("export")
local win = GlassPanel.Share._test.window()
check(win.pane ~= nil and win.reflect ~= nil, "a window is Reflective while following")

-- The options panel: greyed, with a note and a button to Glass UI.
local function open() local p = GlassPanel.Options._test.panel; p:Hide(); p:Show() end
open()
local C = GlassPanel.Options._test.controls
eq(C.glass[1]._disabled, true, "the body radios are disabled")
eq(C.windowGlass[1]._disabled, true, "the window radios are disabled")
eq(C.glassTint[1]._disabled, true, "the tint radios are disabled")
local wn, sn = C.windowGlass[#C.windowGlass], C.suiteButton
check(wn._points[1][5] - sn._points[1][5] >= 88, "the two notes under Windows each have room for two lines")
eq(C.suiteButton._shown, true, "the Glass UI button is shown")
C.suiteButton._scripts.OnClick(C.suiteButton)
eq(opened, 1, "...and it calls Suite.Open")
-- Without Open (an older Glass UI within API 1), no button.
fakeSuite()
GlassUI.Suite.Open = nil
loadAddon()
open()
eq(GlassPanel.Options._test.controls.suiteButton._shown, false, "no Open: no button")
eq(GlassPanel.Suite.Open(), false, "Suite.Open without Open: false")
-- An Open that throws is contained.
fakeSuite({ Open = function() error("x") end })
loadAddon()
eq(GlassPanel.Suite.Open(), false, "a throwing Open: false")

-- Following, then not following: the local look is back, its keys untouched.
noSuite()
loadAddon({ db = { glass = "smoked", windowGlass = "smoked", glassTint = "neutral" } })
eq(GlassPanel.Suite.Following(), false, "not following any more")
eq(GlassPanelDB.glass, "smoked", "the saved body survived")
eq(GlassPanelDB.windowGlass, "smoked", "the saved window look survived")
check(not bodyIsBuilt(), "the bar wears Smoked again")
GlassPanel._test.slash("window reflective")
eq(GlassPanelDB.windowGlass, "reflective", "and /gpanel window writes again")

-- An empty profile is Pearl.
noSuite()
loadAddon({ db = {} })
eq(GlassPanel.Glass.STYLE.grain, 0, "an empty profile: Pearl")
done("test_suite")
