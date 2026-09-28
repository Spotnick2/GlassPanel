-- The PvP plugin (#14).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tip()
    local b = block("pvp").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end

loadAddon()
eq(textOf("pvp"), "|cff40ff40Off|r", "not flagged: Off")
check(tip():find("not flagged", 1, true), "tooltip")

WoW.pvp.flagged, WoW.pvp.desired = true, true
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r", "flagged: On")
check(tip():find("stays on until you turn it off", 1, true), "desired, no timer")

-- The countdown while the flag is about to drop, repainted every second.
WoW.pvp.desired, WoW.pvp.timerMs = false, 272000
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cffffd200(4:32)|r", "timer shown")
eq(GlassPanel.Engine.NextInterval(block("pvp")), 1, "repaints every second while the timer runs")
WoW.pvp.timerMs = 271000
WoW.tick(1.1); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cffffd200(4:31)|r", "countdown ticks")
check(tip():find("Flag drops in\t4:31", 1, true), "tooltip countdown")

WoW.pvp.ffa, WoW.pvp.timerMs = true, nil
WoW.fire("UNIT_FACTION", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040FFA|r", "free-for-all")
eq(GlassPanel.Engine.NextInterval(block("pvp")), 30, "slow when no timer")

-- Secret flag: unknown, not a guess.
WoW.pvp.flagged = "secret"
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cff888888?|r", "secret: ?")
check(tip():find("can't be read", 1, true), "tooltip says so")

-- No click: TogglePVP is protected on this client (ADDON_ACTION_FORBIDDEN,
-- measured). The tooltip points to /pvp instead.
eq(block("pvp").onClick, nil, "no click handler")
check(tip():find("Type /pvp to toggle", 1, true), "tooltip points to /pvp")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_pvp")
