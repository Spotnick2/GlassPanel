-- LayerProbe: the throwaway measurement addon for Layer (#169). A ForeverProbe
-- module (..\ForeverProbe\docs\GUIDE.md): its lines go to the /fp console and
-- LayerProbeDB.log, never to chat.
--
-- Since the 2026-11-20 server hotfix the client hides the realm (#167), and
-- Blizzard announced the same day that targeted layering addons will be
-- disabled through API changes. Layer (and TitanLayer) read a creature GUID's
-- server field, Creature-0-<server>-<instance>-<zoneUID>-<npc>-<spawn>, as the
-- layer (#138). What this measures:
--   - the target, mouseover and nameplate GUIDs: shape, secret or not, and the
--     server field each creature gives, tallied              /fp layer guids
--   - the player's own GUID at ADDON_LOADED, PLAYER_LOGIN and
--     PLAYER_ENTERING_WORLD (Layer's key since #168)          /fp layer player
--   - the realm APIs and the C_GameRules rulesets             /fp layer realm
--   - what GlassPanel's Layer block shows                     /fp layer block
--   - SHARD_TRANSFER, with the GUIDs read again 2, 5 and 12 s after it (logged
--     whenever it fires while this probe is loaded).
--   - a GUILD addon message's sender (TitanLayer's NovaWorldBuffs listener):
--     our own echo whole, others by shape (has a "-", the part after it blank
--     or not, its length), at most 20 a session              /fp layer ping
-- The guided procedure: /fp steps layer guids.
--
-- NPC and player GUIDs are game ids, not anything another player wrote: they
-- are logged whole. Players other than us are logged by shape only.

local ADDON, NS = ...
local MAX_LOG = 3000

local Probe = ForeverProbe:Module("LayerProbe", { api = 1, cmd = "layer" })

local function say(msg) Probe:Say(msg) end
local show = Probe.Show

-- Optional client functions, read without tripping strict globals.
local function G(name) return rawget(_G, name) end
local function call(name, ...)
    local f = G(name)
    if type(f) == "function" then return f(...) end
end

local function secret(v)
    local f = rawget(_G, "issecretvalue")
    return f ~= nil and f(v) == true
end

--------------------------------------------------------------------------------
-- GUIDs
--------------------------------------------------------------------------------

-- A GUID split into its fields, or nil, why. Never touches a secret.
local function fields(g)
    if secret(g) then return nil, "<secret>" end   -- first: even == nil on a secret throws (Codex on #170)
    if g == nil then return nil, "nil" end
    if type(g) ~= "string" then return nil, type(g) end
    local out = {}
    for part in (g .. "-"):gmatch("([^-]*)-") do out[#out + 1] = part end
    return out
end

-- One unit's GUID: logged, and its server field (creatures and vehicles not
-- player-controlled) returned with the kind. Players: shape only, unless it's us.
local function readUnit(unit)
    local g = UnitGUID(unit)
    local f, why = fields(g)
    if not f then
        if why ~= "nil" then say(unit .. ": " .. why) end
        return nil
    end
    local kind = f[1]
    if kind == "Player" and unit ~= "player" then
        say(unit .. ": Player, " .. #f .. " fields (another player: not logged)")
        return nil
    end
    local controlled = call("UnitPlayerControlled", unit)
    local name = call("UnitName", unit)
    say(string.format("%s: %s  (%d fields, kind %s, controlled %s, name %s)", unit, g, #f, kind,
        show(controlled), show(name)))
    if (kind == "Creature" or kind == "Vehicle") and controlled ~= true then
        local server = f[3]
        local zoneUID = f[5]
        local npc = f[6]
        say(string.format("  server=%s instance=%s zoneUID=%s npc=%s spawn=%s", show(server, true), show(f[4], true),
            show(zoneUID, true), show(npc, true), show(f[7], true)))
        return { unit = unit, kind = kind, server = server, zoneUID = zoneUID, npc = npc, guid = g }
    end
    return nil
end

local function units()
    local list = { "target", "mouseover", "focus" }
    for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
    return list
end

-- Every unit in view: returns the creatures read, the tally by server field
-- ({ [server] = count }) and how many distinct GUIDs counted.
local function guids(label)
    local map = G("C_Map")
    map = type(map) == "table" and type(map.GetBestMapForUnit) == "function" and map.GetBestMapForUnit("player") or nil
    say("-- guids" .. (label and (" (" .. label .. ")") or "") .. ": map " .. show(map) .. ", instance "
        .. show(call("IsInInstance")) .. ", taxi " .. show(call("UnitOnTaxi", "player")))
    local seen, creatures, tally, distinct = {}, {}, {}, 0
    for _, unit in ipairs(units()) do
        local c = readUnit(unit)
        if c and not seen[c.guid] then
            seen[c.guid] = true
            creatures[#creatures + 1] = c
            distinct = distinct + 1
            local s = c.server
            if type(s) == "string" then tally[s] = (tally[s] or 0) + 1 end
        end
    end
    local parts = {}
    for s, n in pairs(tally) do parts[#parts + 1] = s .. " x" .. n end
    table.sort(parts)
    say(string.format("tally: %d creature(s); server fields: %s", distinct,
        #parts > 0 and table.concat(parts, ", ") or "none"))
    return creatures, tally, distinct
end

-- The one server field most creatures agree on, its count, and how many
-- distinct values there were.
-- The server field most creatures share: only when at least two distinct GUIDs
-- share it and no other value ties it (Codex on #170: with one value per NPC,
-- as measured since the hotfix, any pick would be arbitrary). Else nil: no
-- consensus. Also returns the best count and how many distinct values.
local function majority(tally)
    local best, n, values, tie = nil, 0, 0, false
    for s, c in pairs(tally) do
        values = values + 1
        if c > n then best, n, tie = s, c, false elseif c == n then tie = true end
    end
    if n < 2 or tie then return nil, n, values end
    return best, n, values
end

--------------------------------------------------------------------------------
-- The player's own GUID, at each load event
--------------------------------------------------------------------------------

local atLoad = {}   -- event -> { shape, guid }
-- quiet: record only (at file scope, before the host has our log).
local function playerGUID(event, quiet)
    local g = UnitGUID("player")
    local entry = { shape = Probe.Shape(g), guid = (not secret(g) and type(g) == "string") and g or nil }
    if event then atLoad[event] = entry end
    if not quiet then
        say("player GUID" .. (event and (" at " .. event) or "") .. ": " .. show(g) .. " (" .. entry.shape .. ")")
    end
    return entry
end

local function player()
    say("-- player")
    for _, e in ipairs({ "file", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" }) do
        local r = atLoad[e]
        say("  at " .. e .. ": " .. (r and (show(r.guid) .. " (" .. r.shape .. ")") or "not reached"))
    end
    local now = playerGUID()
    Probe:Call("GetUnitName(player, false)", G("GetUnitName"), "player", false)
    Probe:Call("UnitName(player)", G("UnitName"), "player")
    return now.guid ~= nil, now.guid
end

--------------------------------------------------------------------------------
-- The realm, and the rulesets
--------------------------------------------------------------------------------

local RULES = { "HardcoreRuleset", "RPRuleset", "PvPRuleset" }

local function realm()
    say("-- realm")
    Probe:Call("GetRealmName()", G("GetRealmName"))
    Probe:Call("GetRealmID()", G("GetRealmID"))
    Probe:Call("GetNormalizedRealmName()", G("GetNormalizedRealmName"))
    Probe:Call("UnitFullName(player)", G("UnitFullName"), "player")
    local rules = G("C_GameRules")
    local enum = type(G("Enum")) == "table" and rawget(G("Enum"), "GameRule") or nil
    say("C_GameRules " .. type(rules) .. ", Enum.GameRule " .. type(enum))
    local read = {}
    for _, name in ipairs(RULES) do
        local v = type(enum) == "table" and enum[name] or nil
        if v == nil then
            say("  Enum.GameRule." .. name .. ": MISSING")
        elseif type(rules) == "table" and type(rules.IsGameRuleActive) == "function" then
            local okR, on = pcall(rules.IsGameRuleActive, v)
            if not okR then
                say("  " .. name .. " (" .. show(v) .. "): ERROR " .. tostring(on))
            else
                if type(on) == "boolean" then read[name] = on end   -- not and/or: false is a reading
                say("  " .. name .. " (" .. show(v) .. "): " .. show(on) .. " (" .. Probe.Shape(on) .. ")")
            end
        end
    end
    local r = call("GetRealmName")
    return not secret(r) and r == "", read
end

--------------------------------------------------------------------------------
-- GlassPanel's Layer block, as the player sees it
--------------------------------------------------------------------------------

local function blockText()
    local gp = rawget(_G, "GlassPanel")
    local b = type(gp) == "table" and gp.Engine and gp.Engine.byId and gp.Engine.byId.layer
    local label = b and b.widget and b.widget.label
    if not label then
        say("Layer block: not loaded")
        return nil
    end
    local ok, t = pcall(label.GetText, label)
    t = ok and t or nil
    say("Layer block shows: " .. show(t) .. " (shown " .. show(b.widget:IsShown()) .. ")")
    return t
end

--------------------------------------------------------------------------------
-- SHARD_TRANSFER: logged whenever it fires; the units read again after it
--------------------------------------------------------------------------------

local before   -- the majority server field when the layer-change step began
local transfers = 0

local function afterTransfer(delay)
    C_Timer.After(delay, function()
        local _, tally = guids("+" .. delay .. " s after SHARD_TRANSFER")
        blockText()
        local now = majority(tally)
        if before and now then
            say(string.format("server field: %s before, %s %d s after: %s", before, now, delay,
                now ~= before and "CHANGED" or "same"))
        else
            say(string.format("server field %d s after: inconclusive (no shared value %s)", delay,
                before and "after" or "before"))
        end
    end)
end

--------------------------------------------------------------------------------
-- Guild addon messages: what a sender looks like since the hotfix
--------------------------------------------------------------------------------

local PREFIX = "LayerProbe"
local MAX_SENDERS = 20
local PENDING_FOR = 30    -- seconds an outstanding ping waits for its echo
local senders, ownEcho = 0, nil
local pending             -- { token, at }: our outstanding ping (Codex on #170)

-- A sender's shape, never another player's name.
local function senderShape(sender)
    if secret(sender) then return "<secret>" end
    if type(sender) ~= "string" then return type(sender) end
    local dash = sender:find("-", 1, true)
    if not dash then return string.format("str%d, no '-'", #sender) end
    local after = sender:sub(dash + 1)
    return string.format("str%d, '-' at %d, after it %s", #sender, dash,
        after:find("%S") and ("str" .. #after) or "BLANK")
end

-- Only the echo of OUR outstanding ping is ours: its token is random and only
-- this client knows it, so another guild member running the probe (who sends a
-- ping too) is never taken for us and never logged by name (Codex on #170).
-- Whether the sender's name part matches ours is the measurement, so it's said.
local function onAddonMessage(prefix, text, channel, sender)
    if channel ~= "GUILD" then return end
    if pending and GetTime() - pending.at > PENDING_FOR then pending = nil end
    local mine = pending ~= nil and prefix == PREFIX and not secret(text) and text == pending.token
    if mine then
        pending = nil
        ownEcho = sender
        say("own GUILD echo: sender " .. show(sender) .. " (" .. senderShape(sender) .. ")")
        local name = call("GetUnitName", "player", false)
        local plain = type(sender) == "string" and not secret(sender)
        local part = plain and (sender:match("^(.-)%-") or sender) or nil
        local same = part ~= nil and not secret(name) and part == name
        say("  GetUnitName(player, false) " .. show(name) .. "; the sender's name part " .. show(part)
            .. (same and " MATCHES" or " doesn't match") .. "; Ambiguate(sender, none) "
            .. show(plain and call("Ambiguate", sender, "none") or nil))
        return
    end
    if senders >= MAX_SENDERS then return end
    senders = senders + 1
    say("GUILD addon message, prefix " .. show(prefix) .. ": sender " .. senderShape(sender))
end

local function ping()
    local chat = G("C_ChatInfo")
    if not call("IsInGuild") then say("ping: not in a guild"); return false end
    if type(chat) ~= "table" then say("ping: no C_ChatInfo"); return false end
    Probe:Call("RegisterAddonMessagePrefix", chat.RegisterAddonMessagePrefix, PREFIX)
    pending = { token = string.format("ping:%d:%d", math.floor(GetTime() * 1000) % 1000000, math.random(1, 999999)),
                at = GetTime() }
    Probe:Call("SendAddonMessage GUILD", chat.SendAddonMessage, PREFIX, pending.token, "GUILD")
    return true
end

--------------------------------------------------------------------------------
-- Commands and the procedure
--------------------------------------------------------------------------------

Probe:Command("guids", function() guids() end, "the target, mouseover and nameplate GUIDs, tallied by server field")
Probe:Command("player", player, "the player's GUID now and at each load event")
Probe:Command("realm", realm, "the realm APIs and the C_GameRules rulesets")
Probe:Command("block", blockText, "what GlassPanel's Layer block shows")
Probe:Command("ping", ping, "send one GUILD addon message, to see our own sender's shape")
Probe:Command("clear", function() Probe:ClearLog(); say("log cleared") end, "empty the saved log")

local function creatureCheck(unit)
    local f = fields(UnitGUID(unit))
    if not f then return false, unit .. " GUID unreadable or none" end
    if f[1] ~= "Creature" and f[1] ~= "Vehicle" then return false, unit .. " is a " .. tostring(f[1]) end
    return tonumber(f[3]) ~= nil, "server field " .. tostring(f[3])
end

Probe:Steps("guids", {
    rev = 2,   -- 2: no-consensus majority, token-correlated echo (Codex on #170)
    title = "Layer: creature GUIDs since the 2026-11-20 hotfix",
    { text = "In an open-world zone (not an instance, not on a flight), out of combat. Type /fp to open the "
          .. "console beside this panel: the readings show there. Then press Next." },
    { text = "Reading the realm APIs and the rulesets.", auto = true, run = realm,
      check = function() local blank = realm(); return true, blank and "GetRealmName() is \"\"" or "GetRealmName() reads" end },
    { text = "Reading your own GUID, now and at each load event.", auto = true, run = player,
      check = function() local ok, g = player(); return ok, g or "unreadable" end },
    { text = "Target an NPC (any creature, not a pet or a totem), then press Read.", button = "Read",
      run = function() return readUnit("target") end,
      check = function() return creatureCheck("target") end },
    { text = "Now put your mouse over a DIFFERENT NPC and keep it there: this step completes by itself.",
      wait = function()
          local t, m = UnitGUID("target"), UnitGUID("mouseover")
          if secret(m) or m == nil then return false, "no readable mouseover yet" end   -- secret first
          if not secret(t) and m == t then return false, "that's your target: another NPC" end
          local f = fields(m)
          if not f or (f[1] ~= "Creature" and f[1] ~= "Vehicle") then return false, "not a creature" end
          readUnit("mouseover")
          return true, f[3]
      end, timeout = 120 },
    { text = "Turn nameplates on (V for enemies, Shift+V for friendly NPCs) and stand where several show, "
          .. "then press Read.", button = "Read",
      run = function() local _, tally, n = guids("nameplates"); return n, majority(tally) end,
      check = function()
          local _, tally, n = guids("nameplates check")
          local best, count, values = majority(tally)
          before = best
          return n >= 2 and count >= 2, string.format("%d creatures, %d server value(s), the most common %s x%d",
              n, values, tostring(best), count)
      end, screenshot = "nameplates" },
    { text = "Look at GlassPanel's Layer block on the bar (hover it for its tooltip).", auto = true, run = blockText },
    { text = "Does the Layer block show a layer number (not a grey ?), and does its tooltip name one?", ask = true,
      screenshot = "layer block" },
    { text = "If you can change layer now (accept a group invite from someone on another layer), do it: this "
          .. "step completes when the game says SHARD_TRANSFER. If you can't, press Skip.", event = "SHARD_TRANSFER" },
    { text = "Wait 15 seconds after the move (the readings at 2, 5 and 12 s are logged), then stand among "
          .. "nameplates again and press Read.", button = "Read",
      run = function() local _, tally = guids("after the layer change"); blockText(); return majority(tally) end,
      check = function()
          local _, tally = guids("after the layer change, check")
          local now = majority(tally)
          if not (before and now) then
              return false, "inconclusive: no server field shared by two NPCs " .. (before and "after" or "before")
          end
          return now ~= before, string.format("%s before, %s after", before, now)
      end },
    { text = "In a guild: press Send. One addon message (not chat) goes to your guild, and its echo shows "
          .. "what a sender looks like now. Not in a guild: Skip.", button = "Send", run = ping },
    { text = "Waiting for the echo of that message.",
      wait = function()
          if ownEcho ~= nil then return true, senderShape(ownEcho) end
          return false, "no echo yet"
      end, timeout = 20 },
    { text = "Type /reload (or press Reload now): the next step reads your GUID at each load event.", reload = true },
    { text = "Your GUID at each load event, after the reload.", auto = true, run = player,
      check = function()
          local a = atLoad.ADDON_LOADED
          return a ~= nil and a.guid ~= nil, a and ("at ADDON_LOADED: " .. tostring(a.guid or a.shape)) or "not reached"
      end },
    { text = "Done. Type /reload to save the results.", reload = true },
})

playerGUID("file", true)

local boot = CreateFrame("Frame")
Probe:RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "SHARD_TRANSFER",
    "CHAT_MSG_ADDON" })
boot:SetScript("OnEvent", function(_, event, name, ...)
    if event == "CHAT_MSG_ADDON" then
        local text, channel, sender = ...
        onAddonMessage(name, text, channel, sender)
        return
    end
    if event == "SHARD_TRANSFER" then
        transfers = transfers + 1
        say("SHARD_TRANSFER #" .. transfers .. " (args " .. show(name) .. ", " .. show((...)) .. ")")
        guids("at SHARD_TRANSFER")
        for _, d in ipairs({ 2, 5, 12 }) do afterTransfer(d) end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if not atLoad[event] then playerGUID(event) end
        return
    end
    if name ~= ADDON then return end
    Probe:Ready()
    local db = rawget(_G, "LayerProbeDB")
    if type(db) ~= "table" then
        db = {}
        LayerProbeDB = db
    end
    if type(db.log) ~= "table" then db.log = {} end
    Probe:UseLog(db.log, MAX_LOG)
    db.loads = (db.loads or 0) + 1
    say("loaded (" .. db.loads .. " loads). /fp layer for the commands, /fp steps layer guids for the procedure")
    playerGUID("ADDON_LOADED")
    say("  (at file scope: " .. show(atLoad.file and (atLoad.file.guid or atLoad.file.shape)) .. ")")
end)

NS._test = { Probe = Probe, fields = fields, readUnit = readUnit, guids = guids, majority = majority,
             player = player, realm = realm, blockText = blockText, atLoad = atLoad, senderShape = senderShape,
             ping = ping, ownEcho = function() return ownEcho end, pending = function() return pending end }
