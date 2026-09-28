-- Role stubs (Plugins/Role). WoW.group = { inGroup, role }; a field set to
-- "secret" comes back secret. WoW.roleSets records UnitSetRole calls; WoW.roleSetFails
-- = "false" makes it refuse, "error" makes it throw. WoW.menu is the last
-- context menu: { owner, radios = { { text, isSelected, setSelected, data } } }.
table.insert(WoW.resetHooks, function()
    WoW.group = { inGroup = false, role = "NONE" }
    WoW.roleSets = {}
    WoW.roleSetFails = nil
    WoW.menu = nil
end)

function IsInGroup(groupType)
    if WoW.group.inGroup == "secret" then return WoW.Secret("group.inGroup") end
    return WoW.group.inGroup
end
function UnitGroupRolesAssigned(unit)
    if WoW.group.role == "secret" then return WoW.Secret("group.role") end
    return WoW.group.role
end
function UnitSetRole(unit, roleStr)
    table.insert(WoW.roleSets, { unit, roleStr })
    if WoW.roleSetFails == "error" then error("role change blocked") end
    if WoW.roleSetFails == "false" then return false end
    WoW.group.role = roleStr
    return true
end

-- Just enough of Blizzard's menu: the generator runs against a root that
-- records its radio items, so a test can click one (setSelected(data)).
MenuUtil = { CreateContextMenu = function(owner, generator)
    local root = { radios = {} }
    function root:CreateRadio(text, isSelected, setSelected, data)
        table.insert(self.radios, { text = text, isSelected = isSelected, setSelected = setSelected, data = data })
    end
    generator(owner, root)
    WoW.menu = { owner = owner, radios = root.radios }
end }
