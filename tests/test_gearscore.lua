-- The GearScore plugin (#16).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tip()
    local b = block("gearscore").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function has(s) return tip():find(s, 1, true) ~= nil end
local function refresh(event, ...) WoW.fire(event or "PLAYER_EQUIPMENT_CHANGED", ...); WoW.tick() end
local ILVL = "|cffffd100 iLvl:|r "

-- Hand calculations from the formula (score = floor((ilvl - A) / B * SlotMOD * 1.8618 * qualityScale)):
-- epic chest 66: table C, (66 - 0.25) / 1.6275 * 1 * 1.8618 = 75.21 -> 75
-- rare head 63: table B, (63 - 0.75) / 1.8 * 1 * 1.8618 = 64.39 -> 64
-- total 139; ramp colour at 139 (grey 0.62 -> white 1.00, t = 0.695): 0.884 * 255 -> e1; at 75: 0.7625 -> c2
WoW.equipped = {
    [5] = { id = 1001, ilvl = 66, quality = 4, equipLoc = "INVTYPE_CHEST" },
    [1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD" },
}
WoW.avgItemLevel = { 66.3, 65.6 }
loadAddon()
eq(textOf("gearscore"), "|cffe1e1e1139|r" .. ILVL .. "66", "score coloured on the ramp, Blizzard's iLvl rounded")
check(has("|cffc69b6dKaruzo|r"), "class-coloured name")
check(has("GearScore\t|cffe1e1e1139|r  (Trash)"), "score and bracket")
check(has("Avg Item Level\t65.6"), "Blizzard's average, one decimal")
check(has("Items Scored\t2"), "items actually scored (the TBC plugin always said 17)")
check(has("Chest  |cffa335ee|Hitem:1001:"), "per-slot line with the item link")
check(has("\t|cff") and has("75|r  |cffffffffiLvl 66|r"), "chest: 75, iLvl 66")
check(has("64|r  |cffffffffiLvl 63|r"), "head: 64, iLvl 63")

-- Legendary and poor/common quality scaling; the two-hander's weight.
-- legendary 2H 80: quality 4 x 1.3, table C, (80 - 0.25) / 1.6275 * 2 * 1.8618 * 1.3 = 237.2 -> 237
-- common ring 20: quality 2 x 0.005, table B, (20 - 8) / 2 * 0.5625 * 1.8618 * 0.005 = 0.03 -> 0
WoW.equipped = {
    [16] = { id = 1003, ilvl = 80, quality = 5, equipLoc = "INVTYPE_2HWEAPON" },
    [11] = { id = 1005, ilvl = 20, quality = 1, equipLoc = "INVTYPE_FINGER" },
}
refresh()
check(textOf("gearscore"):find("^|cff%x%x%x%x%x%x237|r"), "legendary 2H: 237")
check(has("Items Scored\t2"), "a zero-score common ring still counts as scored")
check(has("Main Hand"), "main hand listed")

-- Hunters: ranged x 5.3224, melee x 0.3164.
-- rare bow 60: table B, (60 - 0.75) / 1.8 * 0.3164 * 1.8618 = 19.39 -> 19; hunter: 19 * 5.3224 = 101.1 -> 101
WoW.equipped = { [18] = { id = 1004, ilvl = 60, quality = 3, equipLoc = "INVTYPE_RANGED" } }
refresh()
check(textOf("gearscore"):find("^|cff%x%x%x%x%x%x19|r"), "bow for a warrior: 19")
WoW.playerClass = { "Hunter", "HUNTER", 3 }
refresh()
check(textOf("gearscore"):find("^|cff%x%x%x%x%x%x101|r"), "bow for a hunter: 101")
WoW.equipped[16] = { id = 1003, ilvl = 80, quality = 5, equipLoc = "INVTYPE_2HWEAPON" }
refresh()
check(textOf("gearscore"):find("^|cff%x%x%x%x%x%x175|r"), "hunter's 2H: 237 * 0.3164 = 74, + 101 = 175")
WoW.playerClass = { "Warrior", "WARRIOR", 1 }

-- Brackets on the Classic scale (200 each), whatever the client build says: 800 is Superior.
WoW.equipped = {}
local slots = { { 1, "INVTYPE_HEAD" }, { 5, "INVTYPE_CHEST" }, { 7, "INVTYPE_LEGS" }, { 16, "INVTYPE_2HWEAPON" },
                { 3, "INVTYPE_SHOULDER" }, { 10, "INVTYPE_HAND" }, { 6, "INVTYPE_WAIST" }, { 8, "INVTYPE_FEET" } }
for i, s in ipairs(slots) do WoW.equipped[s[1]] = { id = 2000 + i, ilvl = 88, quality = 4, equipLoc = s[2] } end
refresh()
-- epic 88 (table C): (88 - 0.25) / 1.6275 * 1.8618 = 100.38; x1: 100 (head, chest, legs), x2: 200, x0.75: 75 (x4)
-- total 3 * 100 + 200 + 4 * 75 = 800, the epic stop: 0.64, 0.21, 0.93 -> a3 35 ed
check(textOf("gearscore"):find("^|cffa335ed800|r"), "800: epic purple on the ramp")
check(has("(Superior)"), "800 is Superior on the 200 scale")
local realBuild = GetBuildInfo
GetBuildInfo = function() return "11.0.0", "70009", "Sep 23 2026", 110000 end
loadAddon()
check(has("(Superior)"), "a Retail-sized interface number doesn't change the scale")
GetBuildInfo = realBuild

-- An item not cached yet: requested, left out, flagged; loaded -> counted.
WoW.equipped = {
    [5] = { id = 1001, ilvl = 66, quality = 4, equipLoc = "INVTYPE_CHEST" },
    [1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD", cached = false },
}
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r|cff888888?|r" .. ILVL .. "66", "loading item left out, grey ?")
eq(WoW.itemRequests[1002], 1, "its data requested")
check(has("1 item(s) still loading"), "tooltip says so")
check(has("Items Scored\t1"), "only the loaded one scored")
-- Some other item loading doesn't rescan; ours does.
local reqs = WoW.itemRequests[1002]
refresh("GET_ITEM_INFO_RECEIVED", 9999, true)
eq(WoW.itemRequests[1002], reqs, "an unrelated item's load: no rescan")
WoW.itemLoaded(1002)
refresh("ITEM_DATA_LOAD_RESULT", 1002, true)
eq(textOf("gearscore"), "|cffe1e1e1139|r" .. ILVL .. "66", "our item loaded: counted, no ?")

-- Item loads are listened to only while one of ours is loading: none now.
local function loaderListening()
    for _, w in ipairs(WoW.frames) do
        if w._events and (w._events.ITEM_DATA_LOAD_RESULT or w._events.GET_ITEM_INFO_RECEIVED) then return true end
    end
    return false
end
eq(loaderListening(), false, "nothing loading: item-load events not listened to")
eq(GlassPanel.Engine._test.listeners.GET_ITEM_INFO_RECEIVED, nil, "and never through the bar's engine")

-- Asked once: other rescans while it loads don't ask again.
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD", cached = false }
WoW.equipped[3] = { id = 1006, ilvl = 60, quality = 3, equipLoc = "INVTYPE_SHOULDER", cached = false }
WoW.itemRequests = {}
refresh()
eq(loaderListening(), true, "loading: listening")
WoW.itemLoaded(1006)
refresh("ITEM_DATA_LOAD_RESULT", 1006, true)          -- ours: a rescan
refresh("GET_ITEM_INFO_RECEIVED", 1006, true)         -- the second event for it: ignored
eq(WoW.itemRequests[1002], 1, "the item still loading isn't asked for again")
eq(WoW.itemRequests[1006], 1, "nor the one that arrived")
check(textOf("gearscore"):find("|cff888888?|r", 1, true), "still flagged for 1002")
-- A load that fails: unreadable, not asked again, and no longer listened to.
refresh("ITEM_DATA_LOAD_RESULT", 1002, false)
GlassPanel.Refresh("gearscore"); WoW.tick()
eq(WoW.itemRequests[1002], 1, "failed load: not re-requested")
check(has("1 item(s) can't be read right now"), "failed load: unreadable")
eq(loaderListening(), false, "all answered: stops listening")
-- Gear changes ask again.
refresh()
eq(WoW.itemRequests[1002], 2, "an equipment change asks again")
WoW.itemLoaded(1002)
refresh("ITEM_DATA_LOAD_RESULT", 1002, true)
WoW.equipped[3] = nil
refresh()

-- Only the player's inventory changes matter.
WoW.equipped[1] = nil
refresh("UNIT_INVENTORY_CHANGED", "target")
check(textOf("gearscore"):find("139", 1, true), "another unit's inventory: no rescan")
refresh("UNIT_INVENTORY_CHANGED", "player")
check(textOf("gearscore"):find("75|r", 1, true), "the player's: rescanned")

-- A burst of events is one scan.
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD", cached = false }
WoW.itemRequests = {}
for _ = 1, 15 do WoW.fire("PLAYER_EQUIPMENT_CHANGED", 1, true) end
WoW.tick()
eq(WoW.itemRequests[1002], 1, "15 events, one scan")
WoW.equipped[1].cached = true

-- Secret reads: that item is unreadable (flagged), never guessed.
WoW.equipped[1] = { id = 1002, ilvl = "secret", quality = 3, equipLoc = "INVTYPE_HEAD" }
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r|cff888888?|r" .. ILVL .. "66", "secret ilvl: left out, flagged")
check(has("1 item(s) can't be read right now"), "tooltip says why")
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = "secret", equipLoc = "INVTYPE_HEAD" }
refresh()
check(textOf("gearscore"):find("75|r|cff888888?|r", 1, true), "secret quality: same")
WoW.equipped[1] = { id = "secret", ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD" }
refresh()
check(textOf("gearscore"):find("75|r|cff888888?|r", 1, true), "secret item id: same")
check(not GlassPanel.failures["gearscore:scan"], "secret item id: the scan didn't throw")
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "secret" }
refresh()
check(textOf("gearscore"):find("75|r|cff888888?|r", 1, true), "secret slot type: same")
check(not GlassPanel.failures["gearscore:scan"], "secret slot type: the scan didn't throw")
-- A secret that keeps its number type (as on the client).
WoW.MarkSecret(63.5)
WoW.equipped[1] = { id = 1002, ilvl = 63.5, quality = 3, equipLoc = "INVTYPE_HEAD" }
refresh()
check(textOf("gearscore"):find("75|r|cff888888?|r", 1, true), "secret-but-number ilvl: left out")
-- A secret link: scored from the id, shown without the link.
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD", link = "secret" }
refresh()
check(textOf("gearscore"):find("^|cffe1e1e1139|r"), "secret link: still scored")
-- ... also one that keeps its string type (as on the client): not shown.
local secretLink = "|cff0070dd|Hitem:1002::::::::60:::::|h[Secret Helm]|h|r"
WoW.MarkSecret(secretLink)
WoW.equipped[1].link = secretLink
refresh()
check(textOf("gearscore"):find("^|cffe1e1e1139|r"), "secret string link: still scored")
check(not has("Secret Helm"), "secret string link: not shown")

-- Scored from the item id, not the link: a link lookup that comes back
-- empty doesn't leave it "loading".
local realInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(item) if type(item) == "string" then return nil end return realInfo(item) end
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD" }
refresh()
C_Item.GetItemInfo = realInfo
check(textOf("gearscore"):find("^|cffe1e1e1139|r"), "looked up by id")

-- No slot type returned: unreadable, never silently dropped.
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = nil }
refresh()
check(textOf("gearscore"):find("75|r|cff888888?|r", 1, true), "no slot type: flagged")
-- A quality the formula has no score for (artifact): counted and noted, no "?".
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 6, equipLoc = "INVTYPE_HEAD" }
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r" .. ILVL .. "66", "unscored quality: not unsure")
check(has("1 item(s) have no GearScore"), "unscored: noted")

