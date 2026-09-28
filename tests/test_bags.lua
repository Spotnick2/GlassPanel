-- The Bags plugin (#13).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tooltip()
    local b = block("bags").widget
    b._scripts.OnEnter(b)
    return GameTooltip._lines
end
local function has(pattern)
    for _, l in ipairs(tooltip()) do if l:find(pattern, 1, true) then return l end end
end

-- Used/total over normal bags; special bags listed apart, not counted.
WoW.bags = {
    [0] = { slots = 16, free = 4, family = 0, name = "Backpack" },
    [1] = { slots = 14, free = 0, family = 0, name = "Linen Bag" },
    [2] = { slots = 18, free = 10, family = 1, name = "Quiver" },   -- special
}
loadAddon()
eq(textOf("bags"), "|cffffd20026/30|r", "26 used of 30 normal slots, yellow at 87%")
check(has("Backpack\t12/16"), "backpack listed")
check(has("Free\t4"), "free normal slots")
check(has("Quiver\t8/18"), "quiver listed apart")
check(has("Special bags (not counted)"), "special section")

-- Updates on BAG_UPDATE_DELAYED; colours by fill.
WoW.bags[1].free = 14
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cffffffff12/30|r", "white with room")
WoW.bags[0].free, WoW.bags[1].free = 0, 1
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cffff404029/30|r", "red when nearly full")

-- The reagent slot (bag 5) counts as special, as in TitanBag.
WoW.bags[5] = { slots = 20, free = 20, family = 0, name = "Reagent Bag" }
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cffff404029/30|r", "bag 5 not counted")
check(has("Reagent Bag	0/20"), "but listed under the special bags")
WoW.bags[5] = nil

-- Click opens all bags.
local b = block("bags").widget
b._scripts.OnClick(b, "LeftButton")
eq(WoW.bagToggles, 1, "left-click toggles all bags")
b._scripts.OnClick(b, "RightButton"); b._scripts.OnClick(b, "MiddleButton")
eq(WoW.bagToggles, 1, "other buttons don't")

-- One bag's free count secret: left out AND flagged, never a smaller total
-- passed off as the whole.
WoW.bags = { [0] = { slots = 16, free = "secret", family = 0 }, [1] = { slots = 14, free = 4, family = 0 } }
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cffffffff10/14|r|cff888888?|r", "partial: marked unsure")
check(has("1 bag(s) can't be read right now"), "tooltip says why")

-- A secret family: normal or special is unknown, so the bag isn't counted as normal.
WoW.bags = { [0] = { slots = 16, free = 8, family = 0 }, [2] = { slots = 18, free = 10, family = "secret" } }
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cffffffff8/16|r|cff888888?|r", "secret family: left out and flagged, not counted as normal")

-- Every bag unreadable: "hidden".
WoW.bags = { [0] = { slots = 16, free = "secret", family = 0 } }
WoW.fire("BAG_UPDATE_DELAYED"); WoW.tick()
eq(textOf("bags"), "|cff888888hidden|r", "nothing readable: hidden")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_bags")
