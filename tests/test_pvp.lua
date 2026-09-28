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
WoW.pvp.timerMs = 271000
WoW.tick(1.1); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cffffd200(4:31)|r", "countdown ticks")
check(tip():find("Flag drops in\t4:31", 1, true), "tooltip countdown")

WoW.pvp.ffa, WoW.pvp.timerMs = true, nil
WoW.fire("UNIT_FACTION", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040FFA|r", "free-for-all")

-- Secret flag: unknown, not a guess.
WoW.pvp.flagged = "secret"
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cff888888?|r", "secret: ?")
check(tip():find("can't be read", 1, true), "tooltip says so")

-- No click: TogglePVP is protected on this client (ADDON_ACTION_FORBIDDEN,
-- measured). The tooltip points to /pvp instead.
eq(block("pvp").onClick, nil, "no click handler")
check(tip():find("Type /pvp to toggle", 1, true), "tooltip points to /pvp")

-- Review round (#27).
WoW.pvp = { flagged = false, ffa = false, timerMs = nil, desired = false }
loadAddon()
-- Only the player's firing of these events counts.
WoW.pvp.flagged = true
WoW.fire("PLAYER_FLAGS_CHANGED", "party1"); WoW.tick()
eq(textOf("pvp"), "|cff40ff40Off|r", "another unit's flag change: ignored")
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r", "the player's: repainted")
-- The timer starting is its own event: shown at once, not on the next slow tick.
WoW.pvp.timerMs = 300000
WoW.fire("PVP_TIMER_UPDATE", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cffffd200(5:00)|r", "PVP_TIMER_UPDATE shows the countdown at once")
-- Rounded up: 0.8 s left is 0:01, never a still-flagged 0:00.
WoW.pvp.timerMs = 800
WoW.fire("PVP_TIMER_UPDATE", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cffffd200(0:01)|r", "rounded up")
-- An open tooltip follows the countdown.
WoW.pvp.timerMs = 90000
WoW.fire("PVP_TIMER_UPDATE", "player"); WoW.tick()
local pb = block("pvp").widget
pb._scripts.OnEnter(pb); GameTooltip._shown = true
WoW.pvp.timerMs = 89000
WoW.tick(1.1); WoW.tick()
check(table.concat(GameTooltip._lines, "\n"):find("Flag drops in\t1:29", 1, true), "tooltip redrawn while open")
GameTooltip._shown = false
-- Unknown is shown as unknown: a secret FFA flag or timer.
WoW.pvp.timerMs = nil
WoW.pvp.ffa = "secret"
WoW.fire("PLAYER_FLAGS_CHANGED", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r|cff888888?|r", "secret FFA flag: marked unsure")
WoW.pvp.ffa, WoW.pvp.timerMs = false, "secret"
WoW.fire("PVP_TIMER_UPDATE", "player"); WoW.tick()
eq(textOf("pvp"), "|cffff4040On|r |cff888888(?)|r", "secret timer: (?)")
WoW.pvp.timerMs = nil
check(GlassPanel.RegisterBlock({ id = "badunit", text = function() end, unitEvents = { X = 5 } }) == nil,
      "unitEvents must map event names to units")

check(next(GlassPanel.failures) == nil, "no failures")
done("test_pvp")
