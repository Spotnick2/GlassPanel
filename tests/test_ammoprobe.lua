-- AmmoProbe (#177): every command runs on the stubbed client without throwing,
-- logs to its own saved table and never to chat, reads the ranged slot's count
-- and durability raw, tells whether the slot's count includes the same weapon
-- in the bags, follows UPDATE_INVENTORY_DURABILITY, and survives secrets and
-- missing APIs. A ForeverProbe module: CI skips it (FOREVERPROBE_OPTIONAL=1),
-- locally it runs.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelAmmo" }

local THROWN, BOW = 104, 101
local function catalogue()
    WoW.items = {
        [BOW] = { classID = 2, subClassID = 2, icon = 1001, name = "Hunting Bow" },
        [THROWN] = { classID = 2, subClassID = 16, icon = 1004, name = "Small Throwing Knife" },
    }
end

-- A rogue with weapon in the ranged slot, the slot's count, its durability and the bags.
local function setup(weapon, count, cur, max, bags)
    catalogue()
    WoW.playerClass = { "ROGUE", "ROGUE", 1 }
    WoW.equipped = {}
    if weapon then WoW.equipped[18] = { id = weapon } end
    WoW.invCount = { [18] = count }
    WoW.gear = {}
    if cur then WoW.gear[18] = { cur = cur, max = max } end
    WoW.bags = bags or {}
    WoW.usesAmmo = true
end

loadAddon()   -- GlassPanel with the Ammo plugin
setup(THROWN, 1, 80, 100)
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
WoW.chat = {}  -- (GlassPanel's own lines: the probe's chat is what's checked)
loadForeverProbe()
local ns = {}
assert(loadfile("Tools/AmmoProbe/AmmoProbe.lua"))("AmmoProbe", ns)
WoW.fire("ADDON_LOADED", "AmmoProbe")
local T = ns._test

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local function logHas(pattern)
    for _, line in ipairs(AmmoProbeDB.log) do if line:find(pattern, 1, true) then return line end end
    return nil
end

check(type(AmmoProbeDB) == "table" and logHas("loaded (1 loads)"), "its own saved log")

-- The ranged slot with a thrown weapon: both calls, raw, and the plain reading.
fp("ammo read")
check(logHas("GetInventoryItemCount(player, 18)"), "the slot's count, called")
check(logHas("GetInventoryItemDurability(18)"), "its durability, called")
check(logHas("the ranged weapon is a THROWN weapon"), "the weapon told as thrown")
check(logHas("reading: count 1, durability 80/100, bags 0"), "the plain reading")
local r = T.last()
eq(r.count, 1, "count read")
eq(r.cur, 80, "durability read")
eq(r.max, 100, "and its maximum")

-- The procedure's checks.
local ok, why = T.equippedCheck()
eq(ok, true, "a thrown weapon with durability passes")
eq(why, "durability 80/100, count 1", "and says what it read")
check((T.blockText() or ""):find("80", 1, true), "the Ammo block's text is read (80/100)")
check(logHas("Ammo block shows:"), "and logged")

-- A throw wears it down: every UPDATE_INVENTORY_DURABILITY is logged with the change.
WoW.gear[18].cur = 79
WoW.fire("UPDATE_INVENTORY_DURABILITY")
check(logHas("UPDATE_INVENTORY_DURABILITY #1: ranged 79/100 (-1)"), "the event, with the change")
ok, why = T.wornCheck()
eq(ok, true, "worn down since the first reading")
eq(why, "80 before, 79 now", "by how much")

-- A spare in the bags: does the slot's count include it?
local spare = { [0] = { slots = 2, free = 1, family = 0, items = { { id = THROWN, count = 1 } } } }
WoW.bags = spare
WoW.invCount[18] = 2
ok, why = T.spareCheck()
eq(ok, true, "a spare in the bags")
check(why:find("INCLUDES the bags", 1, true), "a count of 2 with one spare: the count includes the bags")
WoW.invCount[18] = 1
_, why = T.spareCheck()
check(why:find("equipped one only", 1, true), "a count of 1 with one spare: the equipped one only")
local total, slots, unsure = T.inBags(THROWN)
eq(total, 1, "one in the bags")
eq(slots, 1, "in one slot")
eq(unsure, false, "every slot read")
WoW.bags = {}
ok = T.spareCheck()
eq(ok, false, "no spare: the step fails (Skip)")

-- Secrets: said, never compared.
WoW.gear[18] = { cur = "secret", max = "secret" }
WoW.invCount[18] = "secret"
r = T.read("secret")
eq(r.cur, nil, "a secret durability isn't a number")
eq(r.count, nil, "nor a secret count")
WoW.fire("UPDATE_INVENTORY_DURABILITY")
check(logHas("UPDATE_INVENTORY_DURABILITY #2: ranged"), "a secret durability at the event: logged, no throw")
ok, why = T.equippedCheck()
eq(ok, false, "no durability read: the check fails")
check(why:find("no durability read", 1, true), "and says so")
WoW.bags = { [0] = { slots = 1, free = 0, family = 0, items = { "secret" } } }
_, _, unsure = T.inBags(THROWN)
eq(unsure, true, "a secret bag slot: the bag total is unsure")
WoW.bags = {}

-- Not thrown, or nothing equipped.
setup(BOW, 1, 50, 50)
ok, why = T.equippedCheck()
eq(ok, false, "a bow isn't a thrown weapon")
check(logHas("not thrown (class 2, subclass 2)"), "its class and subclass are logged")
setup(nil)
ok, why = T.equippedCheck()
eq(ok, false, "an empty ranged slot")
eq(why, "nothing in the ranged slot", "said")

-- The procedure is defined; nothing went to chat.
fp("steps")
fp("ammo block")
fp("ammo clear")
eq(#WoW.chat, 0, "never writes to chat")

done("test_ammoprobe")
