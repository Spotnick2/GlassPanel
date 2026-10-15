-- XP+ (#3): bar layers, session math, /played, capped and secret handling.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelXP", "GlassPanelGold", "GlassPanelClock" }   -- the lanes these tests assert on

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
    return CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
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

-- The icon (#43): TitanPanelXPP's purple "XP", the bar starting after it.
do
    local x = xpBlock()
    eq(x.icon, "Interface\\Icons\\XP_Icon", "TitanPanelXPP's icon")
    eq(x.widget.icon._shown, true, "shown")
    local host = T().ui().host
    eq(host._points[1][2], x.widget.caption, "the bar starts where the text would, after the icon")
    eq(x.widget.caption._points[1][4], 4 + 14 + 4, "(after the icon)")
    GlassPanel._test.slash("icon xp off"); WoW.tick()
    eq(x.widget.icon._shown, false, "the Icon toggle works for XP+")
    eq(x.widget.caption._points[1][4], 4, "and the bar takes the space back")
    GlassPanel._test.slash("icon xp on"); WoW.tick()
end

-- Hiding Blizzard's XP bar (#9): off by default; on, while XP+ shows.
WoW.player = { level = 30, maxLevel = 60, xp = 100, maxXP = 1000, xpDisabled = false }
GlassPanelXPDB = nil
local container
loadAddon({ before = function() container = blizzardXPBar() end })
local hider = T().blizzardBar
container.Hide = function(self) self._hideCalls = (self._hideCalls or 0) + 1 end
container.SetShown = function(self) self._hideCalls = (self._hideCalls or 0) + 1 end
WoW.flushTimers()
eq(container._parent, UIParent, "off by default: Blizzard's bar left alone")
-- The option, through the options panel.
local panel = GlassPanel.Options._test.panel
panel:Hide(); panel:Show()
local opt = GlassPanel.Options._test.controls["options:xp:1"]
check(opt ~= nil, "XP+ option on the panel")
eq(opt:GetChecked(), false, "unchecked")
opt:SetChecked(true); opt._scripts.OnClick(opt)
eq(GlassPanelXPDB.hideBlizzard, true, "saved in XP+'s own SavedVariables")
eq(container._parent, UIParent, "not reparented synchronously (never inside a caller)")
WoW.flushTimers()
check(container._parent ~= UIParent and container._parent._shown == false, "reparented to a hidden frame")
eq(container._hideCalls, nil, "never Hide() (protected SetShownBase on Edit Mode systems)")
check(hider.IsHidden(), "hidden by us")
-- Blizzard (Edit Mode) reparents it: undone on a timer, not inside its call.
local layoutParent = CreateFrame("Frame", nil, UIParent)
container:SetParent(layoutParent)
eq(container._parent, layoutParent, "not undone inside Blizzard's SetParent")
WoW.flushTimers()
check(hider.IsHidden(), "re-hidden on the next frame")
-- Edit Mode: given back while it's open (to be seen and moved there), never
-- hidden while open, hidden again once it closes.
local em = CreateFrame("Frame", "EditModeManagerFrame", UIParent); em._shown = false
hider.request()   -- (in game EditModeManagerFrame exists from login; here the next check hooks it)
WoW.flushTimers()
check(hider.IsHidden(), "(hidden, Edit Mode closed)")
em:Show()
check(hider.IsHidden(), "not given back inside Edit Mode's own Show")
WoW.flushTimers()
eq(container._parent, layoutParent, "Edit Mode open: given back to its last parent")
container:SetParent(layoutParent)   -- Edit Mode moving it around
WoW.flushTimers()
eq(container._parent, layoutParent, "never hidden while Edit Mode is open")
em:Hide()
check(not hider.IsHidden(), "not hidden inside Edit Mode's own Hide")
WoW.flushTimers()
check(hider.IsHidden(), "hidden again once Edit Mode closed")
rawset(_G, "EditModeManagerFrame", nil)
-- An Edit Mode layout change re-checks (a move the SetParent hook didn't see).
container._parent = layoutParent
WoW.fire("EDIT_MODE_LAYOUTS_UPDATED"); WoW.flushTimers()
check(hider.IsHidden(), "re-hidden after a layout change")
-- A frame this client doesn't have: recorded, nothing thrown.
local ghost = GlassPanel.API.SystemHider("NoSuchBlizzardFrame")
ghost.Set(true); WoW.flushTimers()
check(GlassPanel.failures["hide NoSuchBlizzardFrame"] ~= nil, "missing frame recorded")
GlassPanel.failures["hide NoSuchBlizzardFrame"] = nil
-- Protected in combat: waits for combat to end.
container._protected = true
container:SetParent(layoutParent)
WoW.combat = true
WoW.flushTimers()
eq(container._parent, layoutParent, "protected in combat: waits")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED"); WoW.flushTimers()
check(hider.IsHidden(), "done after combat")
container._protected = false
-- Level cap: XP+ goes, Blizzard gets its bar back (where it last put it).
WoW.player = { level = 60, maxLevel = 60, xp = 0, maxXP = 0, xpDisabled = false }
WoW.fire("PLAYER_LEVEL_UP", 60); WoW.tick(); WoW.flushTimers()
eq(xpBlock().widget._shown, false, "(XP+ gone at the cap)")
eq(container._parent, layoutParent, "Blizzard's bar given back, to its last parent")
-- The whole bar hidden: given back too; shown again: hidden again.
WoW.player = { level = 30, maxLevel = 60, xp = 100, maxXP = 1000, xpDisabled = false }
WoW.fire("PLAYER_XP_UPDATE", "player"); WoW.tick(); WoW.flushTimers()
check(hider.IsHidden(), "XP+ back: hidden again")
GlassPanel._test.slash("toggle"); WoW.flushTimers()
eq(container._parent, layoutParent, "bar toggled off: given back")
GlassPanel._test.slash("toggle"); WoW.tick(); WoW.flushTimers()
check(hider.IsHidden(), "bar toggled on: hidden")
-- Turned off: given back.
opt:SetChecked(false); opt._scripts.OnClick(opt); WoW.flushTimers()
eq(container._parent, layoutParent, "option off: given back")
eq(GlassPanelXPDB.hideBlizzard, nil, "off is the default: nothing stored")
-- Saved on: applied after a reload, once XP+'s SavedVariables are in.
GlassPanelXPDB = { hideBlizzard = true }
local c2
rawset(_G, "StatusTrackingBarManager", nil)
loadAddon({ before = function() c2 = blizzardXPBar() end })
WoW.flushTimers()
check(T().blizzardBar.IsHidden() and c2._parent ~= UIParent, "saved setting applied at login")
GlassPanelXPDB = nil
check(next(GlassPanel.failures) == nil, "no failures (Blizzard XP bar)")

-- Zoomed (#78): double-click XP+'s icon to zoom in or out.
do
    WoW.player = { level = 30, maxLevel = 60, xp = 12000, maxXP = 45000, rested = 3000, xpDisabled = false }
    WoW.quests = { { questID = 10, xp = 2000, complete = true } }
    GlassPanelXPDB = nil
    loadAddon()
    local x = xpBlock()
    local w = x.widget
    eq(w._width, 360, "docked: the 360 px bar")
    eq(T().float(), nil, "the zoomed bar isn't built before it's needed")
    check(w._scripts.OnDoubleClick ~= nil, "the block takes double-clicks")
    check(tooltipHas("Double-click: maximize (a bar on the screen)"), "the docked bar's tooltip: maximize")
    w._scripts.OnClick(w, "LeftButton"); w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    eq(GlassPanelXPDB.detached, true, "double-click: zoomed, and saved")
    local f = T().float()
    check(f ~= nil and f._shown, "the zoomed bar shows")
    eq(f._parent, UIParent, "on UIParent, not the panel")
    eq(w._shown, true, "the handle stays on the panel")
    eq(w._width, 4 + 14 + 4 + 4, "the panel keeps the icon alone")
    eq(T().ui().host._shown, false, "the panel's bar hidden")
    eq(f._scripts.OnDoubleClick, nil, "the zoomed bar takes no double-click: the icon is the toggle")
    local p = f._points[1]
    check(p[1] == "TOP" and p[2] == UIParent and p[4] == 0 and p[5] == -40, "default: top centre, under the panel")
    check(f._clamped and f._movable, "clamped to the screen, movable")
    eq(f._height, 14 + 18 + 14, "the outer frame holds the rows above and below")
    -- What it shows: the same snapshot as everything else.
    local s, rows = T().stats(), T().rows()
    eq(T().floatUI().center._text, "12,000 / 45,000 (33,000)", "the bar's figures")
    eq(rows.level._text, "|cffffd100Time this level:|r " .. T().duration(s.levelTime), "time this level")
    eq(rows.session._text, "|cffffd100Time this session:|r " .. T().duration(s.sessionTime), "time this session")
    eq(rows.rate._text, "-- XP/hr", "no rate yet")
    eq(rows.next._text, "|cffffd100Next level:|r --", "so no time to level")
    eq(rows.extra._text, "|cffffd100Turn-ins|r 4.4%   |cffffd100Rested|r 6.7%", "turn-ins and rested")
    -- The times tick: a 1 s ticker while it shows.
    check(T().ticker() ~= nil, "a ticker while it shows")
    WoW.player.xp = 13000
    WoW.fire("PLAYER_XP_UPDATE", "player"); WoW.now = WoW.now + 3600
    WoW.fireTickers(); WoW.tick()
    eq(rows.rate._text, "1,000 XP/hr", "repainted by the ticker: the session rate")
    eq(rows.next._text, "|cffffd100Next level:|r 1d 8h", "and the time to level from it")
    -- Tooltips: each says what works there.
    w._scripts.OnEnter(w)
    check(tooltipHas("Double-click: minimize (back into the panel)"), "the handle's tooltip: minimize")
    f._scripts.OnEnter(f)
    eq(GameTooltip._owner, f, "the zoomed bar's tooltip is its own")
    local hasShift, hasMenu, hasIcon = false, false, false
    for _, l in ipairs(GameTooltip._lines) do
        hasShift = hasShift or l == "Shift-drag: move"
        hasMenu = hasMenu or l == "Right-click: menu"
        hasIcon = hasIcon or l == "Double-click XP+'s icon on the panel to minimize"
    end
    check(hasShift and hasMenu and hasIcon, "the zoomed bar's tooltip: move, menu, minimize by the icon")
    local before = #GameTooltip._lines
    GameTooltip._lines = {}
    GlassPanel.Refresh("xp"); WoW.tick()
    eq(#GameTooltip._lines, before, "an open tooltip on it is redrawn on a repaint")
    GameTooltip:Hide()
    GlassPanel.Refresh("xp"); WoW.tick()
    eq(GameTooltip._shown, false, "a dismissed one isn't reopened")
    f._scripts.OnLeave(f)
    -- Moving: shift-drag only.
    f._scripts.OnDragStart(f)
    eq(f._moving, nil, "a plain drag doesn't move it")
    f._center = { 100, 100 }
    f._scripts.OnDragStop(f)
    eq(GlassPanelXPDB.spot, nil, "and saves nothing")
    WoW.shift = true
    f._scripts.OnDragStart(f)
    WoW.shift = false
    eq(f._moving, true, "shift-drag moves it")
    f._center = { 600.3, 700 }
    f._scripts.OnDragStop(f)
    eq(f._moving, false, "stopped")
    check(GlassPanelXPDB.spot and GlassPanelXPDB.spot.x == 100.5 and GlassPanelXPDB.spot.y == 316,
          "saved from UIParent's centre, rounded to 0.5")
    p = f._points[1]
    check(#f._points == 1 and p[1] == "CENTER" and p[4] == 100.5 and p[5] == 316, "anchored on the saved spot")
    WoW.menu = nil
    f._scripts.OnClick(f, "RightButton")
    eq(WoW.menu, nil, "the release that ends a move isn't a click")
    WoW.now = WoW.now + 1
    -- A live centre that doesn't read plainly, or out of bounds: nothing saved.
    for _, bad in ipairs({ { WoW.Secret("cx"), 700 }, { 1 / 0, 700 }, { 500 + 5000, 384 } }) do
        WoW.shift = true; f._scripts.OnDragStart(f); WoW.shift = false
        f._center = bad
        f._scripts.OnDragStop(f)
        eq(GlassPanelXPDB.spot.x, 100.5, "an unusable centre saves nothing")
        eq(f._points[1][4], 100.5, "and the bar goes back to the last good spot")
        eq(GlassPanel.failures["xp:float"], nil, "checked, never touched (a secret would throw)")
    end
    WoW.now = WoW.now + 1
    -- The menu.
    f._scripts.OnClick(f, "RightButton")
    eq(WoW.menu.owner, f, "right-click: the menu, on the zoomed bar")
    eq(#WoW.menu.buttons, 3, "three items")
    eq(WoW.menu.buttons[3].text, "Reset position", "reset position")
    WoW.menu.buttons[3].callback()
    eq(GlassPanelXPDB.spot, nil, "forgotten")
    eq(f._points[1][1], "TOP", "back at the default")
    T().S.sessionXP = 5
    WoW.menu.buttons[2].callback()
    eq(T().S.sessionXP, 0, "reset session")
    local realRefresh = GlassPanel.Refresh
    GlassPanel.Refresh = function() error("refresh broke") end
    WoW.menu.buttons[2].callback()
    GlassPanel.Refresh = realRefresh
    check(GlassPanel.failures["xp:float"] ~= nil, "a menu item that throws when chosen is recorded")
    GlassPanel.failures["xp:float"] = nil
    eq(WoW.menu.buttons[1].text, "Back to the panel", "back to the panel")
    WoW.menu.buttons[1].callback(); WoW.tick()
    eq(GlassPanelXPDB.detached, nil, "docked: nothing stored")
    eq(f._shown, false, "the zoomed bar hides")
    eq(T().ticker(), nil, "its ticker stops")
    eq(w._width, 360, "the panel's bar is back")
    eq(T().ui().host._shown, true, "(shown)")
    -- Double-click on the handle docks; on the bar zooms.
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    eq(f._shown, true, "zoomed again")
    w._scripts.OnDoubleClick(w, "RightButton"); WoW.tick()
    eq(f._shown, true, "a right double-click doesn't toggle")
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    eq(f._shown, false, "double-click on the handle: docked")
    -- Hidden mid-move: stopped, nothing saved.
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    WoW.shift = true; f._scripts.OnDragStart(f); WoW.shift = false
    f._center = { 700, 700 }
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    eq(f._moving, false, "docked mid-move: stopped")
    eq(T().moving(), false, "(and forgotten)")
    eq(GlassPanelXPDB.spot, nil, "nothing saved")
    -- The menu, without MenuUtil or broken.
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    local menu = MenuUtil.CreateContextMenu
    MenuUtil.CreateContextMenu = function() error("menu broke") end
    WoW.chat = {}
    f._scripts.OnClick(f, "RightButton")
    check(GlassPanel.failures["xp:menu"] ~= nil, "a menu that throws is recorded")
    eq(GlassPanelXPDB.detached, true, "and changes nothing")
    check(#WoW.chat == 1, "said once")
    GlassPanel.failures["xp:menu"] = nil
    MenuUtil.CreateContextMenu = nil
    f._scripts.OnClick(f, "RightButton"); WoW.tick()
    eq(GlassPanelXPDB.detached, nil, "no MenuUtil: right-click docks")
    MenuUtil.CreateContextMenu = menu
    -- Follows XP+ on screen: hidden, the panel toggled, the level cap.
    w._scripts.OnDoubleClick(w, "LeftButton"); WoW.tick()
    GlassPanel._test.slash("hide xp")
    eq(f._shown, false, "XP+ hidden: the zoomed bar too")
    eq(T().ticker(), nil, "(no ticker)")
    GlassPanel._test.slash("show xp"); WoW.tick()
    eq(f._shown, true, "back")
    check(T().ticker() ~= nil, "(ticking)")
    GlassPanel._test.slash("toggle")
    eq(f._shown, false, "the panel toggled off: hidden")
    GlassPanel._test.slash("toggle"); WoW.tick()
    eq(f._shown, true, "toggled on: back")
    -- Its icon off while zoomed: the handle shows "XP+" instead (core policy).
    GlassPanel._test.slash("icon xp off")
    eq(w.label._text, "XP+", "icon off: the handle says XP+")
    GlassPanel._test.slash("icon xp on")
    eq(w.label._text, "", "icon on: the icon alone")
    -- The options: zoomed, and reset position.
    eq(x.options[2].get(), true, "the Zoomed option reads it")
    x.options[2].set(false); WoW.tick()
    eq(f._shown, false, "the Zoomed option docks")
    x.options[2].set(true); WoW.tick()
    eq(f._shown, true, "and zooms")
    GlassPanelXPDB.spot = { x = 5, y = 6 }
    x.options[4].run()
    eq(GlassPanelXPDB.spot, nil, "Reset position")
    -- Scale (the plugin's slider): live, the spot kept in screen units.
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end
    local sc = x.options[3]
    check(sc.min == 0.5 and sc.max == 2 and sc.step == 0.05, "a slider, 0.5 to 2 in 0.05 steps")
    eq(sc.get(), 1, "scale 1 by default")
    GlassPanelXPDB.spot = { x = 100, y = 50 }
    sc.set(1.5)
    check(near(GlassPanelXPDB.scale, 1.5), "saved")
    check(near(f._scale, 1.5), "applied at once")
    p = f._points[1]
    check(p[1] == "CENTER" and near(p[4], 100 / 1.5) and near(p[5], 50 / 1.5),
          "offsets divided by the scale: the spot stays in screen units")
    WoW.shift = true; f._scripts.OnDragStart(f); WoW.shift = false
    f._center = { 400, 300 }   -- the float's own (scaled) units: 600, 450 on UIParent
    f._scripts.OnDragStop(f)
    check(near(GlassPanelXPDB.spot.x, 100) and near(GlassPanelXPDB.spot.y, 66), "a move at 1.5 saves screen units")
    WoW.now = WoW.now + 1
    sc.set(1.23); check(near(GlassPanelXPDB.scale, 1.25), "rounded to the step")
    sc.set(5); check(near(GlassPanelXPDB.scale, 2), "clamped to 2")
    sc.set(0.1); check(near(GlassPanelXPDB.scale, 0.5), "clamped to 0.5")
    sc.set(0 / 0); check(near(GlassPanelXPDB.scale, 0.5), "NaN ignored")
    sc.set(WoW.Secret("scale")); check(near(GlassPanelXPDB.scale, 0.5), "a secret ignored")
    for _, bad in ipairs({ "big", 9, 0.1, 0 / 0 }) do
        GlassPanelXPDB.scale = bad
        eq(T().floatScale(), 1, "a corrupt saved scale reads as 1: " .. tostring(bad))
    end
    GlassPanelXPDB.spot = nil
    sc.set(2)
    p = f._points[1]
    check(p[1] == "TOP" and near(p[5], -20), "the default spot at scale 2: still 40 under the top")
    sc.set(1)
    eq(GlassPanelXPDB.scale, nil, "1 is the default: nothing stored")
    eq(f._scale, 1, "back to 1")
    -- Its surfaces: LibGlass r6's clean preset when the loaded copy has it (#77).
    local _, minor = LibStub("LibGlass-1.0")
    local clean = GlassPanel.CleanGlass()
    if minor >= 6 then
        check(clean ~= nil and clean ~= GlassPanel.Glass, "r6: a clean instance of its own")
        eq(clean.STYLE.grain, 0, "(clean: no grain)")
        eq(GlassPanel.CleanGlass(), clean, "made once")
        eq(T().surfaceGlass(), clean, "the zoomed bar is built on it")
        -- (inst._bars: LibGlass's own list of the bars an instance built.)
        local function built(inst, bar)
            for _, b in ipairs(inst._bars or {}) do if b == bar then return true end end
            return false
        end
        check(built(clean, T().floatUI().host), "the zoomed bar is a clean bar")
        check(built(GlassPanel.Glass, T().ui().host) and not built(clean, T().ui().host), "the panel's stays classic")
    else
        io.write("  (LibGlass checkout older than r6: the clean path isn't tested here)\n")
    end
    -- The glass backing: off by default; on, painted like the panel.
    eq(T().back(), nil, "no backing by default")
    eq(x.options[5].label, "Glass behind the zoomed bar", "the backing option")
    x.options[5].set(true)
    local bk, bg = T().back(), T().backGlass()
    check(bk ~= nil and bk._shown, "on: a glass backing")
    eq(GlassPanelXPDB.backing, true, "saved")
    eq(bk._level, f._level, "its body under the bar")
    check(bk._level < T().floatUI().host._level, "(the bar above it)")
    check(f._clampInsets and f._clampInsets[1] == -8 and f._clampInsets[3] == 4, "clamping holds the backing too")
    if clean then eq(bg.size, "thin_small", "clean: thin rims") end
    GlassPanel._test.slash("glass smoked")
    eq(bg.tint._color[4], 0.62, "follows the panel's glass: smoked")
    local grain = (clean or GlassPanel.Glass).STYLE.grain * 0.35 / 0.45
    check(math.abs(bg.grain._alpha - grain) < 1e-9, "with its own instance's grain (none on clean)")
    GlassPanel._test.slash("glass clear")
    x.options[5].set(false)
    eq(bk._shown, false, "off: hidden")
    eq(GlassPanelXPDB.backing, nil, "off: nothing stored")
    eq(f._clampInsets[1], 0, "clamping back to the bar")
    x.options[5].set(true)
    eq(T().back(), bk, "on again: the same backing")
    eq(#GlassPanel.Bar.surfaces, 1, "handed to the panel once")
    GlassPanel.API.MatchPanelGlass(bg)
    GlassPanel.API.MatchPanelGlass("not a surface")
    eq(#GlassPanel.Bar.surfaces, 1, "a surface handed over again, or junk: still one")
    x.options[5].set(false)
    WoW.player.level, WoW.player.maxXP = 60, 0
    WoW.player.maxLevel = 60
    WoW.fire("PLAYER_LEVEL_UP", 60); WoW.fire("PLAYER_XP_UPDATE", "player"); WoW.tick()
    eq(f._shown, false, "the level cap hides it")
    check(next(GlassPanel.failures) == nil, "no failures (zoomed)")
end

-- Saved: zoomed and its spot come back; a corrupt spot falls back whole.
do
    WoW.player = { level = 30, maxLevel = 60, xp = 100, maxXP = 1000, xpDisabled = false }
    local function spotAfterLoad(spot)
        GlassPanelXPDB = { detached = true, spot = spot }
        loadAddon()
        local f = T().float()
        return f and f._shown, f and f._points[1]
    end
    local shown, p = spotAfterLoad({ x = 50, y = 60 })
    check(shown and p[1] == "CENTER" and p[4] == 50 and p[5] == 60, "zoomed and its spot kept over a reload")
    eq(xpBlock().widget._width, 4 + 14 + 4 + 4, "and the panel keeps the icon")
    for _, bad in ipairs({ { "here", "not a table" }, { { x = 50, y = "a" }, "one bad field" },
                           { { x = 50, y = 1 / 0 }, "infinite" }, { { x = 9000, y = 0 }, "out of bounds" },
                           { { x = WoW.Secret("x"), y = 3 }, "secret" } }) do
        shown, p = spotAfterLoad(bad[1])
        check(shown and p[1] == "TOP" and p[5] == -40, bad[2] .. ": the default spot, as a whole")
    end
    -- An older LibGlass loaded (r5): no clean instance, the panel's glass instead.
    GlassPanelXPDB = { detached = true, backing = true }
    loadAddon({ before = function() LibStub.minors["LibGlass-1.0"] = 5 end })
    eq(GlassPanel.CleanGlass(), nil, "r5: no clean instance")
    eq(T().surfaceGlass(), GlassPanel.Glass, "the zoomed bar on the panel's glass")
    local bg = T().backGlass()
    check(bg ~= nil and T().back()._shown, "a saved backing is built with the bar")
    eq(bg.size, "small", "the panel's rims")
    check(next(GlassPanel.failures) == nil, "r5: nothing tried, nothing recorded")
    -- Hiding Blizzard's bar still follows XP+ on screen while zoomed.
    local c
    GlassPanelXPDB = { detached = true, hideBlizzard = true }
    rawset(_G, "StatusTrackingBarManager", nil)
    loadAddon({ before = function() c = blizzardXPBar() end })
    WoW.flushTimers()
    check(T().blizzardBar.IsHidden(), "Blizzard's XP bar hidden while zoomed")
    rawset(_G, "StatusTrackingBarManager", nil)
    GlassPanelXPDB = nil
    check(next(GlassPanel.failures) == nil, "no failures (saved zoom)")
end

-- Rested (#81): the cap from Well Rested, how soon it's full, the XP buffs.
do
    WoW.player = { level = 16, maxLevel = 60, xp = 664, maxXP = 16000, rested = 6770, xpDisabled = false }
    WoW.quests = {}
    GlassPanelXPDB = nil
    WoW.wellRested, WoW.resting = 5, true
    loadAddon()
    eq(T().wellRestedRank(), 5, "Well Rested read from its Legacy node")
    check(tooltipHas("Rested\t6,770 (42.3%)"), "the pool")
    -- 5/5: 1.8 levels = 28,800; 6,770 of it.
    check(tooltipHas("Rested cap\t1.8 levels (Well Rested 5/5), 23.5%"), "the cap, from the talent")
    -- Measured: 6% of a level per 8 h at 5/5 = 960 XP per 8 h; 22,030 left = 183.6 h.
    check(tooltipHas("Full in (resting)\t7d 15h"), "how soon it's full, at the measured rate")
    WoW.resting = false
    check(tooltipHas("Full in") == nil, "not resting: no estimate")
    WoW.wellRested = 0
    check(tooltipHas("Rested cap\t1.5 levels, 28.2%"), "no ranks: Vanilla's 1.5 levels")
    WoW.wellRested = nil
    check(tooltipHas("Rested cap") == nil, "no such node on this account: no cap (unknown, not guessed)")
    WoW.wellRested = "secret"
    check(tooltipHas("Rested cap") == nil, "a secret rank: no cap")
    WoW.wellRested, WoW.resting = 5, true
    WoW.player.rested = 30000
    check(tooltipHas("Rested\tfull"), "at the cap: full")
    WoW.player.rested = 6770

    -- XP buffs by spell ID; the Camp Tent's lockout; an unknown buff by its tooltip.
    WoW.buffs = {
        { spellId = 1248406, name = "Well Fed", expirationTime = WoW.now + 900, auraInstanceID = 1 },
        { spellId = 1229741, name = "Camp Benefits", expirationTime = WoW.now + 3300, auraInstanceID = 2 },
        { spellId = 5232, name = "Mark of the Wild", expirationTime = WoW.now + 2900, auraInstanceID = 3 },
        { spellId = 4242, name = "Scroll of Wisdom", expirationTime = WoW.now + 600, auraInstanceID = 4 },
    }
    WoW.auraTips[3] = { "Mark of the Wild", "Increases armor by 88 and all attributes by 3." }
    WoW.auraTips[4] = { "Scroll of Wisdom", "Experience gained increased by 10%." }
    WoW.debuffs = { { spellId = 1229451, name = "Boosted Rest", expirationTime = WoW.now + 3120, auraInstanceID = 9 } }
    check(tooltipHas("Well Fed\t+5% XP from kills, 15m"), "Well Fed, by its spell ID (its tooltip loads lazily)")
    check(tooltipHas("Camp Benefits\trested gained from a tent, 55m"), "Camp Benefits")
    check(tooltipHas("Camp Tent\tagain in 52m"), "the Camp Tent's lockout (Boosted Rest, a debuff)")
    check(tooltipHas("Scroll of Wisdom\texperience, 10m"), "an unknown buff whose tooltip speaks of experience")
    check(tooltipHas("Mark of the Wild") == nil, "other buffs left out")
    WoW.buffs = { WoW.Secret("aura") }
    WoW.debuffs = {}
    check(tooltipHas("Current\t"), "a secret aura: the tooltip still draws")
    WoW.buffs = {}
    check(next(GlassPanel.failures) == nil, "no failures (rested)")
    WoW.wellRested, WoW.resting = nil, false
end

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
