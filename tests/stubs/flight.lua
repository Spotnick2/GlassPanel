-- Flight stubs (Plugins/Flight, #124). From the 70532 dump: TakeTaxiNode,
-- TaxiNodeName, GetNumRoutes, TaxiGetNodeSlot, GetTaxiMapID,
-- C_TaxiMap.GetAllTaxiNodes(uiMapID) (TaxiNodeInfo: nodeID, slotIndex, name, ...),
-- TaxiRequestEarlyLanding. UnitOnTaxi is Layer's stub (WoW.layer.taxi); the
-- Frequent Flier node is in xp.lua's C_Traits (WoW.frequentFlier).
--   WoW.taxi.mapID: GetTaxiMapID() (nil: the map has none)
--   WoW.taxi.nodes[slot] = { id = nodeID or nil, name = "Crossroads, The Barrens" }
--   WoW.taxi.routes[slot] = { slot, slot, ... }: the slots flown through, start first
--   WoW.taxi.taken: the slots TakeTaxiNode was called with; WoW.taxi.early: early landings asked
table.insert(WoW.resetHooks, function()
    WoW.taxi = { mapID = 1414, nodes = {}, routes = {}, taken = {}, early = 0 }
end)

function TakeTaxiNode(slot) table.insert(WoW.taxi.taken, slot) end
function TaxiRequestEarlyLanding() WoW.taxi.early = WoW.taxi.early + 1 end
function GetTaxiMapID() return WoW.taxi.mapID end
function TaxiNodeName(slot)
    local n = WoW.taxi.nodes[slot]
    return n and n.name or "INVALID"
end
function GetNumRoutes(slot)
    local r = WoW.taxi.routes[slot]
    return r and #r - 1 or 0
end
function TaxiGetNodeSlot(slot, hop, isSource)
    local r = WoW.taxi.routes[slot]
    return r and r[isSource and hop or hop + 1]
end
C_TaxiMap = { GetAllTaxiNodes = function(uiMapID)
    if uiMapID ~= WoW.taxi.mapID then return {} end
    local out = {}
    for slot, n in pairs(WoW.taxi.nodes) do
        if n.id then out[#out + 1] = { nodeID = n.id, slotIndex = slot, name = n.name } end
    end
    return out
end }
