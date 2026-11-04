-- API.LevelAlert (#130): a one-time alert when a readout runs low.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ plugins = false })
local API = GlassPanel.API

local on = true
local a = API.LevelAlert("test", function() return on end)
local function said() return #WoW.warnings end
local function last() return WoW.warnings[#WoW.warnings] end

-- The first reading is the baseline: a /reload while low says nothing.
a.Set(1, "Low: 5.")
eq(said(), 0, "baseline: nothing said")

-- Worse: said once, centre screen, in chat and with the raid-warning sound.
a.Set(2, "Critical: 1.")
eq(said(), 1, "a crossing is said")
eq(last().text, "Critical: 1.", "with its message")
eq(last().r, 1, "critical: red"); eq(last().g, 0.25, "critical: red")
eq(WoW.sounds[1], 8959, "the raid-warning sound")
check(WoW.chat[#WoW.chat]:find("|cffff4040Critical: 1.|r", 1, true), "and a chat line, red")

-- Once per crossing: the same level again, or a better one, says nothing.
a.Set(2, "Critical: 0.")
a.Set(1, "Low: 3.")
eq(said(), 1, "no repeat, no alert on the way up")

-- Back up re-arms: low again after recovering is said again.
a.Set(0, "Fine.")
a.Set(1, "Low: 4.")
eq(said(), 2, "re-armed after recovering")
eq(last().g, 0.82, "low: yellow")
-- Recovering only to low arms critical again, not low.
a.Set(2, "Critical: 1.")
a.Set(1, "Low: 4.")
a.Set(2, "Critical: 1.")
eq(said(), 4, "low -> critical -> low -> critical: said twice more")

-- Unknown readings are ignored.
a.Set(nil, "?")
a.Set(0, nil)
eq(said(), 4, "nil level or message: ignored")

-- Never in combat: held until it ends, with the latest message, if still worse.
a.Set(0, "Fine.")
WoW.combat = true
a.Set(1, "Low: 9.")
a.Set(1, "Low: 7.")
eq(said(), 4, "nothing said in combat")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(said(), 5, "said when combat ends")
eq(last().text, "Low: 7.", "with the latest message")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(said(), 5, "said once")
-- A crossing that recovers before the fight ends says nothing.
a.Set(0, "Fine.")
WoW.combat = true
a.Set(1, "Low: 9.")
a.Set(0, "Fine.")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(said(), 5, "recovered in the fight: nothing said")
-- Unreadable combat state counts as combat.
local realLockdown = InCombatLockdown
InCombatLockdown = function() return WoW.Secret("combat") end
a.Set(1, "Low: 9.")
eq(said(), 5, "secret combat state: held")
InCombatLockdown = realLockdown
WoW.fire("PLAYER_REGEN_ENABLED")
eq(said(), 6, "said when combat ends")

-- Switched off: it follows quietly, so switching on says nothing old.
a.Set(0, "Fine.")
on = false
a.Set(2, "Critical: 0.")
eq(said(), 6, "off: nothing said")
on = true
a.Set(2, "Critical: 0.")
eq(said(), 6, "switched on while critical: nothing said")
a.Set(0, "Fine.")
a.Set(1, "Low: 3.")
eq(said(), 7, "the next crossing is said")
-- An enabled() that throws counts as off.
local b = API.LevelAlert("throws", function() error("boom") end)
b.Set(0, "Fine."); b.Set(2, "Critical.")
eq(said(), 7, "throwing enabled(): off")

-- Reset: the next reading is a new baseline, and a held crossing is dropped.
a.Set(0, "Fine.")
WoW.combat = true
a.Set(1, "Low: 2.")
a.Reset()
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
eq(said(), 7, "reset drops a held crossing")
a.Set(2, "Critical: 0.")
eq(said(), 7, "after a reset: a baseline")

-- No raid warning frame (it throws, or an older client): chat and sound still.
WoW.noRaidWarning = true
local chat, sounds = #WoW.chat, #WoW.sounds
a.Set(0, "Fine.")
a.Set(1, "Low: 1.")
eq(#WoW.chat, chat + 1, "chat line without the raid warning")
eq(#WoW.sounds, sounds + 1, "sound without the raid warning")
check(GlassPanel.failures["test:alert"], "the throw is recorded")
WoW.noRaidWarning = false

done("test_alert")
