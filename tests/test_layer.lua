-- The Layer plugin (#17, #138: the layer is the creature GUID's server field).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GREY_Q = "|cff888888?|r"
local function tip()
    local b = block("layer").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
-- A new creature on a layer: its own spawn and its own zoneUID, which says
-- nothing about the layer (#138).
local spawn = 0
local function npc(layer, kind)
    spawn = spawn + 1
    return string.format("%s-0-%d-0-%d-5624-%010X", kind or "Creature", layer, 76000 + spawn, spawn)
end
local function target(guid, opts)
    WoW.units.target = { guid = guid, isPlayer = opts and opts.isPlayer, controlled = opts and opts.controlled }
    WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
end
local function plate(i, guid)
    WoW.units["nameplate" .. i] = { guid = guid }
    WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i); WoW.tick()
end
-- Two creatures that agree: enough while the layer is unknown.
local function seen(layer) target(npc(layer)); plate(1, npc(layer)) end

local T = WoW.serverTime
-- This realm's saved zones.
local function DB() return GlassPanelLayerDB.realms[WoW.realm] end

-- Saves from before #138 hold zoneUIDs, not layers: dropped once.
GlassPanelLayerDB = { maps = { [1429] = { [77] = T } }, realms = { Doomhowl = { [1429] = { [76067] = T } } } }
loadAddon()
eq(GlassPanelLayerDB.v, 2, "format stamped")
eq(GlassPanelLayerDB.maps, nil, "the pre-release realm-less format is dropped")
eq(next(GlassPanelLayerDB.realms), nil, "zoneUID sightings dropped")

-- Saved in this format: one fresh layer here, one expired, one malformed entry.
GlassPanelLayerDB = { v = 2, realms = {
    Doomhowl = {
        [1429] = { [5000] = T - 600, [4000] = T - 7200 },
        [1453] = "junk",
    },
    -- Another realm's ids in the same zone: never ranked with ours.
    Soulseeker = { [1429] = { [100] = T - 60, [200] = T - 60 } },
} }
loadAddon()
eq(textOf("layer"), GREY_Q, "unknown until a creature is seen")
check(tip():find("two must agree", 1, true), "hint")
check(tip():find("Current layer\tunknown", 1, true), "tooltip: unknown")
eq(DB()[1429][4000], nil, "expired entry pruned at load")
eq(DB()[1429][5000], T - 600, "fresh entry kept")
eq(DB()[1453], nil, "malformed entry dropped")
eq(GlassPanelLayerDB.realms.Soulseeker[1429][100], T - 60, "other realms kept")

-- One creature isn't proof; a second that agrees is (any zoneUIDs).
target(npc(6843))
eq(textOf("layer"), GREY_Q, "one creature: not yet")
eq(DB()[1429][6843], nil, "and nothing filed")
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf("layer"), GREY_Q, "the same creature again doesn't vote twice")
plate(1, npc(6843))
eq(textOf("layer"), "2", "two agree: second-lowest id seen here (5000 < 6843, this realm only)")
eq(DB()[1429][6843], T, "sighting saved with the server time")

-- Changing a known layer takes 3 of the last 5.
WoW.serverTime = T + 90
plate(2, npc(4500))
plate(3, npc(4500))
eq(textOf("layer"), "2", "two for another layer: kept (a pair of patrols)")
plate(4, npc(4500))
eq(textOf("layer"), "1", "three of five: the new layer (4500 < 5000 < 6843)")
local t = tip()
check(t:find("Current layer\t1  |cff888888(id 4500)|r", 1, true), "tooltip: current layer and id")
check(t:find("Layer 2\tid 5000, 11 min ago", 1, true), "tooltip: saved layer listed with age")
check(t:find("Layer 3\tid 6843, 1 min ago", 1, true), "tooltip: earlier layer listed")
check(t:find("> |rLayer 1", 1, true), "tooltip marks the current layer")
-- Mouseover votes too, and a sighting of the current layer refreshes it.
WoW.serverTime = T + 120
WoW.units.mouseover = { guid = npc(4500) }
WoW.fire("UPDATE_MOUSEOVER_UNIT"); WoW.tick()
eq(DB()[1429][4500], T + 120, "mouseover: current layer seen again")

