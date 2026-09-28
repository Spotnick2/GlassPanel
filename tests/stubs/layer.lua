-- Layer stubs (Plugins/Layer). The shared ones (UnitGUID, UnitIsPlayer,
-- GetServerTime, GetRealmName, C_Map, strsplit) are in wow_stubs.lua.
-- WoW.layer = { taxi, instance } for the player.
table.insert(WoW.resetHooks, function()
    WoW.layer = { taxi = false, instance = false }
end)

function UnitOnTaxi(unit) return unit == "player" and WoW.layer.taxi end
function IsInInstance() return WoW.layer.instance, WoW.layer.instance and "party" or "none" end
