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
-- The one default dump path: test_methods reads it as WoW.DUMP.
local DUMP = os.getenv("GLASSPANEL_API_DUMP") or "C:/Projects/WoW/References/Forever/api/forever-api-1.60.1.70338.md"
WoW.DUMP = DUMP

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
    -- Without the dump (CI: it is local only) no name can be judged, so every
    -- one is accepted. A hand-kept fallback list goes stale (GlassUnitFrames
    -- #64: events wired later failed to register only where the dump was missing).
    if not WoW.dumpAvailable then
        setmetatable(WoW.KNOWN_EVENTS, { __index = function() return true end })
    end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Plugin stub files (tests/stubs/*.lua) add their state resets here.
WoW.resetHooks = {}

function WoW.reset()
    for _, fn in ipairs(WoW.resetHooks) do fn() end
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = {}
    WoW.addonVersion = "v1.0.0"
    -- Other addons installed and enabled. Like the client, loadAddon skips a
    -- plugin whose ## Dependencies names one that isn't (a bridge plugin
    -- without its addon). AltStable's stub is always there.
    WoW.installed = { AltStable = true }
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
    WoW.combat = false
    -- Equipped items: slot -> { cur, max, cost } (cost nil: tooltip has no repairCost;
    -- "secret" for cur/max/cost: comes back secret). Slots absent: no durability.
    WoW.gear = {}
    WoW.noTooltipInfo = false
    -- Bags: bag index -> { slots, free, family, name } (family 0: normal;
    -- "secret" for free/family: comes back secret).
    WoW.bags = { [0] = { slots = 16, free = 4, family = 0 } }
    WoW.bagToggles = 0
    -- Units by token: { guid, isPlayer } (guid "secret": comes back secret;
    -- a token absent: no unit). The player's map, realm and server time.
    WoW.units = {}
    WoW.map = 1429
    WoW.realm = "Doomhowl"
    WoW.serverTime = 100000
    WoW.settings = {}
    WoW.cvars = { damageMeterEnabled = true }
    WoW.editMode = { presets = {}, saved = { layouts = {}, activeLayout = 1 }, calls = {} }
    WoW.damageMeterAvailable = true
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

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    if ftype == "StatusBar" then w._min, w._max, w._value = 0, 1, 0 end
    -- The template's bar, shown by default as on the client (#36).
    if template == "UIPanelScrollFrameTemplate" then w.ScrollBar = newWidget("Slider", w) end
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
-- The one layout the stub computes: a frame stretched across UIParent by a
-- TOPLEFT and a TOPRIGHT point (the bar). Its width and rect follow the x
-- offsets, and OnSizeChanged fires when the width changes, as on the client.
local function stretchAcrossUIParent(w)
    local l, r
    for _, p in ipairs(w._points) do
        if p[2] == UIParent and p[1] == "TOPLEFT" then l = p[4] or 0 end
        if p[2] == UIParent and p[1] == "TOPRIGHT" then r = p[4] or 0 end
    end
    if not (l and r) then return end
    local width, h = UIParent._width - l + r, w._height or 0
    local changed = w._width ~= width
    w._width = width
    w._rect = { l, UIParent._rect[4] - h, width, h }
    if changed and w._scripts.OnSizeChanged then w._scripts.OnSizeChanged(w, width, h) end
end
function Methods.SetPoint(w, ...)
    table.insert(w._points, { ... })
    if (select(2, ...)) == UIParent then stretchAcrossUIParent(w) end
end
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
function Methods.GetLeft(w) return w._rect and w._rect[1] or 0 end
function Methods.GetEffectiveScale(w) return WoW.uiScale end
-- Like the client (1.60.1.70374, porting guide section 3): a texture with a
-- gradient ignores SetAlpha, made before or after SetGradient. Without this a
-- test that asserts a wash's alpha passes against that bug (#83).
function Methods.SetAlpha(w, a)
    if w._gradient then return end
    w._alpha = a
end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
-- Rect: set w._rect = { left, bottom, width, height } in a test; the bar gets
-- one from the harness.
function Methods.GetRect(w) if w._rect then return unpack(w._rect) end end
function Methods.GetTop(w) if w._rect then return w._rect[2] + w._rect[4] end end
-- The centre: w._center = { x, y } (a test moving a frame sets it), else the
-- rect's middle; nil without either.
function Methods.GetCenter(w)
    if w._center then return w._center[1], w._center[2] end
    if w._rect then return w._rect[1] + w._rect[3] / 2, w._rect[2] + w._rect[4] / 2 end
end
-- Moving with the mouse: recorded (w._moving); a test sets w._center to
-- where the frame was let go.
function Methods.SetMovable(w, v) w._movable = v end
function Methods.SetClampedToScreen(w, v) w._clamped = v end
function Methods.SetClampRectInsets(w, l, r, t, b) w._clampInsets = { l, r, t, b } end
function Methods.StartMoving(w) w._moving = true end
function Methods.StopMovingOrSizing(w) w._moving = false end
function Methods.GetDebugName(w) return w._name or ("<" .. w._type .. ">") end
function Methods.IsForbidden(w) return false end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p) w._parent = p end
-- Frames made with CreateFrame whose parent is w, in creation order.
function Methods.GetChildren(w)
    local out = {}
    for _, f in ipairs(WoW.frames) do if f._parent == w then out[#out + 1] = f end end
    return unpack(out)
end
function Methods.IsProtected(w) return w._protected == true, false end
function Methods.IsMouseEnabled(w) return w._mouse == true end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.GetHeight(w) return w._height end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.EnableMouse(w, v) w._mouse = v end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
-- Secure attributes: recorded; like the client, refused in combat.
function Methods.SetAttribute(w, k, v) if not WoW.combat then w._attrs = w._attrs or {}; w._attrs[k] = v end end
function Methods.GetAttribute(w, k) return w._attrs and w._attrs[k] end

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
function Methods.CreateTexture(w, name, layer, template, sublevel)
    local t = newWidget("Texture", w)
    t._layer, t._sublevel = layer, sublevel
    return t
end
function Methods.CreateMaskTexture(w) return newWidget("MaskTexture", w) end
function Methods.CreateFontString(w) return newWidget("FontString", w) end
function Methods.CreateAnimationGroup(w) return newWidget("AnimationGroup", w) end
function Methods.CreateAnimation(ag, atype) return newWidget(atype or "Animation", ag) end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.SetRotation(t, radians) t._rotation = radians end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    t._gradient = { orientation, c1, c2 }
    t._alpha = nil   -- an alpha set before the gradient doesn't survive it either
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
-- A Slider clamps to its range and fires OnValueChanged (self, value,
-- userInput) as on the client, a refresh included; a StatusBar just stores.
function Methods.SetValue(b, v)
    if b._type == "Slider" then
        v = math.max(b._min or v, math.min(b._max or v, v))
        b._value = v
        if b._scripts.OnValueChanged then b._scripts.OnValueChanged(b, v, false) end
        return
    end
    b._value = v
end
function Methods.SetStatusBarTexture(b, file)
    b._fill = b._fill or newWidget("Texture", b)
    b._fill._file = file
    return true
end
function Methods.GetStatusBarTexture(b) return b._fill end

-- ScrollFrame: the range a test sets (w._yrange).
function Methods.GetVerticalScrollRange(w) return w._yrange or 0 end

-- Buttons: enabled state. EditBox: focus and selection, recorded.
function Methods.Enable(b) b._disabled = false end
function Methods.Disable(b) b._disabled = true end
function Methods.IsEnabled(b) return not b._disabled end
function Methods.SetFocus(e) e._focused = true end
function Methods.ClearFocus(e) e._focused = false end
function Methods.HighlightText(e) e._highlighted = true end
function Methods.SetMaxLetters(e, n) e._maxLetters = n end
-- CheckButton.
function Methods.SetChecked(cb, v) cb._checked = v and true or false end
function Methods.GetChecked(cb) return cb._checked == true end
function Methods.SetEnabled(b, v) b._disabled = not v end

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
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 },
         -- Not in the dump's enum list (70009, 70124, still absent in 70338); values from wow-ui-source (forever):
         -- Blizzard_APIDocumentationGenerated/EditModeManagerConstantsDocumentation.lua.
         DamageMeterVisibility = { Always = 0, InCombat = 1, Hidden = 2, InGroup = 3 },
         -- Edit Mode (#10), from the same generated documentation (forever branch).
         EditModeSystem = { Minimap = 2, AuraFrame = 6, DamageMeter = 23 },
         EditModeAuraFrameSystemIndices = { BuffFrame = 1, DebuffFrame = 2, ExternalDefensivesFrame = 3 },
         EditModeLayoutType = { Preset = 0, Account = 1, Character = 2, Override = 3 },
         -- Item classes (Ammo, #66), from ItemConstantsDocumentation.lua (forever).
         ItemClass = { Weapon = 2, Projectile = 6 },
         ItemWeaponSubclass = { Bows = 2, Guns = 3, Thrown = 16, Crossbow = 18, Wand = 19 },
         BagIndex = { Keyring = -2, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Edit Mode layouts (#10), shaped like the forever source: GetLayouts
-- returns SAVED layouts only, activeLayout counts the presets before them
-- (EditModeManager.lua UpdateLayoutInfo). WoW.editMode = { presets, saved =
-- { layouts, activeLayout }, calls, failSave, failActivate }.
Constants = { EditModeConsts = { EditModeMaxLayoutsPerType = 5 } }
local function deep(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deep(x) end
    return o
end
C_EditMode = {
    GetLayouts = function() return deep(WoW.editMode.saved) end,
    SaveLayouts = function(info)
        table.insert(WoW.editMode.calls, "SaveLayouts")
        if WoW.editMode.failSave then error("save refused") end
        local saved = {}
        for _, l in ipairs(info.layouts) do
            if l.layoutType ~= Enum.EditModeLayoutType.Preset then saved[#saved + 1] = deep(l) end
        end
        WoW.editMode.saved = { layouts = saved, activeLayout = info.activeLayout }
    end,
    OnLayoutAdded = function(index, activate, imported)
        table.insert(WoW.editMode.calls, "OnLayoutAdded " .. index .. " " .. tostring(activate) .. " " .. tostring(imported))
        if WoW.editMode.failActivate then error("activation refused") end
        if activate then WoW.editMode.saved.activeLayout = index end
    end,
    SetActiveLayout = function(index)
        table.insert(WoW.editMode.calls, "SetActiveLayout " .. index)
        if WoW.editMode.failActivate then error("activation refused") end
        WoW.editMode.saved.activeLayout = index
    end,
}
function CopyTable(t) return deep(t) end
EditModePresetLayoutManager = {}
function EditModePresetLayoutManager:GetCopyOfPresetLayouts() return deep(WoW.editMode.presets) end
function ReloadUI() WoW.reloads = (WoW.reloads or 0) + 1 end

-- CVars (WoW.cvars[name]: a boolean, nil when unset) and the damage meter's
-- availability.
C_CVar = { GetCVarBool = function(name) return WoW.cvars[name] end }
C_DamageMeter = { IsDamageMeterAvailable = function()
    if WoW.damageMeterAvailable then return true, "" end
    return false, "unavailable"
end }

-- Shared by several plugins, so defined here once (a plugin's own stub file
-- must not redefine these: whichever file loads first would win).
-- C_ClassColor.GetClassColor(classFile) -> a colour object with r, g, b.
local CLASS_RGB = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 },
    MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 },
}
C_ClassColor = { GetClassColor = function(classFile)
    local c = CLASS_RGB[classFile]
    return c and CreateColor(c[1], c[2], c[3], 1) or nil
end }
-- Ambiguate("Name Surname-Realm", context) -> the name without its realm.
-- Like the client: context "none" keeps the realm; the others drop it (all
-- test names are same-realm).
function Ambiguate(fullName, context)
    if context == "none" then return fullName end
    return (fullName:gsub("%-.*$", ""))
end
function GetBuildInfo() return "1.60.1", "70338", "Oct  9 2026", 16001 end
-- Only "Version" is read. A release-shaped version by default; a test sets
-- WoW.addonVersion = "dev" to run as a deployed development copy.
C_AddOns = { GetAddOnMetadata = function(name, key)
    if key == "Version" then return WoW.addonVersion end
end }
function InCombatLockdown() return WoW.combat == true end
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
function GetServerTime() return WoW.serverTime end
function GetRealmName() return WoW.realm end
function UnitGUID(unit)
    local u = WoW.units[unit]
    if not u then return nil end
    if u.guid == "secret" then return WoW.Secret("guid." .. unit) end
    return u.guid
end
function UnitIsPlayer(unit) return WoW.units[unit] ~= nil and WoW.units[unit].isPlayer == true end
C_Map = { GetBestMapForUnit = function(unit) return unit == "player" and WoW.map or nil end }
-- FrameXML's string split (not Lua's): every piece, or at most `pieces`
-- with the rest left in the last.
function strsplit(delim, str, pieces)
    local out, pos = {}, 1
    while not pieces or #out < pieces - 1 do
        local a, b = string.find(str, delim, pos, true)
        if not a then break end
        out[#out + 1] = str:sub(pos, a - 1)
        pos = b + 1
    end
    out[#out + 1] = str:sub(pos)
    return unpack(out)
end
-- FrameXML's list of frames Escape closes (a table, so not in the dump's
-- function walk; AltStable's Export.lua and SheetUI.lua insert into it on
-- Forever).
UISpecialFrames = {}

-- Retail's Settings framework (names from the dump's _G walk; signatures as
-- GlassUnitFrames and Priestly use them on Forever). WoW.settings records
-- what the addon did.
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local c = { frame = frame, name = name }
        function c:GetID() return 4242 end
        WoW.settings.canvas = c
        return c
    end,
    RegisterAddOnCategory = function(c) WoW.settings.addon = c end,
    OpenToCategory = function(id) WoW.settings.opened = id end,
}
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

-- Durability. A field set to "secret" comes back secret; tipSecret = true
-- makes the whole tooltip-data table secret.
local function gearField(slot, k)
    local g = WoW.gear[slot]
    if not g then return nil end
    if g[k] == "secret" then return WoW.Secret("gear." .. k) end
    return g[k]
end
function GetInventoryItemDurability(slot)
    if not WoW.gear[slot] then return nil end
    return gearField(slot, "cur"), gearField(slot, "max")
end
WoW.tooltipReads = 0
C_TooltipInfo = { GetInventoryItem = function(unit, slot)
    WoW.tooltipReads = WoW.tooltipReads + 1
    if WoW.noTooltipInfo then error("no tooltip data") end
    if not WoW.gear[slot] then return nil end
    if WoW.gear[slot].tipSecret then
        -- A secret keeps its type on the client: a real table, marked secret.
        local t = { repairCost = gearField(slot, "cost") }
        WoW.MarkSecret(t)
        return t
    end
    return { repairCost = gearField(slot, "cost") }
end }

-- Containers: WoW.bags[bag].
local function bagField(bag, k)
    local b = WoW.bags[bag]
    if not b then return nil end
    if b[k] == "secret" then return WoW.Secret("bag." .. k) end
    return b[k]
end
C_Container = {
    GetContainerNumSlots = function(bag)
        if not WoW.bags[bag] then return 0 end
        return bagField(bag, "slots")
    end,
    GetContainerNumFreeSlots = function(bag)
        if not WoW.bags[bag] then return 0, 0 end
        return bagField(bag, "free"), bagField(bag, "family")
    end,
    GetBagName = function(bag) local b = WoW.bags[bag]; return b and (b.name or ("Bag " .. bag)) or nil end,
}
function ToggleAllBags() WoW.bagToggles = WoW.bagToggles + 1 end

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

-- Each plugin's client APIs live in their own file, tests/stubs/<plugin>.lua,
-- so plugins developed in parallel don't all edit this one. A stub file adds
-- its globals and, for per-session state, a WoW.resetHooks entry.
-- The names in a folder, sorted: its subfolders, or its files ending in `ext`.
-- cmd's dir on Windows, find elsewhere (CI runs on Linux).
function WoW.list(dir, ext)
    local cmd
    if package.config:sub(1, 1) == "\\" then
        local win = dir:gsub("/", "\\")
        cmd = ext and ('dir /b "' .. win .. '\\*' .. ext .. '" 2>nul') or ('dir /b /ad "' .. win .. '" 2>nul')
    else
        cmd = 'find "' .. dir .. '" -mindepth 1 -maxdepth 1 '
              .. (ext and ('-type f -name "*' .. ext .. '"') or "-type d") .. " -printf '%f\\n' 2>/dev/null"
    end
    local out = {}
    local p = io.popen(cmd)
    if p then
        for name in p:lines() do
            name = name:gsub("\r", "")
            if name ~= "" then out[#out + 1] = name end
        end
        p:close()
    end
    table.sort(out)
    return out
end

do
    local n = 0
    for _, f in ipairs(WoW.list("tests/stubs", ".lua")) do dofile("tests/stubs/" .. f); n = n + 1 end
    -- The listing needs a shell: fail here, not later on a missing global.
    if n == 0 and io.open("tests/stubs/pvp.lua", "r") then
        error("tests/stubs/*.lua exist but none loaded (the folder listing failed)")
    end
end

-- Client string alias (Blizzard_SharedXMLBase/Compat.lua); LibStub's version check uses it.
strmatch = string.match

WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
local allowNil = { GlassPanel = true, GlassPanelDB = true, LibStub = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
