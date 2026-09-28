-- Plugins/Role/Role.lua: your group role (#20), with its icon, shown only
-- while you're in a group. Left-click opens a small menu to set it: the same
-- choices as the party frame's "Set Role" (Tank, Healer, Damage, No Role).
--
-- Forever (70009 dump): UnitGroupRolesAssigned (cstring: "TANK", "HEALER",
-- "DAMAGER", "NONE"), UnitSetRole(unit, roleStr) -> bool, IsInGroup (walk
-- only). MenuUtil is in the walk (its functions aren't listed): the menu is
-- built under pcall and, when it can't be, a click cycles the role instead.
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
for _, r in ipairs(ROLES) do byRole[r.role] = r end

local function name(r)
    local s = rawget(_G, r.global)
    return type(s) == "string" and s or r.name
end

local function icon(r)
    local c = r.coords
    if not c then return "" end
    return string.format("|T%s:14:14:0:0:64:64:%d:%d:%d:%d|t ", ICON, c[1], c[2], c[3], c[4])
end

-- The player's role entry, or nil when it can't be read.
local function current()
    local role = P(UnitGroupRolesAssigned("player"))
    return type(role) == "string" and byRole[role] or nil
end

local function inGroup() return P(IsInGroup()) == true end

local function setRole(role)
    local ok, res = pcall(UnitSetRole, "player", role)
    if not ok then API.Fail("role:set", res) end
    if not ok or P(res) == false then
        API.Print("couldn't set your role to " .. name(byRole[role]) ..
            " (the client refused: role changes may be restricted in combat or by the group leader).")
    end
    GlassPanel.Refresh("role")
end

-- The fallback when no menu can be shown: the next role in menu order.
local function cycle()
    local now, i = current(), 0
    for n, r in ipairs(ROLES) do if r == now then i = n end end
    setRole(ROLES[i % #ROLES + 1].role)
end

local function isSelected(role)
    local now = current()
    return now ~= nil and now.role == role
end

local function openMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    local ok, err = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        for _, r in ipairs(ROLES) do
            root:CreateRadio(icon(r) .. name(r), isSelected, setRole, r.role)
        end
    end)
    if not ok then API.Fail("role:menu", err) end
    return ok
end

GlassPanel.RegisterBlock({
    id = "role",
    label = "Role",
    side = "right",
    order = 140,
    events = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" },
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
        tt:AddLine("Left-click: set your role", 0.3, 1, 0.3)
    end,
    onClick = function(block, button)
        if button ~= "LeftButton" then return end
        if not openMenu(block.widget) then cycle() end
    end,
})
