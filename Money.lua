-- Money.lua: this character's money session (#160, #161), shared by the Gold
-- and Alts blocks. Alts replaces Gold on the bar (#50), so the session lives
-- here, in the core, and both read it.
--
-- The session is the money at its start and when it started, saved per
-- character in GlassPanelCharDB.moneySession, so a /reload keeps it. This
-- load's first PLAYER_ENTERING_WORLD says which: isReloadingUi plainly true
-- takes the saved session back (checked whole), anything else (a login, a
-- character switch, a reconnect) drops it at once and starts again. Unmeasured
-- by us; Blizzard_CodeOfConduct reads the same arguments.
--
-- GetMoney has been measured SECRET on a PvP realm (porting guide, "Secret
-- values"): the start waits for the first plain read, and no arithmetic is
-- done on a secret.
--
-- Public (additive, API_VERSION unchanged; docs/PLUGINS.md):
--   API.MoneySession() -> { start, at, now, delta, elapsed } or nil
--   API.ResetMoneySession() -> true (started now) | false (waits for a plain read)

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local Money = {}
GlassPanel.Money = Money

local session    -- { start = copper, at = server time or nil }, nil until the first plain read
local decided    -- this load's first PLAYER_ENTERING_WORLD has said login or reload

local function money()
    local m = API.Plain(GetMoney())
    if type(m) == "number" and m >= 0 and m < math.huge then return m end
end

local function now()
    local t = API.Plain(GetServerTime())
    if type(t) == "number" and t == t and t > 0 and t < math.huge then return t end
end

local function db()
    local d = rawget(_G, "GlassPanelCharDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelCharDB = d
    end
    return d
end

local function wholeCopper(v)
    return type(v) == "number" and v >= 0 and v < math.huge and v == math.floor(v)
end

-- The saved session, checked whole; anything odd means none.
local function saved()
    local s = db().moneySession
    if type(s) ~= "table" or not wholeCopper(s.start) then return nil end
    local at = s.at
    if not (type(at) == "number" and at > 0 and at < math.huge) then at = nil end
    return { start = s.start, at = at }
end

local function begin()
    local m = money()
    if m == nil then return end   -- secret: the next plain read starts it
    session = { start = m, at = now() }
    db().moneySession = { start = session.start, at = session.at }
end

local function ensure()
    if decided and session == nil then begin() end
end

local function onEvent(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" and not decided then
        decided = true
        -- Only a plain true is a reload: anything else is a new session.
        if API.Plain(isReloadingUi) == true then session = saved() end
        if session == nil then db().moneySession = nil end   -- an earlier login's
    end
    ensure()
end

local frame = CreateFrame("Frame")
API.RegisterEvent(frame, "PLAYER_ENTERING_WORLD", "money")
API.RegisterEvent(frame, "PLAYER_MONEY", "money")
frame:SetScript("OnEvent", function(...)
    local ok, err = pcall(onEvent, ...)
    if not ok then API.Fail("money:session", err) end
end)

-- The session now: { start, at, now, delta, elapsed }, a fresh table, or nil
-- while there's none (before the first plain read) or the money can't be read
-- right now. delta is now - start (negative: spent); elapsed is seconds, or
-- nil when the server time can't be read.
function API.MoneySession()
    ensure()
    local m = money()
    if not (session and m) then return nil end
    local t = now()
    local elapsed = (session.at and t and t >= session.at) and (t - session.at) or nil
    return { start = session.start, at = session.at, now = m, delta = m - session.start, elapsed = elapsed }
end

-- Start the session again now. True when it started; false when the money
-- can't be read right now (it starts at the next plain read).
function API.ResetMoneySession()
    session = nil
    db().moneySession = nil
    begin()
    return session ~= nil
end

Money._test = { state = function() return session, decided end }
