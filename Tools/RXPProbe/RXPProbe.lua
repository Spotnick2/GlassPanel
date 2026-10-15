-- RXPProbe: the throwaway measurement addon for Glass Panel [RestedXP] (#80).
-- A ForeverProbe module (..\ForeverProbe\docs\GUIDE.md): its lines go to the
-- /fp console and RXPProbeDB.log, never to chat.
--
-- Before the bridge plugin relies on RestedXP (RXPGuides) on Forever, this
-- measures:
--   - how RestedXP is there: loaded, version, the RXP global, AceAddon,
--     the functions the plugin would call                       /fp rxp state
--   - its arrow's target (RXP.arrowFrame.element), and whether it's left
--     stale when the arrow hides                                /fp rxp arrow
--   - our own bearing to that target, the way its map.lua:123-139 does it
--     (HereBeDragons-2.0 position and vector, GetPlayerFacing): plain or
--     secret, and against RestedXP's own distance and angle     /fp rxp bearing
--   - a test arrow drawn from our bearing beside RestedXP's     /fp rxp testarrow [off]
--   - its LibDataBroker launcher, the guide toggle and the step-list
--     collapse, in and out of combat              /fp rxp ldb | toggle | collapse [on]
--   - its global AceEvent messages (RXP_STEP_ACTIVATED, ...)    logged from load
-- The guided procedure: /fp steps rxp arrow.
--
-- Every RestedXP read goes through Probe:Try or a nil check: RXP is its whole
-- addon table ("debug purposes" in its source), not a promised API.

local ADDON, NS = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("RXPProbe", { api = 1, cmd = "rxp" })

local function say(msg) Probe:Say(msg) end
local show = Probe.Show

local function secret(v)
    local f = rawget(_G, "issecretvalue")
    return f ~= nil and f(v) == true
end

-- A plain number, or nil (secret, missing, NaN, infinite).
local function num(v)
    if secret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function rxp() return rawget(_G, "RXP") end

local function lib(name)
    local ls = rawget(_G, "LibStub")
    if not ls then return nil end
    local ok, l = pcall(ls, name, true)   -- LibStub(name, silent)
    return ok and l or nil
end

local function profile()
    local R = rxp()
    return R and type(R.settings) == "table" and type(R.settings.profile) == "table" and R.settings.profile or nil
end

local function guideFrame() return rawget(_G, "RXPFrame") end

local function shownOf(f)
    if not f then return "absent" end
    local ok, v = pcall(f.IsShown, f)
    return ok and show(v) or "error"
end

local function inCombat() return show(InCombatLockdown()) end

local function launcher()
    local ldb = lib("LibDataBroker-1.1")
    if not ldb then return nil end
    local ok, obj = pcall(ldb.GetDataObjectByName, ldb, "RXPGuides")
    return ok and obj or nil
end

local function ldbState()
    local obj = launcher()
    if not obj then say("LDB RXPGuides: ABSENT") return false end
    say("LDB RXPGuides: type=" .. show(obj.type) .. " label=" .. show(obj.label) .. " icon=" .. Probe.Shape(obj.icon)
        .. " OnClick=" .. type(obj.OnClick) .. " OnTooltipShow=" .. type(obj.OnTooltipShow))
    return type(obj.OnClick) == "function"
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local CALLS = { "RXP.settings.ToggleActive", "RXP.settings.SetStepListShown", "RXP.settings.IsStepListShown",
                "RXP.GetGuideProgress", "RXP.UpdateGotoSteps", "RXP.arrowFrame", "RXP.currentGuide",
                "RXP.activeWaypoints", "RXPFrame", "RXPG_ARROW" }

local function state()
    say("-- state (combat " .. inCombat() .. ")")
    local A = rawget(_G, "C_AddOns")
    Probe:Call("GetAddOnInfo(RXPGuides)", A and A.GetAddOnInfo, "RXPGuides")
    Probe:Call("IsAddOnLoaded(RXPGuides)", A and A.IsAddOnLoaded, "RXPGuides")
    Probe:Call("Version", A and A.GetAddOnMetadata, "RXPGuides", "Version")
    -- Which TOC the client chose: RXPGuides.toc lists 16001, RXPGuides_Vanilla.toc only 11509.
    Probe:Call("Interface", A and A.GetAddOnMetadata, "RXPGuides", "Interface")
    local R = rxp()
    say("RXP global: " .. type(R))
    local ace = lib("AceAddon-3.0")
    if ace then
        local ok, a = pcall(ace.GetAddon, ace, "RXPGuides", true)
        say("AceAddon RXPGuides: " .. (not ok and "error" or a == nil and "nil" or (a == R and "the RXP global" or "another table")))
    else
        say("AceAddon-3.0: absent")
    end
    for _, lname in ipairs({ "HereBeDragons-2.0", "LibDataBroker-1.1", "AceEvent-3.0" }) do
        say(lname .. ": " .. (lib(lname) and "present" or "ABSENT"))
    end
    for _, path in ipairs(CALLS) do say(path .. ": " .. (Probe.Present(path) and "present" or "MISSING")) end
    if not R then return false end
    say("RXP.game=" .. show(R.game))
    local g = R.currentGuide
    if type(g) == "table" then
        say("guide " .. show(g.name) .. ", " .. (type(g.steps) == "table" and #g.steps or "?") .. " steps")
    else
        say("guide: none")
    end
    Probe:Call("RXP.GetGuideProgress()", R.GetGuideProgress)
    local p = profile()
    if p then
        say("profile showEnabled=" .. show(p.showEnabled) .. " hideGuideWindow=" .. show(p.hideGuideWindow)
            .. " disableArrow=" .. show(p.disableArrow) .. " frameHeight=" .. show(p.frameHeight))
    else
        say("RXP.settings.profile: MISSING")
    end
    say("RXPFrame shown=" .. shownOf(guideFrame()))
    ldbState()
    return true
end

--------------------------------------------------------------------------------
-- The arrow's target
--------------------------------------------------------------------------------

local function stepText(step)
    if type(step) ~= "table" then return show(step) end
    return "#" .. show(step.index) .. " active=" .. show(step.active) .. " title=" .. show(step.title)
        .. " arrowtext=" .. show(step.arrowtext)
end

local function arrow()
    local R = rxp()
    local af = R and R.arrowFrame
    if type(af) ~= "table" then say("arrow: RXP.arrowFrame MISSING") return false end
    say("-- arrow: shown=" .. shownOf(af) .. " hideArrow=" .. show(R.hideArrow) .. " wrongContinent="
        .. show(af.wrongContinent) .. " distance=" .. show(af.distance) .. " orientation=" .. show(af.orientation))
    local e = af.element
    if type(e) ~= "table" then say("target: " .. show(e)) return false end
    say("target wx=" .. show(e.wx) .. " wy=" .. show(e.wy) .. " instance=" .. show(e.instance) .. " x=" .. show(e.x)
        .. " y=" .. show(e.y) .. " zone=" .. show(e.zone) .. " radius=" .. show(e.radius) .. " textOnly=" .. show(e.textOnly))
    say("target title=" .. show(e.title) .. " step " .. stepText(e.step))
    local w = R.activeWaypoints
    say("activeWaypoints: " .. (type(w) == "table" and #w or show(w)))
    return true
end

--------------------------------------------------------------------------------
-- Our own bearing (RestedXP's map.lua:123-139)
--------------------------------------------------------------------------------

-- orientation (radians, relative to facing), distance (yards), or nil and why.
local function computeBearing()
    local R = rxp()
    local e = R and R.arrowFrame and R.arrowFrame.element
    if type(e) ~= "table" then return nil, nil, "no target" end
    local HBD = lib("HereBeDragons-2.0")
    if not HBD then return nil, nil, "no HereBeDragons" end
    local ok, x, y, inst = pcall(HBD.GetPlayerWorldPosition, HBD)
    if not ok then return nil, nil, "position threw" end
    if secret(x) or secret(y) or secret(inst) then return nil, nil, "position secret" end
    if not (num(x) and num(y)) then return nil, nil, "no position" end
    local tx, ty = num(e.wx), num(e.wy)
    if not (tx and ty) then return nil, nil, "target has no world position" end
    local okV, angle, dist = pcall(HBD.GetWorldVector, HBD, inst, x, y, tx, ty)
    if not okV then return nil, nil, "vector threw" end
    if secret(angle) or secret(dist) then return nil, nil, "vector secret" end
    local okF, facing = pcall(GetPlayerFacing)
    if not okF then return nil, nil, "facing threw" end
    if secret(facing) then return nil, nil, "facing secret" end
    angle, dist, facing = num(angle), num(dist), num(facing)
    if not (angle and dist) then return nil, nil, "no vector (other instance?)" end
    if not facing then return nil, nil, "no facing" end
    return angle - facing, dist
end

local last = { ok = false, why = "not read" }

local function bearing()
    say("-- bearing (combat " .. inCombat() .. ")")
    local inInst, kind = IsInInstance()
    say("IsInInstance " .. show(inInst) .. " " .. show(kind) .. ", IsIndoors " .. show(IsIndoors()))
    local HBD = lib("HereBeDragons-2.0")
    if HBD then Probe:Call("HBD:GetPlayerWorldPosition()", HBD.GetPlayerWorldPosition, HBD) end
    Probe:Call("GetPlayerFacing()", GetPlayerFacing)
    Probe:Call("UnitPosition(player)", UnitPosition, "player")
    Probe:Call("C_Map.GetBestMapForUnit(player)", C_Map.GetBestMapForUnit, "player")
    local o, d, why = computeBearing()
    last = { ok = o ~= nil, why = why or "ok" }
    local af = rxp() and rxp().arrowFrame
    say("ours: orientation=" .. show(o) .. " distance=" .. show(d) .. (why and (" (" .. why .. ")") or "")
        .. " | RestedXP: orientation=" .. show(af and af.orientation) .. " distance=" .. show(af and af.distance))
    return o, d, why
end

--------------------------------------------------------------------------------
-- A test arrow from our bearing, beside RestedXP's
--------------------------------------------------------------------------------

local test   -- the frame, made on first use
local TICK, LOG_EVERY = 0.03, 2

local function makeTest()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(32, 32)
    f:SetFrameStrata("HIGH")
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    -- RestedXP's own arrow art and crop when readable, else a stock arrow.
    local R = rxp()
    local their = R and R.arrowFrame and R.arrowFrame.texture
    local okT, file = false, nil
    if their then okT, file = pcall(their.GetTexture, their) end
    if okT and file ~= nil and not secret(file) then
        tex:SetTexture(file)
        local okC, a, b, c, d, e2, f2, g, h = pcall(their.GetTexCoord, their)
        if okC and num(a) and num(h) then tex:SetTexCoord(a, b, c, d, e2, f2, g, h) end
    else
        tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    tex:SetVertexColor(0.5, 0.85, 1)   -- tinted, to tell it from RestedXP's
    f.tex = tex
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.text:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.acc, f.logAcc = 0, 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.acc, self.logAcc = self.acc + elapsed, self.logAcc + elapsed
        if self.acc < TICK then return end
        self.acc = 0
        local R2 = rxp()
        local e = R2 and R2.arrowFrame and R2.arrowFrame.element
        if e ~= self.target then
            self.target = e
            say("target changed: step " .. stepText(type(e) == "table" and e.step or e) .. " (RestedXP arrow shown="
                .. shownOf(R2 and R2.arrowFrame) .. ")")
        end
        local o, d, why = computeBearing()
        if o then
            self.tex:SetRotation(o)
            self.text:SetText(string.format("probe %d yd", math.floor(d)))
        else
            self.text:SetText("probe: " .. why)
        end
        if self.logAcc >= LOG_EVERY then
            self.logAcc = 0
            local af = R2 and R2.arrowFrame
            say(string.format("sample ours o=%s d=%s | RestedXP o=%s d=%s shown=%s", show(o), show(d and math.floor(d)),
                show(af and af.orientation), show(af and af.distance), shownOf(af)))
        end
    end)
    return f
end

local function testArrow(on)
    if on then
        test = test or makeTest()
        test:ClearAllPoints()
        local their = rawget(_G, "RXPG_ARROW")
        if their then
            test:SetPoint("LEFT", their, "RIGHT", 40, 0)
        else
            test:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
        test:Show()
        say("test arrow on" .. (their and " (beside RestedXP's)" or " (RestedXP's arrow frame absent)"))
    elseif test then
        test:Hide()
        say("test arrow off")
    end
    return on and true or false
end

--------------------------------------------------------------------------------
-- The launcher, the toggle, the collapse
--------------------------------------------------------------------------------

-- `how`: "ldb" (its minimap button's left-click, the default) or "direct" (ToggleActive).
local function toggle(how)
    local p = profile()
    local before = shownOf(guideFrame())
    say("-- toggle via " .. how .. " (combat " .. inCombat() .. "): guide shown=" .. before
        .. " showEnabled=" .. show(p and p.showEnabled))
    if how == "direct" then
        local R = rxp()
        Probe:Try("ToggleActive", R and R.settings and R.settings.ToggleActive)
    else
        local obj = launcher()
        Probe:Try("LDB OnClick", obj and obj.OnClick, UIParent, "LeftButton")
    end
    local after = shownOf(guideFrame())
    say("after: guide shown=" .. after .. " showEnabled=" .. show(p and p.showEnabled) .. " arrow shown="
        .. shownOf(rawget(_G, "RXPG_ARROW")))
    return before, after
end

local function collapse(listShown)
    local R = rxp()
    local s = R and R.settings
    if type(s) ~= "table" then say("collapse: RXP.settings MISSING") return nil end
    say("-- step list shown=" .. show(listShown) .. " (combat " .. inCombat() .. ")")
    Probe:Try("SetStepListShown", s.SetStepListShown, s, listShown)
    local ok, v = pcall(s.IsStepListShown, s)
    local f = guideFrame()
    local okH, h = false, nil
    if f then okH, h = pcall(f.GetHeight, f) end
    say("IsStepListShown=" .. (ok and show(v) or "error") .. " RXPFrame height=" .. (okH and show(h) or "?"))
    return ok and v
end

--------------------------------------------------------------------------------
-- Messages (global AceEvent; no message exists for a new waypoint)
--------------------------------------------------------------------------------

local MESSAGES = { "RXP_STEP_ACTIVATED", "RXP_STEP_DEACTIVATED", "RXP_STEP_COMPLETE", "RXP_GUIDE_LOADED",
                   "RXP_OBJECTIVE_COMPLETE" }
local listener = {}
local counts = {}

local function listen()
    local ae = lib("AceEvent-3.0")
    if not ae then say("messages: AceEvent-3.0 absent") return false end
    local ok, err = pcall(ae.Embed, ae, listener)
    if not ok then say("messages: Embed ERROR " .. tostring(err)) return false end
    for _, m in ipairs(MESSAGES) do
        local okR, errR = pcall(listener.RegisterMessage, listener, m, function(name, a1)
            counts[name] = (counts[name] or 0) + 1
            -- a1: a step (RXP_STEP_*), an element (RXP_OBJECTIVE_COMPLETE) or a guide (RXP_GUIDE_LOADED).
            local what = type(a1) == "table" and (a1.index and ("step " .. stepText(a1)) or ("table name="
                .. show(a1.name))) or show(a1)
            say("message " .. name .. " #" .. counts[name] .. ": " .. what)
        end)
        if not okR then say("messages: RegisterMessage " .. m .. " ERROR " .. tostring(errR)) end
    end
    say("listening to " .. #MESSAGES .. " RestedXP messages")
    return true
end

--------------------------------------------------------------------------------
-- Commands and the procedure
--------------------------------------------------------------------------------

Probe:Command("state", state, "is RestedXP there, and how")
Probe:Command("arrow", arrow, "its arrow's target")
Probe:Command("bearing", bearing, "our bearing to that target, against RestedXP's")
Probe:Command("testarrow", function(args) testArrow(args ~= "off") end, "a test arrow from our maths [off]")
Probe:Command("ldb", ldbState, "its LibDataBroker launcher")
Probe:Command("toggle", function(args) toggle(args == "direct" and "direct" or "ldb") end,
    "show or hide the guide like its minimap button [direct: ToggleActive]")
Probe:Command("collapse", function(args) collapse(args == "on") end, "fold the step list [on: unfold]")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("arrow", {
    title = "RestedXP: arrow, bearing and the guide toggle",
    { text = "Out of combat and outdoors, with a RestedXP guide loaded and its arrow pointing somewhere. "
          .. "Then press Next." },
    { text = "Reading RestedXP.", auto = true, run = state,
      check = function() return rxp() ~= nil, "RXP global" end },
    { text = "Reading the arrow's target.", auto = true, run = arrow,
      check = function()
          local R = rxp()
          return R ~= nil and type(R.arrowFrame) == "table" and type(R.arrowFrame.element) == "table", "a target"
      end },
    { text = "Reading your position and facing.", button = "Read", run = bearing,
      check = function() return last.ok, last.why end },
    { text = "Showing a blue test arrow beside RestedXP's, from our own maths.", button = "Show",
      run = function() return testArrow(true) end },
    { text = "Turn on the spot, then walk a little. Do both arrows point the same way, "
          .. "with about the same distance?", ask = true },
    { text = "Play on until the guide sends you somewhere else (the arrow retargets). "
          .. "Did the blue arrow follow to the new place?", ask = true },
    { text = "Turn RestedXP's own arrow off in its options (hide the waypoint arrow), then press Read.",
      button = "Read", run = arrow },
    { text = "With RestedXP's arrow off, does the blue arrow still point and update as you move?", ask = true },
    { text = "Turn RestedXP's arrow back on. Press Toggle to show or hide the guide, like its minimap button.",
      button = "Toggle", run = function() return toggle("ldb") end },
    { text = "Did the guide window (and its arrow) hide?", ask = true },
    { text = "Press Toggle to bring it back.", button = "Toggle", run = function() return toggle("ldb") end },
    { text = "Press Fold to collapse the guide to its title bar.", button = "Fold",
      run = function() return collapse(false) end },
    { text = "Did the step list fold away, leaving the title bar?", ask = true },
    { text = "Press Unfold to open it again.", button = "Unfold", run = function() return collapse(true) end },
    { text = "Get into combat (pull a weak mob) and press Toggle while you're still in combat.",
      button = "Toggle", run = function() return toggle("ldb") end },
    { text = "Out of combat now: did any error or blocked-action warning appear? (The console logs blocked "
          .. "actions too.)", ask = true },
    { text = "Press Toggle to put the guide back the way you like it.", button = "Toggle",
      run = function() return toggle("ldb") end },
    { text = "If you can, enter a dungeon and press Read (else Skip).", button = "Read", run = bearing },
    { text = "Type /reload to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED" })
boot:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    Probe:Ready()
    local db = rawget(_G, "RXPProbeDB")
    if type(db) ~= "table" then
        db = {}
        RXPProbeDB = db
    end
    if type(db.log) ~= "table" then db.log = {} end
    Probe:UseLog(db.log, MAX_LOG)
    db.loads = (db.loads or 0) + 1
    -- OptionalDeps: RXPGuides loaded first when it's enabled.
    say("loaded (" .. db.loads .. " loads); RestedXP " .. (rxp() and "here" or "NOT loaded")
        .. ". /fp rxp for the commands, /fp steps rxp arrow for the procedure")
    if rxp() then listen() end
end)

NS._test = { Probe = Probe, computeBearing = computeBearing, last = function() return last end,
             test = function() return test end, counts = counts }
