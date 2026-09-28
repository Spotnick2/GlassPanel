-- Layer stubs (Plugins/Layer). WoW.units[token] = { guid, isPlayer } (guid
-- "secret": comes back secret; a token absent: no unit). WoW.layer = { map,
-- taxi, instance } for the player; WoW.serverTime is GetServerTime.
table.insert(WoW.resetHooks, function()
    WoW.units = {}
    WoW.layer = { map = 1429, taxi = false, instance = false }
    WoW.serverTime = 100000
end)

function UnitGUID(unit)
    local u = WoW.units[unit]
    if not u then return nil end
    if u.guid == "secret" then return WoW.Secret("guid." .. unit) end
    return u.guid
end
function UnitIsPlayer(unit) return WoW.units[unit] ~= nil and WoW.units[unit].isPlayer == true end
function UnitOnTaxi(unit) return unit == "player" and WoW.layer.taxi end
function IsInInstance() return WoW.layer.instance, WoW.layer.instance and "party" or "none" end
function GetServerTime() return WoW.serverTime end
C_Map = C_Map or {}
C_Map.GetBestMapForUnit = function(unit) return WoW.layer.map end

-- A client global (FrameXML's string split, not Lua's): every piece, or at
-- most `pieces` with the rest left in the last.
function strsplit(delim, str, pieces)
    local out, pos = {}, 1
    while not pieces or #out < pieces - 1 do
        local a, b = string.find(str, delim, pos, true)
        if not a then break end
        out[#out + 1] = str:sub(pos, a - 1)
        pos = b + 1
    end
    out[#out + 1] = str:sub(pos)
    return unpack(out)
end
