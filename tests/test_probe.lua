-- RXPProbe (#80): every command runs on the stubbed client without throwing,
-- logs to its saved table and never to chat, survives secrets and a missing
-- RestedXP. It's a ForeverProbe module: the host is loaded from its checkout
-- (harness.lua's loadForeverProbe). ForeverProbe is private, so CI has no
-- checkout and this test skips there; locally it runs.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

if not foreverProbeRoot() then
    io.write("test_probe: SKIPPED (no ForeverProbe checkout: ../ForeverProbe or $FOREVERPROBE)\n")
    os.exit(0)
end

-- What the probe reads beyond the shared stub (70338 dump: GetPlayerFacing,
-- UnitPosition, IsInInstance, IsIndoors). Facing is radians; "secret" makes it secret.
local facing = 1.0
rawset(_G, "GetPlayerFacing", function() if facing == "secret" then return WoW.Secret("facing") end return facing end)
rawset(_G, "UnitPosition", function() return 100, 200, 0, 1 end)
rawset(_G, "IsInInstance", function() return false, "none" end)
rawset(_G, "IsIndoors", function() return false end)

-- LibStub with the libraries RestedXP embeds: HereBeDragons-2.0 (position and
-- vector), LibDataBroker-1.1 (its launcher), AceEvent-3.0 (its messages).
local libs = {}
rawset(_G, "LibStub", setmetatable({}, { __call = function(_, name, silent)
    if libs[name] == nil and not silent then error("no library " .. name) end
    return libs[name]
end }))
local player = { x = 0, y = 0, instance = 0 }
libs["HereBeDragons-2.0"] = {
    GetPlayerWorldPosition = function()
        if player.x == "secret" then return WoW.Secret("x"), WoW.Secret("y"), 0 end
        return player.x, player.y, player.instance
    end,
    -- HBD's convention isn't modelled; a fixed angle and the straight distance are enough here.
    GetWorldVector = function(_, inst, x, y, tx, ty)
        return 0.5, math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2)
    end,
}
local clicks = 0
libs["LibDataBroker-1.1"] = { GetDataObjectByName = function(_, name)
    if name ~= "RXPGuides" then return nil end
    return { type = "data source", label = "RXPGuides", icon = "x",
             OnClick = function(_, button) if button == "LeftButton" then RXP.settings.ToggleActive() end end,
             OnTooltipShow = function() end }
end }
local messageHandlers = {}
libs["AceEvent-3.0"] = { Embed = function(_, t)
    function t:RegisterMessage(name, fn) messageHandlers[name] = fn end
end }

-- RestedXP, as much of it as the probe reads (field names from RXPGuides
-- v4.11.23: map.lua, SettingsPanel.lua, GuideWindow.lua).
local guideFrame = CreateFrame("Frame", "RXPFrame", UIParent)
local arrowFrame = CreateFrame("Frame", "RXPG_ARROW", UIParent)
arrowFrame.texture = arrowFrame:CreateTexture()
arrowFrame.distance, arrowFrame.orientation = 50, 0.2
local stepA = { index = 3, title = "Go to the farm", active = true }
arrowFrame.element = { wx = 30, wy = 40, instance = 0, x = 50, y = 60, zone = 1429, step = stepA }
local stepList = true
RXP = {
    game = "FOREVER",
    currentGuide = { name = "1-6 Northshire", steps = { {}, {}, {} } },
    GetGuideProgress = function() return 3, 30 end,
    arrowFrame = arrowFrame,
    activeWaypoints = { arrowFrame.element },
    settings = {
        profile = { showEnabled = true },
        ToggleActive = function()
            clicks = clicks + 1
            RXP.settings.profile.showEnabled = not RXP.settings.profile.showEnabled
            guideFrame:SetShown(RXP.settings.profile.showEnabled)
        end,
        SetStepListShown = function(_, v) stepList = v end,
        IsStepListShown = function() return stepList end,
    },
}

loadForeverProbe()
local ns = {}
assert(loadfile("Tools/RXPProbe/RXPProbe.lua"))("RXPProbe", ns)
WoW.fire("ADDON_LOADED", "RXPProbe")
local T = ns._test

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local function logHas(pattern)
    for _, line in ipairs(RXPProbeDB.log) do if line:find(pattern, 1, true) then return line end end
    return nil
end

check(type(RXPProbeDB) == "table" and type(RXPProbeDB.log) == "table", "its log is its own SavedVariables")
check(logHas("RestedXP here"), "says RestedXP is loaded")
check(logHas("listening to 5 RestedXP messages"), "listens to RestedXP's messages")

-- state
fp("rxp state")
check(logHas("RXP global: table"), "state: the RXP global")
check(logHas("RXP.settings.ToggleActive: present"), "state: the toggle is there")
check(logHas("guide \"1-6 Northshire\", 3 steps"), "state: the guide")
check(logHas("LDB RXPGuides: type=\"data source\""), "state: the launcher")
check(logHas("HereBeDragons-2.0: present"), "state: HereBeDragons")

-- arrow
fp("rxp arrow")
check(logHas("target wx=30 wy=40"), "arrow: the target's world position")
check(logHas("step #3 active=true title=\"Go to the farm\""), "arrow: its step")

-- bearing: ours = vector angle - facing, distance straight
fp("rxp bearing")
eq(T.last().ok, true, "bearing read plainly")
local o, d = T.computeBearing()
check(math.abs(o - (0.5 - 1.0)) < 1e-9, "orientation = angle - facing")
eq(d, 50, "distance")
check(logHas("RestedXP: orientation=0.2 distance=50"), "logged beside RestedXP's own")

-- secrets: never touched, said
facing = "secret"
fp("rxp bearing")
eq(T.last().ok, false, "secret facing: no bearing")
eq(T.last().why, "facing secret", "and why")
check(logHas("GetPlayerFacing(): [1]=<secret>") or logHas("<secret>"), "the secret logged as <secret>")
facing = 1.0
player.x = "secret"
fp("rxp bearing")
eq(T.last().why, "position secret", "secret position: no bearing")
player.x = 0

-- the test arrow follows RestedXP's target
fp("rxp testarrow")
local test = T.test()
check(test and test._shown, "test arrow shown")
eq(test._points[1][2], arrowFrame, "beside RestedXP's arrow")
WoW.tick(0.05)
eq(test.text._text, "probe 50 yd", "drawn from our bearing")
check(logHas("target changed: step #3"), "the first target logged")
local stepB = { index = 4, title = "Back to town", active = true }
arrowFrame.element = { wx = 0, wy = 10, instance = 0, step = stepB }
WoW.tick(0.05)
check(logHas("target changed: step #4"), "a new target logged")
eq(test.text._text, "probe 10 yd", "and followed")
WoW.tick(2.1)
check(logHas("sample ours o="), "samples logged every 2 s")
arrowFrame.element = { textOnly = true, step = stepB }
WoW.tick(0.05)
eq(test.text._text, "probe: target has no world position", "a text-only target says so")
fp("rxp testarrow off")
eq(test._shown, false, "test arrow off")

-- toggle and collapse
fp("rxp toggle")
eq(clicks, 1, "toggle: through the launcher's left-click")
eq(guideFrame._shown, false, "(the guide hid)")
check(logHas("after: guide shown=false"), "before and after logged")
fp("rxp toggle direct")
eq(clicks, 2, "toggle direct: ToggleActive")
fp("rxp collapse")
eq(stepList, false, "collapse folds the step list")
fp("rxp collapse on")
eq(stepList, true, "and unfolds it")

-- messages
messageHandlers.RXP_STEP_ACTIVATED("RXP_STEP_ACTIVATED", stepA, RXP.currentGuide)
check(logHas("message RXP_STEP_ACTIVATED #1: step #3"), "a step message logged")
messageHandlers.RXP_GUIDE_LOADED("RXP_GUIDE_LOADED", RXP.currentGuide)
check(logHas("message RXP_GUIDE_LOADED #1: table name=\"1-6 Northshire\""), "a guide message logged")

-- RestedXP gone: nothing throws, it says so
local saved = RXP
RXP = nil
fp("rxp state")
check(logHas("RXP global: nil"), "no RestedXP: said")
fp("rxp arrow")
check(logHas("arrow: RXP.arrowFrame MISSING"), "no arrow: said")
fp("rxp bearing")
eq(T.last().why, "no target", "no target: no bearing")
fp("rxp toggle")
check(logHas("LDB OnClick: ERROR"), "toggle without RestedXP: the throw is caught and logged")
RXP = saved

-- the procedure is defined; nothing went to chat
fp("steps")
eq(#WoW.chat, 0, "never writes to chat")

done("test_probe")
