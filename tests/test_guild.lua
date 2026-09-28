-- The Guild plugin (#18).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tip()
    local b = block("guild").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end

local function member(name, level, zone, online, classFile, status)
    return { name = name, level = level, zone = zone, online = online, classFile = classFile, status = status }
end

WoW.guild.members = {
    member("Anna Smith-Forever", 40, "Stormwind City", true, "MAGE"),
    member("Bob", 60, "Ironforge", true, "WARRIOR", 1),
    member("Cora", 12, "Elwynn Forest", false, "PRIEST"),
    member("Dain Oakheart", 60, nil, true, "PRIEST", 2),
}
WoW.guild.total = 148

loadAddon()
eq(textOf("guild"), "3/148", "online/total")
eq(WoW.guildRequests, 1, "roster requested at login")

-- Tooltip: guild name, online members only, level desc then name, class
-- colours, AFK/DND tags, zone ("" when not known yet), Ambiguate'd names
-- with their spaces kept.
local t = tip()
check(t:find("^Forever Friends\n"), "guild name header")
check(t:find("Online\t3 of 148", 1, true), "count line")
local bob = t:find("|cff888888" .. "60|r |cffc79c6eBob|r |cffffd200<AFK>|r\tIronforge", 1, true)
local dain = t:find("|cff88888860|r |cffffffffDain Oakheart|r |cffff4040<DND>|r\t", 1, true)
local anna = t:find("|cff88888840|r |cff40c7ebAnna Smith|r\tStormwind City", 1, true)
check(bob and dain and anna and bob < dain and dain < anna, "sorted rows with colours and tags")
check(not t:find("Cora", 1, true), "offline members not listed")
check(t:find("Left-click: open the guild panel", 1, true), "click hint")
eq(WoW.guildRequests, 1, "tooltip within 15 s doesn't request again")

-- Throttling: the tooltip asks again after 15 s, the background after 90 s.
WoW.now = WoW.now + 16
tip()
eq(WoW.guildRequests, 2, "tooltip requests after 15 s")
tip()
eq(WoW.guildRequests, 2, "but not twice in a row")
WoW.fire("GUILD_ROSTER_UPDATE", true); WoW.tick()
eq(WoW.guildRequests, 2, "the answer doesn't ask again")
WoW.now = WoW.now + 91
WoW.fireTickers()
eq(WoW.guildRequests, 3, "periodic refresh after 90 s (a ticker while on screen)")
for _ = 1, 10 do WoW.tick() end
eq(WoW.guildRequests, 3, "never per frame, and not from drawing the text")
-- Hidden: the ticker stops, so no more background requests.
GlassPanel._test.slash("hide guild")
WoW.now = WoW.now + 91
WoW.fireTickers()
eq(WoW.guildRequests, 3, "no background requests while hidden")
GlassPanel._test.slash("show guild")

-- The roster is scanned lazily: once per tooltip open after it changed.
tip()
WoW.guild.members[3].online = true
check(not tip():find("Cora", 1, true), "no rescan without a roster event")
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
check(tip():find("|cff88888812|r |cffffffffCora|r\tElwynn Forest", 1, true), "rescanned after the event")
eq(textOf("guild"), "4/148", "count follows")

-- More than 30 online: capped with "+N more online".
local many = {}
for i = 1, 35 do many[i] = member("M" .. string.format("%02d", i), 10, "Zone", true, "MAGE") end
WoW.guild.members, WoW.guild.total = many, 40
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
t = tip()
check(t:find("M30", 1, true) and not t:find("M31", 1, true), "30 rows")
check(t:find("+5 more online", 1, true), "overflow line")

-- Secret member fields: "?" for name and zone, a secret level sorts last.
WoW.guild.members = {
    member("secret", 50, "secret", true, "WARRIOR"),
    member("Eve", "secret", "Darnassus", true, "MAGE"),
    member("Finn", 5, "Teldrassil", true, "secret"),
    member("Ghost", 5, "Nowhere", "secret", "MAGE"),
}
WoW.guild.total = 4
WoW.guild.online = 4   -- the count says four online: one of them is the unreadable one
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
t = tip()
WoW.guild.online = nil
local q = t:find("|cff88888850|r |cffc79c6e?|r\t?", 1, true)
local finn = t:find("|cff8888885|r Finn\tTeldrassil", 1, true)
local eve = t:find("|cff888888?|r |cff40c7ebEve|r\tDarnassus", 1, true)
check(q and finn and eve and q < finn and finn < eve, "secret name/zone as ?, secret level last")
check(t:find("1 member(s) can't be read", 1, true), "unreadable member noted")

-- Secret counts: grey "?", not a guess.
WoW.guild.online = "secret"
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
eq(textOf("guild"), "|cff888888?|r", "secret count: ?")
check(tip():find("can't be read right now", 1, true), "tooltip says so")
WoW.guild.online = nil
-- A client secret keeps its type: a secret number still passes type() ==
-- "number", so only API.Plain catches it.
WoW.guild.total = 777
WoW.MarkSecret(777, "guild.total")
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
eq(textOf("guild"), "|cff888888?|r", "secret total of type number: ?")
WoW.guild.total = 4

-- Left-click opens the guild panel; other buttons don't.
local b = block("guild").widget
b._scripts.OnClick(b, "LeftButton"); b._scripts.OnClick(b, "RightButton")
eq(WoW.guildToggles, 1, "left-click opens the guild panel")

-- Not in a guild: hidden, and no roster requests.
WoW.guild.inGuild = false
local before = WoW.guildRequests
WoW.now = WoW.now + 200
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(block("guild").widget._shown, false, "no guild: hidden")
eq(WoW.guildRequests, before, "no requests outside a guild")

-- IsInGuild itself secret: "?", not hidden.
WoW.guild.inGuild = "secret"
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(textOf("guild"), "|cff888888?|r", "secret guild state: ?")

-- The caption is the guild's name (owner request), re-read on each repaint.
WoW.guild.inGuild, WoW.guild.name = true, "Forever Friends"
loadAddon()
eq(block("guild").widget.caption._text, "Forever Friends: ", "caption: the guild's name")
WoW.guild.name = "Olympus"
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(block("guild").widget.caption._text, "Olympus: ", "follows a rename without a count change")
WoW.guild.name = "secret"
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(block("guild").widget.caption._text, "Guild: ", "unreadable name: falls back to the label")
WoW.MarkSecret("Hidden Guild")   -- a client secret keeps its type: a string
WoW.guild.name = "Hidden Guild"
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(block("guild").widget.caption._text, "Guild: ", "a secret string name isn't shown")
WoW.guild.name = "Forever Friends"
GlassPanel._test.slash("label guild off")
eq(block("guild").widget.caption._text, "", "the label switch still applies")
GlassPanel._test.slash("label guild default")
check(GlassPanel.RegisterBlock({ id = "badcap", text = function() end, caption = "x" }) == nil,
      "caption must be a function")
-- The bar itself refuses a secret caption (defence in depth for any plugin).
WoW.MarkSecret("Leaky")
GlassPanel.RegisterBlock({ id = "leaky", label = "Leaky Label", text = function() return "1" end,
                           caption = function() return "Leaky" end })
WoW.tick()
eq(block("leaky").widget.caption._text, "Leaky Label: ", "a secret caption falls back to the label")

-- Review round (#28).
-- At login the roster hasn't arrived: GetNumGuildMembers says 0, 0. That's
-- unknown, not "0/0".
WoW.guild = { inGuild = true, name = "Forever Friends", members = {}, total = 0, online = 0 }
loadAddon()
eq(textOf("guild"), "|cff888888?|r", "no roster yet: ?, not 0/0")
WoW.guild.total, WoW.guild.online = nil, nil
-- A new guild asks for its roster at once, whatever the old one's throttle.
WoW.guild.members = { member("Ann", 10, "Elwynn", true, "MAGE") }
WoW.fire("GUILD_ROSTER_UPDATE", true); WoW.tick()
local before = WoW.guildRequests
WoW.fire("PLAYER_GUILD_UPDATE", "player"); WoW.tick()
eq(WoW.guildRequests, before + 1, "joined/changed guild: roster requested now")
-- Other units' guild updates are ignored.
before = WoW.guildRequests
WoW.now = WoW.now + 60
WoW.fire("PLAYER_GUILD_UPDATE", "party1"); WoW.tick()
eq(WoW.guildRequests, before, "a party member's guild update: ignored")
-- A big guild: the scan stops once every online member is found.
local big = {}
for n = 1, 500 do big[n] = member("M" .. n, 10, "Zone", n <= 3, "MAGE") end
WoW.guild.members = big
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
WoW.rosterReads = 0
tip()
check(WoW.rosterReads <= 3, "3 online of 500: 3 reads, not 500 (" .. WoW.rosterReads .. ")")
-- An open tooltip redraws when the roster answer arrives.
local gb = block("guild").widget
gb._scripts.OnEnter(gb); GameTooltip._shown = true
big[4].online = true
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
check(table.concat(GameTooltip._lines, "\n"):find("Online\t4 of 500", 1, true), "tooltip redrawn with the new roster")
GameTooltip._shown = false

-- Unreadable members don't count towards the early stop: two unreadable
-- (really offline) rows before the only online member must not end the scan.
WoW.guild.members = {
    member("Ghost1", 5, "Nowhere", "secret", "MAGE"),
    member("Ghost2", 5, "Nowhere", "secret", "MAGE"),
    member("Real", 40, "Stormwind", true, "PRIEST"),
}
WoW.guild.total, WoW.guild.online = 3, 1
WoW.fire("GUILD_ROSTER_UPDATE", false); WoW.tick()
check(tip():find("Real", 1, true), "the online member after unreadable rows is found")
WoW.guild.total, WoW.guild.online = nil, nil

check(next(GlassPanel.failures) == nil, "no failures")
done("test_guild")
