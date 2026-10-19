-- The bar's glass (#65): clear or smoked, neutral or the class colour.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelGold" }

local function said() return table.concat(WoW.chat, " | ") end
local function g() return GlassPanel.Bar.glass end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end
local function tintIs(r, gg, b, a, msg)
    local c = g().tint._color
    check(near(c[1], r) and near(c[2], gg) and near(c[3], b) and near(c[4], a),
          msg .. " (got " .. table.concat({ tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4]) }, ", ") .. ")")
end
-- The wash is a gradient: what's drawn is its peak (the top colour's alpha),
-- since SetAlpha does nothing on it (#83). The stub models that.
local function washPeak() return g().wash._gradient[3].a end

-- Defaults: clear and neutral, which is the library's own look.
WoW.playerClass = { "Hunter", "HUNTER", 3 }
loadAddon()
eq(GlassPanelDB.glass, "clear", "default glass: clear")
eq(GlassPanelDB.glassTint, "neutral", "default tint: neutral")
local st = GlassPanel.Glass.STYLE
tintIs(st.tint[1], st.tint[2], st.tint[3], st.tint[4], "clear neutral = the built tint")
eq(g().grain._alpha, st.grain, "clear: the library's grain")
check(near(washPeak(), st.wash), "clear: the wash as built")
eq(g().wash._shown, true, "(shown)")

-- Smoked: AltStable's darker preset, painted at once.
GlassPanel._test.slash("glass smoked")
eq(GlassPanelDB.glass, "smoked", "/gpanel glass smoked")
tintIs(0.05, 0.06, 0.08, 0.62, "smoked body")
check(near(g().grain._alpha, st.grain * 0.35 / 0.45), "smoked grain: the built one, scaled (Pearl has none)")
check(near(washPeak(), st.wash * 0.14 / 0.18), "smoked wash, through its gradient (r7's SetWash): the built one, scaled")
g().wash:SetAlpha(0.5)
eq(g().wash._alpha, nil, "(the stub, like the client: SetAlpha on a gradient does nothing)")
GlassPanel._test.slash("glass clear")
check(near(washPeak(), st.wash), "clear again: the built wash")
GlassPanel._test.slash("glass smoked")

-- The class colour, shaded by the preset, at the preset's own alpha.
GlassPanel._test.slash("tint class")
eq(GlassPanelDB.glassTint, "class", "/gpanel tint class")
tintIs(0.67 * 0.3, 0.83 * 0.3, 0.45 * 0.3, 0.62, "smoked hunter green")
GlassPanel._test.slash("glass clear")
tintIs(0.67 * 0.6, 0.83 * 0.6, 0.45 * 0.6, 0.24, "clear hunter green")
GlassPanel._test.slash("tint neutral")
tintIs(0.13, 0.16, 0.22, 0.24, "back to neutral")

-- A wrong word changes nothing and says what's allowed.
WoW.chat = {}
GlassPanel._test.slash("glass frosted")
eq(GlassPanelDB.glass, "clear", "unknown glass refused")
check(said():find("glass: clear or smoked", 1, true), "and said")
GlassPanel._test.slash("tint red")
eq(GlassPanelDB.glassTint, "neutral", "unknown tint refused")
check(said():find("tint: neutral or class", 1, true), "and said")
eq(GlassPanel.Settings.SetGlass(nil), false, "SetGlass(nil): false")

-- Kept across sessions, and painted when the bar is built.
local saved = { glass = "smoked", glassTint = "class" }
loadAddon({ db = saved })
tintIs(0.67 * 0.3, 0.83 * 0.3, 0.45 * 0.3, 0.62, "saved smoked + class painted at load")

-- Bad saved values fall back to the defaults.
loadAddon({ db = { glass = "plastic", glassTint = 7 } })
eq(GlassPanelDB.glass, "clear", "bad saved glass: clear")
eq(GlassPanelDB.glassTint, "neutral", "bad saved tint: neutral")

-- No class colour (an unknown class, or a secret class): the preset's own.
WoW.playerClass = { "Nobody", "NOBODY", 99 }
loadAddon({ db = { glass = "smoked", glassTint = "class" } })
tintIs(0.05, 0.06, 0.08, 0.62, "unknown class: the smoked body")
WoW.playerClass = { WoW.Secret("class name"), WoW.Secret("class file"), 3 }
loadAddon({ db = { glass = "clear", glassTint = "class" } })
tintIs(0.13, 0.16, 0.22, 0.24, "secret class: the clear body")
eq(next(GlassPanel.failures or {}), nil, "nothing failed")

-- The class known only once the world is up: painted then.
WoW.playerClass = { "Nobody", "NOBODY", 99 }
loadAddon({ db = { glass = "clear", glassTint = "class" } })
WoW.playerClass = { "Mage", "MAGE", 8 }
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
tintIs(0.25 * 0.6, 0.78 * 0.6, 0.92 * 0.6, 0.24, "class colour at PLAYER_ENTERING_WORLD")

-- Clear follows the library: its built colour, whatever the defaults are.
loadAddon({ before = function() GlassPanel.Glass.STYLE.tint = { 0.2, 0.2, 0.2, 0.3 } end })
tintIs(0.2, 0.2, 0.2, 0.3, "clear: whatever tint the library built")
GlassPanel._test.slash("glass smoked")
GlassPanel._test.slash("glass clear")
tintIs(0.2, 0.2, 0.2, 0.3, "back to clear: the built tint again")

-- Asking for the class colour while it can't be read: said, not silent;
-- retried at PLAYER_ENTERING_WORLD only while it's pending.
WoW.playerClass = { "Nobody", "NOBODY", 99 }
loadAddon()
WoW.chat = {}
GlassPanel._test.slash("tint class")
check(said():find("class colour can't be read yet", 1, true), "unreadable class colour: said")
eq(GlassPanel.Bar.glassPending, true, "and pending")
WoW.playerClass = { "Mage", "MAGE", 8 }
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
tintIs(0.25 * 0.6, 0.78 * 0.6, 0.92 * 0.6, 0.24, "painted once readable")
eq(GlassPanel.Bar.glassPending, false, "no longer pending")
local calls, real = 0, GlassPanel.Bar.ApplyGlass
GlassPanel.Bar.ApplyGlass = function(...) calls = calls + 1 return real(...) end
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(calls, 0, "a later loading screen doesn't repaint")
GlassPanel.Bar.ApplyGlass = real

-- A throw while painting is recorded, and the bar is still built whole.
loadAddon({ db = { glass = "smoked", glassTint = "neutral" }, before = function()
    GlassPanel.Glass.SetSurfaceTint = function() error("boom") end
end })
check(GlassPanel.failures and GlassPanel.failures["bar:glass"], "paint failure recorded")
check(GlassPanel.Bar.frame and GlassPanel.Bar.content and GlassPanel.Bar.marker, "bar built anyway")

done("test_glass")
