-- AmmoProbe: the throwaway measurement addon for the Ammo plugin's thrown
-- weapons (#177). A ForeverProbe module (..\ForeverProbe\docs\GUIDE.md): its
-- lines go to the /fp console and AmmoProbeDB.log, never to chat.
--
-- A thrown weapon on Forever doesn't stack, it wears down (seen in game on a
-- rogue, 2026-11-21), so Ammo shows its durability when the ranged slot has
-- one and the stack count when it doesn't (#178). What the client answers was
-- never measured. With a thrown weapon in the ranged slot (18) this records:
--   - GetInventoryItemCount("player", 18) and GetInventoryItemDurability(18),
--     raw, with the item, UnitUsesAmmo, the ammo slot's count and
--     C_Item.GetItemCount (does it count the equipped one?)     /fp ammo read
--   - the same item in the bags, and whether the slot's count includes it
--     (Ammo's tooltip would then count those twice)             /fp ammo read
--   - what GlassPanel's Ammo block shows                         /fp ammo block
--   - each UPDATE_INVENTORY_DURABILITY: the ranged slot's durability, to see
--     a throw wear it down (logged whenever it fires while this probe is
--     loaded, at most MAX_WATCH a session).
-- The guided procedure: /fp steps ammo thrown.
--
-- Item names and ids are game data (no other player's words): logged whole.

local ADDON, NS = ...
local MAX_LOG = 3000
local MAX_WATCH = 200
local RANGED, AMMO = 18, 0
local THROWN_CLASS, THROWN_SUBCLASS = 2, 16   -- Weapon, Thrown (ItemConstantsDocumentation)

local Probe = ForeverProbe:Module("AmmoProbe", { api = 1, cmd = "ammo" })

local function say(msg) Probe:Say(msg) end
local show = Probe.Show

-- Optional client functions, read without tripping strict globals.
local function G(name) return rawget(_G, name) end
local function field(t, name)
    if type(t) ~= "table" then return nil end
    return rawget(t, name)
end

local function secret(v)
    local f = rawget(_G, "issecretvalue")
    return f ~= nil and f(v) == true
end

-- A plain finite number, or nil (secret, absent or anything else).
local function num(v)
    if secret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- f(...) under pcall: its results, or nothing when it's absent or throws.
local function try(f, ...)
    if type(f) ~= "function" then return end
    local r = { pcall(f, ...) }
    if not r[1] then return end
    return unpack(r, 2, table.maxn(r))
end

local function inCombat() return show(try(G("InCombatLockdown"))) end

--------------------------------------------------------------------------------
-- The same item in the bags
--------------------------------------------------------------------------------

-- Stacks of item id in bags 0-4: the total, the slots holding it, and whether
-- some slot couldn't be read (the total may then be short).
local function inBags(id)
    local c = G("C_Container")
    local numSlots, itemInfo = field(c, "GetContainerNumSlots"), field(c, "GetContainerItemInfo")
    if type(numSlots) ~= "function" or type(itemInfo) ~= "function" then return nil, 0, true end
    local total, slots, unsure = 0, 0, false
    for bag = 0, 4 do
        local n = num((try(numSlots, bag)))
        if n == nil then
            unsure = true
        else
            for slot = 1, n do
                local ok, info = pcall(itemInfo, bag, slot)
                if not ok or secret(info) then
                    unsure = true
                elseif type(info) == "table" then
                    local itemID, count = num(info.itemID), num(info.stackCount)
                    if itemID == nil or count == nil then
                        unsure = true
                    elseif itemID == id then
                        total, slots = total + count, slots + 1
                    end
                end
            end
        end
    end
    return total, slots, unsure
end

--------------------------------------------------------------------------------
-- The ranged slot
--------------------------------------------------------------------------------

local last   -- the latest reading, plain values only

-- Everything about the ranged slot, raw, then the plain reading it gives:
-- { id, thrown, count, cur, max, bags, bagSlots, bagsUnsure, itemCount, label }.
local function read(label)
    label = label or "now"
    say("-- ranged slot (" .. label .. ", combat " .. inCombat() .. ")")
    local cItem = G("C_Item")
    Probe:Call("GetInventoryItemID(player, 18)", G("GetInventoryItemID"), "player", RANGED)
    local id = num((try(G("GetInventoryItemID"), "player", RANGED)))
    local thrown
    if id then
        Probe:Call("C_Item.GetItemInfoInstant(id)", field(cItem, "GetItemInfoInstant"), id)
        local _, _, _, _, _, classID, subClassID = try(field(cItem, "GetItemInfoInstant"), id)
        classID, subClassID = num(classID), num(subClassID)
        thrown = classID == THROWN_CLASS and subClassID == THROWN_SUBCLASS
        Probe:Call("C_Item.GetItemNameByID(id)", field(cItem, "GetItemNameByID"), id)
        say("  the ranged weapon is " .. (thrown and "a THROWN weapon"
            or ("not thrown (class " .. show(classID) .. ", subclass " .. show(subClassID) .. ")")))
    else
        say("  no ranged weapon (or its id can't be read)")
    end
    Probe:Call("GetInventoryItemCount(player, 18)", G("GetInventoryItemCount"), "player", RANGED)
    Probe:Call("GetInventoryItemDurability(18)", G("GetInventoryItemDurability"), RANGED)
    Probe:Call("GetInventoryItemCount(player, 0)", G("GetInventoryItemCount"), "player", AMMO)
    Probe:Call("UnitUsesAmmo(player)", G("UnitUsesAmmo"), "player")
    local r = { id = id, thrown = thrown, label = label }
    r.count = num((try(G("GetInventoryItemCount"), "player", RANGED)))
    local cur, max = try(G("GetInventoryItemDurability"), RANGED)
    r.cur, r.max = num(cur), num(max)
    if id then
        Probe:Call("C_Item.GetItemCount(id)", field(cItem, "GetItemCount"), id)
        Probe:Call("GetItemCount(id)", G("GetItemCount"), id)
        r.itemCount = num((try(field(cItem, "GetItemCount"), id)))
        r.bags, r.bagSlots, r.bagsUnsure = inBags(id)
        say(string.format("  in the bags: %s in %d slot(s)%s", show(r.bags), r.bagSlots,
            r.bagsUnsure and " (some slots unreadable: may be short)" or ""))
    end
    say(string.format("  reading: count %s, durability %s/%s, bags %s, C_Item.GetItemCount %s",
        show(r.count), show(r.cur), show(r.max), show(r.bags), show(r.itemCount)))
    last = r
    return r
end

--------------------------------------------------------------------------------
-- GlassPanel's Ammo block, as the player sees it
--------------------------------------------------------------------------------

local function blockText()
    local gp = rawget(_G, "GlassPanel")
    local b = type(gp) == "table" and gp.Engine and gp.Engine.byId and gp.Engine.byId.ammo
    local label = b and b.widget and b.widget.label
    if not label then
        say("Ammo block: not loaded")
        return nil
    end
    local ok, t = pcall(label.GetText, label)
    t = ok and t or nil
    say("Ammo block shows: " .. show(t) .. " (shown " .. show(b.widget:IsShown()) .. ")")
    return t
end

--------------------------------------------------------------------------------
-- A throw wearing the weapon down: every UPDATE_INVENTORY_DURABILITY
--------------------------------------------------------------------------------

local events, watched = 0, 0
local prevCur, prevMax   -- the ranged slot's durability at the last event (or reading)

local function onDurability()
    events = events + 1
    if watched >= MAX_WATCH then return end
    watched = watched + 1
    local cur, max = try(G("GetInventoryItemDurability"), RANGED)
    local c, m = num(cur), num(max)
    local change = ""
    if c and prevCur then change = string.format(" (%+d)", c - prevCur) end
    say(string.format("UPDATE_INVENTORY_DURABILITY #%d: ranged %s/%s%s, combat %s", events,
        c and tostring(c) or show(cur), m and tostring(m) or show(max), change, inCombat()))
    if c then prevCur, prevMax = c, m end
end

--------------------------------------------------------------------------------
-- Commands and the procedure
--------------------------------------------------------------------------------

Probe:Command("read", function() read("by hand") end, "the ranged slot: count, durability, the bags, raw")
Probe:Command("block", blockText, "what GlassPanel's Ammo block shows")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local first   -- the reading the procedure started from

local function equippedCheck()
    local r = read("equipped")
    first = r
    prevCur, prevMax = r.cur, r.max
    if not r.id then return false, "nothing in the ranged slot" end
    if not r.thrown then return false, "the ranged weapon isn't a thrown weapon" end
    if r.cur and r.max then return true, string.format("durability %d/%d, count %s", r.cur, r.max, show(r.count)) end
    return false, "no durability read (count " .. show(r.count) .. ")"
end

local function wornCheck()
    local r = read("after a throw")
    if not (first and first.cur and r.cur) then return false, "no durability to compare" end
    if r.id ~= first.id then return false, "a different weapon is equipped now" end
    return r.cur < first.cur, string.format("%d before, %d now", first.cur, r.cur)
end

local function spareCheck()
    local r = read("a spare in the bags")
    if not (r.bags and r.bags > 0) then return false, "none of the same weapon in the bags" end
    local base = first and first.count
    local says = string.format("slot count %s, %d in the bags", show(r.count), r.bags)
    if r.count and base and r.count == base + r.bags then return true, says .. ": the slot count INCLUDES the bags" end
    if r.count and base and r.count == base then return true, says .. ": the slot count is the equipped one only" end
    return true, says .. " (count before " .. show(base) .. ")"
end

Probe:Steps("thrown", {
    rev = 1,
    title = "Ammo: a thrown weapon's count and durability",
    { text = "Equip a thrown weapon in the ranged slot, out of combat, with no other copy of it in your bags. "
          .. "Type /fp to open the console beside this panel: the readings show there. Then press Next." },
    { text = "Reading the ranged slot.", auto = true, run = function() return read("equipped") end,
      check = equippedCheck },
    { text = "Look at GlassPanel's Ammo block on the bar (hover it for its tooltip).", auto = true, run = blockText },
    { text = "Does the Ammo block show the weapon's durability as cur/max (like 73/100), the same as the "
          .. "weapon's own tooltip on your character sheet?", ask = true, screenshot = "ammo block" },
    { text = "Throw it at a mob (or a training dummy) a few times: this step completes when the game says "
          .. "UPDATE_INVENTORY_DURABILITY. If nothing comes after five throws, press Skip.",
      event = "UPDATE_INVENTORY_DURABILITY" },
    { text = "Leave combat, then press Read.", button = "Read", run = function() return read("after a throw") end,
      check = wornCheck },
    { text = "If you have a second one of the same thrown weapon, put it in your bags (leave the first "
          .. "equipped), then press Read. If not, press Skip.", button = "Read",
      run = function() return read("a spare in the bags") end, check = spareCheck },
    { text = "Look at the Ammo block's tooltip again: does it show the spare in your bags?", ask = true,
      screenshot = "ammo tooltip" },
    { text = "Done. Type /reload to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "UPDATE_INVENTORY_DURABILITY" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "UPDATE_INVENTORY_DURABILITY" then
        onDurability()
        return
    end
    if name ~= ADDON then return end
    Probe:Ready()
    local db = rawget(_G, "AmmoProbeDB")
    if type(db) ~= "table" then
        db = {}
        AmmoProbeDB = db
    end
    if type(db.log) ~= "table" then db.log = {} end
    Probe:UseLog(db.log, MAX_LOG)
    db.loads = (db.loads or 0) + 1
    say("loaded (" .. db.loads .. " loads). /fp ammo for the commands, /fp steps ammo thrown for the procedure")
end)

NS._test = { Probe = Probe, read = read, blockText = blockText, inBags = inBags, onDurability = onDurability,
             equippedCheck = equippedCheck, wornCheck = wornCheck, spareCheck = spareCheck,
             last = function() return last end }
