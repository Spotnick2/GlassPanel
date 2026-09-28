-- Plugins/Layer/Layer.lua: which layer of the realm you're on (#17), read
-- from the GUIDs of the creatures around you, like TitanLayer (without its
-- NovaWorldBuffs listener, #26, and without the chat announce).
--
-- Forever notes:
-- - A creature's GUID is "Creature-0-<server>-<instance>-<zone>-<npc>-<spawn>";
--   the zone field tells the layers apart (measured on 70009:
--   Creature-0-4621-0-76067-5624-0008392ED7). Players and pets aren't
--   "Creature", so they never count.
-- - Seen from the target, the mouseover and nameplates. UnitGUID takes a
--   PvP-restricted token: in combat a GUID may be secret, so nothing is read
--   under InCombatLockdown, and a secret or non-string GUID is skipped. Not on
--   a taxi or in an instance either (those creatures aren't on your layer).
-- - The number is the rank of your zone id among the ids seen on the SAME map
--   (C_Map.GetBestMapForUnit), sorted ascending: "2" means the second-lowest
--   id seen here. TitanLayer ranked across every zone, which made it
--   meaningless. Known ids live in GlassPanelLayerDB.maps[uiMapID][zoneId] =
--   GetServerTime() of the last sighting, forgotten after 2 hours.
-- - A group change, a new map or a phase change may move you: the current
--   layer is unknown again until the next creature is seen.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local ADDON = "GlassPanelLayer"
local EXPIRE = 7200   -- layers are reshuffled on restarts; a sighting counts for 2 h

-- maps[uiMapID][zoneId] = server time last seen. A session table until our
-- SavedVariables load (ADDON_LOADED), then GlassPanelLayerDB.maps.
local maps = {}
-- The current layer: its zone id and the map it was seen on (nil: unknown).
local current = { zone = nil, map = nil }

local function now() return P(GetServerTime()) or 0 end

-- Forget what's older than EXPIRE on one map (and the map once empty).
local function prune(map, t)
    local ids = maps[map]
    if not ids then return end
    for zone, seen in pairs(ids) do
        if t - seen >= EXPIRE then ids[zone] = nil end
    end
    if next(ids) == nil then maps[map] = nil end
end

-- The zone ids seen on a map and not expired, ascending: the layer numbers.
local function layers(map)
    local list, t = {}, now()
    for zone, seen in pairs(maps[map] or {}) do
        if t - seen < EXPIRE then list[#list + 1] = zone end
    end
    table.sort(list)
    return list
end

local function rank(map, zone)
    for i, z in ipairs(layers(map)) do
        if z == zone then return i end
    end
    return nil
end

local function zoneOf(unit)
    local guid = P(UnitGUID(unit))
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, zone = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(zone)
end

-- Look at one unit; true when it told us the layer.
local function see(unit)
    unit = P(unit)
    if type(unit) ~= "string" or P(InCombatLockdown()) ~= false then return false end
    if P(UnitOnTaxi("player")) == true or P(IsInInstance()) == true then return false end
    if P(UnitIsPlayer(unit)) == true then return false end
    local zone = zoneOf(unit)
    local map = P(C_Map.GetBestMapForUnit("player"))
    if not zone or type(map) ~= "number" then return false end
    local t = now()
    maps[map] = maps[map] or {}
    maps[map][zone] = t
    prune(map, t)
    current.zone, current.map = zone, map
    return true
end

local function forget() current.zone, current.map = nil, nil end

-- Our SavedVariables: keep only well-formed, unexpired entries, then add
-- anything seen this session before they loaded.
local function load()
    local db = rawget(_G, "GlassPanelLayerDB")
    if type(db) ~= "table" then db = {} end
    local saved, t = type(db.maps) == "table" and db.maps or {}, now()
    local clean = {}
    for map, ids in pairs(saved) do
        if type(map) == "number" and type(ids) == "table" then
            for zone, seen in pairs(ids) do
                if type(zone) == "number" and type(seen) == "number" and t - seen < EXPIRE then
                    clean[map] = clean[map] or {}
                    clean[map][zone] = seen
                end
            end
        end
    end
    for map, ids in pairs(maps) do
        clean[map] = clean[map] or {}
        for zone, seen in pairs(ids) do clean[map][zone] = seen end
    end
    maps = clean
    db.maps = maps
    GlassPanelLayerDB = db
end

-- "12 min", "1 h 05".
local function age(seconds)
    local m = math.floor(math.max(seconds, 0) / 60)
    if m < 60 then return m .. " min" end
    return string.format("%d h %02d", math.floor(m / 60), m % 60)
end

GlassPanel.RegisterBlock({
    id = "layer",
    label = "Layer",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    side = "right",
    order = 140,
    events = { "ADDON_LOADED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
               "GROUP_JOINED", "GROUP_LEFT", "ZONE_CHANGED_NEW_AREA", "UNIT_PHASE" },
    onEvent = function(_, event, arg)
        if event == "ADDON_LOADED" then
            if arg == ADDON then load() end
        elseif event == "PLAYER_TARGET_CHANGED" then see("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then see("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then see(arg)
        elseif event == "UNIT_PHASE" then
            if P(arg) == "player" then forget() end
        else
            forget()   -- GROUP_JOINED, GROUP_LEFT, ZONE_CHANGED_NEW_AREA
        end
    end,
    text = function()
        local n = current.zone and rank(current.map, current.zone)
        return n and tostring(n) or "|cff888888?|r"
    end,
    tooltip = function(_, tt)
        tt:AddLine("Layer")
        local n = current.zone and rank(current.map, current.zone)
        if n then
            tt:AddDoubleLine("Current layer", n .. "  |cff888888(zone " .. current.zone .. ")|r", 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddDoubleLine("Current layer", "unknown", 1, 0.82, 0, 0.7, 0.7, 0.7)
        end
        local map = current.map or P(C_Map.GetBestMapForUnit("player"))
        local list = type(map) == "number" and layers(map) or {}
        if #list > 0 then
            tt:AddLine(" ")
            tt:AddLine("Layers seen on this map")
            local t = now()
            for i, zone in ipairs(list) do
                local mark = zone == current.zone and "|cff40ff40> |r" or ""
                tt:AddDoubleLine(mark .. "Layer " .. i, "zone " .. zone .. ", " .. age(t - maps[map][zone]) .. " ago",
                    1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Target or mouse over an NPC to detect your layer.", 0.7, 0.7, 0.7, true)
        tt:AddLine("Left-click: forget this map's layers", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button ~= "LeftButton" then return end
        local map = current.map or P(C_Map.GetBestMapForUnit("player"))
        if type(map) == "number" then maps[map] = nil end
        forget()
        API.Print("Layer: forgot the layers seen on this map.")
        GlassPanel.Refresh("layer")
    end,
})
