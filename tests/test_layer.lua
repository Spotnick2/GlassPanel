-- The Layer plugin (#17).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GREY_Q = "|cff888888?|r"
local function tip()
    local b = block("layer").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function creature(zone) return "Creature-0-4621-0-" .. zone .. "-5624-0008392ED7" end
local function target(guid, isPlayer)
    WoW.units.target = { guid = guid, isPlayer = isPlayer }
    WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
end

-- Saved from an earlier session: one fresh layer on this map, one expired,
-- one malformed entry.
local T = WoW.serverTime
-- This realm's saved maps.
local function DB() return GlassPanelLayerDB.realms[WoW.realm] end
GlassPanelLayerDB = { maps = { [1429] = { [77] = T } }, realms = {
    Doomhowl = {
        [1429] = { [50] = T - 600, [9] = T - 7200 },
        [1453] = "junk",
    },
    -- Another realm's ids on the same map: never ranked with ours.
    Soulseeker = { [1429] = { [20] = T - 60, [30] = T - 60 } },
} }

loadAddon()
eq(textOf("layer"), GREY_Q, "unknown until a creature is seen")
check(tip():find("Target or mouse over an NPC to detect your layer.", 1, true), "hint")
check(tip():find("Current layer\tunknown", 1, true), "tooltip: unknown")
eq(DB()[1429][9], nil, "expired entry pruned at load")
eq(DB()[1429][50], T - 600, "fresh entry kept")
eq(DB()[1453], nil, "malformed entry dropped")
eq(GlassPanelLayerDB.maps, nil, "the pre-release realm-less format is dropped")
eq(GlassPanelLayerDB.realms.Soulseeker[1429][20], T - 60, "other realms kept")

-- Target: ranked among the zone ids known on this map (50 < 76067).
target(creature(76067))
eq(textOf("layer"), "2", "target: second-lowest zone id seen here (this realm only)")
eq(DB()[1429][76067], T, "sighting saved with the server time")

-- Mouseover: a lower id seen, so that's layer 1 now.
WoW.units.mouseover = { guid = creature(18) }
WoW.fire("UPDATE_MOUSEOVER_UNIT"); WoW.tick()
eq(textOf("layer"), "1", "mouseover detected")

-- Nameplate (the unit token comes with the event): it confirms an id
-- already known on this map...
WoW.units.nameplate3 = { guid = creature(76067) }
WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); WoW.tick()
eq(textOf("layer"), "3", "nameplate detected: third of 18, 50, 76067")
-- ...but never adds one: it may be across a zone border.
WoW.units.nameplate4 = { guid = creature(12) }
WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); WoW.tick()
eq(textOf("layer"), "3", "a new id on a nameplate: ignored")
eq(DB()[1429][12], nil, "and not saved")
WoW.serverTime = T + 90
local t = tip()
check(t:find("Current layer\t3  |cff888888(zone 76067)|r", 1, true), "tooltip: current layer and zone id")
check(t:find("Layer 1\tzone 18, 1 min ago", 1, true), "tooltip: known layers with age")
check(t:find("Layer 2\tzone 50, 11 min ago", 1, true), "tooltip: saved layer listed")
check(t:find("> |rLayer 3", 1, true), "tooltip marks the current layer")

-- Not detected: secret GUIDs, players, pets, and nothing on a taxi, in an
-- instance or in combat.
target(creature(18))
eq(textOf("layer"), "1", "baseline")
WoW.fire("GROUP_JOINED", 1, "Party-1"); WoW.tick()
eq(textOf("layer"), GREY_Q, "group joined: unknown again")
target("secret")
eq(textOf("layer"), GREY_Q, "secret GUID skipped")
-- A client secret keeps its type: a secret GUID is still a "string".
local secretGuid = creature(424242)
WoW.MarkSecret(secretGuid)
target(secretGuid)
eq(textOf("layer"), GREY_Q, "secret string GUID skipped")
eq(DB()[1429][424242], nil, "and not saved")
target("Player-4621-0A1B2C3D", true)
eq(textOf("layer"), GREY_Q, "player skipped")
target("Pet-0-4621-0-76067-416-0100000001")
eq(textOf("layer"), GREY_Q, "pet skipped")
target(creature(76067), true)
eq(textOf("layer"), GREY_Q, "UnitIsPlayer skipped")
WoW.layer.taxi = true
target(creature(76067))
eq(textOf("layer"), GREY_Q, "not on a taxi")
WoW.layer.taxi, WoW.layer.instance = false, true
target(creature(76067))
eq(textOf("layer"), GREY_Q, "not in an instance")
WoW.layer.instance = false
-- A readable GUID counts in combat too (only a secret one is skipped).
local inCombat = InCombatLockdown
InCombatLockdown = function() return true end
target(creature(76067))
InCombatLockdown = inCombat
eq(textOf("layer"), "3", "readable in combat: counted")

