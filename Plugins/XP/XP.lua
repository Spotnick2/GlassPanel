-- Plugins/XP/XP.lua: XP+, a port of the owner's TBC TitanPanelXPP (#3).
--
-- A glass XP bar on the panel with four layers, back to front: rested (the
-- host Glass.Bar's own fill), incomplete-quest XP, completed-quest XP, XP.
-- The tooltip has the leveling statistics: time played, XP/hr and time to
-- level, both for this level and for this session.
-- Zoomed (#78): a double-click on XP+'s icon (the block) turns it into a wide
-- bar on the screen, after the owner's old WeakAura, and the panel keeps the
-- icon alone; another double-click there puts it back.
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

-- This plugin's SavedVariables. Read lazily: the first read is on the first
-- repaint or layout, after they load (never while the files run).
local function db()
    local d = rawget(_G, "GlassPanelXPDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelXPDB = d
    end
    return d
end

-- Zoomed (#78): the bar on the screen, only XP+'s icon left on the panel.
local function detached() return db().detached == true end

-- Whether XP+ is on screen (onShown): the panel's block, and with it the
-- zoomed bar.
local onScreen = false

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

-- One snapshot of every figure the bar and the tooltip show, or nil when
-- XP isn't readable. One place, so the views can't disagree.
local function stats()
    local cur, max, rested = readXP()
    if not cur then return nil end
    local s = { cur = cur, max = max, rested = rested, toLevel = max - cur }
    s.qc, s.qi = questXP()
    s.total, s.levelTime = playedNow()
    s.sessionTime = S.sessionStart and (GetTime() - S.sessionStart) or nil
    s.rateSession = (s.sessionTime and s.sessionTime > 0 and S.sessionXP > 0) and S.sessionXP / s.sessionTime or nil
    s.rateLevel = (s.levelTime and s.levelTime > 0 and cur > 0) and cur / s.levelTime or nil
    return s
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local ui, panel   -- the panel's bar, and the block's widget it sits on

local function layer(host, color, level, glass)
    local sb = CreateFrame("StatusBar", nil, host)
    sb:SetAllPoints(host)
    sb:SetStatusBarTexture(glass.MEDIA .. "bar_fill")
    sb:GetStatusBarTexture():AddMaskTexture(glass.Mask(sb, "bar_mask", 8))
    sb:SetStatusBarColor(color[1], color[2], color[3], color[4])
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetFrameLevel(host:GetFrameLevel() + level)
    return sb
end

-- The four-layer glass bar with its three texts, on `parent`; the caller
-- anchors ui.host. The host glass bar is the background, gloss and edge; its
-- own fill is rested. `glass` builds the surfaces (the zoomed bar's clean
-- instance, else GlassPanel.Glass); the texts are always GlassPanel.Glass's,
-- whose font the player sets.
local function makeBar(parent, height, fontSize, glass)
    glass = glass or Glass
    local host = glass.Bar(parent, height)
    host:SetFrameLevel(parent:GetFrameLevel() + 1)
    local c = COLORS.rested
    host:SetStatusBarColor(c[1], c[2], c[3], c[4])

    local incomplete = layer(host, COLORS.incomplete, 1, glass)
    local complete = layer(host, COLORS.complete, 2, glass)
    local xp = layer(host, COLORS.xp, 3, glass)
    host.overlay:SetFrameLevel(host:GetFrameLevel() + 4)   -- gloss over every layer

    local tf = CreateFrame("Frame", nil, host)
    tf:SetAllPoints(host)
    tf:SetFrameLevel(host:GetFrameLevel() + 5)
    local left = Glass.Font(tf, fontSize, "LEFT")
    left:SetPoint("LEFT", host, "LEFT", 6, 0)
    local center = Glass.Font(tf, fontSize, "CENTER")
    center:SetPoint("CENTER", host, "CENTER", 0, 0)
    local right = Glass.Font(tf, fontSize, "RIGHT")
    right:SetPoint("RIGHT", host, "RIGHT", -6, 0)

    return { host = host, incomplete = incomplete, complete = complete, xp = xp,
             left = left, center = center, right = right }
end

local function paintBar(bar, s)
    local cur, max = s.cur, s.max
    Glass.SetBar(bar.host, max, math.min(cur + s.rested, max))
    Glass.SetBar(bar.incomplete, max, math.min(cur + s.qc + s.qi, max))
    Glass.SetBar(bar.complete, max, math.min(cur + s.qc, max))
    Glass.SetBar(bar.xp, max, cur)

    bar.left:SetText("|cffffffccLv " .. level() .. "|r")
    bar.center:SetText(num(cur) .. " / " .. num(max) .. " (" .. num(s.toLevel) .. ")")
    local right = pct(cur, max)
    if s.qc > 0 then right = right .. " |cffff9700(" .. pct(math.min(cur + s.qc, max), max) .. ")|r" end
    bar.right:SetText(right)
end

local function build(block)
    local w = block.widget
    panel = w
    ui = makeBar(w, BAR_H, FONT)
    -- After the icon (TitanPanelXPP's XP_Icon): the bar starts where the
    -- block's text would (its empty caption, which Bar moves when the icon
    -- is turned off), so it takes the icon's space back then.
    ui.host:SetPoint("LEFT", w.caption, "LEFT", -2, 0)
    ui.host:SetPoint("RIGHT", w, "RIGHT", -2, 0)
end

--------------------------------------------------------------------------------
-- Tooltip
--------------------------------------------------------------------------------

local WHITE = { 1, 1, 1 }

local function line(tt, label, value, color)
    color = color or WHITE
    tt:AddDoubleLine(label, value, 1, 0.82, 0, color[1], color[2], color[3])
end

-- The clicks that work where the mouse is: the bar on the panel, the icon
-- left on the panel while zoomed, or the zoomed bar.
local HINTS = {
    panel = { "Double-click: maximize (a bar on the screen)", "Left-click: refresh time played",
              "Right-click: reset session" },
    handle = { "Double-click: minimize (back into the panel)", "Left-click: refresh time played",
               "Right-click: reset session" },
    float = { "Shift-drag: move", "Left-click: refresh time played", "Right-click: menu",
              "Double-click XP+'s icon on the panel to minimize" },
}

-- `where`: "float" from the zoomed bar; the panel's block passes nothing.
--------------------------------------------------------------------------------
-- Rested: its cap, how soon it's full, the XP buffs (#81)
--------------------------------------------------------------------------------

-- Measured on 1.60.1.70374 (docs/FOREVER-PROBE.md, RestProbe):
-- - Well Rested is a Legacy talent (the account-wide trees): Adventure tree
--   1188, node 110301 (spell 1225478), read through C_Traits as Blizzard's
--   own Camelot micro-menu override reads a Legacy node.
-- - Resting builds 6.000% of a level per 8 h at Well Rested 5/5: Vanilla's
--   5% x 1.20, online and across a logout.
-- - XP buffs are matched by spell ID: tooltip data loads lazily (Well Fed's
--   "+5% kill XP" line was missing right after eating).
-- Not measured: the cap itself (Vanilla's 1.5 levels, +20% says the talent
-- at 5/5) and ranks 1-4 (taken as 4% a rank, the 5/5 text's 20% spread).
local WELL_RESTED_TREE, WELL_RESTED_NODE = 1188, 110301
local BASE_CAP, BASE_RATE, PER_RANK = 1.5, 0.05, 0.04   -- levels; levels per 8 h; +4% a rank
local EIGHT_HOURS = 8 * 3600
-- spellID -> what it does for XP (buffs), or what it locks (debuffs).
local XP_BUFFS = {
    [1248406] = "+5% XP from kills",           -- Well Fed (XP food)
    [1229741] = "rested gained from a tent",   -- Camp Benefits
}
local LOCKOUTS = {
    [1229451] = "Camp Tent",                   -- Boosted Rest: a tent again in 1 h
}

-- Well Rested's rank (0..5), or nil when it can't be read (no C_Traits, no
-- such node on this account, a secret).
local function wellRestedRank()
    local T = rawget(_G, "C_Traits")
    if not (T and T.GetConfigIDByTreeID and T.GetNodeInfo) then return nil end
    local ok, config = pcall(T.GetConfigIDByTreeID, WELL_RESTED_TREE)
    config = ok and plain(config) or nil
    if type(config) ~= "number" then return nil end
    local okN, info = pcall(T.GetNodeInfo, config, WELL_RESTED_NODE)
    if not okN or type(info) ~= "table" or API.IsSecret(info) then return nil end
    if plain(info.ID) ~= WELL_RESTED_NODE then return nil end   -- an unknown node comes back as ID 0
    local rank = plain(info.activeRank)
    if type(rank) ~= "number" or rank < 0 or rank > 5 then return nil end
    return rank
end

-- Seconds left on an aura, or nil (permanent, unreadable).
local function timeLeft(a)
    local e = plain(a.expirationTime)
    if type(e) ~= "number" or e <= 0 then return nil end
    return e - GetTime()
end

-- An unknown buff whose tooltip speaks of experience (lazy: may be missed).
local function speaksOfXP(a)
    local TI = rawget(_G, "C_TooltipInfo")
    local id = plain(a.auraInstanceID)
    if not (TI and TI.GetUnitBuffByAuraInstanceID and type(id) == "number") then return false end
    local ok, data = pcall(TI.GetUnitBuffByAuraInstanceID, "player", id, "HELPFUL")
    if not ok or API.IsSecret(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return false end
    for _, l in ipairs(data.lines) do
        local t = type(l) == "table" and plain(l.leftText)
        if type(t) == "string" and t:lower():find("experience", 1, true) then return true end
    end
    return false
end

-- { { name, what, left } } for the XP buffs and lockouts on the player.
-- Unreadable auras (secret, in combat) are skipped.
local function xpAuras()
    local A = rawget(_G, "C_UnitAuras")
    local out = {}
    if not (A and A.GetAuraDataByIndex) then return out end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
            local ok, a = pcall(A.GetAuraDataByIndex, "player", i, filter)
            -- Secrecy first: comparing a secret, even with nil, throws on the client
            -- (GetAuraDataByIndex is SecretWhenUnitAuraRestricted; Codex on #88).
            if not ok or API.IsSecret(a) or a == nil then break end
            if type(a) == "table" then
                local id, name = plain(a.spellId), plain(a.name)
                local what = filter == "HELPFUL" and XP_BUFFS[id] or (filter == "HARMFUL" and LOCKOUTS[id])
                if not what and filter == "HELPFUL" and speaksOfXP(a) then what = "experience" end
                if what then
                    out[#out + 1] = { name = type(name) == "string" and name or "?", what = what,
                                      lockout = filter == "HARMFUL", left = timeLeft(a) }
                end
            end
        end
    end
    return out
end

-- The rested lines: the pool, its cap (when Well Rested reads), how soon it's
-- full while resting, then the XP buffs and the Camp Tent's lockout.
local function restedLines(tt, max, rested)
    local blue = { 0.31, 0.56, 1 }
    local resting = IsResting() == true
    local rank = wellRestedRank()
    if rested > 0 then line(tt, "Rested", num(rested) .. " (" .. pct(rested, max) .. ")", blue) end
    if rank then
        local cap = BASE_CAP * (1 + PER_RANK * rank) * max
        local talent = rank > 0 and (" (Well Rested " .. rank .. "/5)") or ""
        line(tt, "Rested cap", string.format("%.1f levels", cap / max) .. talent .. ", " .. pct(rested, cap), blue)
        if resting and rested < cap then
            local perSecond = BASE_RATE * (1 + PER_RANK * rank) * max / EIGHT_HOURS
            line(tt, "Full in (resting)", duration((cap - rested) / perSecond), blue)
        elseif rested >= cap then
            line(tt, "Rested", "full", blue)
        end
    elseif resting then
        line(tt, "Resting", "yes", blue)
    end
    for _, a in ipairs(xpAuras()) do
        local left = a.left and duration(a.left) or nil
        if a.lockout then
            line(tt, a.what, left and ("again in " .. left) or "not yet", { 0.7, 0.7, 0.7 })
        else
            line(tt, a.name, a.what .. (left and (", " .. left) or ""), { 0.3, 1, 0.3 })
        end
    end
end

local function tooltip(_, tt, where)
    where = where or (detached() and "handle" or "panel")
    local s = stats()
    if not s then
        tt:AddLine("XP+")
        tt:AddLine("Experience is not available right now.", 0.7, 0.7, 0.7, true)
        return
    end
    local cur, max, rested, toLevel, qc, qi = s.cur, s.max, s.rested, s.toLevel, s.qc, s.qi
    local total, levelTime, sessionTime = s.total, s.levelTime, s.sessionTime
    local rateSession, rateLevel = s.rateSession, s.rateLevel

    tt:AddLine("XP+  |cffffffffLevel " .. level() .. "|r")
    line(tt, "Time played", duration(total))
    line(tt, "This level", duration(levelTime))
    line(tt, "This session", duration(sessionTime))
    tt:AddLine(" ")
    line(tt, "Current", num(cur) .. " / " .. num(max) .. " (" .. pct(cur, max) .. ")")
    line(tt, "Remaining", num(toLevel) .. " (" .. pct(toLevel, max) .. ")")
    local ok, err = pcall(restedLines, tt, max, rested)
    if not ok then API.Fail("xp:rested", err) end
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
    line(tt, "XP/hr (this level)", rateLevel and num(rateLevel * 3600) or "--")
    line(tt, "XP/hr (this session)", rateSession and num(rateSession * 3600) or "--")
    line(tt, "Level in (this level)", duration(rateLevel and toLevel / rateLevel))
    line(tt, "Level in (this session)", duration(rateSession and toLevel / rateSession))
    tt:AddLine(" ")
    for _, hint in ipairs(HINTS[where] or HINTS.panel) do tt:AddLine(hint, 0.3, 1, 0.3) end
end

local function resetSessionAndSay()
    resetSession()
    API.Print("XP+ session reset")
    GlassPanel.Refresh("xp")
end

--------------------------------------------------------------------------------
-- Zoomed (#78): the bar on the screen, after the owner's old WeakAura
--------------------------------------------------------------------------------

-- A plain Button on UIParent (nothing secure: it zooms, docks and moves in
-- combat), built on the first zoom. Shown while zoomed and XP+ is on screen:
-- hiding XP+, the panel, the level cap all hide it, and its handle (XP+'s
-- icon on the panel) with it. The outer frame holds the rows above and below
-- the bar, so clamping keeps them on screen. Its spot is CENTER offsets from
-- UIParent's centre (GlassUnitFrames' cast bars), in GlassPanelXPDB.spot;
-- never set (or anything wrong with it): under the panel, top centre. Its
-- scale (GlassPanelXPDB.scale, the plugin's slider) leaves the spot in screen
-- units: SetPoint offsets are in the float's own scaled units, so they are
-- divided by it, and its centre multiplied by it (GlassUnitFrames' PlaceAt).
local FLOAT_W, FLOAT_BAR_H, FLOAT_FONT = 480, 18, 12
local ROW_H, ROW_FONT = 14, 10
local SPOT_LIMIT = 4096
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2, 0.05
local GOLD = "|cffffd100"

local float, floatUI, rows, ticker
local back, backGlass       -- the glass backing (an option), built when first wanted
local BACK_PAD_X, BACK_PAD_Y = 8, 4

-- The zoomed bar's surfaces: LibGlass r6's clean preset when the loaded copy
-- has it (#77), else the panel's own glass.
local function surfaceGlass() return GlassPanel.CleanGlass() or Glass end
local moving, lastMoveStop = false, -1

-- fn under pcall, a throw recorded: these run from the client (scripts, the
-- ticker, a menu item chosen later), outside the engine's guard.
local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then API.Fail("xp:float", err) end
    end
end

-- A plain, finite number, or nil.
local function finite(v)
    v = plain(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- The saved spot, or nil for the default: never half saved, half default.
local function savedSpot()
    local s = db().spot
    if type(s) ~= "table" then return nil end
    local x, y = finite(s.x), finite(s.y)
    if not (x and y and math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT) then return nil end
    return x, y
end

-- The saved scale, or 1 when unset or out of range.
local function floatScale()
    local s = finite(db().scale)
    if not s or s < SCALE_MIN or s > SCALE_MAX then return 1 end
    return s
end

local function placeFloat()
    local scale = floatScale()
    float:SetScale(scale)
    float:ClearAllPoints()
    local x, y = savedSpot()
    if x then
        float:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
    else
        float:SetPoint("TOP", UIParent, "TOP", 0, API.FloatDefaultY(float) / scale)
    end
    API.UpdateTopEdge()
end

-- Where the frame was let go, saved when every coordinate reads plainly and
-- the offsets are in bounds; either way it's anchored on our point again (the
-- last good spot when this one isn't). The float's centre is in its own
-- scaled units: times its scale, it's in UIParent's.
local function saveSpot()
    local scale = floatScale()
    local fx, fy = float:GetCenter()
    local ux, uy = UIParent:GetCenter()
    fx, fy, ux, uy = finite(fx), finite(fy), finite(ux), finite(uy)
    if fx and fy and ux and uy then
        fx, fy = fx * scale, fy * scale
        local x, y = math.floor((fx - ux) * 2 + 0.5) / 2, math.floor((fy - uy) * 2 + 0.5) / 2
        if math.abs(x) <= SPOT_LIMIT and math.abs(y) <= SPOT_LIMIT then db().spot = { x = x, y = y } end
    end
    placeFloat()
end

local function resetSpot()
    db().spot = nil
    if float then placeFloat() end
end

-- The slider: clamped, in steps; 1 (the default) is stored as nothing. Live:
-- the bar grows or shrinks around its spot.
local function setScale(v)
    v = finite(v)
    if not v then return end
    v = math.max(SCALE_MIN, math.min(SCALE_MAX, math.floor(v / SCALE_STEP + 0.5) * SCALE_STEP))
    db().scale = (math.abs(v - 1) > 1e-6) and v or nil
    if float then placeFloat() end
end

local function stopTicker()
    if ticker then ticker:Cancel() end
    ticker = nil
end

local function showFloatTooltip(f)
    GameTooltip:SetOwner(f, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOP", f, "BOTTOM", 0, -4)
    GameTooltip:ClearLines()
    tooltip(nil, GameTooltip, "float")
    GameTooltip:Show()
end

local setDetached   -- below: the menu docks through it
local applyBacking  -- below: the float builds its backing through it

-- Role's pattern (#20): a menu that throws changes nothing, it's reported; a
-- client with no MenuUtil docks on the right-click instead.
local function openMenu(owner)
    local menu = rawget(_G, "MenuUtil")
    if not (menu and menu.CreateContextMenu) then
        setDetached(false)
        return
    end
    local ok, err = pcall(menu.CreateContextMenu, owner, function(_, root)
        root:CreateButton("Back to the panel", guarded(function() setDetached(false) end))
        root:CreateButton("Reset session", guarded(resetSessionAndSay))
        root:CreateButton("Reset position", guarded(resetSpot))
    end)
    if not ok then
        API.Fail("xp:menu", err)
        API.Print("XP+: the menu couldn't open (see /gpanel failures).")
    end
end

-- The optional glass behind the whole zoomed bar, rows included: painted like
-- the panel (Clear or Smoked, Neutral or Class colour) through
-- API.MatchPanelGlass, which repaints it whenever those change. On its own
-- frame at the float's level, so its body sits under the bar (float + 1) and
-- its rims (+ 10) around it, as the panel's blocks sit in the panel's glass.
-- Clamping grows with it.
function applyBacking()
    if not float then return end
    local on = db().backing == true
    if on and not back then
        local glass = surfaceGlass()
        back = CreateFrame("Frame", nil, float)
        back:SetPoint("TOPLEFT", float, "TOPLEFT", -BACK_PAD_X, BACK_PAD_Y)
        back:SetPoint("BOTTOMRIGHT", float, "BOTTOMRIGHT", BACK_PAD_X, -BACK_PAD_Y)
        back:SetFrameLevel(float:GetFrameLevel())
        backGlass = glass.Apply(back, "small")
        API.MatchPanelGlass(backGlass, glass ~= Glass and glass or nil)
    end
    if back then back:SetShown(on) end
    if on then
        float:SetClampRectInsets(-BACK_PAD_X, BACK_PAD_X, BACK_PAD_Y, -BACK_PAD_Y)
    else
        float:SetClampRectInsets(0, 0, 0, 0)
    end
end

local function setBacking(on)
    db().backing = on and true or nil
    applyBacking()
end

local function buildFloat()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(FLOAT_W, ROW_H + FLOAT_BAR_H + ROW_H)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:Hide()
    float = f
    -- Registered as a float (#108): its default slot is the first, a drop snaps clear of the
    -- others, and the top-edge announcement counts it (#97).
    API.RegisterFloat(f, { order = 1, placed = function() return savedSpot() ~= nil end, place = function() placeFloat() end })

    floatUI = makeBar(f, FLOAT_BAR_H, FLOAT_FONT, surfaceGlass())
    floatUI.host:SetPoint("LEFT", f, "LEFT", 0, 0)
    floatUI.host:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    -- The rows, on a layer over the bar's (its texts are at host + 5).
    local tf = CreateFrame("Frame", nil, f)
    tf:SetAllPoints(f)
    tf:SetFrameLevel(floatUI.host:GetFrameLevel() + 6)
    local host = floatUI.host
    local function row(justify, point, relPoint, x, y)
        local fs = Glass.Font(tf, ROW_FONT, justify)
        fs:SetPoint(point, host, relPoint, x, y)
        return fs
    end
    rows = {
        level   = row("LEFT", "BOTTOMLEFT", "TOPLEFT", 2, 2),
        session = row("RIGHT", "BOTTOMRIGHT", "TOPRIGHT", -2, 2),
        rate    = row("LEFT", "TOPLEFT", "BOTTOMLEFT", 2, -2),
        next    = row("CENTER", "TOP", "BOTTOM", 0, -2),
        extra   = row("RIGHT", "TOPRIGHT", "BOTTOMRIGHT", -2, -2),
    }

    f:SetScript("OnEnter", guarded(showFloatTooltip))
    f:SetScript("OnLeave", guarded(function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end))
    f:SetScript("OnDragStart", guarded(function(self)
        if not IsShiftKeyDown() then return end
        moving = true
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        self:StartMoving()
    end))
    f:SetScript("OnDragStop", guarded(function(self)
        if not moving then return end   -- a plain drag moves nothing, saves nothing
        moving = false
        lastMoveStop = GetTime()
        self:StopMovingOrSizing()
        API.SnapFloat(self)
        saveSpot()
        API.UpdateTopEdge()
    end))
    f:SetScript("OnClick", guarded(function(self, button)
        -- The release that ends a move is not a click.
        if moving or GetTime() - lastMoveStop < 0.2 then return end
        if button == "LeftButton" then
            requestPlayed()
        elseif button == "RightButton" then
            openMenu(self)
        end
    end))
    -- Hidden mid-move (docked, XP+ hidden): stopped where it was saved last.
    f:SetScript("OnHide", guarded(function(self)
        if moving then
            moving = false
            self:StopMovingOrSizing()
            placeFloat()
        end
        stopTicker()
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end))
    placeFloat()
    applyBacking()
end

-- Shown while zoomed and XP+ is on screen. The times on it tick: a 1 s
-- ticker repaints while it shows (Guild's and Warlock's pattern), the display
-- only (never /played).
local function applyFloat()
    local want = onScreen and detached()
    if want and not float then buildFloat() end
    if not float then return end
    if want and not float:IsShown() then
        float:Show()
        if not ticker then ticker = C_Timer.NewTicker(1, guarded(function() GlassPanel.Refresh("xp") end)) end
    elseif not want then
        float:Hide()   -- OnHide stops the ticker
    end
    API.PlaceFloats()   -- the others' default slots follow what is shown (#108)
end

local function paintFloat(s)
    paintBar(floatUI, s)
    local rate = s.rateSession or s.rateLevel
    rows.level:SetText(GOLD .. "Time this level:|r " .. duration(s.levelTime))
    rows.session:SetText(GOLD .. "Time this session:|r " .. duration(s.sessionTime))
    rows.rate:SetText((rate and num(rate * 3600) or "--") .. " XP/hr")
    rows.next:SetText(GOLD .. "Next level:|r " .. duration(rate and s.toLevel / rate))
    rows.extra:SetText(GOLD .. "Turn-ins|r " .. pct(s.qc, s.max) .. "   " .. GOLD .. "Rested|r " .. pct(s.rested, s.max))
end

-- Zoom or dock. The panel's width follows on the next repaint (the block's
-- width function), the lane keeping its place.
function setDetached(on)
    db().detached = on and true or nil
    local owner = GameTooltip:GetOwner()
    if owner ~= nil and (owner == float or owner == panel) then
        GameTooltip:Hide()
    end
    applyFloat()
    GlassPanel.Refresh("xp")
end

-- One snapshot for whichever view shows: the panel's bar, or the zoomed one
-- (the panel then keeps only the icon). Only while XP+ is on screen.
local function paint()
    local s = stats()
    if not s then return end
    local zoomed = detached()
    if ui then
        ui.host:SetShown(not zoomed)
        if not zoomed then paintBar(ui, s) end
    end
    if zoomed and float and float:IsShown() then
        paintFloat(s)
        -- Redrawn only while it's open on the zoomed bar (not reopened).
        if GameTooltip:GetOwner() == float and GameTooltip:IsShown() then showFloatTooltip(float) end
    end
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
-- in onShown, which runs on the first layout, after they load). While Edit
-- Mode is open the bars are given back, so they can be seen and moved.
local blizzardBar = API.SystemHider("StatusTrackingBarManager")

local function applyBlizzardBar()
    blizzardBar.Set(onScreen and db().hideBlizzard == true)
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = "xp",
    label = "XP+",
    icon = "Interface\\Icons\\XP_Icon",   -- TitanPanelXPP's purple "XP"
    order = 20,
    -- Zoomed: sized to its content, which is the icon alone (the handle).
    -- An explicit branch: `detached() and nil or WIDTH` is always WIDTH.
    width = function()
        if detached() then return nil end
        return WIDTH
    end,
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
        applyFloat()
    end,
    options = {
        { label = "Hide Blizzard's XP bar",
          note = "And the reputation bar under it, while XP+ shows; both come back at the level cap.",
          get = function() return db().hideBlizzard == true end,
          set = function(on)
              db().hideBlizzard = on or nil
              applyBlizzardBar()
          end },
        { label = "Zoomed: a bar on the screen, not on the panel",
          note = "Double-click XP+'s icon to zoom in or out. Shift-drag the zoomed bar to move it.",
          get = detached,
          set = function(on) setDetached(on) end },
        { label = "Zoomed bar's scale", min = SCALE_MIN, max = SCALE_MAX, step = SCALE_STEP,
          get = floatScale, set = setScale },
        { label = "Reset the zoomed bar's position", run = resetSpot },
        { label = "Glass behind the zoomed bar",
          note = "Painted like the panel: Clear or Smoked, Neutral or Class colour.",
          get = function() return db().backing == true end,
          set = setBacking },
    },
    onClick = function(_, button)
        if button == "RightButton" then
            resetSessionAndSay()
        elseif button == "LeftButton" then
            requestPlayed()
        end
    end,
    -- On the bar, or on the icon left while zoomed: zoom in or out.
    onDoubleClick = function(_, button)
        if button == "LeftButton" then setDetached(not detached()) end
    end,
})

if block then
    block._test = { S = S, duration = duration, pending = function() return pending end, blizzardBar = blizzardBar,
                    ui = function() return ui end, stats = stats, setDetached = setDetached,
                    float = function() return float end, rows = function() return rows end,
                    floatUI = function() return floatUI end, moving = function() return moving end,
                    setScale = setScale, floatScale = floatScale, surfaceGlass = surfaceGlass,
                    back = function() return back end, backGlass = function() return backGlass end,
                    ticker = function() return ticker end, wellRestedRank = wellRestedRank, xpAuras = xpAuras }
end