-- Not counted: secret GUIDs, players, pets, totems and guardians, and
-- nothing on a taxi or in an instance.
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
eq(textOf("layer"), GREY_Q, "own phase change: unknown")
WoW.fire("UNIT_PHASE", "party1"); WoW.tick()
local function oneThen(guid, opts, what)
    target(guid, opts)
    plate(5, npc(7777))
    eq(textOf("layer"), GREY_Q, what)
    WoW.fire("UNIT_PHASE", "player"); WoW.tick()
end
oneThen(npc(7777), { controlled = true }, "a player-controlled creature (totem) doesn't vote")
oneThen("Player-4621-0A1B2C3D", { isPlayer = true }, "a player doesn't vote")
oneThen("Pet-0-7777-0-76067-416-0100000001", nil, "a pet doesn't vote")
oneThen(npc(7777), { isPlayer = true }, "UnitIsPlayer doesn't vote")
oneThen("secret", nil, "a secret GUID doesn't vote")
-- A client secret keeps its type: a secret GUID is still a "string".
local secretGuid = npc(7777)
WoW.MarkSecret(secretGuid)
oneThen(secretGuid, nil, "a secret string GUID doesn't vote")
oneThen(npc(0), nil, "a zero server id doesn't vote")
WoW.layer.taxi = true
oneThen(npc(7777), nil, "not on a taxi")
WoW.layer.taxi, WoW.layer.instance = false, true
target(npc(7777)); plate(5, npc(7777))
eq(textOf("layer"), GREY_Q, "not in an instance")
WoW.layer.instance = false
-- Vehicles are creatures too; a readable GUID counts in combat (only a secret one is skipped).
local inCombat = InCombatLockdown
InCombatLockdown = function() return true end
target(npc(4500, "Vehicle")); plate(5, npc(4500))
InCombatLockdown = inCombat
eq(textOf("layer"), "1", "a vehicle and a creature, in combat: counted")

-- A group change moves nobody by itself (a host on the same layer).
WoW.fire("GROUP_JOINED", 1, "Party-1"); WoW.tick()
eq(textOf("layer"), "1", "group joined: kept")

-- SHARD_TRANSFER: the game moved us. Unknown; what's in view is the old layer's.
WoW.timers = {}
local inView = { target = { guid = npc(4500) }, nameplate1 = { guid = npc(4500) }, nameplate2 = { guid = npc(4500) } }
WoW.units = inView
WoW.fire("SHARD_TRANSFER"); WoW.tick()
eq(textOf("layer"), GREY_Q, "moved: unknown")
eq(#WoW.timers, 3, "three looks scheduled")
WoW.now = WoW.now + 0.3
WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf("layer"), GREY_Q, "the units in view at the move don't vote")
WoW.now = WoW.now + 5
WoW.flushTimers(5); WoW.tick()
eq(textOf("layer"), GREY_Q, "5 s later: still the old layer's units, still unknown")
plate(3, npc(5000))
plate(4, npc(5000))
eq(textOf("layer"), "2", "two creatures of the new layer: known")
-- After STALE seconds the units that were in view vote again.
WoW.fire("UNIT_PHASE", "player")
WoW.units = inView
WoW.now = WoW.now + 10
WoW.flushTimers(); WoW.tick()
eq(textOf("layer"), "1", "the last look: the units in view at the move vote again")
WoW.units = {}

-- Layers are a zone's: a cave or building map inside it keeps the layer.
WoW.mapInfo = { [1429] = { mapType = 3, parentMapID = 1415 }, [1415] = { mapType = 2, parentMapID = 947 },
    [2001] = { mapType = 5, parentMapID = 2000 }, [2000] = { mapType = 4, parentMapID = 1429 } }
WoW.map = 2001
WoW.fire("ZONE_CHANGED_INDOORS"); WoW.tick()
eq(textOf("layer"), "1", "a micro map inside the zone: kept")
plate(5, npc(4500))
eq(DB()[2001], nil, "filed under the zone, not the building")
WoW.map = 1429

