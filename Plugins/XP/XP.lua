-- Plugins/XP/XP.lua: XP+, a port of the owner's TBC TitanPanelXPP (#3).
--
-- A glass XP bar on the panel with four layers, back to front: rested (the
-- host Glass.Bar's own fill), incomplete-quest XP, completed-quest XP, XP.
-- The tooltip has the leveling statistics: time played, XP/hr and time to
-- level, both for this level and for this session.
--
-- Forever notes:
-- - UnitXP, UnitXPMax and GetXPExhaustion were measured plain, but secrecy is
--   per-API and situational, so every read goes through plain(). A secret
--   read hides the block rather than guessing.
-- - UnitXPMax is 0 at the level cap (0 is truthy): capped is tested first.
-- - Session XP follows the wrap-around from the previous level's max, so it
--   stays right whichever of PLAYER_XP_UPDATE / PLAYER_LEVEL_UP comes first.
-- - /played is asked for quietly by muting TIME_PLAYED_MSG on the chat frames
--   around our request, not by replacing ChatFrame_DisplayTimePlayed (that
--   would taint a Blizzard global).
-- - Kill XP parsed from CHAT_MSG_COMBAT_XP_GAIN is gone: chat text may be
--   secret here, and "last gain" from PLAYER_XP_UPDATE covers it.

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass

local WIDTH = 360
local BAR_H = 14
local FONT = 11
-- r, g, b, a: the TBC plugin's colours.
local COLORS = {
    rested     = { 0.31, 0.56, 1.00, 0.45 },
    incomplete = { 0.90, 0.80, 0.10, 0.60 },
    complete   = { 1.00, 0.59, 0.04, 0.85 },
    xp         = { 0.25, 0.60, 0.90, 0.95 },
}

-- Blizzard's XP bar is NOT hidden here: MainStatusTrackingBarContainer is an
-- Edit Mode system frame, and hiding it from addon code (in combat, inside
-- Edit Mode's own show path) risks tainting Edit Mode (#9).

-- Session and played-time state. nil means unknown, never 0.
local S = {
    sessionStart = nil, sessionXP = 0, lastXP = nil, lastMax = nil, lastGain = 0,
    played = nil, playedLevel = nil, playedAt = nil,
    questComplete = 0, questIncomplete = 0, questDirty = true,
}

local plain = API.Plain

local function capped()
    if IsXPUserDisabled() then return true end
    local level, max = plain(UnitLevel("player")), plain(GetMaxPlayerLevel())
    return level ~= nil and max ~= nil and level >= max
end

-- current, max, rested; nil when unknown (secret, capped, not loaded).
local function readXP()
    if capped() then return nil end
    local cur, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
    if cur == nil or max == nil or max <= 0 then return nil end
    local rested = plain(GetXPExhaustion()) or 0   -- nil when not rested
    return cur, max, rested
end

--------------------------------------------------------------------------------
-- Session
--------------------------------------------------------------------------------

local function resetSession()
    S.sessionStart, S.sessionXP, S.lastGain = GetTime(), 0, 0
    S.lastXP, S.lastMax = readXP()
    S.lastLevel = plain(UnitLevel("player"))
end

-- A level was crossed when the level (or the level's max XP) changed, not
-- when XP went down: 100/1400 + 1900 XP = level up at 600/2100, which is
-- more XP than before. Several levels in one gain can't be told apart (the
-- in-between maxes are unknown) and count as one.
local function onXPUpdate()
    local cur, max = readXP()
    if cur == nil then return end
    local level = plain(UnitLevel("player"))
    if S.lastXP == nil then S.lastXP, S.lastMax, S.lastLevel = cur, max, level return end
    local crossed = (level ~= nil and S.lastLevel ~= nil and level > S.lastLevel) or max ~= S.lastMax
    local delta
    if crossed then
        delta = (S.lastMax - S.lastXP) + cur
    else
        delta = cur - S.lastXP
    end
    if delta > 0 then
        S.sessionXP = S.sessionXP + delta
        S.lastGain = delta
    end
    S.lastXP, S.lastMax, S.lastLevel = cur, max, level
end

--------------------------------------------------------------------------------
-- Time played, asked for without printing to chat
--------------------------------------------------------------------------------

-- One request at a time: a second RequestTimePlayed while one is pending
-- would get its answer after chat is unmuted, and print. `pending` is the
-- current request's token, so an older request's fallback timer can't unmute
-- in the middle of a newer one.
local muted = {}
local pending

local function unmuteChat()
    for _, f in ipairs(muted) do f:RegisterEvent("TIME_PLAYED_MSG") end
    muted = {}
    pending = nil
end

local function requestPlayed()
    if pending then return end   -- the answer is on its way
    for i = 1, rawget(_G, "NUM_CHAT_WINDOWS") or 10 do
        local f = rawget(_G, "ChatFrame" .. i)
        if f and f:IsEventRegistered("TIME_PLAYED_MSG") then
            f:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = f
        end
    end
    local token = {}
    pending = token
    C_Timer.After(10, function()   -- in case the answer never comes
        if pending == token then unmuteChat() end
    end)
    RequestTimePlayed()
end

local function playedNow()
    if not S.playedAt then return nil, nil end
    local since = GetTime() - S.playedAt
    return S.played + since, S.playedLevel + since
end

--------------------------------------------------------------------------------
-- Quest XP in the log
--------------------------------------------------------------------------------

local function scanQuests()
    local complete, incomplete = 0, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local id = info.questID
            local xp = plain(GetQuestLogRewardXP(id))
            if xp and xp > 0 then
                if C_QuestLog.ReadyForTurnIn(id) or C_QuestLog.IsComplete(id) then
                    complete = complete + xp
                else
                    incomplete = incomplete + xp
                end
            end
        end
    end
    return complete, incomplete
end

-- Cached, rescanned at most once per repaint (the engine batches a burst of
-- QUEST_LOG_UPDATEs into one) and not at all while the block is hidden;
-- the tooltip reuses the last scan.
local function questXP()
    if S.questDirty then
        S.questDirty = false
        local ok, c, inc = pcall(scanQuests)
        if ok then
            S.questComplete, S.questIncomplete = c, inc
        else
            API.Fail("xp:quests", c)
        end
    end
    return S.questComplete, S.questIncomplete
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function num(n) return BreakUpLargeNumbers(math.floor(n + 0.5)) end

local function level() return tostring(plain(UnitLevel("player")) or "?") end

local function pct(a, b) return string.format("%.1f%%", a / b * 100) end

local function duration(sec)
    if sec == nil or sec ~= sec or sec <= 0 or sec == math.huge then return "--" end
    sec = math.floor(sec)
    local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return string.format("%ds", sec)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local ui

local function layer(host, color, level)
    local sb = CreateFrame("StatusBar", nil, host)
    sb:SetAllPoints(host)
    sb:SetStatusBarTexture(Glass.MEDIA .. "bar_fill")
    sb:GetStatusBarTexture():AddMaskTexture(Glass.Mask(sb, "bar_mask", 8))
    sb:SetStatusBarColor(color[1], color[2], color[3], color[4])
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetFrameLevel(host:GetFrameLevel() + level)
    return sb
end

local function build(block)
    local w = block.widget
    -- The host glass bar: background, gloss and edge; its own fill is rested.
    local host = Glass.Bar(w, BAR_H)
    host:SetPoint("LEFT", w, "LEFT", 2, 0)
    host:SetPoint("RIGHT", w, "RIGHT", -2, 0)
    host:SetFrameLevel(w:GetFrameLevel() + 1)
    local c = COLORS.rested
    host:SetStatusBarColor(c[1], c[2], c[3], c[4])

    local incomplete = layer(host, COLORS.incomplete, 1)
    local complete = layer(host, COLORS.complete, 2)
    local xp = layer(host, COLORS.xp, 3)
    host.overlay:SetFrameLevel(host:GetFrameLevel() + 4)   -- gloss over every layer

    local tf = CreateFrame("Frame", nil, host)
    tf:SetAllPoints(host)
    tf:SetFrameLevel(host:GetFrameLevel() + 5)
    local left = Glass.Font(tf, FONT, "LEFT")
    left:SetPoint("LEFT", host, "LEFT", 6, 0)
    local center = Glass.Font(tf, FONT, "CENTER")
    center:SetPoint("CENTER", host, "CENTER", 0, 0)
    local right = Glass.Font(tf, FONT, "RIGHT")
    right:SetPoint("RIGHT", host, "RIGHT", -6, 0)

    ui = { host = host, incomplete = incomplete, complete = complete, xp = xp,
           left = left, center = center, right = right }
end

local function paint()
    local cur, max, rested = readXP()
    if not (ui and cur) then return end
    local qc, qi = questXP()
    Glass.SetBar(ui.host, max, math.min(cur + rested, max))
    Glass.SetBar(ui.incomplete, max, math.min(cur + qc + qi, max))
    Glass.SetBar(ui.complete, max, math.min(cur + qc, max))
    Glass.SetBar(ui.xp, max, cur)

    ui.left:SetText("|cffffffccLv " .. level() .. "|r")
    ui.center:SetText(num(cur) .. " / " .. num(max) .. " (" .. num(max - cur) .. ")")
    local right = pct(cur, max)
    if qc > 0 then right = right .. " |cffff9700(" .. pct(math.min(cur + qc, max), max) .. ")|r" end
    ui.right:SetText(right)
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }

local function line(tt, label, value, color)
    color = color or WHITE
    tt:AddDoubleLine(label, value, 1, 0.82, 0, color[1], color[2], color[3])
end

local function tooltip(_, tt)
    local cur, max, rested = readXP()
    if not cur then
        tt:AddLine("XP+")
        tt:AddLine("Experience is not available right now.", 0.7, 0.7, 0.7, true)
        return
    end
    local now = GetTime()
    local toLevel = max - cur
    local qc, qi = questXP()
    local total, levelTime = playedNow()
    local sessionTime = S.sessionStart and (now - S.sessionStart) or nil

    tt:AddLine("XP+  |cffffffffLevel " .. level() .. "|r")
    line(tt, "Time played", duration(total))
    line(tt, "This level", duration(levelTime))
    line(tt, "This session", duration(sessionTime))
    tt:AddLine(" ")
    line(tt, "Current", num(cur) .. " / " .. num(max) .. " (" .. pct(cur, max) .. ")")
    line(tt, "Remaining", num(toLevel) .. " (" .. pct(toLevel, max) .. ")")
    if rested > 0 then line(tt, "Rested", num(rested) .. " (" .. pct(rested, max) .. ")", { 0.31, 0.56, 1 }) end
    if qc + qi > 0 then
        line(tt, "Quest XP", num(qc + qi) .. " (" .. pct(qc + qi, max) .. ")", { 0.9, 0.8, 0.1 })
        if qc > 0 then line(tt, "  Completed", num(qc) .. " (" .. pct(qc, max) .. ")", { 1, 0.59, 0.04 }) end
        if qi > 0 then line(tt, "  Incomplete", num(qi) .. " (" .. pct(qi, max) .. ")", { 0.9, 0.8, 0.1 }) end
    end
    tt:AddLine(" ")
    line(tt, "Session XP", num(S.sessionXP))
    if S.lastGain > 0 then
        line(tt, "Last gain", num(S.lastGain) .. " (" .. math.ceil(toLevel / S.lastGain) .. " to level)")
    end
    local rateSession = (sessionTime and sessionTime > 0 and S.sessionXP > 0) and S.sessionXP / sessionTime or nil
    local rateLevel = (levelTime and levelTime > 0 and cur > 0) and cur / levelTime or nil
    line(tt, "XP/hr (this level)", rateLevel and num(rateLevel * 3600) or "--")
    line(tt, "XP/hr (this session)", rateSession and num(rateSession * 3600) or "--")
    line(tt, "Level in (this level)", duration(rateLevel and toLevel / rateLevel))
    line(tt, "Level in (this session)", duration(rateSession and toLevel / rateSession))
    tt:AddLine(" ")
    tt:AddLine("Left-click: refresh time played", 0.3, 1, 0.3)
    tt:AddLine("Right-click: reset session", 0.3, 1, 0.3)
end

--------------------------------------------------------------------------------
-- Blizzard's XP bar (#9)
--------------------------------------------------------------------------------

-- Optional, off by default (TitanPanelXPP's "hide the default XP bar"):
-- hidden only while XP+ is on screen, and given back whenever it isn't (the
-- level cap, XP disabled, the block or the bar hidden). Through
-- API.SystemHider on StatusTrackingBarManager, as TitanPanelXPP did on
-- Retail: its two Edit Mode containers (XP while levelling, since Blizzard
-- ranks it first; reputation) call it through GetParent(), so hiding one
-- container under our frame broke Edit Mode (measured), and the manager goes
-- instead. A watched reputation bar hides with it while XP+ shows. The
-- setting lives in GlassPanelXPDB (this plugin's SavedVariables; first read
-- in onShown, which runs on the first layout, after they load).
local blizzardBar = API.SystemHider("StatusTrackingBarManager")
local onScreen = false

local function db()
    local d = rawget(_G, "GlassPanelXPDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelXPDB = d
    end
    return d
end

local function applyBlizzardBar()
    blizzardBar.Set(onScreen and db().hideBlizzard == true)
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = "xp",
    label = "XP+",
    order = 20,
    width = WIDTH,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
               "PLAYER_UPDATE_RESTING", "TIME_PLAYED_MSG", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
               "ENABLE_XP_GAIN", "DISABLE_XP_GAIN" },
    onEvent = function(_, event, a1, a2)
        if event == "PLAYER_ENTERING_WORLD" then
            if S.sessionStart == nil then
                resetSession()
                requestPlayed()
            end
        elseif event == "PLAYER_XP_UPDATE" then
            onXPUpdate()
        elseif event == "PLAYER_LEVEL_UP" then
            S.questDirty = true   -- reward XP depends on the player's level
            local total = playedNow()
            if total then S.played, S.playedLevel, S.playedAt = total, 0, GetTime() end
        elseif event == "TIME_PLAYED_MSG" then
            local total, lvl = plain(a1), plain(a2)
            if total and lvl then S.played, S.playedLevel, S.playedAt = total, lvl, GetTime() end
            -- Unmute only for our own request, after this event is delivered.
            if pending then
                local token = pending
                C_Timer.After(0, function() if pending == token then unmuteChat() end end)
            end
        elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" then
            S.questDirty = true
        end
    end,
    -- nil hides the block (capped, disabled, unreadable); "" shows the bar.
    text = function()
        if readXP() == nil then return nil end
        return ""
    end,
    build = build,
    paint = paint,
    tooltip = tooltip,
    onShown = function(_, visible)
        onScreen = visible
        applyBlizzardBar()
    end,
    options = {
        { label = "Hide Blizzard's XP bar",
          note = "And the reputation bar under it, while XP+ shows; both come back at the level cap.",
          get = function() return db().hideBlizzard == true end,
          set = function(on)
              db().hideBlizzard = on or nil
              applyBlizzardBar()
          end },
    },
    onClick = function(_, button)
        if button == "RightButton" then
            resetSession()
            API.Print("XP+ session reset")
            GlassPanel.Refresh("xp")
        elseif button == "LeftButton" then
            requestPlayed()
        end
    end,
})

if block then
    block._test = { S = S, duration = duration, pending = function() return pending end, blizzardBar = blizzardBar }
end
