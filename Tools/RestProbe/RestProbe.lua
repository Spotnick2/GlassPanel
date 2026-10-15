-- RestProbe: the throwaway measurement addon for XP+'s rested tooltip (#81).
-- A ForeverProbe module (..\ForeverProbe\docs\GUIDE.md): its lines go to the
-- /fp console and RestProbeDB.log, never to chat.
--
-- What XP+ would show, and what it needs measured first:
--   - the rested pool against the cap: GetXPExhaustion, UnitXPMax, the rest
--     state (GetRestState, IsResting)                             /fp rest pool
--   - Well Rested (a 5-rank talent: +20% build-up and cap at 5/5): how to
--     find it and read its rank                                   /fp rest talent
--   - XP buffs (XP food, camping...): the player's auras with their spell
--     IDs, and which ones speak of experience                     /fp rest buffs
--   - how fast rested builds while resting: a sample every minute /fp rest watch [off]
-- The guided procedure: /fp steps rest rested.
--
-- Aura names and descriptions are game text (no other player's words), so
-- they're logged as they are.

local ADDON, NS = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("RestProbe", { api = 1, cmd = "rest" })

local function say(msg) Probe:Say(msg) end
local show = Probe.Show

local function secret(v)
    local f = rawget(_G, "issecretvalue")
    return f ~= nil and f(v) == true
end

local function num(v)
    if secret(v) or type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local function inCombat() return show(InCombatLockdown()) end

--------------------------------------------------------------------------------
-- The pool against the cap
--------------------------------------------------------------------------------

local function pool()
    say("-- pool (combat " .. inCombat() .. ")")
    Probe:Call("UnitLevel(player)", UnitLevel, "player")
    Probe:Call("UnitXP(player)", UnitXP, "player")
    Probe:Call("UnitXPMax(player)", UnitXPMax, "player")
    Probe:Call("GetXPExhaustion()", GetXPExhaustion)
    Probe:Call("GetRestState()", GetRestState)
    Probe:Call("IsResting()", IsResting)
    local rested, max = num(GetXPExhaustion()), num(UnitXPMax("player"))
    if rested and max and max > 0 then
        say(string.format("rested = %.4f levels of this level's XP (Vanilla cap 1.5; 1.8 with Well Rested 5/5)",
            rested / max))
    else
        say("rested / max: unreadable (rested " .. show(rested) .. ", max " .. show(max) .. ")")
    end
    return rested, max
end

--------------------------------------------------------------------------------
-- XP buffs
--------------------------------------------------------------------------------

local XP_WORDS = { "experience", "rested", "xp" }

local function mentionsXP(text)
    if type(text) ~= "string" or secret(text) then return false end
    local lower = text:lower()
    for _, w in ipairs(XP_WORDS) do if lower:find(w, 1, true) then return true end end
    return false
end

-- Every helpful aura: spell ID, name, time left, and its description when it
-- speaks of experience. Returns how many speak of it.
local function buffs()
    say("-- buffs (combat " .. inCombat() .. ")")
    local A = rawget(_G, "C_UnitAuras")
    if not (A and A.GetAuraDataByIndex) then say("C_UnitAuras.GetAuraDataByIndex: MISSING") return 0 end
    local found, now = 0, GetTime()
    for i = 1, 40 do
        local ok, a = pcall(A.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then say("aura " .. i .. ": ERROR " .. tostring(a)) break end
        if a == nil then break end
        if secret(a) then say("aura " .. i .. ": <secret table>") break end
        local id, name = a.spellId, a.name
        local left = num(a.expirationTime) and a.expirationTime > 0 and (a.expirationTime - now) or nil
        local desc
        local S = rawget(_G, "C_Spell")
        if num(id) and S and S.GetSpellDescription then
            local okD, d = pcall(S.GetSpellDescription, id)
            desc = okD and d or nil
        end
        local xp = mentionsXP(name) or mentionsXP(desc)
        if xp then found = found + 1 end
        say(string.format("aura %d: id=%s name=%s left=%s source=%s%s", i, show(id), show(name),
            left and string.format("%.0fs", left) or "none", show(a.sourceUnit),
            xp and ("  XP: " .. show(desc)) or ""))
    end
    say(found .. " aura(s) speak of experience")
    return found
end

--------------------------------------------------------------------------------
-- Well Rested (the talent)
--------------------------------------------------------------------------------

-- Forever's account-wide Legacy trees (Blizzard_LegacySystem, camelot only),
-- read through C_Traits the way Blizzard_MicroMenu's Camelot override reads a
-- Legacy node's rank. IDs from LegacyConstantsDocumentation.lua (forever).
-- No node ID is known for Well Rested: every node's spell name is matched.
local LEGACY_TREES = { { 1188, "Adventure" }, { 1189, "Progression" }, { 1187, "Professions" } }
local MATCH = { "rested", "experience" }

local found   -- { tree, nodeID, spellID, name, rank, max } once seen

local function matches(name)
    if type(name) ~= "string" or secret(name) then return false end
    local lower = name:lower()
    for _, w in ipairs(MATCH) do if lower:find(w, 1, true) then return true end end
    return false
end

local function nodeName(T, configID, info)
    for _, entryID in ipairs(type(info.entryIDs) == "table" and info.entryIDs or {}) do
        local okE, entry = pcall(T.GetEntryInfo, configID, entryID)
        local defID = okE and type(entry) == "table" and entry.definitionID
        if defID then
            local okD, def = pcall(T.GetDefinitionInfo, defID)
            if okD and type(def) == "table" then
                local name = def.overrideName
                if (type(name) ~= "string" or name == "") and num(def.spellID) and C_Spell and C_Spell.GetSpellName then
                    local okN, n = pcall(C_Spell.GetSpellName, def.spellID)
                    name = okN and n or nil
                end
                return name, def.spellID
            end
        end
    end
    return nil, nil
end

local function talent()
    say("-- talent (combat " .. inCombat() .. ")")
    local T = rawget(_G, "C_Traits")
    if not (T and T.GetConfigIDByTreeID and T.GetTreeNodes and T.GetNodeInfo) then
        say("C_Traits: MISSING pieces") return nil
    end
    local C = rawget(_G, "Constants")
    say("Constants.LegacyConsts: " .. Probe.Describe(C and C.LegacyConsts))
    found = nil
    for _, tree in ipairs(LEGACY_TREES) do
        local treeID, label = tree[1], tree[2]
        local okC, configID = pcall(T.GetConfigIDByTreeID, treeID)
        local okN, nodes = pcall(T.GetTreeNodes, treeID)
        local count = okN and type(nodes) == "table" and #nodes or 0
        say(label .. " tree " .. treeID .. ": configID " .. (okC and show(configID) or "ERROR") .. ", "
            .. (okN and (count .. " nodes") or "nodes ERROR"))
        if okC and num(configID) and count > 0 then
            local named = 0
            for _, nodeID in ipairs(nodes) do
                local okI, info = pcall(T.GetNodeInfo, configID, nodeID)
                if okI and type(info) == "table" then
                    local name, spellID = nodeName(T, configID, info)
                    if name then named = named + 1 end
                    if matches(name) then
                        local desc
                        if num(spellID) and C_Spell and C_Spell.GetSpellDescription then
                            local okD, d = pcall(C_Spell.GetSpellDescription, spellID)
                            desc = okD and d or nil
                        end
                        say(string.format("  node %s %s (spell %s): activeRank=%s currentRank=%s ranksPurchased=%s "
                            .. "maxRanks=%s  %s", show(nodeID), show(name), show(spellID), show(info.activeRank),
                            show(info.currentRank), show(info.ranksPurchased), show(info.maxRanks), show(desc)))
                        if type(name) == "string" and name:lower():find("well rested", 1, true) then
                            found = { tree = treeID, nodeID = nodeID, spellID = spellID, name = name,
                                      rank = info.activeRank, max = info.maxRanks }
                        end
                    end
                end
            end
            say("  " .. named .. " of " .. count .. " nodes named")
        end
    end
    if found then
        say("Well Rested: tree " .. found.tree .. " node " .. show(found.nodeID) .. " spell " .. show(found.spellID)
            .. ", rank " .. show(found.rank) .. "/" .. show(found.max))
    else
        say("Well Rested: NOT FOUND in the Legacy trees")
    end
    return found ~= nil, found and found.rank, found and found.max
end

--------------------------------------------------------------------------------
-- Build-up while resting: a sample a minute
--------------------------------------------------------------------------------

local watch          -- the ticker
local first          -- { t, rested, max } at the start

local function sample()
    local rested, max = num(GetXPExhaustion()), num(UnitXPMax("player"))
    local resting = IsResting()
    local t = GetTime()
    if not first then
        first = { t = t, rested = rested, max = max }
        say("watch start: rested " .. show(rested) .. " max " .. show(max) .. " resting " .. show(resting))
        return
    end
    local dt = t - first.t
    if rested and first.rested and max and max > 0 and dt > 0 then
        local perHour = (rested - first.rested) / dt * 3600
        say(string.format("watch +%.0fs: rested %s (+%s), %.1f XP/h = %.3f%% of a level per 8 h, resting %s",
            dt, show(rested), show(rested - first.rested), perHour, perHour * 8 / max * 100, show(resting)))
    else
        say("watch +" .. string.format("%.0f", dt) .. "s: rested " .. show(rested) .. " (unreadable or no change)")
    end
end

local function setWatch(on)
    if watch then watch:Cancel(); watch = nil end
    first = nil
    if on then
        sample()
        watch = C_Timer.NewTicker(60, sample)
        say("watching: a sample a minute (/fp rest watch off to stop)")
    else
        say("watch off")
    end
    return on
end

--------------------------------------------------------------------------------
-- Commands and the procedure
--------------------------------------------------------------------------------

Probe:Command("pool", pool, "the rested pool against the cap")
Probe:Command("buffs", buffs, "your auras, and the ones about experience")
Probe:Command("talent", talent, "Well Rested: found, and its rank")
Probe:Command("watch", function(args) setWatch(args ~= "off") end, "sample rested every minute [off]")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

Probe:Steps("rested", {
    title = "XP+: the rested cap, Well Rested and XP buffs",
    { text = "Log in a character below the level cap, out of combat. Then press Next." },
    { text = "Reading the rested pool.", auto = true, run = pool,
      check = function() local r, m = pool(); return r ~= nil and m ~= nil, "rested and max readable" end },
    { text = "Looking for Well Rested in the Legacy talents.", auto = true, run = talent,
      check = function() return found ~= nil, found and ("rank " .. tostring(found.rank)) or "not found" end },
    { text = "Open your Legacy talents (Adventure). Does the rank shown for Well Rested match what the "
          .. "console says? (Note the rank you see.)", ask = true },
    { text = "Eat XP food, or get a camping buff (or both), then press Read.", button = "Read", run = buffs,
      check = function() return buffs() > 0, "an aura speaks of experience" end },
    { text = "Was every XP buff you have listed in the console (with its spell ID)? Note any missing.", ask = true },
    { text = "Go to an inn or a city so you're resting, then press Start: a sample every minute.",
      button = "Start", run = function() return setWatch(true) end },
    { text = "Stay resting for at least 10 minutes (you can stand or log out at the inn; logging out stops "
          .. "the samples). Then press Next.", },
    { text = "Stopping the samples.", auto = true, run = function()
          sample()
          return setWatch(false)
      end },
    { text = "If you can, leave the inn and camp (use your camping buff) for a few minutes with Start "
          .. "again, else Skip.", button = "Start", run = function() return setWatch(true) end },
    { text = "After a few minutes camping, press Run to stop.", button = "Stop", run = function()
          sample()
          return setWatch(false)
      end },
    { text = "Type /reload to save the results.", reload = true },
})

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING" })
boot:SetScript("OnEvent", function(_, event, name)
    if event == "UPDATE_EXHAUSTION" or event == "PLAYER_UPDATE_RESTING" then
        if watch then say(event .. ": rested " .. show(GetXPExhaustion()) .. " resting " .. show(IsResting())) end
        return
    end
    if name ~= ADDON then return end
    Probe:Ready()
    local db = rawget(_G, "RestProbeDB")
    if type(db) ~= "table" then
        db = {}
        RestProbeDB = db
    end
    if type(db.log) ~= "table" then db.log = {} end
    Probe:UseLog(db.log, MAX_LOG)
    db.loads = (db.loads or 0) + 1
    say("loaded (" .. db.loads .. " loads). /fp rest for the commands, /fp steps rest rested for the procedure")
end)

NS._test = { Probe = Probe, pool = pool, buffs = buffs, talent = talent, setWatch = setWatch, sample = sample,
             found = function() return found end }
