-- Layer stubs (Plugins/Layer). The shared ones (UnitGUID, UnitIsPlayer,
-- GetServerTime, GetRealmName, C_Map.GetBestMapForUnit, strsplit) are in wow_stubs.lua.
-- WoW.layer = { taxi, instance } for the player.
-- WoW.mapInfo[uiMapID] = { mapType, parentMapID } (absent: GetMapInfo returns nil).
-- WoW.units[unit].controlled = true: a player-controlled creature (a totem, a guardian).
table.insert(WoW.resetHooks, function()
    WoW.layer = { taxi = false, instance = false }
    WoW.mapInfo = {}
end)

function UnitOnTaxi(unit) return unit == "player" and WoW.layer.taxi end
function IsInInstance() return WoW.layer.instance, WoW.layer.instance and "party" or "none" end
function UnitPlayerControlled(unit)
    local u = WoW.units[unit]
    return u ~= nil and (u.isPlayer == true or u.controlled == true)
end
-- C_Map.GetMapInfo(uiMapID) -> UiMapDetails { mapID, name, mapType, parentMapID, flags } (70938 dump).
C_Map.GetMapInfo = function(id)
    local i = WoW.mapInfo[id]
    if not i then return nil end
    return { mapID = id, name = "map " .. id, mapType = i.mapType, parentMapID = i.parentMapID or 0, flags = 0 }
end
-- Values from wow-ui-source (forever): MapConstantsDocumentation.lua.
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
