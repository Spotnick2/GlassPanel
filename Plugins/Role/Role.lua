-- Plugins/Role/Role.lua: your group role (#20), with its icon, shown only
-- while you're in a group. Left-click opens a small menu to set it: the same
-- choices as the party frame's "Set Role" (Tank, Healer, Damage, No Role).
--
-- Forever (70009 dump): UnitGroupRolesAssigned (cstring: "TANK", "HEALER",
-- "DAMAGER", "NONE"), UnitSetRole(unit, roleStr) -> bool, IsInGroup (walk
-- only). MenuUtil is in the walk (its functions aren't listed; EllesmereUI
-- on Forever calls MenuUtil.CreateContextMenu). The menu is built under
-- pcall: if it throws, the click only says so. Only a client with no
-- MenuUtil at all gets the fallback, a click that cycles the role.
-- Every read through API.Plain: an unreadable role shows a grey "?".

GlassPanel = GlassPanel or {}
local API = GlassPanel.API
local P = API.Plain

-- In menu order. The name is the client's localized string when it has one;
-- the icon is the standard role icon file, cut at these pixels (64x64).
local ICON = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLES = {
    { role = "TANK", global = "TANK", name = "Tank", coords = { 0, 19, 22, 41 } },
    { role = "HEALER", global = "HEALER", name = "Healer", coords = { 20, 39, 1, 20 } },
    { role = "DAMAGER", global = "DAMAGER", name = "Damage", coords = { 20, 39, 22, 41 } },
    { role = "NONE", global = "NO_ROLE", name = "No Role" },
}
local byRole = {}
for _, r in ipairs(ROLES) do
    byRole[r.role] = r
    -- Built once: the markup never changes.
    local c = r.coords
    r.markup = c and string.format("|T%s:14:14:0:0:64:64:%d:%d:%d:%d|t ", ICON, c[1], c[2], c[3], c[4]) or ""
end

local function name(r)
    local s = rawget(_G, r.global)
    return type(s) == "string" and s or r.name
end

local function icon(r) return r.markup end

-- The player's role entry, or nil when it can't be read.
local function current()
    local role = P(UnitGroupRolesAssigned("player"))
    return type(role) == "string" and byRole[role] or nil
end

local function inGroup() return P(IsInGroup()) == true end

-- A role we asked for and the server hasn't confirmed yet (UnitSetRole takes
-- effect with ROLE_CHANGED_INFORM / PLAYER_ROLES_ASSIGNED): the menu's check
-- and the fallback's next step go from it, so a quick second click doesn't
-- resend the same role. Forgotten after PENDING seconds.
local PENDING = 5
local pending, pendingAt

local function effective()
    if pending and GetTime() - pendingAt < PENDING then return byRole[pending] end
    pending = nil
    return current()
end

local function setRole(role)
    local ok, res = pcall(UnitSetRole, "player", role)
    if not ok then API.Fail("role:set", res) end
    if not ok or P(res) == false then
        API.Print("couldn't set your role to " .. name(byRole[role]) ..
            " (the client refused: role changes may be restricted in combat or by the group leader).")
        return
    end
    pending, pendingAt = role, GetTime()
    GlassPanel.Refresh("role")
end

-- The fallback when the client has no menu at all: the next role in menu
-- order. Never from an unreadable role (that would overwrite it blindly).
local function cycle()
    local now = effective()
    if not now then
        API.Print("Role: your role can't be read right now, so it isn't changed.")
        return
    end
    local i = 0
    for n, r in ipairs(ROLES) do if r == now then i = n end end
    setRole(ROLES[i % #ROLES + 1].role)
end

local function isSelected(role)
    local now = effective()
    return now ~= nil and now.role == role
end

local function hasMenu() return MenuUtil ~= nil and MenuUtil.CreateContextMenu ~= nil end

-- true when a menu opened. A menu that throws changes nothing (a role
-- switched without asking is worse than no menu): it's reported instead.
local function openMenu(owner)
    local ok, err = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        for _, r in ipairs(ROLES) do
            root:CreateRadio(icon(r) .. name(r), isSelected, setRole, r.role)
        end
    end)
    if not ok then
        API.Fail("role:menu", err)
        API.Print("Role: the role menu couldn't open (see /gpanel failures).")
    end
    return ok
end

GlassPanel.RegisterBlock({
    id = "role",
    label = "Role",
    side = "right",
    order = 140,
    events = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" },
    onEvent = function(_, event)
        -- The server answered: the live role is the truth again.
        if event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then pending = nil end
    end,
    text = function()
        if not inGroup() then return nil end
        local r = current()
        if not r then return "|cff888888?|r" end
        return icon(r) .. name(r)
    end,
    tooltip = function(_, tt)
        local r = current()
        tt:AddLine("Role")
        if not r then
            tt:AddLine("Your group role can't be read right now.", 0.7, 0.7, 0.7, true)
        elseif r.role == "NONE" then
            tt:AddLine("You haven't set a group role.", 0.7, 0.7, 0.7)
        else
            tt:AddDoubleLine("Your group role", icon(r) .. name(r), 1, 0.82, 0, 1, 1, 1)
        end
        tt:AddLine(" ")
        tt:AddLine(hasMenu() and "Left-click: set your role" or "Left-click: next role", 0.3, 1, 0.3)
    end,
    onClick = function(block, button)
        if button ~= "LeftButton" then return end
        if hasMenu() then openMenu(block.widget) else cycle() end
    end,
})
