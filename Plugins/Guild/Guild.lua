-- Plugins/Guild/Guild.lua: guild members online out of the total (#18),
-- like Titan's "Guild: 12/148", with who is online in the tooltip.
-- Left-click opens the guild panel. Hidden when you're not in a guild.
--
-- Forever (70009 dump):
-- - IsInGuild() -> bool; GetGuildInfo("player") (global walk only): the
--   guild name first, as on Retail.
-- - GetNumGuildMembers / GetGuildRosterInfo are in the global walk only (no
--   signature). Retail shapes: total, online = GetNumGuildMembers() and
--   name, rank, rankIndex, level, class, zone, note, officerNote, isOnline,
--   status (1 AFK, 2 DND), classFile, ... = GetGuildRosterInfo(i). To be
--   confirmed in game.
-- - The roster is only as fresh as the last C_GuildInfo.GuildRoster()
--   request (the global GuildRoster is absent). We request at login, on
--   opening the tooltip (at most every 15 s) and every 90 s while the block
--   repaints; GUILD_ROSTER_UPDATE answers. Never per frame.
-- - Names: Ambiguate(name, "guild") drops the realm. Forever characters have
--   surnames with spaces, so a name is never split on spaces.
-- - Every read through API.Plain: a secret name or zone shows as "?", a
--   secret level sorts last, unreadable counts show a grey "?".
-- - The roster scan is the tooltip's only: events mark it stale, and it is
--   rebuilt at most once per tooltip open. The bar text needs one call.

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

local MAX_ROWS = 30
local TOOLTIP_REQUEST = 15   -- seconds between roster requests from the tooltip
local REFRESH = 90           -- seconds between background roster requests

local lastRequest   -- GetTime() of the last roster request, nil before the first
local ticker        -- the background refresh while the block is on screen
local roster = { members = {}, unreadable = 0 }   -- online members, sorted
local stale = true

local function now() return P(GetTime()) or 0 end

-- Ask the server for a fresh roster, unless we asked less than minAge
-- seconds ago. The answer is a GUILD_ROSTER_UPDATE.
local function request(minAge)
    if lastRequest and now() - lastRequest < minAge then return end
    if not (C_GuildInfo and C_GuildInfo.GuildRoster) then return end
    lastRequest = now()
    local ok, err = pcall(C_GuildInfo.GuildRoster)
    if not ok then API.Fail("guild:request", err) end
end

-- true / false / nil (can't be read).
local function inGuild()
    local raw = IsInGuild()
    if API.IsSecret(raw) then return nil end
    return raw == true
end

-- online, total: plain numbers, or nil when unreadable.
local function counts()
    local total, online = GetNumGuildMembers()
    total, online = P(total), P(online)
    if type(total) ~= "number" or type(online) ~= "number" then return nil end
    -- In a guild the total is at least 1: 0 means the roster hasn't arrived
    -- yet (at login), so unknown, not "0/0".
    if total <= 0 then return nil end
    return online, total
end

-- "|cffrrggbb" for a class file ("WARRIOR"), or nil.
local function classColour(classFile)
    if not (classFile and C_ClassColor and C_ClassColor.GetClassColor) then return nil end
    local ok, c = pcall(C_ClassColor.GetClassColor, classFile)
    c = ok and P(c) or nil
    if type(c) ~= "table" then return nil end
    local r, g, b = P(c.r), P(c.g), P(c.b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(r), byte(g), byte(b))
end

local function displayName(raw)
    local name = P(raw)
    if type(name) ~= "string" then return "?" end
    local ok, short = pcall(Ambiguate, name, "guild")
    short = ok and P(short) or nil
    return type(short) == "string" and short or name
end

local function scan()
    local members, unreadable = {}, 0
    local onlineCount, total = counts()
    for i = 1, total or 0 do
        -- Every online member found: the rest are offline (a big guild would
        -- otherwise cost one call per member per hover). Only READABLE online
        -- members count: an unreadable one may be offline, so counting it
        -- could stop before a real online member (Codex review).
        if onlineCount and #members >= onlineCount then break end
        local name, _, _, level, _, rawZone, _, _, isOnline, status, classFile = GetGuildRosterInfo(i)
        local online = P(isOnline)
        if online == true then
            local zone
            level, zone, status, classFile = P(level), P(rawZone), P(status), P(classFile)
            members[#members + 1] = {
                name = displayName(name),
                level = type(level) == "number" and level or nil,
                -- No zone yet right after login: blank; a secret one: "?".
                zone = type(zone) == "string" and zone or (API.Returned(rawZone) and "?" or ""),
                status = status,
                colour = classColour(type(classFile) == "string" and classFile or nil),
            }
        elseif online == nil and API.Returned(isOnline) then
            unreadable = unreadable + 1
        end
    end
    -- Level high to low (an unreadable level last), then name.
    table.sort(members, function(a, b)
        if a.level ~= b.level then
            if not a.level then return false end
            if not b.level then return true end
            return a.level > b.level
        end
        return a.name < b.name
    end)
    roster.members, roster.unreadable = members, unreadable
end

-- A scan that throws leaves the roster stale (tried again next time) and is
-- recorded, rather than leaving an old roster marked fresh.
local function ensure()
    if not stale then return end
    local ok, err = pcall(scan)
    if ok then stale = false else API.Fail("guild:scan", err) end
end

local TAGS = { [1] = " |cffffd200<AFK>|r", [2] = " |cffff4040<DND>|r" }

GlassPanel.RegisterBlock({
    id = "guild",
    label = "Guild",
    icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
    side = "right",
    order = 170,
    events = { "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE" },
    -- The caption is the guild's name ("Olympus: 12/148"); "Guild" when
    -- there's none or it can't be read.
    caption = function()
        if not inGuild() then return nil end
        local name = P((GetGuildInfo("player")))
        return type(name) == "string" and name or nil
    end,
    -- PLAYER_GUILD_UPDATE carries a unit: only the player's own guild matters.
    unitEvents = { PLAYER_GUILD_UPDATE = "player" },
    onEvent = function(_, event)
        stale = true
        if event == "PLAYER_GUILD_UPDATE" then
            lastRequest = nil   -- a new guild: its roster now, not after the old one's throttle
        end
        if event ~= "GUILD_ROSTER_UPDATE" and inGuild() then request(TOOLTIP_REQUEST) end
    end,
    -- The background refresh runs only while the block is on screen: a
    -- ticker started and stopped with it, not a side effect of drawing.
    onShown = function(_, visible)
        if ticker then ticker:Cancel(); ticker = nil end
        if visible and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(REFRESH, function() if inGuild() then request(REFRESH) end end)
        end
    end,
    text = function()
        local g = inGuild()
        if g == false then return nil end
        -- The background refresh: a repaint at least every REFRESH seconds.
        local online, total = counts()
        if not (g and online) then return "|cff888888?|r" end
        return online .. "/" .. total
    end,
    tooltip = function(_, tt)
        local g = inGuild()
        if g then request(TOOLTIP_REQUEST) end
        local guildName = g and P((GetGuildInfo("player")))
        tt:AddLine(type(guildName) == "string" and guildName or "Guild")
        if g == false then
            tt:AddLine("You are not in a guild.", 0.7, 0.7, 0.7)
            return
        end
        local online, total = counts()
        if not (g and online) then
            tt:AddLine("Your guild roster can't be read right now.", 0.7, 0.7, 0.7, true)
        else
            ensure()
            tt:AddDoubleLine("Online", online .. " of " .. total, 1, 0.82, 0, 1, 1, 1)
            local list = roster.members
            for i = 1, math.min(#list, MAX_ROWS) do
                local m = list[i]
                local left = "|cff888888" .. (m.level or "?") .. "|r "
                    .. (m.colour and (m.colour .. m.name .. "|r") or m.name)
                    .. (TAGS[m.status] or "")
                tt:AddDoubleLine(left, m.zone, 1, 1, 1, 0.5, 0.8, 0.8)
            end
            if #list > MAX_ROWS then
                tt:AddLine("+" .. (#list - MAX_ROWS) .. " more online", 0.7, 0.7, 0.7)
            end
            if roster.unreadable > 0 then
                tt:AddLine(roster.unreadable .. " member(s) can't be read right now.", 0.7, 0.7, 0.7, true)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("Left-click: open the guild panel", 0.3, 1, 0.3)
    end,
    onClick = function(_, button)
        if button ~= "LeftButton" then return end
        local toggle = rawget(_G, "ToggleGuildFrame") or rawget(_G, "ToggleCommunitiesFrame")
        if not toggle then return end
        local ok, err = pcall(toggle)
        if not ok then API.Fail("guild:click", err) end
    end,
})
