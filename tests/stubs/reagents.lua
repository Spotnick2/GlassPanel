-- Reagents stubs (Plugins/Reagents, #68). WoW.bagItems[id] = { name, icon,
-- cached }: what the client knows of an item (an id not listed is one it
-- doesn't know). cached = false: no name until the test sets it.
-- WoW.itemCounts[id] = n (absent: 0; "secret": comes back secret), the same
-- shape as stubs/warlock.lua (#67), which defines GetItemCount too: whichever
-- loads first defines it, the other keeps it. Signatures from the 70338
-- dump. UnitClass (WoW.playerClass) and RequestLoadItemDataByID
-- (WoW.itemRequests) come from gearscore.lua.
table.insert(WoW.resetHooks, function()
    WoW.bagItems = {}
    WoW.itemCounts = {}
end)

C_Item = rawget(_G, "C_Item") or {}
-- C_Item.GetItemCount(itemInfo, includeBank, includeUses, includeReagentBank, includeAccountBank) -> count
C_Item.GetItemCount = C_Item.GetItemCount or function(item)
    local n = WoW.itemCounts[item]
    if n == "secret" then return WoW.Secret("itemCount " .. tostring(item)) end
    return n or 0
end
-- C_Item.GetItemIconByID(itemInfo) -> optional icon
function C_Item.GetItemIconByID(item)
    local e = WoW.bagItems[item]
    return e and (e.icon or 134400) or nil
end
-- C_Item.GetItemNameByID(itemInfo) -> optional itemName
function C_Item.GetItemNameByID(item)
    local e = WoW.bagItems[item]
    if not e or e.cached == false then return nil end
    return e.name
end
