-- Blocks/Clock.lua: local time on the bar, realm time in the tooltip.
--
-- While this block is on screen, Blizzard's minimap clock
-- (TimeManagerClockButton, from Blizzard_TimeManager) is hidden: two clocks
-- side by side is noise. It comes back when the block is hidden or the bar is
-- toggled off. We only ever Show() it again if we were the ones who hid it.
-- It is a plain button, not a protected frame, so this is safe in combat.
-- (Not handled: turning Blizzard's clock OFF in Settings while we hide it;
-- the frame is hidden either way, so there is nothing to observe.)

GlassPanel = GlassPanel or {}

local wantHidden = false   -- our block is visible
local hidBlizzard = false  -- we hid it (so we may show it again)
local hooked = false

local function blizzardClock()
    return rawget(_G, "TimeManagerClockButton")
end

local function syncBlizzardClock()
    local c = blizzardClock()
    if not c then return end   -- Blizzard_TimeManager not loaded yet: ADDON_LOADED retries
    if not hooked then
        -- Blizzard re-shows it (settings, Edit Mode). A local flag, not a field
        -- on their frame: writing into a Blizzard frame's table taints it.
        -- Hiding a clock that was just shown (by Blizzard or by the user in
        -- Settings) counts as ours to give back.
        c:HookScript("OnShow", function(self)
            if wantHidden then hidBlizzard = true; self:Hide() end
        end)
        hooked = true
    end
    if wantHidden then
        if c:IsShown() then hidBlizzard = true end
        c:Hide()
    elseif hidBlizzard then
        hidBlizzard = false
        c:Show()
    end
end

local function realmTime()
    local h, m = GetGameTime()
    return string.format("%02d:%02d", h, m)
end

GlassPanel.RegisterBlock({
    id = "clock",
    label = "Clock",
    side = "right",
    order = 100,
    -- Wake on the next minute, when the text changes, not every second.
    interval = function() return 60 - tonumber(date("%S")) end,
    events = { "ADDON_LOADED" },
    onEvent = function(_, _, addon)
        if addon == "Blizzard_TimeManager" then syncBlizzardClock() end
    end,
    onShown = function(_, visible)
        wantHidden = visible
        syncBlizzardClock()
    end,
    text = function() return date("%H:%M") end,
    tooltip = function(_, tt)
        tt:AddLine("Clock")
        tt:AddDoubleLine("Local", date("%H:%M"), 1, 1, 1, 1, 1, 1)
        tt:AddDoubleLine("Realm", realmTime(), 1, 1, 1, 1, 1, 1)
    end,
})
