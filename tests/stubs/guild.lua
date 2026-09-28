-- Guild stubs (Plugins/Guild). WoW.guild = { inGuild, name, total, online,
-- members = { { name, level, zone, online, status, classFile }, ... } };
-- total / online default to the members' counts. A field set to "secret"
-- comes back secret. WoW.guildRequests counts roster requests (at WoW.now
-- times, in WoW.guildRequestTimes); WoW.guildToggles counts panel opens.
table.insert(WoW.resetHooks, function()
    WoW.guild = { inGuild = true, name = "Forever Friends", members = {} }
    WoW.guildRequests, WoW.guildRequestTimes = 0, {}
    WoW.guildToggles = 0
end)

local function secretOr(v, label)
    if v == "secret" then return WoW.Secret("guild." .. label) end
    return v
end

function IsInGuild() return secretOr(WoW.guild.inGuild, "inGuild") end

-- total, online, onlineAndMobile (Retail shape).
function GetNumGuildMembers()
    local g = WoW.guild
    if g.inGuild ~= true then return 0, 0, 0 end
    local online = 0
    for _, m in ipairs(g.members) do if m.online == true then online = online + 1 end end
    local total = g.total or #g.members
    online = g.online or online
    return secretOr(total, "total"), secretOr(online, "online"), secretOr(online, "online")
end

-- name, rankName, rankIndex, level, classDisplayName, zone, publicNote,
-- officerNote, isOnline, status, classFile, achievementPoints,
-- achievementRank, isMobile, canSoR, repStanding, guid (Retail shape).
function GetGuildRosterInfo(i)
    local m = WoW.guild.members[i]
    if not m then return nil end
    local function f(k) return secretOr(m[k], "member." .. k) end
    return f("name"), "Member", 2, f("level"), m.classFile, f("zone"), "", "",
        f("online"), f("status") or 0, f("classFile"), 0, 0, false, false, 4, "Player-1-" .. i
end

-- guildName, guildRankName, guildRankIndex, realm.
function GetGuildInfo(unit)
    if WoW.guild.inGuild ~= true then return nil end
    return secretOr(WoW.guild.name, "name"), "Member", 2, nil
end

C_GuildInfo = { GuildRoster = function()
    WoW.guildRequests = WoW.guildRequests + 1
    table.insert(WoW.guildRequestTimes, WoW.now)
end }

function ToggleGuildFrame() WoW.guildToggles = WoW.guildToggles + 1 end

-- Ambiguate and C_ClassColor come from wow_stubs.lua (shared by several plugins).
