-- The Warlock plugin (#67).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local HS, SS = "|TInterface\\Icons\\INV_Stone_04:14:14:0:0:64:64:5:59:5:59|t",
               "|TInterface\\Icons\\INV_Misc_Orb_04:14:14:0:0:64:64:5:59:5:59|t"

local function tip()
    local b = block("warlock").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function repaint() WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick() end

-- Not a warlock: the block isn't registered at all (no events, no clock).
WoW.playerClass = { "Warrior", "WARRIOR", 1 }
WoW.itemCounts[6265] = 12
loadAddon()
eq(block("warlock"), nil, "warrior: no block")
-- A class that can't be read at load: registered, nothing shown until it can.
WoW.playerClass = { WoW.Secret("class"), WoW.Secret("class file"), 9 }
loadAddon()
check(block("warlock") ~= nil, "unreadable class: registered")
eq(block("warlock").widget._shown, false, "and hidden")

-- A warlock.
WoW.playerClass = { "Warlock", "WARLOCK", 9 }
loadAddon()
eq(textOf("warlock"), "12", "shards, nothing else carried")
eq(block("warlock").widget._shown, true, "warlock: shown")
eq(block("warlock").interval, nil, "no clock: the bar text doesn't depend on time")
check(tip():find("Healthstone\tnone", 1, true), "tooltip: no healthstone")

-- Colours: yellow under 5, red at 0.
WoW.itemCounts[6265] = 3; repaint()
eq(textOf("warlock"), "|cffffd2003|r", "low: yellow")
WoW.itemCounts[6265] = 0; repaint()
eq(textOf("warlock"), "|cffff40400|r", "none: red")
WoW.itemCounts[6265] = 5; repaint()
eq(textOf("warlock"), "5", "at the mark: plain")

-- The counts are a snapshot: a cooldown event doesn't rescan them.
WoW.itemCounts[6265] = 9
WoW.fire("BAG_UPDATE_COOLDOWN"); WoW.tick()
eq(textOf("warlock"), "5", "BAG_UPDATE_COOLDOWN: counts not re-read")
repaint()
eq(textOf("warlock"), "9", "a bag event re-reads them")
local reads, real = 0, C_Item.GetItemCount
C_Item.GetItemCount = function(...) reads = reads + 1 return real(...) end
WoW.fire("BAG_UPDATE_DELAYED"); WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
tip()
eq(reads, 21, "one scan for two events, a repaint and a tooltip")
C_Item.GetItemCount = real
WoW.itemCounts[6265] = 5; repaint()

-- Stones: any rank, talented ones too; the best is named.
WoW.itemCounts[19011] = 1   -- a talented Greater Healthstone
WoW.itemCounts[5512] = 1    -- and a Minor
repaint()
eq(textOf("warlock"), "5 " .. HS, "healthstone marker")
check(tip():find("Healthstone\tGreater Healthstone (|cff40ff40ready|r)", 1, true), "best healthstone named, ready")
WoW.itemCounts[5232] = 1; repaint()
eq(textOf("warlock"), "5 " .. HS .. " " .. SS, "soulstone marker")
check(tip():find("Soulstone\tMinor Soulstone", 1, true), "soulstone named")
-- The client's (localised) name when it has one.
WoW.itemNames[5232] = "Pierre d'âme mineure"
check(tip():find("Soulstone\tPierre d'âme mineure", 1, true), "client's item name")
WoW.itemNames[5232] = nil

-- The healthstone's cooldown in the tooltip, ticking only while it's open.
GameTooltip:Hide()
WoW.itemCooldowns[19011] = { WoW.now - 30, 120, 1 }
WoW.fire("BAG_UPDATE_COOLDOWN"); WoW.tick()
eq(block("warlock")._test.ticker(), nil, "no ticker while the tooltip is closed")
check(tip():find("Greater Healthstone (|cffffd2001:30|r)", 1, true), "cooldown left")
check(block("warlock")._test.ticker() ~= nil, "tooltip open with a cooldown: ticking")
WoW.now = WoW.now + 1
WoW.fireTickers(); WoW.tick()
check(table.concat(GameTooltip._lines, "\n"):find("(|cffffd2001:29|r)", 1, true), "the open tooltip counts down")
GameTooltip:Hide()
WoW.fireTickers()
eq(block("warlock")._test.ticker(), nil, "tooltip closed: the ticker stops")
-- The global cooldown isn't the stone's.
WoW.itemCooldowns[19011] = { WoW.now, 1.5, 1 }
check(tip():find("Greater Healthstone (|cff40ff40ready|r)", 1, true), "GCD: ready")
eq(block("warlock")._test.ticker(), nil, "and no ticker for it")
-- Held until something ends (enable 0): not ready.
WoW.itemCooldowns[19011] = { WoW.now, 120, 0 }
check(tip():find("Greater Healthstone (|cffffd200waiting|r)", 1, true), "enable 0: waiting")
WoW.itemCooldowns[19011] = { "secret", 120, 1 }
check(tip():find("Greater Healthstone (|cff888888?|r)", 1, true), "secret cooldown: ?")
WoW.itemCooldowns[19011] = nil
GameTooltip:Hide(); WoW.fireTickers()

-- Secret counts: a grey ? for shards; a stone that can't be read isn't shown.
WoW.itemCounts[6265] = "secret"; repaint()
eq(textOf("warlock"), "|cff888888?|r " .. HS .. " " .. SS, "secret shards: ?")
check(tip():find("can't be read", 1, true), "tooltip says so")
WoW.itemCounts = { [6265] = 7, [9421] = "secret" }; repaint()
eq(textOf("warlock"), "7", "unreadable healthstone: no marker")
check(tip():find("Healthstone\t|cff888888?|r", 1, true), "tooltip: healthstone unknown")
check(tip():find("can't be read", 1, true), "an unreadable stone: footnote too")
-- Readable as carried beats an unreadable better rank.
WoW.itemCounts[5509] = 1; repaint()
eq(textOf("warlock"), "7 " .. HS, "a lower rank carried still shows")
check(not tip():find("can't be read", 1, true), "all readable: no footnote")

eq(block("warlock").onClick, nil, "no click (using a stone is secure)")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_warlock")
