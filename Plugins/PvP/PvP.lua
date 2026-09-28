-- Plugins/PvP/PvP.lua: whether you're flagged for PvP (#14), and the time
-- left before the flag drops when a timer is running. No click: toggling is
-- protected (measured on 70009: C_PvP.TogglePVP from a click raised
-- ADDON_ACTION_FORBIDDEN), so the tooltip points to /pvp, which the player
-- types themselves.
--
-- Forever (70009 dump): UnitIsPVP / UnitIsPVPFreeForAll (bool),
-- IsPVPTimerRunning / GetPVPTimer (ms left), GetPVPDesired (what you asked
-- for: on, or off-but-still-flagged while the timer runs).
-- Every read through API.Plain: a secret shows as unknown, never a guess.
-- The timer text needs a repaint every second only while it runs.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

-- flagged: true/false/nil (unknown); ffa; timer: seconds left or nil.
local function read()
    local flagged, ffa = P(UnitIsPVP("player")), P(UnitIsPVPFreeForAll("player"))
    local timer
    if P(IsPVPTimerRunning()) == true then
        local ms = P(GetPVPTimer())
        if type(ms) == "number" and ms > 0 then timer = math.floor(ms / 1000) end
    end
    return flagged, ffa == true, timer
end

local function clock(s) return string.format("%d:%02d", math.floor(s / 60), s % 60) end

GlassPanel.RegisterBlock({
    id = "pvp",
    label = "PvP",
    icon = "Interface\\Icons\\Ability_DualWield",
    side = "right",
    order = 130,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_FLAGS_CHANGED", "UNIT_FACTION", "ZONE_CHANGED_NEW_AREA" },
    -- Once a second while the flag's timer runs (the countdown), else rarely.
    interval = function()
        local _, _, timer = read()
        return timer and 1 or 30
    end,
    text = function()
        local flagged, ffa, timer = read()
        if flagged == nil then return "|cff888888?|r" end
        if not flagged then return "|cff40ff40Off|r" end
        local t = ffa and "|cffff4040FFA|r" or "|cffff4040On|r"
        if timer then t = t .. " |cffffd200(" .. clock(timer) .. ")|r" end
        return t
    end,
    tooltip = function(_, tt)
        local flagged, ffa, timer = read()
        tt:AddLine("PvP")
        if flagged == nil then
            tt:AddLine("Your PvP flag can't be read right now.", 0.7, 0.7, 0.7, true)
        elseif not flagged then
            tt:AddLine("You are not flagged for PvP.", 0.3, 1, 0.3)
        else
            tt:AddLine(ffa and "You are flagged for free-for-all PvP." or "You are flagged for PvP.", 1, 0.25, 0.25)
            if timer then
                tt:AddDoubleLine("Flag drops in", clock(timer), 1, 0.82, 0, 1, 1, 1)
            elseif P(GetPVPDesired()) == true then
                tt:AddLine("You turned it on: it stays on until you turn it off.", 0.7, 0.7, 0.7, true)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Type /pvp to toggle your PvP flag.", 0.3, 1, 0.3)
    end,
})
