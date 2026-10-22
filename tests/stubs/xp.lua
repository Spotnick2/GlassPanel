-- XP+'s rested lines (Plugins/XP, #81). From the 70338 dump: IsResting,
-- C_UnitAuras.GetAuraDataByIndex, C_Traits.GetConfigIDByTreeID / GetNodeInfo,
-- C_TooltipInfo.GetUnitBuffByAuraInstanceID. Shaped as RestProbe measured them
-- on 70374 (docs/FOREVER-PROBE.md).
--   WoW.resting: IsResting()
--   WoW.wellRested: Well Rested's rank (Legacy node 110301 in tree 1188); nil:
--     no such node (GetNodeInfo answers with ID 0); "secret": a secret rank
--   WoW.buffs / WoW.debuffs: AuraData tables, in order
--   WoW.auraTips[auraInstanceID]: the tooltip's lines (leftText)
table.insert(WoW.resetHooks, function()
    WoW.resting = false
    WoW.wellRested = nil
    WoW.buffs, WoW.debuffs, WoW.auraTips = {}, {}, {}
end)

function IsResting() return WoW.resting end

C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
    if unit ~= "player" then return nil end
    if filter == "HARMFUL" then return WoW.debuffs[index] end
    return WoW.buffs[index]
end }

-- Flight (#124) reads Frequent Flier, node 110300 of the same tree:
-- WoW.frequentFlier is its rank (nil: no such node, "secret": a secret rank).
table.insert(WoW.resetHooks, function() WoW.frequentFlier = 0 end)

C_Traits = {
    GetConfigIDByTreeID = function(treeID) return treeID == 1188 and 13280556 or nil end,
    GetNodeInfo = function(configID, nodeID)
        if configID == 13280556 and nodeID == 110300 and WoW.frequentFlier ~= nil then
            local rank = WoW.frequentFlier == "secret" and WoW.Secret("rank") or WoW.frequentFlier
            return { ID = 110300, activeRank = rank, currentRank = rank, ranksPurchased = rank, maxRanks = 1 }
        end
        if configID ~= 13280556 or nodeID ~= 110301 or WoW.wellRested == nil then
            return { ID = 0, activeRank = 0, maxRanks = 0 }
        end
        local rank = WoW.wellRested == "secret" and WoW.Secret("rank") or WoW.wellRested
        return { ID = 110301, activeRank = rank, currentRank = rank, ranksPurchased = rank, maxRanks = 5 }
    end,
}

C_TooltipInfo.GetUnitBuffByAuraInstanceID = function(unit, id)
    local t = WoW.auraTips[id]
    if not t then return nil end
    local lines = {}
    for i, text in ipairs(t) do lines[i] = { leftText = text } end
    return { lines = lines }
end
