-- Blocks/Gold.lua: the player's money, and what changed this session.
--
-- GetMoney has been measured SECRET on a PvP realm (porting guide, "Secret
-- values"), so every read is tested before any arithmetic. While it is secret
-- the block says so instead of guessing, and the session baseline waits for
-- the first plain read.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API

local sessionStart   -- copper at the first plain read this session

local function money() return API.Plain(GetMoney()) end

GlassPanel.RegisterBlock({
    id = "gold",
    label = "Gold",
    -- No block icon: the coin text carries its own icons, and it drops zero
    -- denominations, so a leading coin icon made "37s 81c" read as 37 gold.
    order = 30,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    onEvent = function()
        if sessionStart == nil then sessionStart = money() end
    end,
    text = function()
        local m = money()
        if m == nil then return "|cff888888gold hidden|r" end
        return API.CoinText(m)
    end,
    tooltip = function(_, tt)
        tt:AddLine("Gold")
        local m = money()
        if m == nil then
            tt:AddLine("The client is hiding your money right now.", 0.7, 0.7, 0.7, true)
            return
        end
        tt:AddDoubleLine("Carried", API.CoinText(m), 1, 1, 1, 1, 1, 1)
        if sessionStart then
            local delta = m - sessionStart
            local sign, r, g = "+", 0.3, 1
            if delta < 0 then sign, r, g, delta = "-", 1, 0.3, -delta end
            tt:AddDoubleLine("This session", sign .. API.CoinText(delta), 1, 1, 1, r, g, 0.3)
        end
    end,
})
