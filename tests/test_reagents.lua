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
    WoW.itemRequests = {}
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

-- A warrior: no list, no block (no Options row, no empty chooser).
WoW.playerClass = { "Warrior", "WARRIOR", 1 }
GlassPanelReagentsDB = nil
loadAddon()
eq(B(), nil, "a warrior: no block")
-- A class that can't be read at load: the block, empty and hidden.
WoW.playerClass = { "secret", "secret", 1 }
loadAddon()
check(B() ~= nil, "unreadable class: the block is there")
eq(#T().available(), 0, "and offers nothing")
eq(B().widget._shown, false, "and stays hidden")

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
eq(GlassPanelReagentsDB.order, nil, "bags not settled yet: nothing saved")
-- Bags still filling: the defaults follow what's there until they settle.
WoW.itemCounts[17031] = nil
GlassPanel.Refresh("reagents"); WoW.tick()
eq(textOf("reagents"), ic(2001) .. "40  " .. ic(2003) .. "3  " .. ic(2004) .. "12",
   "before bags settle: worked out again")
WoW.itemCounts[17031] = 5
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,17032", "the defaults are saved once bags settle")
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
w._scripts.OnClick(w, "LeftButton")
eq(rows[1].id, 17020, "the chooser lists the resolved pick")
rows[2].check:SetChecked(true); rows[2].check._scripts.OnClick(rows[2].check)
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17031,99999", "an unresolved saved id is kept at the end")
T().window():Hide()
GlassPanelReagentsDB.order = { 99999, 17020 }
WoW.bagItems[17056] = nil
local ids = {}
for _, c in ipairs(T().available()) do ids[c.id] = true end
check(ids[17056] and ids[17020], "a class id with no icon yet is still offered (pending its load)")
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
eq(WoW.itemRequests[17020], nil, "the bar alone asks for no name")
check(tip():find("item 17020", 1, true), "tooltip: a placeholder while loading")
eq(WoW.itemRequests[17020], 1, "requested by the tooltip")
check(T().pending()[17020], "pending")
GlassPanel.Refresh("reagents"); WoW.tick()
eq(WoW.itemRequests[17020], 1, "requested once")
WoW.bagItems[17020].cached = true
WoW.fire("ITEM_DATA_LOAD_RESULT", 17020, true); WoW.tick()
check(T().pending()[17020] == nil, "answered")
check(tip():find("Arcane Powder\t40", 1, true), "the name once loaded")

-- A failed name load: never requested again, and only the name is lost.
mage()
WoW.itemCounts[17020], WoW.itemCounts[17031] = 40, 5
WoW.bagItems[17031].cached = false
GlassPanelReagentsDB = { order = { 17020, 17031 } }
loadAddon()
tip()
eq(WoW.itemRequests[17031], 1, "requested once")
WoW.fire("ITEM_DATA_LOAD_RESULT", 17031, false); WoW.tick()
check(T().answered()[17031], "a failed load is recorded")
eq(textOf("reagents"), ic(2001) .. "40  " .. ic(2002) .. "5", "a failed name keeps the icon and count")
check(tip():find("item 17031|r\t5", 1, true), "tooltip: the fallback name")
tip(); GlassPanel.Refresh("reagents"); WoW.tick(); tip()
eq(WoW.itemRequests[17031], 1, "and never requested again")
eq(T().pending()[17031], nil, "nothing left pending")

-- A load that succeeds but leaves no name: no request loop through the open
-- tooltip (answer, repaint, tooltip redraw, request).
mage()
WoW.itemCounts[17031] = 5
WoW.bagItems[17031].cached = false
GlassPanelReagentsDB = { order = { 17031 } }
loadAddon()
tip()
eq(WoW.itemRequests[17031], 1, "requested by the tooltip")
for _ = 1, 5 do WoW.fire("ITEM_DATA_LOAD_RESULT", 17031, true); WoW.tick() end
eq(WoW.itemRequests[17031], 1, "loaded but nameless: not requested again")
check(tip():find("item 17031|r\t5", 1, true), "the fallback name")
-- The client says it's cached but has no name: never requested at all.
mage()
WoW.itemCounts[17031] = 5
WoW.bagItems[17031].name = nil
GlassPanelReagentsDB = { order = { 17031 } }
loadAddon()
tip(); WoW.tick(); tip()
eq(WoW.itemRequests[17031], nil, "cached but nameless: no request")

-- The icon comes from GetItemInfoInstant first (no item data needed).
mage()
WoW.itemCounts[17020] = 40
WoW.bagItems[17020].iconByID = false
GlassPanelReagentsDB = { order = { 17020 } }
loadAddon()
eq(textOf("reagents"), ic(2001) .. "40", "GetItemIconByID has none: GetItemInfoInstant's icon")

-- A fresh cache: a class id with no icon yet (from either call) is pending,
-- not unknown. Requested, kept (the question mark), and drawn once it loads.
local function offeredIds()
    local o = {}
    for _, c in ipairs(T().available()) do o[c.id] = true end
    return o
end
mage()
WoW.itemCounts[17020], WoW.itemCounts[17056] = 40, 3
WoW.bagItems[17056].icon, WoW.bagItems[17056].cached = false, false
GlassPanelReagentsDB = nil
loadAddon()
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020,17056", "carried with no icon: still a default pick")
eq(textOf("reagents"), ic(2001) .. "40  " .. ic(134400) .. "3", "carried with no icon: on the bar, a question mark")
eq(WoW.itemRequests[17056], 1, "its data is requested")
check(T().pending()[17056], "pending")
check(offeredIds()[17056], "and offered, unnamed")
for _ = 1, 3 do GlassPanel.Refresh("reagents"); WoW.tick(); tip() end
eq(WoW.itemRequests[17056], 1, "requests don't climb on repaints")
WoW.bagItems[17056].icon, WoW.bagItems[17056].cached = 2004, true
WoW.fire("ITEM_DATA_LOAD_RESULT", 17056, true); WoW.tick()
eq(textOf("reagents"), ic(2001) .. "40  " .. ic(2004) .. "3", "loaded: its icon")
check(tip():find("Light Feather	3", 1, true), "and its name")
eq(WoW.itemRequests[17056], 1, "requested once")

-- In the chooser too: a pending id is listed, and gains its icon on load.
mage()
WoW.bagItems[17032].icon, WoW.bagItems[17032].cached = false, false
GlassPanelReagentsDB = { order = { 17020 } }
loadAddon()
B().widget._scripts.OnClick(B().widget, "LeftButton")
local rs = T().rows
eq(rs[3].id, 17032, "the chooser lists the pending id")
check(rs[3].text:GetText():find("|T134400:16", 1, true) and rs[3].text:GetText():find("item 17032", 1, true),
      "with the question mark and a grey name")
WoW.bagItems[17032].icon, WoW.bagItems[17032].cached = 2003, true
WoW.fire("ITEM_DATA_LOAD_RESULT", 17032, true); WoW.tick(); WoW.flushTimers(0)
check(rs[3].text:GetText():find("|T2003:16", 1, true) and rs[3].text:GetText():find("Rune of Portals", 1, true),
      "loaded: the chooser shows its icon and name")
T().window():Hide()

-- A failed load with still no icon: left out (bar, chooser, defaults), and
-- not requested again.
mage()
WoW.itemCounts[17020], WoW.itemCounts[17056] = 40, 3
WoW.bagItems[17056].icon, WoW.bagItems[17056].cached = false, false
GlassPanelReagentsDB = { order = { 17020, 17056 } }
loadAddon()
eq(WoW.itemRequests[17056], 1, "requested")
WoW.fire("ITEM_DATA_LOAD_RESULT", 17056, false); WoW.tick()
check(T().failed()[17056], "a failed load is recorded")
eq(textOf("reagents"), ic(2001) .. "40", "failed with no icon: left out")
check(not offeredIds()[17056], "and not offered")
tip(); GlassPanel.Refresh("reagents"); WoW.tick()
eq(WoW.itemRequests[17056], 1, "and never requested again")
GlassPanelReagentsDB = nil
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(table.concat(GlassPanelReagentsDB.order, ","), "17020", "and not a default pick")

-- The default search and the bar read no names: counts and icons only.
mage()
WoW.itemCounts[17032] = 2
GlassPanelReagentsDB = nil
local nameReads, realName = 0, C_Item.GetItemNameByID
C_Item.GetItemNameByID = function(...) nameReads = nameReads + 1 return realName(...) end
loadAddon()
eq(textOf("reagents"), ic(2003) .. "2", "the carried one, by default")
eq(nameReads, 0, "no name read for the bar or the default search")
C_Item.GetItemNameByID = realName

-- The shaman's water reagents are offered.
WoW.playerClass = { "Shaman", "SHAMAN", 7 }
WoW.bagItems = { [17030] = { name = "Ankh", icon = 1 }, [17058] = { name = "Fish Oil", icon = 2 },
                 [17057] = { name = "Shiny Fish Scales", icon = 3 } }
GlassPanelReagentsDB = nil
loadAddon()
local sh = {}
for _, c in ipairs(T().available()) do sh[#sh + 1] = c.name end
eq(table.concat(sh, ","), "Ankh,Fish Oil,Shiny Fish Scales", "shaman: Ankh, Fish Oil, Shiny Fish Scales")

check(next(GlassPanel.failures) == nil, "no failures")
-- Like Bags: its own icon and the gold caption "Reagents: ".
check(block("reagents").icon ~= nil, "reagents: a block icon")
eq(GlassPanel.Bar.ShowsCaption(block("reagents")), true, "reagents: the caption shows by default")
done("test_reagents")
