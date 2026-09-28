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
GlassPanelLayerDB = { maps = {
    [1429] = { [50] = T - 600, [9] = T - 7200 },
    [1453] = "junk",
} }

loadAddon()
eq(textOf("layer"), GREY_Q, "unknown until a creature is seen")
check(tip():find("Target or mouse over an NPC to detect your layer.", 1, true), "hint")
check(tip():find("Current layer\tunknown", 1, true), "tooltip: unknown")
eq(GlassPanelLayerDB.maps[1429][9], nil, "expired entry pruned at load")
eq(GlassPanelLayerDB.maps[1429][50], T - 600, "fresh entry kept")
eq(GlassPanelLayerDB.maps[1453], nil, "malformed entry dropped")

-- Target: ranked among the zone ids known on this map (50 < 76067).
target(creature(76067))
eq(textOf("layer"), "2", "target: second-lowest zone id seen here")
eq(GlassPanelLayerDB.maps[1429][76067], T, "sighting saved with the server time")

-- Mouseover: a lower id seen, so that's layer 1 now.
WoW.units.mouseover = { guid = creature(18) }
WoW.fire("UPDATE_MOUSEOVER_UNIT"); WoW.tick()
eq(textOf("layer"), "1", "mouseover detected")

-- Nameplate (the unit token comes with the event).
WoW.units.nameplate3 = { guid = creature(76067) }
WoW.fire("NAME_PLATE_UNIT_ADDED", "nameplate3"); WoW.tick()
eq(textOf("layer"), "3", "nameplate detected: third of 18, 50, 76067")
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
eq(GlassPanelLayerDB.maps[1429][424242], nil, "and not saved")
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
local inCombat = InCombatLockdown
InCombatLockdown = function() return true end
target(creature(76067))
InCombatLockdown = inCombat
eq(textOf("layer"), GREY_Q, "not in combat")
target(creature(76067))
eq(textOf("layer"), "3", "detected again out of combat")

-- Resets: group left, phase change for the player (not for others).
WoW.fire("GROUP_LEFT", 1, "Party-1"); WoW.tick()
eq(textOf("layer"), GREY_Q, "group left: unknown")
target(creature(76067))
WoW.fire("UNIT_PHASE", "party1"); WoW.tick()
eq(textOf("layer"), "3", "someone else's phase change: kept")
WoW.fire("UNIT_PHASE", "player"); WoW.tick()
eq(textOf("layer"), GREY_Q, "own phase change: unknown")

-- A new map ranks its own zone ids: 76067 is layer 1 in Stormwind.
target(creature(76067))
WoW.layer.map = 1453
WoW.fire("ZONE_CHANGED_NEW_AREA"); WoW.tick()
eq(textOf("layer"), GREY_Q, "new map: unknown")
target(creature(76067))
eq(textOf("layer"), "1", "ranked among this map's ids only")
eq(GlassPanelLayerDB.maps[1453][76067], WoW.serverTime, "kept per map")

-- Expiry: after 2 hours an old sighting stops counting, and is pruned on
-- the next one.
WoW.layer.map = 1429
WoW.fire("ZONE_CHANGED_NEW_AREA")
WoW.serverTime = T + 90 + 7200
target(creature(76067))   -- 18 last seen at T + 90, 50 at T - 600
eq(textOf("layer"), "1", "expired layers no longer counted")
eq(GlassPanelLayerDB.maps[1429][18], nil, "expired layer pruned")

-- Persistence: a reload keeps what was seen.
WoW.units.target = { guid = creature(18) }
WoW.fire("PLAYER_TARGET_CHANGED")
GlassPanelLayerDB.maps[1453][5] = WoW.serverTime   -- fresh on another map (76067 there expires)
loadAddon()
eq(textOf("layer"), GREY_Q, "after a reload: unknown until seen")
target(creature(76067))
eq(textOf("layer"), "2", "saved layers rank the new sighting")

-- A layer that expires between sightings stops counting at the next repaint.
GlassPanelLayerDB.maps[1429][18] = WoW.serverTime - 7000
WoW.serverTime = WoW.serverTime + 300
WoW.fire("UNIT_PHASE", "party1"); WoW.tick()
eq(textOf("layer"), "1", "expired layer dropped from the ranks")
check(not tip():find("zone 18", 1, true), "and from the tooltip")

-- Left-click forgets this map's layers; other buttons don't.
local b = block("layer").widget
b._scripts.OnClick(b, "RightButton")
eq(textOf("layer"), "1", "right-click does nothing")
check(GlassPanelLayerDB.maps[1429] ~= nil, "right-click keeps the map")
b._scripts.OnClick(b, "LeftButton"); WoW.tick()
eq(textOf("layer"), GREY_Q, "left-click: unknown")
eq(GlassPanelLayerDB.maps[1429], nil, "left-click forgets this map")
check(GlassPanelLayerDB.maps[1453] ~= nil, "other maps kept")
check(WoW.chat[#WoW.chat]:find("forgot the layers seen on this map", 1, true), "prints a line")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_layer")
