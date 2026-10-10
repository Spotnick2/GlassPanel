-- Plugins/Ammo/Ammo.lua: ammunition (#66), a block of its own as in Titan,
-- for hunters, warriors and rogues only.
--
-- The ranged slot decides the kind: a bow or crossbow shoots arrows, a gun
-- bullets, a thrown weapon is its own ammunition (the equipped stack); a wand
-- or nothing: no block. The figure is coloured yellow under the class's "low"
-- threshold and red under "critical" (settable per class, GlassPanelAmmoDB).
--
-- Forever (70338): UnitUsesAmmo(unit) is new in this build, and Blizzard's
-- paper doll shows CharacterAmmoSlot only when it's true
-- (Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:1499); it counts the slot
-- with GetInventoryItemCount("player", slot) (:2149). INVSLOT_AMMO = 0,
-- INVSLOT_RANGED = 18 (Blizzard_FrameXMLBase/Constants.lua). Item classes from
-- ItemConstantsDocumentation (Weapon 2: Bows 2, Guns 3, Thrown 16, Crossbow
-- 18; Projectile 6). The projectile subclasses have no enum: Arrow 2 and
-- Bullet 3 are the item data's values (Vanilla), unmeasured here.
--
-- UNMEASURED on the client: whether GetInventoryItemCount on the ammo slot
-- totals that ammo across the bags (Vanilla) or counts the slot alone; what
-- UnitUsesAmmo says for warriors and rogues; the thrown stack's count. When
-- the slot count can't be read, the same item is counted in the bags.
--
-- No ammo equipped, or the wrong kind for the weapon: the matching
-- projectiles in the bags are counted, with a red "!" (you can't shoot until
-- you equip them). Every number through API.Plain: unknown is a grey "?".

GlassPanel = GlassPanel or {}
local API, Glass = GlassPanel.API, GlassPanel.Glass
local P = API.Plain

local AMMO_SLOT = rawget(_G, "INVSLOT_AMMO") or 0
local RANGED_SLOT = rawget(_G, "INVSLOT_RANGED") or 18

local IC = Enum and Enum.ItemClass or {}
local WS = Enum and Enum.ItemWeaponSubclass or {}
local WEAPON, PROJECTILE = IC.Weapon or 2, IC.Projectile or 6
local ARROW, BULLET = 2, 3   -- projectile subclasses (no enum on the client)

-- The weapon subclasses that take ammo, and which.
local KIND_OF_WEAPON = {
    [WS.Bows or 2] = "arrow",
    [WS.Crossbow or 18] = "arrow",
    [WS.Guns or 3] = "bullet",
    [WS.Thrown or 16] = "thrown",
}
local KIND_OF_PROJECTILE = { [ARROW] = "arrow", [BULLET] = "bullet" }
local KIND_NAME = { arrow = "Arrows", bullet = "Bullets", thrown = "Thrown" }
local KIND_ICON = { arrow = "Interface\\Icons\\INV_Ammo_Arrow_02", bullet = "Interface\\Icons\\INV_Ammo_Bullet_02" }

-- Who carries ammo, and when the figure turns yellow (low) and red (critical).
local DEFAULTS = {
    HUNTER = { low = 600, critical = 200 },
    WARRIOR = { low = 100, critical = 40 },
    ROGUE = { low = 100, critical = 40 },
}
local CLASS_NAME = { HUNTER = "Hunter", WARRIOR = "Warrior", ROGUE = "Rogue" }

local function db()
    local d = rawget(_G, "GlassPanelAmmoDB")
    if type(d) ~= "table" then
        d = {}
        GlassPanelAmmoDB = d
    end
    if type(d.thresholds) ~= "table" then d.thresholds = {} end
    return d
end

local function playerClass()
    local ok, _, class = pcall(UnitClass, "player")
    class = ok and P(class) or nil
    return type(class) == "string" and class or nil
end

-- This class's thresholds: the saved ones when they hold up, else the defaults.
local function thresholds(class)
    local def = DEFAULTS[class]
    if not def then return nil end
    local t = db().thresholds[class]
    if type(t) == "table" and type(t.low) == "number" and type(t.critical) == "number"
        and t.critical >= 0 and t.critical < t.low then
        return t.low, t.critical
    end
    return def.low, def.critical
end

-- Two typed values -> low, critical; or nil and why. Whole numbers, 0 or
-- more, critical below low.
local function validate(lowText, critText)
    local low, crit = tonumber(lowText), tonumber(critText)
    if not low or not crit or low ~= math.floor(low) or crit ~= math.floor(crit) then
        return nil, nil, "Enter whole numbers."
    end
    if low < 0 or crit < 0 then return nil, nil, "Numbers can't be negative." end
    if crit >= low then return nil, nil, "Critical must be below low." end
    return low, crit
end

local function setThresholds(class, low, crit)
    if low == nil then db().thresholds[class] = nil
    else db().thresholds[class] = { low = low, critical = crit } end
    GlassPanel.Refresh("ammo")
end

--------------------------------------------------------------------------------
-- Reading the client
--------------------------------------------------------------------------------

-- id -> classID, subClassID, icon (nil when unknown).
local function itemClass(id)
    local ok, _, _, _, _, icon, classID, subClassID = pcall(C_Item.GetItemInfoInstant, id)
    if not ok then return nil end
    return P(classID), P(subClassID), P(icon)
end

local function itemName(id)
    local ok, name = pcall(C_Item.GetItemNameByID, id)
    name = ok and P(name) or nil
    return type(name) == "string" and name ~= "" and name or nil
end

local function equippedID(slot)
    local ok, id = pcall(GetInventoryItemID, "player", slot)
    id = ok and P(id) or nil
    return type(id) == "number" and id or nil
end

local function slotCount(slot)
    local ok, n = pcall(GetInventoryItemCount, "player", slot)
    n = ok and P(n) or nil
    return type(n) == "number" and n or nil
end

-- What the bags hold: match(id) -> true to count it. Returns the count and
-- whether some slot couldn't be read (the count may then be short).
local BI = Enum and Enum.BagIndex or {}
local function bagCount(match)
    local total, unsure = 0, false
    for bag = BI.Backpack or 0, BI.Bag_4 or 4 do
        local slots = P(C_Container.GetContainerNumSlots(bag))
        if slots == nil then
            unsure = true
        else
            for slot = 1, slots do
                local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
                if not ok or API.IsSecret(info) then
                    unsure = true
                elseif type(info) == "table" then
                    local id, n = P(info.itemID), P(info.stackCount)
                    if type(id) ~= "number" or type(n) ~= "number" then
                        unsure = true
                    elseif match(id) then
                        total = total + n
                    end
                end
            end
        end
    end
    return total, unsure
end

-- The client's own gate for the ammo slot (70338+). Only a plain false
-- counts: absent, throwing or unreadable leaves the weapon to decide.
local function clientSaysNoAmmo()
    local f = rawget(_G, "UnitUsesAmmo")
    if type(f) ~= "function" then return false end
    local ok, uses = pcall(f, "player")
    return ok and P(uses) == false
end

-- The cache, rebuilt at most once per repaint after an event (a bag walk).
-- kind: "arrow" | "bullet" | "thrown" | nil (no block). count: nil = unknown.
local state = { kind = nil }
local stale = true

local function scan()
    stale = false
    local s = { class = playerClass() }
    state = s
    if not (s.class and DEFAULTS[s.class]) then return end
    s.weapon = equippedID(RANGED_SLOT)
    if not s.weapon then return end
    local classID, subClassID, icon = itemClass(s.weapon)
    if classID ~= WEAPON then return end
    local kind = KIND_OF_WEAPON[subClassID]
    if not kind then return end
    if kind ~= "thrown" and clientSaysNoAmmo() then return end
    s.kind, s.weaponIcon = kind, icon

    if kind == "thrown" then
        s.count = slotCount(RANGED_SLOT)
        s.icon = icon
        s.spare = bagCount(function(id) return id == s.weapon end)
        return
    end

    s.ammo = equippedID(AMMO_SLOT)
    if s.ammo then
        local aClass, aSub, aIcon = itemClass(s.ammo)
        s.ammoKind = aClass == PROJECTILE and KIND_OF_PROJECTILE[aSub] or nil
        s.icon = aIcon
        if s.ammoKind == kind then
            s.count = slotCount(AMMO_SLOT)
            if s.count == nil then
                local n, unsure = bagCount(function(id) return id == s.ammo end)
                if not unsure then s.count = n end
            end
            return
        end
        s.wrong = true
    end
    -- Nothing usable equipped: what the bags hold of the right kind.
    s.missing = true
    s.icon = s.icon and not s.wrong and s.icon or KIND_ICON[kind]
    local n, unsure = bagCount(function(id)
        local c, sub = itemClass(id)
        return c == PROJECTILE and KIND_OF_PROJECTILE[sub] == kind
    end)
    s.count, s.unsure = n, unsure
end

local function current()
    if stale then scan() end
    return state
end

local function colour(count, class)
    local low, crit = thresholds(class)
    if count < crit then return "ff4040" end
    if count < low then return "ffd200" end
    return "ffffff"
end

local function iconText(icon, size)
    if type(icon) ~= "number" and type(icon) ~= "string" then return "" end
    return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", tostring(icon), size, size)
end

local UNSURE = "|cff888888?|r"
local WARN = "|cffff4040!|r"

--------------------------------------------------------------------------------
-- The thresholds window: low and critical for the player's class.
--------------------------------------------------------------------------------

local win

local function numberBox(label, y)
    local text = Glass.Font(win, 12, "LEFT")
    text:SetPoint("TOPLEFT", win.hint, "BOTTOMLEFT", 0, y)
    text:SetText(label)
    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(80, 20)
    box:SetPoint("LEFT", text, "LEFT", 150, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(5)
    box:SetScript("OnEscapePressed", function() win:Hide() end)
    return box
end

local function fillWindow()
    local low, crit = thresholds(win.class)
    win.low:SetText(tostring(low))
    win.critical:SetText(tostring(crit))
    win.status:SetText("")
end

local function save()
    local low, crit, err = validate(win.low:GetText(), win.critical:GetText())
    if not low then
        win.status:SetText("|cffff4040" .. err .. "|r")
        return false
    end
    setThresholds(win.class, low, crit)
    win.status:SetText("Saved.")
    return true
end

local function openWindow()
    local class = playerClass()
    if not DEFAULTS[class] then
        API.Print("Ammo thresholds are for hunters, warriors and rogues.")
        return
    end
    if not win then
        win = API.Window("GlassPanelAmmoWindow", 340, 190)
        win.low = numberBox("Low (yellow) below", -12)
        win.critical = numberBox("Critical (red) below", -40)
        win.low:SetScript("OnEnterPressed", function() save() end)
        win.critical:SetScript("OnEnterPressed", function() save() end)
        win.status = Glass.Font(win, 11, "LEFT")
        win.status:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 40)
        win.save = API.Button(win, "Save", 80, function() save() end)
        win.save:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -108, 10)
        win.reset = API.Button(win, "Defaults", 90, function()
            setThresholds(win.class, nil)
            fillWindow()
        end)
        win.reset:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 10)
        win.close = API.Button(win, "Close", 90, function() win:Hide() end)
        win.close:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
    end
    win.class = class
    win.title:SetText("Ammo warnings: " .. CLASS_NAME[class])
    local def = DEFAULTS[class]
    win.hint:SetText("The count turns yellow below low and red below critical. Defaults: "
        .. def.low .. " and " .. def.critical .. ".")
    fillWindow()
    win:Show()
