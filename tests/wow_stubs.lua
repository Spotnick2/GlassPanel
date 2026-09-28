-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Modelled on GlassUnitFrames' stub, trimmed to what a data bar touches.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump; defining
--   something Forever lacks is how a missing API survives into a build
--   (e.g. the global GetCoinTextureString, absent on 70009).
-- - SECRETS as newproxy userdata: arithmetic, ordering, tostring, concat and
--   string.format on one throw. Lua 5.1 cannot make a truth test or == throw,
--   so those two misuses are NOT caught here (only in game / in review).
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare.
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.

WoW = {}
local DUMP = os.getenv("GLASSPANEL_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"

--------------------------------------------------------------------------------
-- Secrets
--------------------------------------------------------------------------------

local secrets = setmetatable({}, { __mode = "k" })

function WoW.Secret(label)
    local p = newproxy(true)
    local mt = getmetatable(p)
    local function boom() error("secret value touched in Lua: " .. label, 2) end
    for _, k in ipairs({ "__tostring", "__concat", "__add", "__sub", "__mul", "__div", "__mod",
                         "__pow", "__unm", "__lt", "__le", "__len", "__index", "__newindex", "__call" }) do
        mt[k] = boom
    end
    secrets[p] = label
    return p
end

function issecretvalue(v) return secrets[v] ~= nil end

-- Mark an existing value secret for issecretvalue. The client's secrets keep
-- their type (a secret string is still type "string"), which a proxy can't
-- model; use this to reach `type(x) == "string"` branches.
function WoW.MarkSecret(v, label) secrets[v] = label or "marked" end

--------------------------------------------------------------------------------
-- Known events (from the dump when present)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
WoW.dumpAvailable = false
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
        WoW.dumpAvailable = next(WoW.KNOWN_EVENTS) ~= nil
    end
    if not WoW.dumpAvailable then
        for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_XP_UPDATE", "BAG_UPDATE",
            "UPDATE_INVENTORY_DURABILITY", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
            WoW.KNOWN_EVENTS[e] = true
        end
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.money = 12345
    WoW.moneySecret = false
    WoW.gameTime = { 18, 3 }
    WoW.now = 1000
    WoW.player = { level = 23, maxLevel = 60, xp = 12000, maxXP = 45000, rested = nil, xpDisabled = false }
    WoW.quests = {}          -- { { questID, xp, complete = bool, isHeader = bool }, ... }
    WoW.playedRequests = 0
    WoW.timers = {}
    WoW.cursor = { 0, 0 }     -- screen pixels, as GetCursorPosition returns them
    WoW.uiScale = 1
    WoW.shift = false
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- shared implementations, by method name

local function record(w, name)
    WoW.methodsCalled[w._type .. ":" .. name] = true
end

local widgetMT = {
    __index = function(w, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end  -- fields read as nil
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
}

local function newWidget(wtype, parent, name)
    return setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                          _scripts = {}, _events = {},
                          _level = parent and parent._level and (parent._level + 1) or 1,
                          _width = 0, _height = 0, _name = name }, widgetMT)
end

function CreateFrame(ftype, name, parent)
    local w = newWidget(ftype, parent, name)
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    return w
end

function Methods.Show(w) w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end
function Methods.Hide(w)
    local was = w._shown
    w._shown = false
    if was and w._scripts.OnHide then w._scripts.OnHide(w) end
end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetLeft(w) return 0 end
function Methods.GetEffectiveScale(w) return WoW.uiScale end
function Methods.SetAlpha(w, a) w._alpha = a end
-- Rect: set w._rect = { left, bottom, width, height } in a test; the bar gets
-- one from the harness.
function Methods.GetRect(w) if w._rect then return unpack(w._rect) end end
function Methods.GetTop(w) if w._rect then return w._rect[2] + w._rect[4] end end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end
function Methods.GetParent(w) return w._parent end
function Methods.IsProtected(w) return w._protected == true, false end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.GetHeight(w) return w._height end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.EnableMouse(w, v) w._mouse = v end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end

function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end
function Methods.IsEventRegistered(w, e) return w._events[e] == true end

-- Regions.
function Methods.CreateTexture(w) return newWidget("Texture", w) end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w) return newWidget("FontString", w) end
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    t._gradient = { orientation, c1, c2 }
end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end

