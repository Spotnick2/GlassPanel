-- Warlock stubs (Plugins/Warlock). WoW.itemCounts[id] = n (absent: 0;
-- "secret": comes back secret). WoW.itemCooldowns[id] = { start, duration,
-- enable } (absent: no cooldown). UnitClass comes from stubs/gearscore.lua
-- (WoW.playerClass).
table.insert(WoW.resetHooks, function()
    WoW.itemCounts = {}
    WoW.itemCooldowns = {}
end)

C_Item = rawget(_G, "C_Item") or {}
function C_Item.GetItemCount(item, includeBank, includeUses, includeReagentBank, includeAccountBank)
    local n = WoW.itemCounts[item]
    if n == "secret" then return WoW.Secret("itemCount " .. tostring(item)) end
    return n or 0
end

function C_Container.GetItemCooldown(itemID)
    local c = WoW.itemCooldowns[itemID]
    if not c then return 0, 0, 1 end
    local start = c[1] == "secret" and WoW.Secret("cooldown start") or c[1]
    return start, c[2], c[3] or 1
end