-- Rings and trinkets: numbered when the client names both slots the same.
FINGER0SLOT, FINGER1SLOT = "Finger", "Finger"
WoW.equipped[11] = { id = 1007, ilvl = 60, quality = 3, equipLoc = "INVTYPE_FINGER" }
WoW.equipped[12] = { id = 1008, ilvl = 60, quality = 3, equipLoc = "INVTYPE_FINGER" }
refresh()
check(has("Finger 1  ") and has("Finger 2  "), "same client name: numbered")
FINGER0SLOT, FINGER1SLOT = "Finger 1", "Finger 2"
refresh()
check(has("Finger 1  ") and not has("Finger 1 1"), "distinct client names: as they are")
FINGER0SLOT, FINGER1SLOT = nil, nil
WoW.equipped[11], WoW.equipped[12] = nil, nil

-- Nothing scorable, only unreadable: "?" alone, not a plausible 0.
WoW.equipped = { [1] = { id = 1002, ilvl = "secret", quality = 3, equipLoc = "INVTYPE_HEAD" } }
refresh()
eq(textOf("gearscore"), "|cff888888?|r" .. ILVL .. "66", "all unreadable: ?")

-- Blizzard's average unreadable: the iLvl part is left off.
WoW.equipped = { [5] = { id = 1001, ilvl = 66, quality = 4, equipLoc = "INVTYPE_CHEST" } }
WoW.avgItemLevel = { 66.3, "secret" }
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r", "secret average: no iLvl part")
check(has("Avg Item Level\t|cff888888?|r"), "tooltip: unknown")
WoW.MarkSecret(71.4)
WoW.avgItemLevel = { 66.3, 71.4 }
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r", "secret-but-number average: no iLvl part")
WoW.avgItemLevel = { 66.3, 65.6 }

