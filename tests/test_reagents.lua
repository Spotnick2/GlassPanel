-- The Reagents plugin (#68).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelReagents" }

local function B() return block("reagents") end
local function T() return B()._test end
local function tip()
    local w = B().widget
    w._scripts.OnEnter(w)
    return table.concat(GameTooltip._lines, "\n")
end
local function mage()
    WoW.playerClass = { "Mage", "MAGE", 8 }
    WoW.itemCounts = {}
    WoW.bagItems = {
        [17020] = { name = "Arcane Powder", icon = 2001 },
        [17031] = { name = "Rune of Teleportation", icon = 2002 },
        [17032] = { name = "Rune of Portals", icon = 2003 },
        [17056] = { name = "Light Feather", icon = 2004 },
    }
end
local function ic(n) return "|T" .. n .. ":14:14:0:0:64:64:5:59:5:59|t " end

-- The class lists hold no ammo, shards or stones (their own plugins), and
-- hunters and warriors have none.
local L = nil
mage()
GlassPanelReagentsDB = nil
loadAddon()
L = T().CLASS
check(L.HUNTER == nil and L.WARRIOR == nil, "no list for hunters and warriors")
for _, ids in pairs(L) do
    for _, id in ipairs(ids) do
        check(id ~= 6265 and id ~= 5509 and id ~= 16893, "no soul shard, healthstone or soulstone: " .. id)
    end
end
eq(B().widget._shown, false, "nothing carried, never chosen: hidden")
local names = {}
for _, c in ipairs(T().available()) do names[#names + 1] = c.name end
eq(table.concat(names, ","), "Arcane Powder,Rune of Teleportation,Rune of Portals,Light Feather",
   "the mage's reagents, in the table's order")
eq(GlassPanelReagentsDB.order, nil, "nothing saved while nothing is carried")

-- A warrior: no list, no block, nothing offered.
WoW.playerClass = { "Warrior", "WARRIOR", 1 }
GlassPanelReagentsDB = nil
loadAddon()
eq(#T().available(), 0, "a warrior is offered nothing")
eq(B().widget._shown, false, "a warrior: hidden")

-- First run carrying powder and teleport runes: shown by default, saved once.
mage()
WoW.itemCounts[17020] = 40
WoW.itemCounts[17031] = 5
WoW.itemCounts[17056] = 12
WoW.itemCounts[17032] = 3
GlassPanelReagentsDB = nil
loadAddon()
eq(textOf("reagents"), ic(2001) .. "40  " .. ic(2002) .. "5  " .. ic(2003) .. "3",
   "carried reagents shown by default, up to 3, in the class's order")
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,17032", "the defaults are saved once found")
check(tip():find("Arcane Powder\t40", 1, true), "tooltip: name and count")
-- Using them up: red 0, and the pick stays.
WoW.itemCounts[17031] = 0
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
check(textOf("reagents"):find(ic(2002) .. "|cffff40400|r", 1, true), "none left: a red 0")
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,17032", "a used-up pick stays")

-- The chooser: from the option button and a left-click.
local panel = GlassPanel.Options._test.panel
panel:Hide(); panel:Show()
local btn = GlassPanel.Options._test.controls["options:reagents:1"]
check(btn ~= nil, "a 'Choose reagents...' button under Plugin options")
btn._scripts.OnClick(btn)
local win = T().window()
eq(win and win._shown, true, "opens the chooser")
local rows = T().rows
eq(rows[1].id, 17020, "shown first, in order")
eq(rows[4].id, 17056, "then the rest")
eq(rows[4].check:GetChecked(), false, "unticked")
rows[4].check:SetChecked(true); rows[4].check._scripts.OnClick(rows[4].check)
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,17032,17056", "ticked: added at the end")
rows[4].up._scripts.OnClick(rows[4].up)
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,17056,17032", "Up reorders")
WoW.tick()
check(textOf("reagents"):find(ic(2004) .. "12  " .. ic(2003), 1, true), "the bar follows the order")
eq(rows[1].up:IsEnabled(), false, "the first can't go up")
rows[1].check:SetChecked(false); rows[1].check._scripts.OnClick(rows[1].check)
eq(table.concat(GlassPanelReagentsDB.order, ","), "17031,17056,17032", "unticked: removed")
win:Hide()
local w = B().widget
w._scripts.OnClick(w, "LeftButton")
eq(T().window()._shown, true, "left-click opens the chooser")
T().window():Hide()

-- Nothing picked: hidden, and the empty choice is kept.
GlassPanelReagentsDB.order = {}
GlassPanel.Refresh("reagents"); WoW.tick()
eq(B().widget._shown, false, "nothing picked: hidden")
eq(#GlassPanelReagentsDB.order, 0, "the empty choice is kept")

-- A secret count: a grey ?, never a guess.
GlassPanelReagentsDB.order = { 17020 }
WoW.itemCounts[17020] = "secret"
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("reagents"), ic(2001) .. "|cff888888?|r", "secret count: ?")
WoW.itemCounts[17020] = 40

-- An id the client doesn't know is skipped; corrupt saved data: defaults.
GlassPanelReagentsDB.order = { 99999, 17020 }
GlassPanel.Refresh("reagents"); WoW.tick()
eq(textOf("reagents"), ic(2001) .. "40", "unknown id skipped")
WoW.bagItems[17056] = nil
local ids = {}
for _, c in ipairs(T().available()) do ids[c.id] = true end
check(not ids[17056] and ids[17020], "a class id the client doesn't know isn't offered")
mage()
WoW.itemCounts[17020] = 40
GlassPanelReagentsDB.order = "junk"
GlassPanel.Refresh("reagents"); WoW.tick()
eq(textOf("reagents"), ic(2001) .. "40", "corrupt order: defaults")

-- A name the client hasn't loaded: requested once, shown when it arrives.
mage()
WoW.itemCounts[17020] = 40
WoW.bagItems[17020].cached = false
GlassPanelReagentsDB = { order = { 17020 } }
loadAddon()
eq(textOf("reagents"), ic(2001) .. "40", "the icon and count don't wait for the name")
check(tip():find("item 17020", 1, true), "tooltip: a placeholder while loading")
eq(WoW.itemRequests[17020], 1, "requested")
check(T().pending()[17020], "pending")
GlassPanel.Refresh("reagents"); WoW.tick()
eq(WoW.itemRequests[17020], 1, "requested once")
WoW.bagItems[17020].cached = true
WoW.fire("ITEM_DATA_LOAD_RESULT", 17020, true); WoW.tick()
check(T().pending()[17020] == nil, "answered")
check(tip():find("Arcane Powder\t40", 1, true), "the name once loaded")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_reagents")
