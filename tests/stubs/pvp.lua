-- PvP stubs (Plugins/PvP). WoW.pvp = { flagged, ffa, timerMs, desired };
-- a field set to "secret" comes back secret.
table.insert(WoW.resetHooks, function()
    WoW.pvp = { flagged = false, ffa = false, timerMs = nil, desired = false }
end)

local function field(k)
    local v = WoW.pvp[k]
    if v == "secret" then return WoW.Secret("pvp." .. k) end
    return v
end

function UnitIsPVP(unit) return field("flagged") end
function UnitIsPVPFreeForAll(unit) return field("ffa") end
function IsPVPTimerRunning() return WoW.pvp.timerMs ~= nil end
function GetPVPTimer() return field("timerMs") or 300000 end
function GetPVPDesired() return field("desired") end
