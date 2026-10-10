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

-- Not a warlock: no block.
WoW.playerClass = { "Warrior", "WARRIOR", 1 }
WoW.itemCounts[6265] = 12
loadAddon()
eq(block("warlock").widget._shown, false, "warrior: hidden")

-- A warlock.
WoW.playerClass = { "Warlock", "WARLOCK", 9 }
loadAddon()
eq(textOf("warlock"), "12", "shards, nothing else carried")
eq(block("warlock").widget._shown, true, "warlock: shown")
check(tip():find("Healthstone\tnone", 1, true), "tooltip: no healthstone")

-- Colours: yellow under 5, red at 0.
WoW.itemCounts[6265] = 3; repaint()
eq(textOf("warlock"), "|cffffd2003|r", "low: yellow")
WoW.itemCounts[6265] = 0; repaint()
eq(textOf("warlock"), "|cffff40400|r", "none: red")
WoW.itemCounts[6265] = 5; repaint()
eq(textOf("warlock"), "5", "at the mark: plain")

-- Stones: any rank, talented ones too; the best is named.
WoW.itemCounts[19011] = 1   -- a talented Greater Healthstone
WoW.itemCounts[5512] = 1    -- and a Minor
repaint()
eq(textOf("warlock"), "5 " .. HS, "healthstone marker")
check(tip():find("Healthstone\tGreater Healthstone (|cff40ff40ready|r)", 1, true), "best healthstone named, ready")
WoW.itemCounts[5232] = 1; repaint()
eq(textOf("warlock"), "5 " .. HS .. " " .. SS, "soulstone marker")
check(tip():find("Soulstone\tMinor Soulstone", 1, true), "soulstone named")

-- The healthstone's cooldown in the tooltip, counting down every second.
WoW.itemCooldowns[19011] = { WoW.now - 30, 120, 1 }
WoW.fire("BAG_UPDATE_COOLDOWN"); WoW.tick()
check(tip():find("Greater Healthstone (|cffffd2001:30|r)", 1, true), "cooldown left")
eq(GlassPanel.Engine.NextInterval(block("warlock")), 1, "1 s while a cooldown runs")
WoW.itemCooldowns[19011] = nil
eq(GlassPanel.Engine.NextInterval(block("warlock")), 30, "30 s otherwise")
WoW.itemCooldowns[19011] = { "secret", 120, 1 }
check(tip():find("Greater Healthstone (|cff888888?|r)", 1, true), "secret cooldown: ?")
WoW.itemCooldowns[19011] = nil

-- Secret counts: a grey ? for shards; a stone that can't be read isn't shown.
WoW.itemCounts[6265] = "secret"; repaint()
eq(textOf("warlock"), "|cff888888?|r " .. HS .. " " .. SS, "secret shards: ?")
check(tip():find("can't be read", 1, true), "tooltip says so")
WoW.itemCounts = { [6265] = 7, [9421] = "secret" }; repaint()
eq(textOf("warlock"), "7", "unreadable healthstone: no marker")
check(tip():find("Healthstone\t|cff888888?|r", 1, true), "tooltip: healthstone unknown")
-- Readable as carried beats an unreadable better rank.
WoW.itemCounts[5509] = 1; repaint()
eq(textOf("warlock"), "7 " .. HS, "a lower rank carried still shows")

eq(block("warlock").onClick, nil, "no click (using a stone is secure)")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_warlock")
