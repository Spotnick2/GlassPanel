-- Ammo stubs (Plugins/Ammo). WoW.items[id] = { classID, subClassID, icon,
-- name }: the item catalogue C_Item.GetItemInfoInstant / GetItemNameByID read.
-- GetItemInfoInstant is wrapped once, after every stub file has loaded (at the
-- first reset): the catalogue first, else whatever another stub (gearscore)
-- defined. No other plugin's stub file is edited. WoW.invCount[slot]
-- is GetInventoryItemCount's answer; WoW.bags[bag].items[slot] = { id, count }
-- what the bags hold. WoW.usesAmmo is UnitUsesAmmo's answer (nil: the
-- function returns nil). A value set to "secret" comes back secret.
--
-- Each function is defined only when no other stub file has (plugins built
-- in parallel, #66 / #67 / #68): whichever merges first, they don't clash.
local function sv(v, label)
    if v == "secret" then return WoW.Secret(label) end
    return v
end

local wrapped = false
local function wrapInfoInstant()
    if wrapped then return end
    wrapped = true
    local original = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(item)
        local c = WoW.items and WoW.items[item]
        if c then
            return item, "Item", "Item", "", sv(c.icon, "icon"), sv(c.classID, "classID"), sv(c.subClassID, "subClassID")
        end
        if original then return original(item) end
        return nil
    end
end

table.insert(WoW.resetHooks, function()
    WoW.items = {}
    WoW.invCount = {}
    WoW.usesAmmo = true
    wrapInfoInstant()
end)

-- In the 70338 dump (Unit), new in that build.
UnitUsesAmmo = rawget(_G, "UnitUsesAmmo") or function(unit) return sv(WoW.usesAmmo, "usesAmmo") end
GetInventoryItemCount = rawget(_G, "GetInventoryItemCount")
    or function(unit, slot) return sv(WoW.invCount[slot], "inv count") end

C_Item = rawget(_G, "C_Item") or {}
-- Plugins' stubs chain this one: each answers from its own data, else asks
-- the one before (any load order). WoW.itemNames is stubs/warlock.lua's.
local otherItemName = C_Item.GetItemNameByID
function C_Item.GetItemNameByID(id)
    local n = type(WoW.itemNames) == "table" and WoW.itemNames[id] or nil
    if n ~= nil then return n end
    local c = WoW.items and WoW.items[id]
    if c then return c.name end
    if otherItemName then return otherItemName(id) end
end

C_Container.GetContainerItemInfo = C_Container.GetContainerItemInfo or function(bag, slot)
    local b = WoW.bags[bag]
    local it = b and b.items and b.items[slot]
    if it == "secret" then return WoW.Secret("container item") end
    if not it then return nil end
    return { itemID = sv(it.id, "item id"), stackCount = sv(it.count, "stack") }
end
