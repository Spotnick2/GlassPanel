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
C_Item.GetItemNameByID = C_Item.GetItemNameByID or function(id)
    local c = WoW.items and WoW.items[id]
    return c and c.name or nil
end

C_Container.GetContainerItemInfo = C_Container.GetContainerItemInfo or function(bag, slot)
    local b = WoW.bags[bag]
    local it = b and b.items and b.items[slot]
    if it == "secret" then return WoW.Secret("container item") end
    if not it then return nil end
    return { itemID = sv(it.id, "item id"), stackCount = sv(it.count, "stack") }
end