-- Resets: group left, phase change for the player (not for others).
WoW.fire("GROUP_LEFT", 1, "Party-1"); WoW.tick()
eq(textOf("layer"), GREY_Q, "group left: unknown")
WoW.timers = {}
target(creature(76067))
WoW.fire("UNIT_PHASE", "party1"); WoW.tick()
eq(textOf("layer"), "3", "someone else's phase change: kept")
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
eq(textOf("layer"), GREY_Q, "own phase change: unknown")

-- A new map ranks its own zone ids: 80001 is layer 1 in Stormwind.
target(creature(76067))
WoW.map = 1453
WoW.fire("ZONE_CHANGED_NEW_AREA"); WoW.tick()
eq(textOf("layer"), GREY_Q, "new map: unknown")
target(creature(80001))
eq(textOf("layer"), "1", "ranked among this map's ids only")
eq(DB()[1453][80001], WoW.serverTime, "kept per map")
-- An id known on one map isn't filed under another (a creature across the
-- border, even targeted): 50 belongs to 1429. The layer stays as it was.
target(creature(50))
eq(textOf("layer"), "1", "another map's id: not this map's layer")
eq(DB()[1453][50], nil, "and not saved here")

-- Expiry: after 2 hours an old sighting stops counting, and is pruned on
-- the next one.
WoW.map = 1429
WoW.fire("ZONE_CHANGED_NEW_AREA")
WoW.serverTime = T + 90 + 7200
target(creature(76067))   -- 18 last seen at T + 90, 50 at T - 600
eq(textOf("layer"), "1", "expired layers no longer counted")
eq(DB()[1429][18], nil, "expired layer pruned")

-- Persistence: a reload keeps what was seen, and reads the target again.
WoW.units.target = { guid = creature(18) }
WoW.fire("PLAYER_TARGET_CHANGED")
DB()[1453][5] = WoW.serverTime   -- fresh on another map (80001 there expires)
local saved = WoW.units.target
WoW.units = {}
loadAddon()
eq(textOf("layer"), GREY_Q, "after a reload: unknown until seen")
WoW.units.target = saved
WoW.fire("PLAYER_ENTERING_WORLD", false, true); WoW.tick()
eq(textOf("layer"), "1", "the target is read again on entering the world")
target(creature(76067))
eq(textOf("layer"), "2", "saved layers rank the new sighting")

-- A layer that expires between sightings stops counting at the next repaint.
DB()[1429][18] = WoW.serverTime - 7000
target(creature(76070))
eq(textOf("layer"), "3", "18, 76067, 76070")
WoW.serverTime = WoW.serverTime + 300
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), "2", "expired layer dropped from the ranks")
check(not tip():find("zone 18", 1, true), "and from the tooltip")

