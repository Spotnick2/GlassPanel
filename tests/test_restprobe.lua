-- RestProbe (#81): every command runs on the stubbed client without throwing,
-- logs to its own saved table and never to chat, finds Well Rested in the
-- Legacy trees, lists XP buffs, and survives secrets and missing APIs. A
-- ForeverProbe module: CI skips it (FOREVERPROBE_OPTIONAL=1), locally it runs.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- What the probe reads beyond the shared stub (70338 dump: GetRestState,
-- IsResting, C_UnitAuras, C_Spell, C_Traits).
rawset(_G, "GetRestState", function() return 1, "Rested", 2 end)
local resting = true
rawset(_G, "IsResting", function() return resting end)
local auras = {}
rawset(_G, "C_UnitAuras", { GetAuraDataByIndex = function(unit, i, filter)
    if unit == "player" and filter == "HELPFUL" then return auras[i] end
end })
local spells = { [9001] = { "Well Rested", "Your rested experience accumulates 20% faster and your rested experience "
                            .. "cap is increased by 20%." },
                 [9002] = { "Swift Feet", "Run faster." },
                 [7001] = { "Well Fed", "Experience gained increased by 5%." },
                 [7002] = { "Arcane Intellect", "Increases Intellect." } }
rawset(_G, "C_Spell", {
    GetSpellName = function(id) return spells[id] and spells[id][1] end,
    GetSpellDescription = function(id) return spells[id] and spells[id][2] or "" end,
})
-- The Adventure tree (1188): two nodes, Well Rested at 3/5.
local trees = { [1188] = { 501, 502 }, [1189] = {}, [1187] = {} }
local nodes = { [501] = { activeRank = 3, currentRank = 3, ranksPurchased = 3, maxRanks = 5, entryIDs = { 801 } },
                [502] = { activeRank = 1, maxRanks = 1, entryIDs = { 802 } } }
local entries = { [801] = 901, [802] = 902 }
local defs = { [901] = { spellID = 9001 }, [902] = { spellID = 9002 } }
rawset(_G, "C_Traits", {
    GetConfigIDByTreeID = function(tree) return trees[tree] and 7000 + tree or nil end,
    GetTreeNodes = function(tree) return trees[tree] or {} end,
    GetNodeInfo = function(_, id) return nodes[id] end,
    GetEntryInfo = function(_, id) return { definitionID = entries[id] } end,
    GetDefinitionInfo = function(id) return defs[id] end,
})
rawset(_G, "Constants", { LegacyConsts = { LEGACY_TREE_ADVENTURE_ID = 1188 } })

loadForeverProbe()
local ns = {}
assert(loadfile("Tools/RestProbe/RestProbe.lua"))("RestProbe", ns)
WoW.fire("ADDON_LOADED", "RestProbe")
local T = ns._test

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local function logHas(pattern)
    for _, line in ipairs(RestProbeDB.log) do if line:find(pattern, 1, true) then return line end end
    return nil
end

check(type(RestProbeDB) == "table" and logHas("loaded (1 loads)"), "its own saved log")

-- The pool: 12000/45000 with 3000 rested = 0.0667 of the level.
WoW.player.rested = 3000
fp("rest pool")
check(logHas("rested = 0.0667 levels"), "rested as levels of this level's XP")
check(logHas("GetRestState() 3: [1]=1  [2]=\"Rested\"  [3]=2"), "the rest state, whole")
WoW.player.rested = "secret"
fp("rest pool")
check(logHas("rested / max: unreadable (rested nil"), "a secret pool: said, not touched")
WoW.player.rested = 3000

-- Well Rested in the Adventure tree.
fp("rest talent")
local f = T.found()
check(f and f.tree == 1188 and f.nodeID == 501 and f.rank == 3 and f.max == 5, "Well Rested found: 3/5")
check(logHas("Well Rested: tree 1188 node 501 spell 9001, rank 3/5"), "logged")
check(logHas("node 501 \"Well Rested\" (spell 9001): activeRank=3"), "with every rank field")
eq(logHas("Swift Feet"), nil, "a node that isn't about rest isn't listed")
check(logHas("2 of 2 nodes named"), "every node named")
defs[901] = { spellID = 9001, overrideName = "" }
fp("rest talent")
check(T.found() ~= nil, "an empty override name falls back to the spell's")
trees[1188] = {}
fp("rest talent")
eq(T.found(), nil, "not there: nil")
check(logHas("Well Rested: NOT FOUND"), "and said")
trees[1188] = { 501, 502 }
local realTraits = C_Traits
rawset(_G, "C_Traits", nil)
fp("rest talent")
check(logHas("C_Traits: MISSING pieces"), "no C_Traits: said")
rawset(_G, "C_Traits", realTraits)

-- XP buffs: the ones that speak of experience, with their IDs.
auras = { { spellId = 7001, name = "Well Fed", expirationTime = WoW.now + 600, sourceUnit = "player" },
          { spellId = 7002, name = "Arcane Intellect", expirationTime = 0 } }
fp("rest buffs")
check(logHas("aura 1: id=7001 name=\"Well Fed\" left=600s"), "an aura with its time left")
check(logHas("XP: \"Experience gained increased by 5%.\""), "its description, when it's about experience")
check(logHas("1 aura(s) speak of experience"), "counted")
check(logHas("aura 2: id=7002 name=\"Arcane Intellect\" left=none"), "a permanent one too")
auras = { WoW.Secret("aura") }
fp("rest buffs")
check(logHas("aura 1: <secret table>"), "a secret aura: said, not touched")
auras = {}

-- Build-up: a sample a minute.
fp("rest watch")
check(logHas("watch start: rested 3000"), "watch starts with a sample")
WoW.player.rested = 3000 + 45
WoW.now = WoW.now + 60
WoW.fireTickers()
check(logHas("watch +60s: rested 3045 (+45), 2700.0 XP/h = 48.000% of a level per 8 h"), "rate per hour and per 8 h")
fp("rest watch off")
check(logHas("watch off"), "stopped")

-- The procedure is defined; nothing went to chat.
fp("steps")
eq(#WoW.chat, 0, "never writes to chat")
check(next(GlassPanel and GlassPanel.failures or {}) == nil, "(no GlassPanel failures)")

done("test_restprobe")
