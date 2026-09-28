-- The Durability plugin (#12).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tooltip()
    local b = block("durability").widget
    b._scripts.OnEnter(b)
    return GameTooltip._lines
end
local function has(pattern)
    for _, l in ipairs(tooltip()) do if l:find(pattern, 1, true) then return l end end
end

-- Lowest durability, coloured, with the total repair cost.
WoW.gear = {
    [1] = { cur = 50, max = 50, cost = 0 },
    [5] = { cur = 97, max = 100, cost = 2500 },
    [16] = { cur = 20, max = 100, cost = 4504 },   -- 20%: damaged (yellow)
}
loadAddon()
eq(textOf("durability"), "|cffffd20020%|r (" .. GlassPanel.API.CoinText(7004) .. ")", "lowest %, yellow, total cost")
check(has("Chest\t|cff40ff4097/100 (97%)|r"), "damaged chest listed (fallback label, colour)")
check(has("Main Hand\t|cffffd20020/100 (20%)|r"), "damaged main hand listed")
check(not has("Head\t"), "undamaged items not listed")
check(has("Repair cost\t" .. GlassPanel.API.CoinText(7004)), "total in the tooltip")

-- Repairs (at a merchant) update it: fully repaired shows 100% and no cost.
for _, g in pairs(WoW.gear) do g.cur, g.cost = g.max, 0 end
WoW.fire("MERCHANT_CLOSED"); WoW.tick()
eq(textOf("durability"), "|cff40ff40100%|r", "fully repaired: no cost shown")
check(has("Everything is fully repaired."), "tooltip says so")

-- A broken item is red.
WoW.gear[8] = { cur = 0, max = 60, cost = 900 }
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
check(textOf("durability"):find("^|cffff40400%%|r"), "broken: red 0%")

-- Localized slot names are used when the client has them.
rawset(_G, "FEETSLOT", "Pieds")
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
check(has("Pieds\t"), "localized slot name")
rawset(_G, "FEETSLOT", nil)

-- No repairCost in the tooltip data (or no C_TooltipInfo): durability only.
WoW.gear = { [5] = { cur = 40, max = 100 } }
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
eq(textOf("durability"), "|cff40ff4040%|r", "unknown cost: not shown")
check(has("Repair cost unknown here."), "tooltip says the cost is unknown")
WoW.noTooltipInfo = true
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
eq(textOf("durability"), "|cff40ff4040%|r", "tooltip data throwing: still durability")
WoW.noTooltipInfo = false

-- Secret reads: that item is skipped, nothing throws.
WoW.gear = { [5] = { cur = "secret", max = 100, cost = 10 }, [7] = { cur = 80, max = 100, cost = "secret" } }
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
eq(textOf("durability"), "|cff40ff4080%|r", "secret durability skipped; secret cost unknown")

-- A secret cost that keeps its number type (as on the client): unknown, not added.
WoW.MarkSecret(4321)
WoW.gear = { [5] = { cur = 50, max = 100, cost = 4321 } }
WoW.fire("UPDATE_INVENTORY_DURABILITY"); WoW.tick()
eq(textOf("durability"), "|cff40ff4050%|r", "secret-but-number cost treated as unknown")

-- Nothing with durability equipped: the block hides.
WoW.gear = {}
WoW.fire("PLAYER_EQUIPMENT_CHANGED", 5, false); WoW.tick()
eq(block("durability").widget._shown, false, "hidden with nothing to repair")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_durability")