-- A new zone ranks its own ids; a server id may be shared between zones.
WoW.map = 1453
WoW.fire("ZONE_CHANGED_NEW_AREA"); WoW.tick()
eq(textOf("layer"), GREY_Q, "new zone: unknown")
seen(5000)
eq(textOf("layer"), "1", "ranked among this zone's ids only")
eq(DB()[1453][5000], WoW.serverTime, "kept per zone")
-- Votes cast in one zone don't count in the next, even with no event.
target(npc(8000))
WoW.map = 1429
plate(6, npc(8000))
eq(textOf("layer"), GREY_Q, "one vote per zone: not yet")

-- Expiry: after 2 hours an old sighting stops counting, and is pruned on the next one.
WoW.fire("ZONE_CHANGED_NEW_AREA")
WoW.serverTime = T + 120 + 7200
seen(6843)   -- 4500 last seen at T + 120, 5000 and 6843 earlier
eq(textOf("layer"), "1", "expired layers no longer counted")
eq(DB()[1429][4500], nil, "expired layer pruned")

-- Persistence: a reload keeps what was seen, and reads what's on screen again.
DB()[1429][9000] = WoW.serverTime
DB()[1429][1000] = WoW.serverTime - 7000
WoW.units = {}
loadAddon()
eq(textOf("layer"), GREY_Q, "after a reload: unknown until seen")
WoW.units = { target = { guid = npc(6843) }, nameplate9 = { guid = npc(6843) } }
WoW.fire("PLAYER_ENTERING_WORLD", false, true); WoW.tick()
eq(textOf("layer"), "2", "target and nameplates read again on entering the world (1000, 6843, 9000)")
check(tip():find("Layer 3\tid 9000", 1, true), "saved layers rank with the new sighting")
WoW.units = {}

-- A layer that expires between sightings stops counting at the next repaint.
WoW.serverTime = WoW.serverTime + 300
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), "1", "expired layer dropped from the ranks")
check(not tip():find("id 1000", 1, true), "and from the tooltip")

-- Rescans after combat and a taxi.
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
WoW.units = { target = { guid = npc(6843) }, mouseover = { guid = npc(6843) } }
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick()
eq(textOf("layer"), "1", "read again after combat")
WoW.fire("UNIT_PHASE", "player")
WoW.units = { nameplate2 = { guid = npc(9000) }, nameplate3 = { guid = npc(9000) } }
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
eq(textOf("layer"), "2", "read again after a taxi")

