-- LayerProbe (#169): every command runs on the stubbed client without throwing,
-- logs to its own saved table and never to chat, tallies creature GUIDs by their
-- server field, keeps other players out of the log, and survives secrets and
-- missing APIs. A ForeverProbe module: CI skips it (FOREVERPROBE_OPTIONAL=1),
-- locally it runs.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- What the probe reads beyond the shared stubs (71037 dump: C_ChatInfo's
-- RegisterAddonMessagePrefix / SendAddonMessage). The realm APIs it calls
-- without a stub (GetRealmID, GetNormalizedRealmName, UnitFullName, C_GameRules)
-- are left absent: it must say so, not throw.
local sent = {}
rawset(_G, "C_ChatInfo", {
    RegisterAddonMessagePrefix = function() return 0 end,
    SendAddonMessage = function(prefix, msg, chatType) sent[#sent + 1] = { prefix, msg, chatType }; return 0 end,
})

loadAddon()   -- GlassPanel with every plugin, Layer included
WoW.chat = {}  -- (GlassPanel's own lines: the probe's chat is what's checked)
loadForeverProbe()
local ns = {}
WoW.units.player = { guid = "Player-6796-00EDB653" }
assert(loadfile("Tools/LayerProbe/LayerProbe.lua"))("LayerProbe", ns)
WoW.fire("ADDON_LOADED", "LayerProbe")
WoW.fire("PLAYER_LOGIN")
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
local T = ns._test

local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end
local function logHas(pattern)
    for _, line in ipairs(LayerProbeDB.log) do if line:find(pattern, 1, true) then return line end end
    return nil
end

check(type(LayerProbeDB) == "table" and logHas("loaded (1 loads)"), "its own saved log")
check(logHas("player GUID at ADDON_LOADED: \"Player-6796-00EDB653\""), "the player's GUID at ADDON_LOADED")
eq(T.atLoad.file.guid, "Player-6796-00EDB653", "and at file scope (recorded quietly)")

-- GUIDs: three creatures on two server fields, a pet, another player, a secret.
WoW.units.target = { guid = "Creature-0-4395-0-76001-5624-0000000001" }
WoW.units.nameplate1 = { guid = "Creature-0-4395-0-76002-5625-0000000002" }
WoW.units.nameplate2 = { guid = "Creature-0-5100-0-76003-5626-0000000003" }
WoW.units.nameplate3 = { guid = "Creature-0-4395-0-76001-5624-0000000001" }   -- the target again: counted once
WoW.units.nameplate4 = { guid = "Pet-0-4395-0-76004-416-0000000004", controlled = true }
WoW.units.nameplate5 = { guid = "Player-6933-00ABCDEF", isPlayer = true }
WoW.units.nameplate6 = { guid = "secret" }
fp("layer guids")
check(logHas("target: Creature-0-4395-0-76001-5624-0000000001  (7 fields, kind Creature"), "the raw GUID, whole")
check(logHas("server=4395 instance=0 zoneUID=76001 npc=5624 spawn=0000000001"), "its fields")
check(logHas("tally: 3 creature(s); server fields: 4395 x2, 5100 x1"), "tallied, one GUID once, pets and players out")
check(logHas("nameplate5: Player, 3 fields (another player: not logged)"), "another player: shape only")
eq(logHas("Player-6933"), nil, "never their GUID")
check(logHas("nameplate6: <secret>"), "a secret GUID: said, not touched")
local _, why = T.fields(WoW.Secret("guid"))
eq(why, "<secret>", "fields() tests secrecy before comparing with nil")
local _, tally = T.guids()
local best, n, values = T.majority(tally)
eq(best, "4395", "the most common server field")
eq(n, 2, "and its count")
eq(values, 2, "two values seen")
-- No consensus (Codex on #170): one value per NPC, as measured since the hotfix,
-- or a tie, gives no field, never an arbitrary pick.
eq(T.majority({ ["13621"] = 1, ["7122"] = 1, ["52070"] = 1 }), nil, "one value each: no consensus")
eq(T.majority({ a = 2, b = 2 }), nil, "a tie: no consensus")
eq(T.majority({ a = 3, b = 2 }), "a", "a clear majority of two or more")

-- The player, now and at each load event.
fp("layer player")
check(logHas("at PLAYER_LOGIN: \"Player-6796-00EDB653\""), "at PLAYER_LOGIN")
check(logHas("at PLAYER_ENTERING_WORLD: \"Player-6796-00EDB653\""), "at PLAYER_ENTERING_WORLD")

-- The realm: blank, and the rest absent here.
WoW.realm = ""
fp("layer realm")
check(logHas("GetRealmName() 1: [1]=\"\""), "GetRealmName's answer, whole")
check(logHas("GetRealmID() ABSENT"), "an absent function is said")
check(logHas("Enum.GameRule.HardcoreRuleset: MISSING") or logHas("C_GameRules nil"), "no GameRule enum: said")
local blank = T.realm()
eq(blank, true, "a blank realm is reported as blank")
-- The rulesets when they exist: a boolean each, a throw is no reading.
rawset(Enum, "GameRule", { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 })
rawset(_G, "C_GameRules", { IsGameRuleActive = function(r)
    if r == 2 then error("boom") end
    return r == 3
end })
local _, read = T.realm()
eq(read.PvPRuleset, true, "PvP on")
eq(read.HardcoreRuleset, false, "Hardcore off")
eq(read.RPRuleset, nil, "a throwing query is no reading")
check(logHas("RPRuleset (2): ERROR"), "and said")
rawset(_G, "C_GameRules", nil)
rawset(Enum, "GameRule", nil)
WoW.realm = "Doomhowl"

-- GlassPanel's Layer block.
fp("layer block")
-- (Layer is retired by #171: then the probe says so instead.)
check(logHas("Layer block shows: ") or logHas("Layer block: not loaded"), "the block's text read, or its absence said")

-- A guild addon message: our own echo whole, others by shape only.
WoW.guild.inGuild = true
fp("layer ping")
eq(sent[1] and sent[1][3], "GUILD", "one GUILD addon message sent")
eq(sent[1] and sent[1][1], "LayerProbe", "on our own prefix")
local token = sent[1] and sent[1][2]
check(type(token) == "string" and token:find("^ping:"), "a random token, not a bare ping")
-- Another guild member running the probe sends a ping too: never taken for ours (Codex on #170).
WoW.fire("CHAT_MSG_ADDON", "LayerProbe", "ping", "GUILD", "Other Prober-")
WoW.fire("CHAT_MSG_ADDON", "LayerProbe", "ping:1:2", "GUILD", "Other Prober-")
eq(T.ownEcho(), nil, "someone else's ping isn't our echo")
eq(logHas("Other Prober"), nil, "and their name isn't logged")
WoW.fire("CHAT_MSG_ADDON", "LayerProbe", token, "GUILD", "Karuzo Elegia-")
check(logHas("own GUILD echo: sender \"Karuzo Elegia-\" (str14, '-' at 14, after it BLANK)"), "our echo, whole, its realm part blank")
check(logHas("the sender's name part \"Karuzo Elegia\""), "its name part said")
eq(T.ownEcho(), "Karuzo Elegia-", "kept for the procedure")
eq(T.pending(), nil, "the ping is answered")
local before = #LayerProbeDB.log
WoW.fire("CHAT_MSG_ADDON", "LayerProbe", token, "GUILD", "Karuzo Elegia-")
check(LayerProbeDB.log[before + 1] and LayerProbeDB.log[before + 1]:find("after it BLANK", 1, true)
      and not LayerProbeDB.log[before + 1]:find("Karuzo", 1, true), "the token again after the echo: shape only")
WoW.fire("CHAT_MSG_ADDON", "NovaWorldBuffs", "x", "GUILD", "Someone Else-Realm7")
check(logHas("GUILD addon message, prefix \"NovaWorldBuffs\": sender str19, '-' at 13, after it str6"), "another sender: shape")
eq(logHas("Someone"), nil, "never their name")
WoW.fire("CHAT_MSG_ADDON", "NovaWorldBuffs", "x", "WHISPER", "Someone Else-Realm7")
eq(T.senderShape(WoW.Secret("sender")), "<secret>", "a secret sender: not touched")
WoW.guild.inGuild = false
eq(T.ping(), false, "not in a guild: no send")

-- SHARD_TRANSFER: logged, and the units read again 2, 5 and 12 s later.
WoW.fire("SHARD_TRANSFER")
check(logHas("SHARD_TRANSFER #1"), "the transfer is logged")
WoW.units.target = { guid = "Creature-0-6000-0-76001-5624-0000000009" }
WoW.units.nameplate1, WoW.units.nameplate2, WoW.units.nameplate3 = nil, nil, nil
WoW.flushTimers(12)
check(logHas("(+2 s after SHARD_TRANSFER)") and logHas("(+12 s after SHARD_TRANSFER)"), "read again after it")

-- The procedure is defined; nothing went to chat.
fp("steps")
eq(#WoW.chat, 0, "never writes to chat")

done("test_layerprobe")