-- Blizzard's average settles later, on its own event: repainted, and the
-- gear isn't rescanned (an item still loading isn't asked for again).
WoW.avgItemLevel = { 66.3, 60 }
refresh()
eq(textOf("gearscore"), "|cffc2c2c275|r" .. ILVL .. "60", "baseline average 60")
WoW.equipped[1] = { id = 1002, ilvl = 63, quality = 3, equipLoc = "INVTYPE_HEAD", cached = false }
WoW.itemRequests = {}
refresh()
WoW.avgItemLevel = { 66.3, 66 }
refresh("PLAYER_AVG_ITEM_LEVEL_UPDATE")
check(textOf("gearscore"):find(ILVL .. "66", 1, true), "average update repaints the bar")
eq(WoW.itemRequests[1002], 1, "no rescan: the loading item isn't asked for again")
WoW.equipped[1] = nil
WoW.avgItemLevel = { 66.3, 65.6 }
refresh()

-- A secret class or name: plain name / title, nothing throws.
WoW.playerClass = { "secret", "secret", 1 }
refresh()
check(has("Karuzo"), "secret class: name uncoloured")
WoW.playerName = "secret"
check(tip():find("^GearScore\n"), "secret name: a plain title")
WoW.playerName, WoW.playerClass = "Karuzo", { "Warrior", "WARRIOR", 1 }

-- A scan that throws is recorded and retried.
local real = GetInventoryItemID
GetInventoryItemID = function() error("client hiccup") end
refresh()
check(GlassPanel.failures["gearscore:scan"], "failed scan recorded")
eq(textOf("gearscore"), "|cff888888?|r" .. ILVL .. "66", "failed scan: unknown, not the old score")
check(has("couldn't be read"), "tooltip says so")
GetInventoryItemID = real
GlassPanel.failures["gearscore:scan"] = nil
GlassPanel.Refresh("gearscore"); WoW.tick()
eq(textOf("gearscore"), "|cffc2c2c275|r" .. ILVL .. "66", "retried on the next repaint")

-- No click action.
local b = block("gearscore").widget
WoW.chat = {}
WoW.shift = true   -- the TBC plugin's shift-click print is dropped
b._scripts.OnClick(b, "LeftButton")
WoW.shift = false
eq(#WoW.chat, 0, "click does nothing")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_gearscore")
