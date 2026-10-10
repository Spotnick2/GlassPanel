-- GearScore stubs (Plugins/GearScore). WoW.equipped[slot] = { id, ilvl,
-- quality, equipLoc, cached, link }: cached = false means the client hasn't
-- loaded the item yet (no level or quality until WoW.itemLoaded(id)). A field
-- set to "secret" comes back secret. WoW.avgItemLevel = { total, equipped };
-- WoW.playerClass = { className, classFilename, classID }.
table.insert(WoW.resetHooks, function()
    WoW.equipped = {}
    WoW.itemRequests = {}
    WoW.avgItemLevel = { 0, 0 }
    WoW.playerName = "Karuzo"
    WoW.playerClass = { "Warrior", "WARRIOR", 1 }
end)

local function sv(v, label)
    if v == "secret" then return WoW.Secret(label) end
    return v
end

-- The equipped item with this id (a number, or a link "item:<id>...").
local function byItem(item)
    local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
    for _, e in pairs(WoW.equipped) do if e.id == id then return e end end
end

-- The client loaded item id: its data is now cached.
function WoW.itemLoaded(id)
    local e = byItem(id)
    if e then e.cached = true end
end

function GetInventoryItemID(unit, slot)
    local e = WoW.equipped[slot]
    return e and sv(e.id, "item id") or nil
end
function GetInventoryItemLink(unit, slot)
    local e = WoW.equipped[slot]
    if not e then return nil end
    if e.link then return sv(e.link, "item link") end
    return "|cffa335ee|Hitem:" .. tostring(e.id) .. "::::::::60:::::|h[Item " .. tostring(e.id) .. "]|h|r"
end
function GetAverageItemLevel()
    return sv(WoW.avgItemLevel[1], "avg total"), sv(WoW.avgItemLevel[2], "avg equipped"), 0
end
function UnitClass(unit)
    local c = WoW.playerClass
    return sv(c[1], "class name"), sv(c[2], "class file"), c[3]
end
function UnitName(unit) return sv(WoW.playerName, "name"), nil end

C_Item = rawget(_G, "C_Item") or {}
function C_Item.IsItemDataCachedByID(item)
    local e = byItem(item)
    return e ~= nil and e.cached ~= false
end
function C_Item.RequestLoadItemDataByID(item)
    WoW.itemRequests[item] = (WoW.itemRequests[item] or 0) + 1
end
function C_Item.GetItemInfo(item)
    local e = byItem(item)
    if not e or e.cached == false then return nil end
    return "Item " .. e.id, "item:" .. e.id, sv(e.quality, "quality"), sv(e.ilvl, "ilvl"), 1,
        "Armor", "Misc", 1, e.equipLoc, 134400, 0, 4, 0, 1, 0
end
function C_Item.GetItemInfoInstant(item)
    -- An item from the Ammo stubs' catalogue (stubs/ammo.lua): its own class.
    local c = WoW.items and WoW.items[item]
    if c then
        return item, "Item", "Item", "", sv(c.icon, "icon"), sv(c.classID, "classID"), sv(c.subClassID, "subClassID")
    end
    local e = byItem(item)
    if not e then return nil end
    return e.id, "Armor", "Misc", sv(e.equipLoc, "equipLoc"), 134400, 4, 0
end

-- C_ClassColor comes from wow_stubs.lua (shared by several plugins).