end

--------------------------------------------------------------------------------
-- The block
--------------------------------------------------------------------------------

local block = GlassPanel.RegisterBlock({
    id = "ammo",
    label = "Ammo",
    showLabel = false,   -- the ammo's own icon says what it is
    side = "right",
    order = 118,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED" },
    unitEvents = { UNIT_INVENTORY_CHANGED = "player" },
    onEvent = function() stale = true end,
    -- nil hides the block: not a class that shoots, or no weapon that takes ammo.
    text = function()
        local s = current()
        if not s.kind then return nil end
        local t
        if s.count == nil then t = UNSURE
        else t = "|cff" .. colour(s.count, s.class) .. BreakUpLargeNumbers(s.count) .. "|r" end
        if s.count ~= nil and s.unsure then t = t .. UNSURE end
        if s.missing then t = t .. WARN end
        return iconText(s.icon, 14) .. t
    end,
    tooltip = function(_, tt)
        local s = current()
        tt:AddLine("Ammo")
        if not s.kind then
            tt:AddLine("No ranged weapon that takes ammo.", 0.7, 0.7, 0.7)
            return
        end
        tt:AddDoubleLine("Weapon", itemName(s.weapon) or "?", 1, 0.82, 0, 1, 1, 1)
        if s.kind == "thrown" then
            tt:AddDoubleLine("Equipped", s.count and BreakUpLargeNumbers(s.count) or "?", 1, 0.82, 0, 1, 1, 1)
            if s.spare and s.spare > 0 then
                tt:AddDoubleLine("In your bags", BreakUpLargeNumbers(s.spare), 1, 0.82, 0, 1, 1, 1)
            end
        else
            if s.ammo then
                tt:AddDoubleLine("Equipped", itemName(s.ammo) or "?", 1, 0.82, 0, 1, 1, 1)
            end
            tt:AddDoubleLine(KIND_NAME[s.kind], s.count and BreakUpLargeNumbers(s.count) or "?", 1, 0.82, 0, 1, 1, 1)
            if s.wrong then
                tt:AddLine("The equipped ammo doesn't fit this weapon: equip " .. KIND_NAME[s.kind]:lower()
                    .. ". The count is what your bags hold.", 1, 0.25, 0.25, true)
            elseif s.missing then
                tt:AddLine("No ammo equipped. The count is what your bags hold.", 1, 0.25, 0.25, true)
            end
            if s.unsure then
                tt:AddLine("Some bag slots can't be read right now and aren't counted.", 0.7, 0.7, 0.7, true)
            end
        end
        local low, crit = thresholds(s.class)
        tt:AddLine(" ")
        tt:AddLine("Yellow below " .. low .. ", red below " .. crit .. ".", 0.7, 0.7, 0.7)
        tt:AddLine("Left-click: set the warnings", 0.3, 1, 0.3)
    end,
    onClick = function(_, button) if button == "LeftButton" then openWindow() end end,
    options = {
        { label = "Set ammo warnings...", run = openWindow,
          note = "When the count turns yellow and red, for your class." },
    },
})

if block then
    block._test = { validate = validate, thresholds = thresholds, window = function() return win end,
                    state = current, save = save }
end
