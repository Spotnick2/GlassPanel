-- Plugins/Layer/Layer.lua: which layer of the realm you're on (#17), read
-- from the GUIDs of the creatures around you (without TitanLayer's
-- NovaWorldBuffs listener: NWB doesn't track layers on Forever, #26; and
-- without the chat announce).
--
-- Forever notes (#138; measured on live Forever by LayerSwap, 9 Nov 2026,
-- References\Addons\Miscellaneous\LayerSwap; LayerETA reads it the same way):
-- - A creature's GUID is "Creature-0-<server>-<instance>-<zoneUID>-<npc>-<spawn>";
--   the layer is the <server> field. The zoneUID (which #17 keyed on) differs
--   between two players on one layer and changes when the world refreshes.
--   Players and pets aren't "Creature"; totems and guardians are, but carry
--   the place they were summoned (UnitPlayerControlled), so they never count.
-- - One creature isn't proof: each GUID votes once, and of the last VOTES
--   votes 2 must agree to set a layer, 3 to change a known one (a pair of
--   patrols from the next zone mustn't flip it). Target, mouseover and
--   nameplates all vote. A GUID may come back secret (UnitGUID takes a
--   PvP-restricted token): API.Plain plus the type check skip it, so readable
--   GUIDs still count in combat. Not on a taxi or in an instance.
-- - The game moves a player with SHARD_TRANSFER (a group join on another
--   layer, a world refresh). The units in view then still carry the old layer
--   for a few seconds (LayerSwap: 17 s of the old layer from nameplates read
--   0.3 s after a move), so they don't vote for STALE seconds, and what's on
--   screen is read again a few times.
-- - Layers are a zone's: they're filed under the zone-level map (a cave or a
--   building has a uiMapID of its own). The number is the rank of your layer
--   id among the ids seen in the SAME zone, ascending: "2" means the
--   second-lowest id seen here. The numbers are local: nothing on the client
--   says how many layers exist, so a newly seen lower id renumbers yours, and
--   another player's "2" may be your "1" (NovaWorldBuffs, which shares
--   sightings on Classic, doesn't track layers on Forever: #26, closed).
--   Known ids live in GlassPanelLayerDB.realms[realm][zoneMap][id] =
--   GetServerTime() of the last sighting, forgotten after 2 hours.
-- - The current layer holds only while the player is in the zone it was seen
--   in (checked at every read: a zone change may come with ZONE_CHANGED /
--   ZONE_CHANGED_INDOORS rather than ZONE_CHANGED_NEW_AREA).

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local ADDON = "GlassPanelLayer"
local FORMAT = 2            -- GlassPanelLayerDB.v: 2 = server ids (#138); older saves held zoneUIDs
local EXPIRE = 7200         -- layers are reshuffled on restarts; a sighting counts for 2 h
local VOTES = 5             -- the last votes kept
local STALE = 10            -- seconds the units in view at a move don't vote
local AFTER_MOVE = { 2, 5, STALE + 2 }  -- seconds after a move to read what's on screen again
local PLATES = 40
local ZONE_TYPE = 3         -- Enum.UIMapType.Zone (MapConstantsDocumentation.lua)
local MAP_DEPTH = 6

-- realms[realm][zoneMap][layerId] = server time last seen. A session table
-- until our SavedVariables load (ADDON_LOADED), then GlassPanelLayerDB.realms.
local realms = {}
-- The current layer: its id and the zone map it was seen in (nil: unknown).
local current = { layer = nil, map = nil }
-- The last VOTES layer ids read, the GUIDs that voted (once each), and the
-- zone map they were read in.
local votes, voted, votesMap = {}, {}, nil
-- Creatures of a layer just left: [guid] = GetTime() until which they don't vote.
local stale = {}
-- The sorted, unexpired ids of one zone, kept until something changes.
local cache = { realm = nil, map = nil, list = nil, validUntil = nil }

-- nil when unreadable: never a made-up 0.
local function now()
    local t = P(GetServerTime())
    return type(t) == "number" and t or nil
end

-- Which realm the saved layers belong to. Since the 2026-11-20 hotfix the
-- client hides the realm on purpose: GetRealmName() is "" (AltStable #408,
-- #412; #167 here; the porting guide, "The realm is hidden"). Then this
-- character: a character never leaves its realm, so its own sightings are one
-- realm's. Keyed by its whole GUID, an opaque id (the guide: never parse a
-- server out of it, which may leave the GUID). Alts on one realm no longer
-- share sightings, which last 2 h anyway. Else "?".
local function realm()
    local r = P(GetRealmName())
    if type(r) == "string" and r:find("%S") then return r end
    local g = P(UnitGUID("player"))
    if type(g) == "string" and g:find("%S") then return "char:" .. g end
    return "?"
end

-- This realm's zones (created on first use). With no realm and no character
-- to file them under ("?"), sightings stay in this session only, never saved
-- (Codex on #168): a saved "?" would rank another character's realm against
-- ours within the 2 h.
local unplaced = {}
local function maps()
    local r = realm()
    if r == "?" then return unplaced end
    realms[r] = realms[r] or {}
    return realms[r]
end

local function invalidate() cache.realm, cache.map, cache.list, cache.validUntil = nil, nil, nil, nil end

-- Forget what's older than EXPIRE in one zone (and the zone once empty).
local function prune(map, t)
    local all = maps()
    local ids = all[map]
    if not ids then return end
    for id, seen in pairs(ids) do
        if t - seen >= EXPIRE then ids[id] = nil end
    end
    if next(ids) == nil then all[map] = nil end
end

-- The layer ids seen in a zone and not expired, ascending: the layer numbers.
-- nil when the time can't be read (expiry can't be judged).
local function layers(map)
    local t = now()
    if not t then return nil end
    local r = realm()
    if cache.realm == r and cache.map == map and cache.list and t < cache.validUntil then return cache.list end
    local list, oldest = {}, nil
    for id, seen in pairs(maps()[map] or {}) do
        if t - seen < EXPIRE then
            list[#list + 1] = id
            if not oldest or seen < oldest then oldest = seen end
        end
    end
    table.sort(list)
    cache.realm, cache.map, cache.list = r, map, list
    cache.validUntil = oldest and oldest + EXPIRE or t + EXPIRE
    return list
end

local function rank(map, id)
    for i, l in ipairs(layers(map) or {}) do
        if l == id then return i end
    end
    return nil
end

-- The zone-level map the player is in, or nil: the uiMapID walked up its
-- parents to the Zone map. A map with no Zone above it stays itself.
local function liveMap()
    local id = P(C_Map.GetBestMapForUnit("player"))
    if type(id) ~= "number" or id <= 0 then return nil end
    local zoneType = Enum and Enum.UIMapType and P(Enum.UIMapType.Zone)
    if type(zoneType) ~= "number" then zoneType = ZONE_TYPE end
    local m = id
    for _ = 1, MAP_DEPTH do
        local info = C_Map.GetMapInfo(m)
        if type(info) ~= "table" then break end
        local kind, up = P(info.mapType), P(info.parentMapID)
        if type(kind) ~= "number" then break end
        if kind == zoneType then return m end
        if kind < zoneType or type(up) ~= "number" or up <= 0 then break end
        m = up
    end
    return id
end

-- The current layer's id, only while you're still in the zone it was seen
-- in: a zone change doesn't always come with ZONE_CHANGED_NEW_AREA.
local function currentLayer(map)
    if current.layer and map and current.map == map then return current.layer end
    return nil
end

-- The layer a unit's GUID tells, and the GUID; nil when it tells none.
local function layerOf(unit)
    local guid = P(UnitGUID(unit))
    if type(guid) ~= "string" then return nil end
    local kind, _, server = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    if P(UnitPlayerControlled(unit)) == true then return nil end
    local id = tonumber(server)
    if not id or id <= 0 then return nil end
    return id, guid
end

local function forget()
    current.layer, current.map = nil, nil
    votes, voted, votesMap = {}, {}, nil
end

-- File a sighting of the current layer.
local function file(map, id, t)
    local all = maps()
    local known = all[map] and all[map][id] and t - all[map][id] < EXPIRE
    all[map] = all[map] or {}
    all[map][id] = t
    prune(map, t)
    if not known then invalidate() end
end

-- Look at one unit: its creature votes once for the layer it carries.
local function see(unit)
    unit = P(unit)
    if type(unit) ~= "string" then return end
    if P(UnitOnTaxi("player")) == true or P(IsInInstance()) == true then return end
    if P(UnitIsPlayer(unit)) == true then return end
    local id, guid = layerOf(unit)
    local map, t = liveMap(), now()
    if not id or not map or not t then return end
    if stale[guid] and GetTime() < stale[guid] then return end
    -- Another zone than the votes were cast in: they were about that zone.
    if votesMap ~= map then forget(); votesMap = map end
    -- A sighting of the current layer keeps it fresh, even from a creature
    -- that already voted (else a layer seen all along would expire).
    if currentLayer(map) == id then file(map, id, t) end
    if voted[guid] then return end
    voted[guid] = true
    votes[#votes + 1] = id
    if #votes > VOTES then table.remove(votes, 1) end
    if currentLayer(map) == id then return end
    local count = 0
    for _, v in ipairs(votes) do if v == id then count = count + 1 end end
    if count >= (current.layer and 3 or 2) then
        current.layer, current.map = id, map
        file(map, id, t)
    end
end

-- Read what's already on screen again (no event fires for it).
local function rescan()
    see("target")
    see("mouseover")
    for i = 1, PLATES do see("nameplate" .. i) end
end

-- The game moved us: unknown, the creatures in view are the old layer's for
-- STALE seconds, and what's on screen is read again a few times.
local function moved()
    -- Every creature that voted before the move is the old layer's too, even
    -- one with no unit token right now (its nameplate may come back). Those
    -- set aside by an earlier move keep their own expiry (#140).
    local t = GetTime()
    for guid, untilAt in pairs(stale) do
        if untilAt <= t then stale[guid] = nil end
    end
    for guid in pairs(voted) do stale[guid] = t + STALE end
    forget()
    local function add(unit)
        local guid = P(UnitGUID(unit))
        if type(guid) == "string" then stale[guid] = t + STALE end
    end
    add("target")
    add("mouseover")
    for i = 1, PLATES do add("nameplate" .. i) end
    for _, s in ipairs(AFTER_MOVE) do
        C_Timer.After(s, function()
            rescan()
            GlassPanel.Refresh("layer")
        end)
    end
end

-- Our SavedVariables: keep only well-formed, unexpired entries, then add
-- anything seen this session before they loaded.
local function load()
    local db = rawget(_G, "GlassPanelLayerDB")
    if type(db) ~= "table" then db = {} end
    db.maps = nil   -- the pre-release format, without realms
    if db.v ~= FORMAT then db.realms = nil end   -- zoneUIDs (#17), not layers
    db.v = FORMAT
    local saved, t = type(db.realms) == "table" and db.realms or {}, now()
    local clean = {}
    for r, rmaps in pairs(saved) do
        if type(r) == "string" and r ~= "?" and type(rmaps) == "table" then   -- "?": never ours (above)
            for map, ids in pairs(rmaps) do
                if type(map) == "number" and type(ids) == "table" then
                    for id, seen in pairs(ids) do
                        -- Unreadable time: keep it all, the next sighting prunes.
                        if type(id) == "number" and type(seen) == "number" and (not t or t - seen < EXPIRE) then
                            clean[r] = clean[r] or {}
                            clean[r][map] = clean[r][map] or {}
                            clean[r][map][id] = seen
                        end
                    end
                end
            end
        end
    end
    for r, rmaps in pairs(realms) do
        for map, ids in pairs(r ~= "?" and rmaps or {}) do
            clean[r] = clean[r] or {}
            clean[r][map] = clean[r][map] or {}
            for id, seen in pairs(ids) do clean[r][map][id] = seen end
        end
    end
    realms = clean
    db.realms = realms
    GlassPanelLayerDB = db
    invalidate()
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
               "SHARD_TRANSFER", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
               "UNIT_PHASE" },
    unitEvents = { UNIT_PHASE = "player" },
    onEvent = function(_, event, arg)
        if event == "ADDON_LOADED" then
            if arg == ADDON then load() end
        elseif event == "PLAYER_TARGET_CHANGED" then see("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then see("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then see(arg)
        elseif event == "SHARD_TRANSFER" then
            moved()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
            or event == "PLAYER_CONTROL_GAINED" then
            rescan()
        elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
            -- Mostly subzones (same zone): only a new zone map resets it.
            if current.layer and current.map ~= liveMap() then
                forget()
                rescan()
            end
        else
            forget()   -- ZONE_CHANGED_NEW_AREA, the player's UNIT_PHASE
        end
    end,
    text = function()
        local map = liveMap()
        local id = currentLayer(map)
        local n = id and rank(map, id)
        return n and tostring(n) or "|cff888888?|r"
    end,
    tooltip = function(_, tt)
        tt:AddLine("Layer")
        local map = liveMap()
        local cur = currentLayer(map)
        local list = map and layers(map) or {}
        local n
        for i, id in ipairs(list) do if id == cur then n = i end end
        if n then
            tt:AddDoubleLine("Current layer", n .. "  |cff888888(id " .. cur .. ")|r", 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddDoubleLine("Current layer", "unknown", 1, 0.82, 0, 0.7, 0.7, 0.7)
        end
        local t = now()
        if #list > 0 and t then
            tt:AddLine(" ")
            tt:AddLine("Layers seen in this zone")
            local ids = maps()[map]
            for i, id in ipairs(list) do
                local mark = id == cur and "|cff40ff40> |r" or ""
                tt:AddDoubleLine(mark .. "Layer " .. i, "id " .. id .. ", " .. age(t - ids[id]) .. " ago",
                    1, 1, 1, 0.7, 0.7, 0.7)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Detected from the NPCs around you (target, mouseover, nameplates): two must agree.",
            0.7, 0.7, 0.7, true)
        tt:AddLine("Numbers count the layers you've seen here; others may number them differently.",
            0.7, 0.7, 0.7, true)
        tt:AddLine("Left-click: forget this zone's layers", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button ~= "LeftButton" then return end
        -- The zone you're in, not the one the last sighting was in.
        local map = liveMap()
        if map then maps()[map] = nil end
        invalidate()
        forget()
        API.Print("Layer: forgot the layers seen in this zone.")
        GlassPanel.Refresh("layer")
    end,
})
