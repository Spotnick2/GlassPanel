-- Plugins/Layer/Layer.lua: which layer of the realm you're on (#17), read
-- from the GUIDs of the creatures around you, like TitanLayer (without its
-- NovaWorldBuffs listener, #26, and without the chat announce).
--
-- Forever notes:
-- - A creature's GUID is "Creature-0-<server>-<instance>-<zone>-<npc>-<spawn>";
--   the zone field tells the layers apart (measured on 70009:
--   Creature-0-4621-0-76067-5624-0008392ED7). Players and pets aren't
--   "Creature", so they never count.
-- - Seen from the target, the mouseover and nameplates. A GUID may come back
--   secret (UnitGUID takes a PvP-restricted token): API.Plain plus the type
--   check skip it, so readable GUIDs still count in combat. Not on a taxi or
--   in an instance (those creatures aren't on your layer).
-- - A creature's own map can't be read, only the player's, and a nameplate
--   or mouseover may be across a zone border. So a zone id is filed under
--   the player's map only from the target or mouseover (you're pointing at
--   it), never when that id is already known on another map (zone ids are
--   per zone); nameplates only confirm an id already known on this map.
-- - The number is the rank of your zone id among the ids seen on the SAME map
--   (C_Map.GetBestMapForUnit), sorted ascending: "2" means the second-lowest
--   id seen here. TitanLayer ranked across every zone, which made it
--   meaningless. The numbers are local: nothing on the client says how many
--   layers exist, so a newly seen lower id renumbers yours, and another
--   player's "2" may be your "1" (#26, sharing sightings, would fix that).
--   Known ids live in GlassPanelLayerDB.realms[realm][uiMapID][zoneId] =
--   GetServerTime() of the last sighting, forgotten after 2 hours.
-- - A group change, a new map or a phase change may move you: the current
--   layer is unknown again until the next creature is seen. After a group
--   change the hop comes a little later with no event, so the target and
--   nameplates are read again a few times. They're also read again when you
--   log in or reload, leave combat and land from a taxi.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local ADDON = "GlassPanelLayer"
local EXPIRE = 7200         -- layers are reshuffled on restarts; a sighting counts for 2 h
local REGROUP = { 5, 15, 30 }  -- seconds after a group change to look again
local PLATES = 40

-- realms[realm][uiMapID][zoneId] = server time last seen. A session table
-- until our SavedVariables load (ADDON_LOADED), then GlassPanelLayerDB.realms.
local realms = {}
-- The current layer: its zone id and the map it was seen on (nil: unknown).
local current = { zone = nil, map = nil }
-- The sorted, unexpired ids of one map, kept until something changes.
local cache = { realm = nil, map = nil, list = nil, validUntil = nil }

-- nil when unreadable: never a made-up 0.
local function now()
    local t = P(GetServerTime())
    return type(t) == "number" and t or nil
end

local function realm()
    local r = P(GetRealmName())
    return type(r) == "string" and r or "?"
end

-- This realm's maps (created on first use).
local function maps()
    local r = realm()
    realms[r] = realms[r] or {}
    return realms[r]
end

local function invalidate() cache.realm, cache.map, cache.list, cache.validUntil = nil, nil, nil, nil end

-- Forget what's older than EXPIRE on one map (and the map once empty).
local function prune(map, t)
    local all = maps()
    local ids = all[map]
    if not ids then return end
    for zone, seen in pairs(ids) do
        if t - seen >= EXPIRE then ids[zone] = nil end
    end
    if next(ids) == nil then all[map] = nil end
end

-- The zone ids seen on a map and not expired, ascending: the layer numbers.
-- nil when the time can't be read (expiry can't be judged).
local function layers(map)
    local t = now()
    if not t then return nil end
    local r = realm()
    if cache.realm == r and cache.map == map and cache.list and t < cache.validUntil then return cache.list end
    local list, oldest = {}, nil
    for zone, seen in pairs(maps()[map] or {}) do
        if t - seen < EXPIRE then
            list[#list + 1] = zone
            if not oldest or seen < oldest then oldest = seen end
        end
    end
    table.sort(list)
    cache.realm, cache.map, cache.list = r, map, list
    cache.validUntil = oldest and oldest + EXPIRE or t + EXPIRE
    return list
end

local function rank(map, zone)
    for i, z in ipairs(layers(map) or {}) do
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

-- Is this zone id known, unexpired, on another map of this realm?
local function elsewhere(zone, map, t)
    for m, ids in pairs(maps()) do
        if m ~= map and ids[zone] and t - ids[zone] < EXPIRE then return true end
    end
    return false
end

-- Look at one unit; true when it told us the layer. `confirmOnly`: accept
-- only an id already known on this map (nameplates).
local function see(unit, confirmOnly)
    unit = P(unit)
    if type(unit) ~= "string" then return false end
    if P(UnitOnTaxi("player")) == true or P(IsInInstance()) == true then return false end
    if P(UnitIsPlayer(unit)) == true then return false end
    local zone = zoneOf(unit)
    local map = P(C_Map.GetBestMapForUnit("player"))
    local t = now()
    if not zone or type(map) ~= "number" or not t then return false end
    local all = maps()
    local known = all[map] and all[map][zone] and t - all[map][zone] < EXPIRE
    if not known and (confirmOnly or elsewhere(zone, map, t)) then return false end
    all[map] = all[map] or {}
    all[map][zone] = t
    prune(map, t)
    if not known then invalidate() end
    current.zone, current.map = zone, map
    return true
end

local function forget() current.zone, current.map = nil, nil end

-- Read again what's already on screen (no event fires for it): the target
-- first, then the mouseover, then nameplates; the first that answers wins.
local function rescan()
    if see("target") or see("mouseover") then return end
    for i = 1, PLATES do
        if see("nameplate" .. i, true) then return end
    end
end

-- Our SavedVariables: keep only well-formed, unexpired entries, then add
-- anything seen this session before they loaded.
local function load()
    local db = rawget(_G, "GlassPanelLayerDB")
    if type(db) ~= "table" then db = {} end
    db.maps = nil   -- the pre-release format, without realms
    local saved, t = type(db.realms) == "table" and db.realms or {}, now()
    local clean = {}
    for r, rmaps in pairs(saved) do
        if type(r) == "string" and type(rmaps) == "table" then
            for map, ids in pairs(rmaps) do
                if type(map) == "number" and type(ids) == "table" then
                    for zone, seen in pairs(ids) do
                        -- Unreadable time: keep it all, the next sighting prunes.
                        if type(zone) == "number" and type(seen) == "number" and (not t or t - seen < EXPIRE) then
                            clean[r] = clean[r] or {}
                            clean[r][map] = clean[r][map] or {}
                            clean[r][map][zone] = seen
                        end
                    end
                end
            end
        end
    end
    for r, rmaps in pairs(realms) do
        for map, ids in pairs(rmaps) do
            clean[r] = clean[r] or {}
            clean[r][map] = clean[r][map] or {}
            for zone, seen in pairs(ids) do clean[r][map][zone] = seen end
        end
    end
    realms = clean
    db.realms = realms
    GlassPanelLayerDB = db
    invalidate()
end

-- A group change: unknown now, and look again while the hop happens.
local function regroup()
    forget()
    for _, s in ipairs(REGROUP) do
        C_Timer.After(s, function()
            forget()
            rescan()
            GlassPanel.Refresh("layer")
        end)
    end
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
    order = 180,
    events = { "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_CONTROL_GAINED",
               "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
               "GROUP_JOINED", "GROUP_LEFT", "ZONE_CHANGED_NEW_AREA", "UNIT_PHASE" },
    unitEvents = { UNIT_PHASE = "player" },
    onEvent = function(_, event, arg)
        if event == "ADDON_LOADED" then
            if arg == ADDON then load() end
        elseif event == "PLAYER_TARGET_CHANGED" then see("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then see("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then see(arg, true)
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
            or event == "PLAYER_CONTROL_GAINED" then
            rescan()
        elseif event == "GROUP_JOINED" or event == "GROUP_LEFT" then
            regroup()
        else
            forget()   -- ZONE_CHANGED_NEW_AREA, the player's UNIT_PHASE
        end
    end,
    text = function()
        local n = current.zone and rank(current.map, current.zone)
        return n and tostring(n) or "|cff888888?|r"
    end,
    tooltip = function(_, tt)
        tt:AddLine("Layer")
        local map = current.map or P(C_Map.GetBestMapForUnit("player"))
        local list = type(map) == "number" and layers(map) or {}
        local n
        for i, zone in ipairs(list) do if zone == current.zone then n = i end end
        if n then
            tt:AddDoubleLine("Current layer", n .. "  |cff888888(zone " .. current.zone .. ")|r", 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddDoubleLine("Current layer", "unknown", 1, 0.82, 0, 0.7, 0.7, 0.7)
        end
        local t = now()
        if #list > 0 and t then
            tt:AddLine(" ")
            tt:AddLine("Layers seen on this map")
            local ids = maps()[map]
            for i, zone in ipairs(list) do
                local mark = zone == current.zone and "|cff40ff40> |r" or ""
                tt:AddDoubleLine(mark .. "Layer " .. i, "zone " .. zone .. ", " .. age(t - ids[zone]) .. " ago",
                    1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Target or mouse over an NPC to detect your layer.", 0.7, 0.7, 0.7, true)
        tt:AddLine("Numbers count the layers you've seen here; others may number them differently.",
            0.7, 0.7, 0.7, true)
        tt:AddLine("Left-click: forget this map's layers", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button ~= "LeftButton" then return end
        local map = current.map or P(C_Map.GetBestMapForUnit("player"))
        if type(map) == "number" then maps()[map] = nil end
        invalidate()
        forget()
        API.Print("Layer: forgot the layers seen on this map.")
        GlassPanel.Refresh("layer")
    end,
})
