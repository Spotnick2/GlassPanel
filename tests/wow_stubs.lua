-- wow_stubs.lua: GlassPanel's own WoW: Forever client APIs for Lua 5.1 unit tests,
-- on WowTestKit (#134). dofile("tests/wow_stubs.lua") FIRST in every test; drive it
-- via the WoW table.
--
-- The kit (tests/kit.lua, at the commit tests/kit.pin names) is the mechanics:
-- the assertions, strict globals, secrets, event names checked against the
-- pinned build, widgets that record every method called (a method the build
-- lacks on that widget type reads nil, as on the client), timers, print with
-- the stray-"|" check, hooksecurefunc, WoW.fire / WoW.tick. Its README is the
-- reference. What stays here: the client APIs this addon calls (each verified
-- in the API dump), the methods the kit's core doesn't have, and GlassPanel's
-- own test state.

dofile("tests/kit.lua")
local Methods = WoW.Methods
local secrets = WoW.secrets

--------------------------------------------------------------------------------
-- Widgets: what the kit's core doesn't model
--------------------------------------------------------------------------------

-- The template's bar, shown by default as on the client (#36).
WoW.templates.UIPanelScrollFrameTemplate = function(w) w.ScrollBar = WoW.newWidget("Slider", w) end

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
local coreSetPoint = Methods.SetPoint
function Methods.SetPoint(w, ...)
    coreSetPoint(w, ...)
    if (select(2, ...)) == UIParent then stretchAcrossUIParent(w) end
end
function Methods.GetLeft(w) return w._rect and w._rect[1] or 0 end
function Methods.GetRight(w) if w._rect then return w._rect[1] + w._rect[3] end end
function Methods.GetEffectiveScale(w) return WoW.uiScale * (w._scale or 1) end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
-- Rect: set w._rect = { left, bottom, width, height } in a test; the bar gets
-- one from its anchors (above).
function Methods.GetRect(w) if w._rect then return unpack(w._rect) end end
function Methods.GetTop(w) if w._rect then return w._rect[2] + w._rect[4] end end
function Methods.GetBottom(w) if w._rect then return w._rect[2] end end
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
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
function Methods.SetRotation(t, radians) t._rotation = radians end
function Methods.SetTextureSliceMargins(t, l, tp, r, b) t._slice = { l, tp, r, b } end
-- 6 px per visible character: enough for layout arithmetic to be checkable.
function Methods.GetStringWidth(fs)
    local t = fs._text
    if type(t) ~= "string" then error("GetStringWidth on non-string text", 2) end
    return #(t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6
end
-- ScrollFrame: the range a test sets (w._yrange).
function Methods.GetVerticalScrollRange(w) return w._yrange or 0 end
-- EditBox: focus and selection, recorded.
function Methods.SetFocus(e) e._focused = true end
function Methods.ClearFocus(e) e._focused = false end
function Methods.HighlightText(e) e._highlighted = true end
function Methods.SetMaxLetters(e, n) e._maxLetters = n end
-- GameTooltip: records its lines.
function Methods.SetOwner(tt, owner) tt._owner = owner; tt._lines = {} end
function Methods.GetOwner(tt) return tt._owner end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.AddLine(tt, text) table.insert(tt._lines, text) end
function Methods.AddDoubleLine(tt, l, r) table.insert(tt._lines, l .. "\t" .. r) end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

UIParent._width, UIParent._rect = 1000, { 0, 0, 1000, 768 }
GameTooltip = WoW.newWidget("GameTooltip", UIParent, "GameTooltip")
GameTooltip._shown = false

-- Blizzard_RaidWarning's frame (RaidWarningFrameMixin:AddMessage(text,
-- colorInfo, displayTime, messageType)) and PlaySound (global walk; the
-- SoundKitConstants id): both recorded. WoW.noRaidWarning: an older client.
RaidWarningFrame = { AddMessage = function(_, text, c)
    if WoW.noRaidWarning then error("no raid warning frame") end
    table.insert(WoW.warnings, { text = text, r = c.r, g = c.g, b = c.b })
end }
function PlaySound(id) table.insert(WoW.sounds, id); return true end

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
function GetBuildInfo() return "1.60.1", "71037", "Nov 18 2026", 16001 end
-- Only "Version" is read. A release-shaped version by default; a test sets
-- WoW.addonVersion = "dev" to run as a deployed development copy.
C_AddOns = { GetAddOnMetadata = function(name, key)
    if key == "Version" then return WoW.addonVersion end
end }
-- The cursor as GlassPanel's tests set it: WoW.cursor = { x, y } in screen
-- pixels (the kit's core reads WoW.cursorX / cursorY; the README lets a stub
-- define GetCursorPosition itself).
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

function GetMoney()
    if WoW.moneySecret then return WoW.Secret("money") end
    return WoW.money
end
C_CurrencyInfo = { GetCoinTextureString = function(copper)
    if secrets[copper] then error("formatter given a secret") end
    return string.format("%dg%ds%dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end }
function GetGameTime() return WoW.gameTime[1], WoW.gameTime[2] end
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
-- Plugin stubs, and GlassPanel's test state
--------------------------------------------------------------------------------

-- Each plugin's client APIs live in their own file, tests/stubs/<plugin>.lua,
-- so plugins developed in parallel don't all edit this one. A stub file adds
-- its globals and, for per-session state, a WoW.resetHooks entry (the kit's
-- WoW.onReset: its functions run at every WoW.reset).
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

WoW.resetHooks = WoW.onReset
do
    local n = 0
    for _, f in ipairs(WoW.list("tests/stubs", ".lua")) do dofile("tests/stubs/" .. f); n = n + 1 end
    -- The listing needs a shell: fail here, not later on a missing global.
    if n == 0 and io.open("tests/stubs/pvp.lua", "r") then
        error("tests/stubs/*.lua exist but none loaded (the folder listing failed)")
    end
end

-- GlassPanel's own state, after the plugins' (as before the kit: their resets ran first).
table.insert(WoW.onReset, function()
    WoW.warnings = {}       -- RaidWarningFrame:AddMessage calls: { text, r, g, b }
    WoW.sounds = {}         -- PlaySound ids
    WoW.noRaidWarning = false
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
    WoW.cursor = { 0, 0 }     -- screen pixels, as GetCursorPosition returns them
    WoW.uiScale = 1
    WoW.shift = false
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
end)
WoW.reset()

-- Strict globals: any read of an undefined global is an error, except the
-- addon's own globals that are legitimately nil before first assignment.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassPanel = true, GlassPanelDB = true, LibStub = true })