-- Left-click forgets this map's layers; other buttons don't.
local b = block("layer").widget
b._scripts.OnClick(b, "RightButton")
eq(textOf("layer"), "2", "right-click does nothing")
check(DB()[1429] ~= nil, "right-click keeps the map")
b._scripts.OnClick(b, "LeftButton"); WoW.tick()
eq(textOf("layer"), GREY_Q, "left-click: unknown")
eq(DB()[1429], nil, "left-click forgets this map")
check(DB()[1453] ~= nil, "other maps kept")
check(WoW.chat[#WoW.chat]:find("forgot the layers seen on this map", 1, true), "prints a line")

-- Rescans: what's on screen is read again after combat and a taxi, and a
-- few times after a group change (the hop comes later, with no event).
WoW.fire("ZONE_CHANGED_NEW_AREA"); WoW.tick()
target(creature(18))         -- known here again, for the group change below
target(creature(76067))
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
eq(textOf("layer"), GREY_Q, "baseline: unknown, a creature targeted")
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick()
eq(textOf("layer"), "2", "read again after combat")
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
WoW.fire("PLAYER_CONTROL_GAINED"); WoW.tick()
eq(textOf("layer"), "2", "read again after a taxi")
WoW.units.target = nil
WoW.units.nameplate7 = { guid = creature(76067) }
WoW.timers = {}
-- The target wins over the mouseover and nameplates (all three known).
WoW.fire("UNIT_PHASE", "player")
WoW.units.target = { guid = creature(18) }
WoW.units.mouseover = { guid = creature(76067) }
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick()
eq(textOf("layer"), "1", "rescan: the target first")
-- A rescan that finds only a new id on a nameplate files nothing.
WoW.units.target, WoW.units.mouseover = nil, nil
WoW.units.nameplate7 = { guid = creature(99999) }
WoW.fire("UNIT_PHASE", "player")
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.tick()
eq(textOf("layer"), GREY_Q, "rescan: a new nameplate id isn't a layer")
eq(DB()[1429][99999], nil, "nor saved")
WoW.units.nameplate7 = { guid = creature(76067) }
WoW.fire("GROUP_JOINED", 1, "Party-1"); WoW.tick()
eq(textOf("layer"), GREY_Q, "group joined: unknown")
eq(#WoW.timers, 3, "three looks scheduled")
WoW.units.nameplate7 = { guid = creature(18) }   -- the old layer's creature still there
WoW.flushTimers(5); WoW.tick()
eq(textOf("layer"), "1", "5 s later: still the old layer")
WoW.units.nameplate7 = { guid = creature(76067) }  -- the hop happened
WoW.flushTimers(15); WoW.tick()
eq(textOf("layer"), "2", "15 s later: the new layer, with no event")
WoW.flushTimers(); WoW.tick()
WoW.units.nameplate7 = nil

-- A new uiMapID without ZONE_CHANGED_NEW_AREA (Codex review): the old
-- sighting doesn't carry over, even with no creature to read.
WoW.fire("ZONE_CHANGED_NEW_AREA"); WoW.tick()
target(creature(76067))
eq(textOf("layer"), "2", "baseline on 1429")
WoW.units = {}
WoW.map = 1453
WoW.fire("ZONE_CHANGED_INDOORS"); WoW.fire("PLAYER_TARGET_CHANGED"); WoW.tick()
eq(textOf("layer"), GREY_Q, "map changed through ZONE_CHANGED_INDOORS: unknown")
local t2 = tip()
check(t2:find("Current layer\tunknown", 1, true), "tooltip: unknown")
check(not t2:find("zone 76067", 1, true), "tooltip: the old map's layers aren't listed")
-- Even with no event at all, the next repaint checks the live map.
WoW.map = 1429
WoW.fire("ZONE_CHANGED"); WoW.tick()
target(creature(76067))
WoW.map = 1453
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), GREY_Q, "map changed silently: unknown at the next repaint")
local t3 = tip()
check(t3:find("Current layer	unknown", 1, true), "silent change: tooltip unknown")
check(not t3:find("zone 76067", 1, true), "silent change: the old map's layers aren't listed")
-- The reset forgets the map you're on, not the last sighting's.
local b1429 = DB()[1429]
local blk = block("layer").widget
blk._scripts.OnClick(blk, "LeftButton"); WoW.tick()
check(DB()[1429] == b1429 and b1429 ~= nil, "left-click on 1453 keeps 1429's layers")
eq(DB()[1453], nil, "and forgets 1453's")
-- A subzone change on the same map keeps the layer (nothing to re-read).
WoW.map = 1429
target(creature(76067))
WoW.units = {}
WoW.fire("ZONE_CHANGED"); WoW.tick()
eq(textOf("layer"), "2", "subzone change, same map: kept")
-- A new map through ZONE_CHANGED re-reads what's on screen.
WoW.map = 1453
WoW.units.target = { guid = creature(80500) }
WoW.fire("ZONE_CHANGED"); WoW.tick()
eq(textOf("layer"), "1", "map change: the target is read again")
WoW.units = {}
WoW.map = 1429

-- Unreadable server time: nothing saved, nothing ranked (never a made-up 0).
local st = WoW.serverTime
WoW.serverTime = WoW.Secret("time")
target(creature(76067))
eq(textOf("layer"), GREY_Q, "secret time: unknown")
check(tip():find("Current layer	unknown", 1, true), "tooltip: unknown")
WoW.serverTime = st
for _, seen in pairs(DB()[1429]) do check(type(seen) == "number" and seen > 0, "no 0 or secret saved") end

-- A realm of its own: another character's realm starts empty here.
target(creature(76067))
WoW.realm = "Soulseeker"
GlassPanel.Refresh("layer"); WoW.tick()
eq(textOf("layer"), GREY_Q, "another realm: our ids don't rank there")
GlassPanelLayerDB.realms.Soulseeker = { [1429] = { [20] = WoW.serverTime, [30] = WoW.serverTime } }
WoW.fire("ZONE_CHANGED_NEW_AREA")
target(creature(25))
eq(textOf("layer"), "2", "ranked among Soulseeker's ids (20, 25, 30)")
eq(GlassPanelLayerDB.realms.Soulseeker[1429][25], WoW.serverTime, "saved under its realm")
eq(GlassPanelLayerDB.realms.Doomhowl[1429][25], nil, "not under ours")
WoW.realm = "Doomhowl"

check(next(GlassPanel.failures) == nil, "no failures")
done("test_layer")