-- A new zone map without ZONE_CHANGED_NEW_AREA (Codex review on #17): the old
-- sighting doesn't carry over, even with no creature to read.
WoW.units = {}
WoW.map = 1453
WoW.fire("ZONE_CHANGED_INDOORS"); WoW.tick()
eq(textOf("layer"), GREY_Q, "zone changed through ZONE_CHANGED_INDOORS: unknown")
local t2 = tip()
check(t2:find("Current layer\tunknown", 1, true), "tooltip: unknown")
check(not t2:find("id 9000", 1, true), "tooltip: the old zone's layers aren't listed")
-- Even with no event at all, the next repaint checks the live zone.
WoW.map = 1429
seen(9000)
eq(textOf("layer"), "2", "baseline")
WoW.map = 1453
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), GREY_Q, "zone changed silently: unknown at the next repaint")
seen(3500)
eq(textOf("layer"), "1", "1453's own layer")
-- The reset forgets the zone you're in, not the last sighting's.
local b1429 = DB()[1429]
local blk = block("layer").widget
blk._scripts.OnClick(blk, "RightButton")
check(DB()[1453] ~= nil, "right-click does nothing")
blk._scripts.OnClick(blk, "LeftButton"); WoW.tick()
eq(textOf("layer"), GREY_Q, "left-click: unknown")
check(DB()[1429] == b1429 and b1429 ~= nil, "left-click in 1453 keeps 1429's layers")
eq(DB()[1453], nil, "and forgets 1453's")
check(WoW.chat[#WoW.chat]:find("forgot the layers seen in this zone", 1, true), "prints a line")
-- A new zone through ZONE_CHANGED reads what's on screen again.
WoW.map = 1429
seen(9000)
WoW.map = 1453
WoW.units = { target = { guid = npc(3000) }, nameplate1 = { guid = npc(3000) } }
WoW.fire("ZONE_CHANGED"); WoW.tick()
eq(textOf("layer"), "1", "zone change: what's on screen is read again")
WoW.units = {}
WoW.map = 1429

-- Unreadable server time: nothing saved, nothing ranked (never a made-up 0).
WoW.fire("ZONE_CHANGED_NEW_AREA")
local st = WoW.serverTime
WoW.serverTime = WoW.Secret("time")
seen(9000)
eq(textOf("layer"), GREY_Q, "secret time: unknown")
check(tip():find("Current layer\tunknown", 1, true), "tooltip: unknown")
WoW.serverTime = st
for _, when in pairs(DB()[1429]) do check(type(when) == "number" and when > 0, "no 0 or secret saved") end

-- A realm of its own: another character's realm starts empty here.
seen(9000)
WoW.realm = "Soulseeker"
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), GREY_Q, "another realm: our ids don't rank there")
GlassPanelLayerDB.realms.Soulseeker = { [1429] = { [100] = WoW.serverTime, [200] = WoW.serverTime } }
WoW.fire("ZONE_CHANGED_NEW_AREA")
seen(150)
eq(textOf("layer"), "2", "ranked among Soulseeker's ids (100, 150, 200)")
eq(GlassPanelLayerDB.realms.Soulseeker[1429][150], WoW.serverTime, "saved under its realm")
eq(GlassPanelLayerDB.realms.Doomhowl[1429][150], nil, "not under ours")
WoW.realm = "Doomhowl"

-- Codex review on #139: the same creatures seen again keep a layer fresh...
WoW.fire("ZONE_CHANGED_NEW_AREA")
WoW.units = {}
seen(9100)
check(textOf("layer") ~= GREY_Q, "baseline: known")
local t0 = WoW.serverTime
WoW.serverTime = t0 + 7000
WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()   -- the very same target
eq(DB()[1429][9100], t0 + 7000, "a creature that already voted still refreshes the sighting")
WoW.serverTime = t0 + 7300
GlassPanel.Refresh("layer"); WoW.tick()
check(textOf("layer") ~= GREY_Q, "still known 2 h after the first sighting")
-- ...and creatures that voted before a move stay the old layer's for STALE
-- seconds, even with no unit token at the move (their nameplates come back).
WoW.fire("ZONE_CHANGED_NEW_AREA")
WoW.units = {}
local g1, g2 = npc(9200), npc(9200)
plate(1, g1); plate(2, g2)
check(textOf("layer") ~= GREY_Q, "baseline: known from two nameplates")
WoW.units, WoW.timers = {}, {}
WoW.fire("SHARD_TRANSFER"); WoW.tick()
WoW.now = WoW.now + 1
plate(1, g1); plate(2, g2)
eq(textOf("layer"), GREY_Q, "old nameplates back after the move: no vote")
WoW.units, WoW.timers = {}, {}
-- A second move within the 10 s keeps the first move's creatures out until
-- their own 10 s are up, even when they're out of view at the second (#140).
WoW.fire("ZONE_CHANGED_NEW_AREA")
local o1, o2 = npc(9300), npc(9300)
plate(1, o1); plate(2, o2)
check(textOf("layer") ~= GREY_Q, "baseline: known")
WoW.units = {}
local t1 = WoW.now
WoW.fire("SHARD_TRANSFER")
WoW.now = t1 + 3
WoW.fire("SHARD_TRANSFER"); WoW.tick()
WoW.now = t1 + 4
plate(1, o1); plate(2, o2)
eq(textOf("layer"), GREY_Q, "4 s after the first move: its creatures still don't vote")
WoW.now = t1 + 11
plate(1, o1); plate(2, o2)
check(textOf("layer") ~= GREY_Q, "11 s after the first move: they vote again")
WoW.units, WoW.timers = {}, {}

check(next(GlassPanel.failures) == nil, "no failures")
done("test_layer")
