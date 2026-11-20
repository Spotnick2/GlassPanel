-- Plugins/Gold/Gold.lua: the player's money, and what changed this session.
--
-- GetMoney has been measured SECRET on a PvP realm (porting guide, "Secret
-- values"), so every read is tested before any arithmetic. While it is secret
-- the block says so instead of guessing, and the session baseline waits for
-- the first plain read.
--
-- The session (#161, TitanGold's session stats): the money at its start and
-- when it started, saved per character in GlassPanelGoldDB.session, so a
-- /reload keeps it. PLAYER_ENTERING_WORLD's isReloadingUi says which: a reload
-- takes the saved session back, anything else (a login, a character switch, a
-- reconnect) drops it and starts again. Unmeasured by us on Forever; Blizzard's
-- own Blizzard_CodeOfConduct reads the same arguments.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API

local PER_HOUR_AFTER = 300   -- seconds: a per-hour rate from a minute of play is noise

local session    -- { start = copper, at = server time or nil }, nil until the first plain read
local decided    -- this load's first PLAYER_ENTERING_WORLD has said login or reload

local function money() return API.Plain(GetMoney()) end
local function now()
    local t = API.Plain(GetServerTime())
    if type(t) == "number" and t == t and t > 0 and t < math.huge then return t end
end

local function db()
    local d = rawget(_G, "GlassPanelGoldDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelGoldDB = d
    end
    return d
end

local function wholeCopper(v)
    return type(v) == "number" and v >= 0 and v < math.huge and v == math.floor(v)
end

-- The saved session, checked whole; anything odd means none.
local function saved()
    local s = db().session
    if type(s) ~= "table" or not wholeCopper(s.start) then return nil end
    local at = s.at
    if not (type(at) == "number" and at > 0 and at < math.huge) then at = nil end
    return { start = s.start, at = at }
end

local function begin()
    local m = money()
    if m == nil then return end   -- secret: the next plain read starts it
    session = { start = m, at = now() }
    db().session = { start = session.start, at = session.at }
end

local function ensure()
    if decided and session == nil then begin() end
end

local function reset()
    session = nil
    db().session = nil
    begin()
    if session then
        API.Print("Gold: the session starts again now.")
    else
        API.Print("Gold: the session starts again at the next readable amount (the client is hiding your money).")
    end
    GlassPanel.Refresh("gold")
end

local function duration(s)
    s = math.floor(s)
    if s < 60 then return "under a minute" end
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

local block = GlassPanel.RegisterBlock({
    id = "gold",
    label = "Gold",
    showLabel = false,   -- the coin icons say it (no caption on the TBC bar either)
    -- No block icon: the coin text carries its own icons, and it drops zero
    -- denominations, so a leading coin icon made "37s 81c" read as 37 gold.
    order = 30,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    onEvent = function(_, event, isInitialLogin, isReloadingUi)
        if event == "PLAYER_ENTERING_WORLD" and not decided then
            decided = true
            -- Only a plain true is a reload: anything else is a new session.
            if API.Plain(isReloadingUi) == true then session = saved() end
            if session == nil then db().session = nil end   -- an earlier login's
        end
        ensure()
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
        ensure()
        if not session then return end
        local t = now()
        local elapsed = (session.at and t and t >= session.at) and (t - session.at) or nil
        tt:AddLine(" ")
        tt:AddDoubleLine("This session", elapsed and duration(elapsed) or "", 1, 0.82, 0, 0.7, 0.7, 0.7)
        tt:AddDoubleLine("Started with", API.CoinText(session.start), 1, 1, 1, 1, 1, 1)
        local delta = m - session.start
        local label, sign, r, g = "Earned", "+", 0.3, 1
        if delta < 0 then label, sign, r, g, delta = "Spent", "-", 1, 0.3, -delta end
        if delta == 0 then
            tt:AddDoubleLine("Earned", API.CoinText(0), 1, 1, 1, 0.7, 0.7, 0.7)
        else
            tt:AddDoubleLine(label, sign .. API.CoinText(delta), 1, 1, 1, r, g, 0.3)
            if elapsed and elapsed >= PER_HOUR_AFTER then
                local rate = math.floor(delta * 3600 / elapsed)
                tt:AddDoubleLine("Per hour", sign .. API.CoinText(rate), 1, 1, 1, r, g, 0.3)
            end
        end
        tt:AddLine("Kept across /reload; starts again at each login.", 0.7, 0.7, 0.7, true)
    end,
    options = {
        { label = "Reset the gold session",
          note = "The session is kept across /reload and starts again at each login.",
          run = reset },
    },
})

if block then
    block._test = { reset = reset, session = function() return session end, duration = duration }
end
