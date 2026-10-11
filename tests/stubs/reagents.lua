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
-- C_Item.GetItemIconByID(itemInfo) -> optional icon. e.icon: nil is the
-- question mark (134400), false no icon at all; e.iconByID, when set,
-- overrides this call's answer alone (false: nil).
function C_Item.GetItemIconByID(item)
    local e = WoW.bagItems[item]
    if not e then return nil end
    if e.iconByID ~= nil then return e.iconByID or nil end
    if e.icon == false then return nil end
    return e.icon or 134400
end
-- C_Item.GetItemInfoInstant(itemInfo) -> itemID, itemType, itemSubType,
-- itemEquipLoc, icon, classID, subClassID (MayReturnNothing). A bag item
-- answers from e.icon (false: nothing); anything else asks gearscore.lua's.
local otherInstant = C_Item.GetItemInfoInstant
function C_Item.GetItemInfoInstant(item)
    local e = WoW.bagItems[item]
    if e then
        if e.icon == false then return nil end
        return item, "Reagent", "Reagent", "", e.icon or 134400, 5, 0
    end
    if otherInstant then return otherInstant(item) end
end
-- C_Item.GetItemNameByID(itemInfo) -> optional itemName. Plugins' stubs
-- chain it: each answers from its own data, else asks the one before (any
-- load order). WoW.itemNames is stubs/warlock.lua's (#67).
local otherItemName = C_Item.GetItemNameByID
function C_Item.GetItemNameByID(item)
    local n = type(WoW.itemNames) == "table" and WoW.itemNames[item] or nil
    if n ~= nil then return n end
    local e = WoW.bagItems[item]
    if e then
        if e.cached == false then return nil end
        return e.name
    end
    if otherItemName then return otherItemName(item) end
end
-- C_Item.IsItemDataCachedByID(itemInfo) -> isCached: a bag item unless
-- cached = false; anything else asks gearscore.lua's (equipped items).
local equippedCached = C_Item.IsItemDataCachedByID
function C_Item.IsItemDataCachedByID(item)
    local e = WoW.bagItems[item]
    if e then return e.cached ~= false end
    return equippedCached ~= nil and equippedCached(item) or false
end
