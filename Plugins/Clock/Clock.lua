-- Plugins/Clock/Clock.lua: local time on the bar, realm time in the tooltip.
--
-- While this block is on screen, Blizzard's minimap clock
-- (TimeManagerClockButton, from Blizzard_TimeManager) is hidden: two clocks
-- side by side is noise. It comes back when the block is hidden or the bar is
-- toggled off (API.Suppressor). It is a plain button, not a protected frame,
-- so this is safe in combat.

GlassPanel = GlassPanel or {}
local blizzardClock = GlassPanel.API.Suppressor("TimeManagerClockButton")

local function realmTime()
    local h, m = GetGameTime()
    return string.format("%02d:%02d", h, m)
end

GlassPanel.RegisterBlock({
    id = "clock",
    label = "Clock",
    showLabel = false,
    side = "right",
    order = 100,
    -- Wake on the next minute, when the text changes, not every second.
    interval = function() return 60 - tonumber(date("%S")) end,
    events = { "ADDON_LOADED" },
    onEvent = function(_, _, addon)
        if addon == "Blizzard_TimeManager" then blizzardClock.Sync() end
    end,
    onShown = function(_, visible) blizzardClock.Want(visible) end,
    text = function() return date("%H:%M") end,
    tooltip = function(_, tt)
        tt:AddLine("Clock")
        tt:AddDoubleLine("Local", date("%H:%M"), 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("Realm", realmTime(), 1, 1, 1, 1, 1, 1)
    end,
})