-- FontString: the client formats natively and accepts secrets. With any
-- secret argument, keep the arguments unformatted instead of calling
-- string.format (which would throw on the proxy).
function Methods.SetText(fs, text) fs._text = text end
function Methods.GetText(fs) return fs._text end
function Methods.SetFormattedText(fs, fmt, ...)
    local n = select("#", ...)
    for i = 1, n do
        if secrets[(select(i, ...))] then fs._text = { secretFormat = fmt, n = n }; return end
    end
    fs._text = string.format(fmt, ...)
end
-- 6 px per visible character: enough for layout arithmetic to be checkable.
function Methods.GetStringWidth(fs)
    local t = fs._text
    if type(t) ~= "string" then error("GetStringWidth on non-string text", 2) end
    return #(t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end

-- StatusBar.
function Methods.SetMinMaxValues(b, lo, hi, interp) b._min, b._max = lo, hi end
function Methods.SetStatusBarColor(b, r, g, bl, a) b._color = { r, g, bl, a } end
function Methods.GetValue(b) return b._value end
function Methods.SetValue(b, v) b._value = v end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

-- GameTooltip: records its lines.
function Methods.SetOwner(tt, owner) tt._owner = owner; tt._lines = {} end
function Methods.GetOwner(tt) return tt._owner end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.AddLine(tt, text) table.insert(tt._lines, text) end
function Methods.AddDoubleLine(tt, l, r) table.insert(tt._lines, l .. "\t" .. r) end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent = newWidget("Frame", nil, "UIParent")
UIParent._level = 0
UIParent._width, UIParent._rect = 1000, { 0, 0, 1000, 768 }
GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._shown = false

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetBuildInfo() return "1.60.1", "70009", "Sep 23 2026", 16001 end
function InCombatLockdown() return false end
function GetCursorPosition() return WoW.cursor[1], WoW.cursor[2] end
function IsShiftKeyDown() return WoW.shift end
-- Every frame the addon or a test created, in creation order.
function EnumerateFrames(after)
    local found = after == nil
    for _, w in ipairs(WoW.frames) do
        if found then return w end
        if w == after then found = true end
    end
    return nil
end

function hooksecurefunc(t, name, fn)
    local orig = t[name]
    rawset(t, name, function(self, ...)
        local r = orig(self, ...)
        fn(self, ...)
        return r
    end)
end

function GetMoney()
    if WoW.moneySecret then return WoW.Secret("money") end
    return WoW.money
end
C_CurrencyInfo = { GetCoinTextureString = function(copper)
    if secrets[copper] then error("formatter given a secret") end
    return string.format("%dg%ds%dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end }
function GetGameTime() return WoW.gameTime[1], WoW.gameTime[2] end
function GetTime() return WoW.now end
-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo
-- seconds (all when nil) and keeps the rest, so a fallback timer can't mask a
-- missing immediate one.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
end

-- XP. A field set to "secret" comes back as a secret value.
local function playerField(k)
    local v = WoW.player[k]
    if v == "secret" then return WoW.Secret("player." .. k) end
    return v
end
function UnitXP() return playerField("xp") end
function UnitXPMax() return playerField("maxXP") end
function GetXPExhaustion() return playerField("rested") end
function UnitLevel() return playerField("level") end
function GetMaxPlayerLevel() return WoW.player.maxLevel end
function IsXPUserDisabled() return WoW.player.xpDisabled end
function RequestTimePlayed() WoW.playedRequests = WoW.playedRequests + 1 end
function BreakUpLargeNumbers(n)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

-- Quest log: WoW.quests = { { questID = n, xp = n, complete = bool, isHeader = bool }, ... }
C_QuestLog = {
    GetNumQuestLogEntries = function() return #WoW.quests, #WoW.quests end,
    GetInfo = function(i)
        local q = WoW.quests[i]
        if not q then return nil end
        return { questID = q.questID, isHeader = q.isHeader == true, isHidden = false }
    end,
    ReadyForTurnIn = function(id)
        for _, q in ipairs(WoW.quests) do if q.questID == id then return q.complete == true end end
        return false
    end,
    IsComplete = function() return false end,
}
function GetQuestLogRewardXP(id)
    for _, q in ipairs(WoW.quests) do if q.questID == id then return q.xp or 0 end end
    return 0
end
date = os.date

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught: a
-- handler that throws fails the test.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
local allowNil = { GlassPanel = true, GlassPanelDB = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
