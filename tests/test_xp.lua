-- XP+ (#3): bar layers, session math, /played, capped and secret handling.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function xpBlock() return block("xp") end
local function T() return xpBlock()._test end
local function tooltipLines()
    local b = xpBlock()
    b.widget._scripts.OnEnter(b.widget)
    return GameTooltip._lines
end
local function tooltipHas(pattern)
    for _, l in ipairs(tooltipLines()) do if l:find(pattern, 1, true) then return l end end
    return nil
end
local function chatFrame(i)
    local f = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i, UIParent)
    f:RegisterEvent("TIME_PLAYED_MSG")
    return f
end
local function blizzardXPBar()
    return CreateFrame("Frame", "MainStatusTrackingBarContainer", UIParent)
end

-- The bar: four layers, texts. Blizzard's XP bar is left alone (#9).
WoW.player.rested = 3000
WoW.quests = {
    { questID = 1, isHeader = true },
    { questID = 10, xp = 2000, complete = true },
    { questID = 11, xp = 1500 },
}
local chat1, bxp
loadAddon({ before = function() chat1 = chatFrame(1); bxp = blizzardXPBar() end })
local b = xpBlock()
check(b.widget._shown, "xp block shown")
eq(b.widget._width, 360, "fixed width")
local l = b.widget._points[1]
eq(l[1], "LEFT", "xp on the left lane")
local ui = {}
for _, w in ipairs(WoW.frames) do
    if w._type == "StatusBar" then ui[#ui + 1] = w end
end
eq(#ui, 4, "four bar layers")
local values = {}
for _, bar in ipairs(ui) do values[#values + 1] = bar._value end
table.sort(values)
eq(values[1], 12000, "xp layer = current")
eq(values[2], 14000, "completed-quest layer = current + completed")
eq(values[3], 15000, "rested layer = current + rested")
eq(values[4], 15500, "incomplete-quest layer = current + all quest XP")
eq(bxp._shown, true, "Blizzard XP bar (an Edit Mode system frame) never touched")
GlassPanel._test.slash("hide xp")
GlassPanel._test.slash("show xp")
eq(bxp._shown, true, "not by hiding or showing ours either")

-- /played asked for quietly: chat frames muted, then restored.
eq(WoW.playedRequests, 1, "time played requested once at login")
eq(chat1._events.TIME_PLAYED_MSG, nil, "chat frame muted during our request")
WoW.fire("TIME_PLAYED_MSG", 7200, 1800)
WoW.flushTimers(0)
eq(chat1._events.TIME_PLAYED_MSG, true, "chat frame unmuted right after the answer")
WoW.flushTimers()
WoW.fire("PLAYER_ENTERING_WORLD", false, false)
eq(WoW.playedRequests, 1, "not re-requested on a zone change")

-- Tooltip.
WoW.now = WoW.now + 600
check(tooltipHas("Time played\t2h 10m"), "time played ticks on from the answer")
check(tooltipHas("This level\t40m"), "time this level")
check(tooltipHas("Current\t12,000 / 45,000 (26.7%)"), "current xp line")
check(tooltipHas("Rested\t3,000"), "rested line")
check(tooltipHas("Completed\t2,000"), "completed quest xp")
check(tooltipHas("Incomplete\t1,500"), "incomplete quest xp")
check(tooltipHas("XP/hr (this level)\t18,000"), "xp/hr this level: 12000 over 40 min")
check(tooltipHas("XP/hr (this session)\t--"), "no session rate before any gain")

-- Session math: gains, and a level crossed in either event order.
WoW.player.xp = 13000
WoW.fire("PLAYER_XP_UPDATE", "player")
eq(T().S.sessionXP, 1000, "gain counted")
eq(T().S.lastGain, 1000, "last gain")
-- XP_UPDATE arrives after the level-up, already wrapped: 45000 - 13000 + 500.
WoW.player.xp, WoW.player.maxXP, WoW.player.level = 500, 50000, 24
WoW.fire("PLAYER_LEVEL_UP", 24)
WoW.fire("PLAYER_XP_UPDATE", "player")
eq(T().S.sessionXP, 1000 + 32500, "wrap-around counted across the level")
check(tooltipHas("This level\t0s") or tooltipHas("This level\t--") , "level time restarts at level-up")
WoW.tick()
check(tooltipHas("Session XP\t33,500"), "session xp in tooltip")

-- Right-click resets the session.
b.widget._scripts.OnClick(b.widget, "RightButton")
eq(T().S.sessionXP, 0, "right-click resets the session")
b.widget._scripts.OnClick(b.widget, "LeftButton")
eq(WoW.playedRequests, 2, "left-click asks for time played")
eq(chat1._events.TIME_PLAYED_MSG, nil, "muted again for the click")
b.widget._scripts.OnClick(b.widget, "LeftButton")
eq(WoW.playedRequests, 2, "no second request while one is pending (its answer would print)")
WoW.flushTimers(10)   -- no answer: the fallback gives chat back
eq(chat1._events.TIME_PLAYED_MSG, true, "unmuted by the fallback when no answer comes")
eq(T().pending(), nil, "request no longer pending")
b.widget._scripts.OnClick(b.widget, "MiddleButton")
b.widget._scripts.OnClick(b.widget, "Button4")
eq(WoW.playedRequests, 2, "only left-click asks for time played (nothing pending here)")

-- An older request's fallback timer can't unmute a newer request.
b.widget._scripts.OnClick(b.widget, "LeftButton")                -- request A
WoW.fire("TIME_PLAYED_MSG", 7300, 100); WoW.flushTimers(0)       -- answered: A's 10 s timer still queued
local staleTimer = WoW.timers[1].fn
b.widget._scripts.OnClick(b.widget, "LeftButton")                -- request B
eq(chat1._events.TIME_PLAYED_MSG, nil, "muted for request B")
staleTimer()
eq(chat1._events.TIME_PLAYED_MSG, nil, "A's stale fallback leaves B's mute alone")
WoW.fire("TIME_PLAYED_MSG", 7300, 100); WoW.flushTimers()
eq(chat1._events.TIME_PLAYED_MSG, true, "B's answer unmutes")

-- An unsolicited /played (the user typed it) is recorded, and touches no mute.
WoW.fire("TIME_PLAYED_MSG", 9000, 200); WoW.flushTimers()
eq(T().S.played, 9000, "user's own /played recorded")

-- A level crossed with the new XP ABOVE the old: counted in full.
b.widget._scripts.OnClick(b.widget, "RightButton")
WoW.player.xp, WoW.player.maxXP, WoW.player.level = 100, 1400, 3
b.widget._scripts.OnClick(b.widget, "RightButton")
WoW.player.xp, WoW.player.maxXP, WoW.player.level = 600, 2100, 4
WoW.fire("PLAYER_XP_UPDATE", "player")
eq(T().S.sessionXP, 1900, "1300 to finish level 3 + 600 into level 4")

-- Quest scan is cached: QUEST_LOG_UPDATE only marks it stale.
WoW.quests = { { questID = 20, xp = 900, complete = true } }
WoW.fire("QUEST_LOG_UPDATE")
WoW.tick()
check(tooltipHas("Completed\t900"), "quest xp rescanned after QUEST_LOG_UPDATE")

-- Reward XP depends on the level: a level-up alone rescans.
WoW.quests = { { questID = 20, xp = 450, complete = true } }
WoW.fire("PLAYER_LEVEL_UP", 5); WoW.tick()
check(tooltipHas("Completed\t450"), "quest xp rescanned after a level-up")

-- Hidden: no painting (no quest scans); shown again: catches up.
local scans = 0
local realReward = GetQuestLogRewardXP
GetQuestLogRewardXP = function(id) scans = scans + 1; return realReward(id) end
GlassPanel._test.slash("hide xp")
WoW.quests = { { questID = 20, xp = 300, complete = true } }
WoW.fire("QUEST_LOG_UPDATE"); WoW.tick()
eq(scans, 0, "no quest scan while hidden")
GlassPanel._test.slash("show xp"); WoW.tick()
check(scans > 0, "scanned once back on screen")
local seg = {}
for _, w in ipairs(WoW.frames) do if w._type == "StatusBar" then seg[#seg + 1] = w._value end end
table.sort(seg)
eq(seg[2], WoW.player.xp + 300, "bar repainted with the new quest XP")
GetQuestLogRewardXP = realReward

check(next(GlassPanel.failures) == nil, "no failures")

-- Capped: the block hides.
WoW.player = { level = 60, maxLevel = 60, xp = 0, maxXP = 0, xpDisabled = false }
loadAddon()
eq(xpBlock().widget._shown, false, "hidden at the level cap")

-- Leveling on the fly into the cap hides it.
WoW.player = { level = 59, maxLevel = 60, xp = 100, maxXP = 1000, xpDisabled = false }
loadAddon()
eq(xpBlock().widget._shown, true, "shown below the cap")
WoW.player.level, WoW.player.maxXP = 60, 0
WoW.fire("PLAYER_LEVEL_UP", 60); WoW.fire("PLAYER_XP_UPDATE", "player"); WoW.tick()
eq(xpBlock().widget._shown, false, "hidden on reaching the cap")

-- XP disabled by the player behaves like the cap.
WoW.player = { level = 30, maxLevel = 60, xp = 100, maxXP = 1000, xpDisabled = true }
loadAddon()
eq(xpBlock().widget._shown, false, "hidden while XP gain is disabled")

-- Secret XP: hidden, nothing thrown, nothing recorded.
WoW.player = { level = 30, maxLevel = 60, xp = "secret", maxXP = 1000, xpDisabled = false }
loadAddon()
eq(xpBlock().widget._shown, false, "hidden while XP is secret")
WoW.fire("PLAYER_XP_UPDATE", "player"); WoW.tick()
check(tooltipHas("not available"), "tooltip says so")
check(next(GlassPanel.failures) == nil, "no failures while secret")

-- Durations.
local d = T().duration
eq(d(nil), "--", "unknown duration")
eq(d(45), "45s", "seconds")
eq(d(125), "2m", "minutes")
eq(d(3 * 3600 + 5 * 60), "3h 05m", "hours")
eq(d(2 * 86400 + 4 * 3600), "2d 4h", "days")
eq(d(0 / 0), "--", "NaN")
eq(d(1 / 0), "--", "infinity")

done("test_xp")
