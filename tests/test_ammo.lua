-- The Ammo plugin (#66).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelAmmo" }

local BOW, GUN, XBOW, THROWN, WAND = 101, 102, 103, 104, 105
local ARROWS, BULLETS, ARROWS2 = 201, 202, 203
local function catalogue()
    WoW.items = {
        [BOW] = { classID = 2, subClassID = 2, icon = 1001, name = "Hunting Bow" },
        [GUN] = { classID = 2, subClassID = 3, icon = 1002, name = "Ornate Blunderbuss" },
        [XBOW] = { classID = 2, subClassID = 18, icon = 1003, name = "Light Crossbow" },
        [THROWN] = { classID = 2, subClassID = 16, icon = 1004, name = "Small Throwing Knife" },
        [WAND] = { classID = 2, subClassID = 19, icon = 1005, name = "Lesser Magic Wand" },
        [ARROWS] = { classID = 6, subClassID = 2, icon = 2001, name = "Rough Arrow" },
        [BULLETS] = { classID = 6, subClassID = 3, icon = 2002, name = "Light Shot" },
        [ARROWS2] = { classID = 6, subClassID = 2, icon = 2003, name = "Sharp Arrow" },
    }
end

local function setup(class, ranged, ammo, ammoCount, bags)
    catalogue()
    WoW.playerClass = { class, class, 1 }
    WoW.equipped = {}
    if ranged then WoW.equipped[18] = { id = ranged } end
    if ammo then WoW.equipped[0] = { id = ammo } end
    WoW.invCount = { [0] = ammoCount }
    WoW.bags = bags or {}
    WoW.usesAmmo = true
end
local function hidden() return textOf("ammo") == "" and not block("ammo").widget:IsShown() end
local function refresh() WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick() end
local function tooltip()
    local b = block("ammo").widget
    b._scripts.OnEnter(b)
    return GameTooltip._lines
end
local function has(pattern)
    for _, l in ipairs(tooltip()) do if l:find(pattern, 1, true) then return l end end
end
-- The bar shows the count after the block's own icon and "Ammo: " caption;
-- which ammo (the id below) is the tooltip's.
local ICON = function(id) return "" end

-- A hunter with a bow and arrows: the count, white above "low".
setup("HUNTER", BOW, ARROWS, 1200)
loadAddon()
eq(textOf("ammo"), ICON(2001) .. "|cffffffff1,200|r", "hunter: arrows, white")
check(has("Weapon\tHunting Bow"), "weapon in the tooltip")
check(has("Equipped\tRough Arrow"), "ammo in the tooltip")
check(has("Yellow below 600, red below 200."), "default hunter thresholds")

-- Yellow under low, red under critical (strictly under).
WoW.invCount[0] = 599; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffd200599|r", "yellow under 600")
WoW.invCount[0] = 600; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffffff600|r", "600 is not low")
WoW.invCount[0] = 199; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffff4040199|r", "red under 200")

-- A crossbow takes arrows; a gun bullets.
setup("HUNTER", XBOW, ARROWS, 800); refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffffff800|r", "crossbow: arrows")
setup("HUNTER", GUN, BULLETS, 800); refresh()
eq(textOf("ammo"), ICON(2002) .. "|cffffffff800|r", "gun: bullets")

-- Arrows with a gun: wrong kind. The bags' bullets are counted, flagged.
setup("HUNTER", GUN, ARROWS, 900, {
    [0] = { slots = 4, free = 1, family = 0, items = { { id = BULLETS, count = 200 }, { id = ARROWS, count = 200 },
                                                       { id = BULLETS, count = 150 } } },
}); refresh()
eq(textOf("ammo"), ICON("Interface\\Icons\\INV_Ammo_Bullet_02") .. "|cffffd200350|r|cffff4040!|r",
   "wrong ammo: bullets in bags (yellow), warned")
check(has("doesn't fit this weapon: equip bullets"), "tooltip says the ammo is wrong")

-- No ammo equipped: the matching projectiles in the bags, warned.
setup("HUNTER", BOW, nil, nil, {
    [0] = { slots = 3, free = 0, family = 0, items = { { id = ARROWS, count = 200 }, { id = ARROWS2, count = 500 },
                                                       { id = BULLETS, count = 200 } } },
    [1] = { slots = 1, free = 0, family = 1, items = { { id = ARROWS, count = 100 } } },   -- a quiver
}); refresh()
eq(textOf("ammo"), ICON("Interface\\Icons\\INV_Ammo_Arrow_02") .. "|cffffffff800|r|cffff4040!|r",
   "no ammo equipped: every arrow in the bags and quiver")
check(has("No ammo equipped"), "tooltip says so")

-- An unreadable bag slot: the count is marked unsure.
WoW.bags[0].items[3] = "secret"; refresh()
eq(textOf("ammo"), ICON("Interface\\Icons\\INV_Ammo_Arrow_02") .. "|cffffffff800|r|cff888888?|r|cffff4040!|r",
   "unreadable slot: unsure")
check(has("can't be read right now"), "and explained")

-- The slot count unreadable: the same ammo counted in the bags.
setup("HUNTER", BOW, ARROWS, "secret", {
    [0] = { slots = 2, free = 0, family = 0, items = { { id = ARROWS, count = 200 }, { id = ARROWS2, count = 50 } } },
}); refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffd200200|r", "secret slot count: the equipped ammo in the bags")
-- ...and nothing to fall back on: "?".
WoW.bags[0].items[2] = "secret"; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cff888888?|r", "unknown: grey ?")

-- Thrown: the stack in the ranged slot, the weapon's icon; spares in bags.
setup("ROGUE", THROWN, nil, nil, {
    [0] = { slots = 1, free = 0, family = 0, items = { { id = THROWN, count = 200 } } },
})
WoW.invCount[18] = 75; refresh()
eq(textOf("ammo"), ICON(1004) .. "|cffffd20075|r", "rogue thrown: yellow under 100")
check(has("In your bags\t200"), "spare stacks listed")
check(has("Yellow below 100, red below 40."), "rogue defaults")
WoW.usesAmmo = false; refresh()
eq(textOf("ammo"), ICON(1004) .. "|cffffd20075|r", "thrown doesn't depend on UnitUsesAmmo")

-- A warrior with a bow; the client says no ammo is used: no block.
setup("WARRIOR", BOW, ARROWS, 30); refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffff404030|r", "warrior: red under 40")
WoW.usesAmmo = false; refresh()
check(hidden(), "UnitUsesAmmo false: no block")
WoW.usesAmmo = "secret"; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffff404030|r", "unreadable UnitUsesAmmo: the weapon decides")
WoW.usesAmmo = true

-- A wand, no ranged weapon, or a class that doesn't shoot: no block.
setup("HUNTER", WAND); refresh()
check(hidden(), "wand: no block")
setup("HUNTER", nil); refresh()
check(hidden(), "nothing in the ranged slot: no block")
setup("MAGE", BOW, ARROWS, 500); refresh()
check(hidden(), "a mage: no block")
setup("WARRIOR", BOW, ARROWS, 500)
WoW.playerClass = { "secret", "secret", 1 }; refresh()
check(hidden(), "unreadable class: no block")

-- Equipped ammo whose class can't be read: the slot counted, unsure, no "!".
setup("HUNTER", BOW, 204, 700)
WoW.items[204] = { classID = "secret", subClassID = 2, icon = 2004, name = "Odd Arrow" }; refresh()
eq(textOf("ammo"), ICON(2004) .. "|cffffffff700|r|cff888888?|r", "unreadable ammo class: the slot, unsure, not 'wrong'")
check(not has("doesn't fit this weapon"), "no wrong-ammo warning")
check(has("kind isn't known yet"), "said in the tooltip")

-- Thrown, the stack unreadable: what the bags hold, marked unsure.
setup("ROGUE", THROWN, nil, nil, {
    [0] = { slots = 2, free = 0, family = 0, items = { { id = THROWN, count = 200 }, "secret" } },
})
WoW.invCount[18] = "secret"; refresh()
eq(textOf("ammo"), ICON(1004) .. "|cffffffff200|r|cff888888?|r", "secret thrown stack: the bags', unsure")
check(has("equipped stack can't be read"), "said in the tooltip")
check(has("Some bag slots can't be read"), "an unreadable spare slot is said for thrown too")

-- A projectile's kind is looked up once per item, not on every bag walk.
setup("HUNTER", BOW, nil, nil, {
    [0] = { slots = 2, free = 0, family = 0, items = { { id = ARROWS, count = 200 }, { id = BULLETS, count = 200 } } },
}); refresh()
local lookups, realInstant = 0, C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(id)
    if id == ARROWS or id == BULLETS then lookups = lookups + 1 end
    return realInstant(id)
end
refresh(); refresh()
eq(lookups, 0, "bag projectiles: kinds cached")
C_Item.GetItemInfoInstant = realInstant

-- Items the client hasn't seen (GetItemInfoInstant returns nothing): pending,
-- requested once, rescanned when they load, with no other event.
local NEWGUN, NEWARROWS, NEWAMMO = 301, 302, 303
local function loaded(id, event)
    WoW.items[id].pending = nil
    WoW.fire(event or "ITEM_DATA_LOAD_RESULT", id, true); WoW.tick()
end

-- A ranged weapon: no block until it loads, then the right kind.
setup("HUNTER", NEWGUN, BULLETS, 900)
WoW.items[NEWGUN] = { classID = 2, subClassID = 3, icon = 1301, name = "New Gun", pending = true }
WoW.itemRequests = {}; refresh()
check(hidden(), "unresolved weapon: no block yet")
eq(WoW.itemRequests[NEWGUN], 1, "the weapon's data requested")
refresh(); refresh()
eq(WoW.itemRequests[NEWGUN], 1, "and not again on every repaint")
loaded(NEWGUN)
eq(textOf("ammo"), ICON(2002) .. "|cffffffff900|r", "the weapon loads: the block appears, bullets")
eq(next(block("ammo")._test.pending()), nil, "nothing pending")
WoW.items[NEWGUN].pending = true; refresh()
eq(textOf("ammo"), ICON(2002) .. "|cffffffff900|r", "a known weapon isn't lost to a later miss")

-- A bag projectile: the count unsure until it loads, then counted.
setup("HUNTER", BOW, nil, nil, {
    [0] = { slots = 2, free = 0, family = 0, items = { { id = ARROWS, count = 200 }, { id = NEWARROWS, count = 300 } } },
})
WoW.items[NEWARROWS] = { classID = 6, subClassID = 2, icon = 1302, name = "Fresh Arrow", pending = true }
WoW.itemRequests = {}; refresh()
eq(textOf("ammo"), ICON("Interface\\Icons\\INV_Ammo_Arrow_02") .. "|cffffd200200|r|cff888888?|r|cffff4040!|r",
   "unresolved bag projectile: unsure, not a definite count")
eq(WoW.itemRequests[NEWARROWS], 1, "its data requested")
refresh(); refresh()
eq(WoW.itemRequests[NEWARROWS], 1, "and not again on every repaint")
loaded(NEWARROWS, "GET_ITEM_INFO_RECEIVED")
eq(textOf("ammo"), ICON("Interface\\Icons\\INV_Ammo_Arrow_02") .. "|cffffd200500|r|cffff4040!|r",
   "it loads: counted, no ?")

-- Equipped ammo of unknown kind: the slot counted, unsure, never "wrong".
setup("HUNTER", BOW, NEWAMMO, 700)
WoW.items[NEWAMMO] = { classID = 6, subClassID = 2, icon = 1303, name = "Mystery Arrow", pending = true }
WoW.itemRequests = {}; refresh()
eq(textOf("ammo"), "|cffffffff700|r|cff888888?|r", "unresolved equipped ammo: counted, unsure")
check(not has("doesn't fit this weapon"), "not called the wrong kind")
eq(WoW.itemRequests[NEWAMMO], 1, "its data requested")
refresh(); refresh()
eq(WoW.itemRequests[NEWAMMO], 1, "and not again on every repaint")
loaded(NEWAMMO)
eq(textOf("ammo"), ICON(1303) .. "|cffffffff700|r", "it loads: the right kind, no ?")

-- A load that still leaves the item unresolved: asked once, never again (no loop).
setup("HUNTER", BOW, 304, 700)
WoW.items[304] = { classID = 6, subClassID = 2, icon = 1304, name = "Ghost Arrow", pending = true }
WoW.itemRequests = {}; refresh()
WoW.fire("ITEM_DATA_LOAD_RESULT", 304, false); WoW.tick()
refresh(); refresh()
eq(WoW.itemRequests[304], 1, "an answered id isn't requested again")
eq(textOf("ammo"), "|cffffffff700|r|cff888888?|r", "and stays unsure")

-- An older client without UnitUsesAmmo (before 70338): the weapon decides.
setup("WARRIOR", BOW, ARROWS, 60)
local realUses = UnitUsesAmmo
UnitUsesAmmo = nil; refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffd20060|r", "no UnitUsesAmmo: shown from the weapon")
UnitUsesAmmo = realUses

-- Thresholds: validation.
local T = block("ammo")._test
local lo, cr, err = T.validate("300", "100"); eq(lo, 300, "low"); eq(cr, 100, "critical"); eq(err, nil, "no error")
_, _, err = T.validate("100", "100"); eq(err, "Critical must be below low.", "critical == low refused")
_, _, err = T.validate("50", "100"); eq(err, "Critical must be below low.", "critical > low refused")
_, _, err = T.validate("", "10"); eq(err, "Enter whole numbers.", "empty refused")
_, _, err = T.validate("10.5", "1"); eq(err, "Enter whole numbers.", "fractions refused")
_, _, err = T.validate("-5", "-10"); eq(err, "Numbers can't be negative.", "negatives refused")
lo, cr = T.validate("10", "0"); eq(lo, 10, "low 10"); eq(cr, 0, "critical 0 allowed")

-- Thresholds: set through the window, per class, saved.
setup("WARRIOR", BOW, ARROWS, 150); refresh()
eq(textOf("ammo"), ICON(2001) .. "|cffffffff150|r", "150: white for a warrior")
local b = block("ammo").widget
b._scripts.OnClick(b, "LeftButton")
local win = T.window()
check(win and win:IsShown(), "left-click opens the thresholds window")
eq(win.low:GetText(), "100", "low box"); eq(win.critical:GetText(), "40", "critical box")
win.low:SetText("200"); win.critical:SetText("120")
win.save._scripts.OnClick(win.save)
WoW.tick()
eq(GlassPanelAmmoDB.thresholds.WARRIOR.low, 200, "saved per class")
eq(GlassPanelAmmoDB.thresholds.HUNTER, nil, "other classes untouched")
eq(textOf("ammo"), ICON(2001) .. "|cffffd200150|r", "150 is now low")
win.low:SetText("50"); win.critical:SetText("60")
win.save._scripts.OnClick(win.save)
check(win.status:GetText():find("Critical must be below low", 1, true), "a bad pair is refused, said")
eq(GlassPanelAmmoDB.thresholds.WARRIOR.low, 200, "and not saved")
win.reset._scripts.OnClick(win.reset); WoW.tick()
eq(GlassPanelAmmoDB.thresholds.WARRIOR, nil, "Defaults clears the class's own")
eq(win.low:GetText(), "100", "and shows the defaults")
eq(textOf("ammo"), ICON(2001) .. "|cffffffff150|r", "white again")

-- A corrupt saved pair falls back to the defaults.
GlassPanelAmmoDB.thresholds.WARRIOR = { low = 10, critical = 50 }
lo, cr = T.thresholds("WARRIOR"); eq(lo, 100, "corrupt low"); eq(cr, 40, "corrupt pair: defaults")
GlassPanelAmmoDB.thresholds.WARRIOR = "junk"
lo = T.thresholds("WARRIOR"); eq(lo, 100, "junk: defaults")

-- The plugin option opens the same window; a mage is told it doesn't apply.
win:Hide()
block("ammo").options[1].run()
check(win:IsShown(), "option button opens the window")
win:Hide()
setup("MAGE", nil)
WoW.chat = {}
block("ammo").options[1].run()
check(not win:IsShown(), "not for a mage")
check(WoW.chat[1] and WoW.chat[1]:find("hunters, warriors and rogues", 1, true), "said why")

-- Equipment changes repaint.
setup("HUNTER", BOW, ARROWS, 1000); refresh()
WoW.invCount[0] = 100
WoW.fire("UNIT_INVENTORY_CHANGED", "player"); WoW.tick()
eq(textOf("ammo"), ICON(2001) .. "|cffff4040100|r", "UNIT_INVENTORY_CHANGED repaints")
WoW.equipped[18] = { id = WAND }
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 18, true); WoW.tick()
check(hidden(), "swapping to a wand hides it")

check(next(GlassPanel.failures) == nil, "no failures")

-- A scan that throws: recorded, the last good state kept, tried again.
setup("HUNTER", BOW, ARROWS, 900); refresh()
local realSlots = C_Container.GetContainerNumSlots
WoW.invCount[0] = "secret"   -- forces the bag walk
C_Container.GetContainerNumSlots = function() error("boom") end
refresh()
check(GlassPanel.failures["ammo:scan"], "scan failure recorded")
eq(textOf("ammo"), ICON(2001) .. "|cffffffff900|r", "last good state kept")
C_Container.GetContainerNumSlots = realSlots
WoW.invCount[0] = 300
eq(block("ammo")._test.state().count, 300, "still stale: the next read scans again")
-- Like Bags: its own icon and the gold caption "Ammo: ".
check(block("ammo").icon ~= nil, "ammo: a block icon")
eq(GlassPanel.Bar.ShowsCaption(block("ammo")), true, "ammo: the caption shows by default")
done("test_ammo")
