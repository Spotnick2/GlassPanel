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
local ICON = function(id) return "|T" .. id .. ":14:14:0:0:64:64:5:59:5:59|t " end

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
done("test_ammo")
