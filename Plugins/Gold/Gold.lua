-- Plugins/Gold/Gold.lua: the player's money, and what changed this session.
--
-- GetMoney has been measured SECRET on a PvP realm (porting guide, "Secret
-- values"), so every read is tested before any arithmetic. While it is secret
-- the block says so instead of guessing.
--
-- The session (#161, TitanGold's session stats) is the core's (Money.lua,
-- #160): API.MoneySession(), kept across /reload, new at each login, shared
-- with the Alts block, which replaces this one on the bar.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API

local PER_HOUR_AFTER = 300   -- seconds: a per-hour rate from a minute of play is noise

local function money() return API.Plain(GetMoney()) end

local function reset()
    if API.ResetMoneySession() then
        API.Print("Gold: the session starts again now.")
    else
        API.Print("Gold: the session starts again at the next readable amount (the client is hiding your money).")
    end
    GlassPanel.Refresh("gold")
    GlassPanel.Refresh("altstable")
end

local function duration(s)
    s = math.floor(s)
    if s < 60 then return "under a minute" end
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

-- The session's length and rate move while the tooltip is open (Codex on #162):
-- a 1 s ticker repaints it then (Warlock's pattern), and stops itself.
local block, ticker
local function tooltipOpen()
    local w = block and block.widget
    return w ~= nil and GameTooltip:GetOwner() == w and GameTooltip:IsShown() and true or false
end
local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end
local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        if tooltipOpen() then GlassPanel.Refresh("gold") else stopTicker() end
    end)
end

block = GlassPanel.RegisterBlock({
    id = "gold",
    label = "Gold",
    showLabel = false,   -- the coin icons say it (no caption on the TBC bar either)
    -- No block icon: the coin text carries its own icons, and it drops zero
    -- denominations, so a leading coin icon made "37s 81c" read as 37 gold.
    order = 30,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    text = function()
        local m = money()
        if m == nil then return "|cff888888gold hidden|r" end
        return API.CoinText(m)
    end,
    tooltip = function(_, tt)
        tt:AddLine("Gold")
        local m = money()
        if m == nil then
            stopTicker()
            tt:AddLine("The client is hiding your money right now.", 0.7, 0.7, 0.7, true)
            return
        end
        tt:AddDoubleLine("Carried", API.CoinText(m), 1, 1, 1, 1, 1, 1)
        local s = API.MoneySession()
        if not s then stopTicker(); return end
        local elapsed = s.elapsed
        tt:AddLine(" ")
        tt:AddDoubleLine("This session", elapsed and duration(elapsed) or "", 1, 0.82, 0, 0.7, 0.7, 0.7)
        tt:AddDoubleLine("Started with", API.CoinText(s.start), 1, 1, 1, 1, 1, 1)
        local delta = s.delta
        local label, sign, r, g = "Earned", "+", 0.3, 1
        if delta < 0 then label, sign, r, g, delta = "Spent", "-", 1, 0.3, -delta end
        if delta == 0 then sign, r, g = "", 0.7, 0.7 end   -- no change: grey, no sign
        tt:AddDoubleLine(label, sign .. API.CoinText(delta), 1, 1, 1, r, g, r == 0.7 and 0.7 or 0.3)
        if elapsed and elapsed >= PER_HOUR_AFTER then
            local rate = math.floor(delta * 3600 / elapsed)
            if rate == 0 then sign, r, g = "", 0.7, 0.7 end
            tt:AddDoubleLine("Per hour", sign .. API.CoinText(rate), 1, 1, 1, r, g, r == 0.7 and 0.7 or 0.3)
        end
        tt:AddLine("Kept across /reload; starts again at each login.", 0.7, 0.7, 0.7, true)
        if elapsed then startTicker() else stopTicker() end
    end,
    options = {
        { label = "Reset the gold session",
          note = "The session is kept across /reload and starts again at each login.",
          run = reset },
    },
})

if block then
    block._test = { reset = reset, duration = duration, ticker = function() return ticker end }
end
