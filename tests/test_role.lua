-- The Role plugin (#20).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function tip()
    local b = block("role").widget
    b._scripts.OnEnter(b)
    return table.concat(GameTooltip._lines, "\n")
end
local function click(button)
    local b = block("role").widget
    b._scripts.OnClick(b, button)
end
local function roster() WoW.fire("GROUP_ROSTER_UPDATE"); WoW.tick() end

local TANK = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:0:19:22:41|t Tank"
local HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:1:20|t Healer"
local DAMAGE = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:14:14:0:0:64:64:20:39:22:41|t Damage"

-- Solo: not on the bar.
loadAddon()
eq(block("role").widget._shown, false, "hidden when not in a group")

WoW.group.inGroup = true
roster()
eq(textOf("role"), "No Role", "in a group, no role")
check(tip():find("haven't set a group role", 1, true), "tooltip: no role")

WoW.group.role = "HEALER"
WoW.fire("PLAYER_ROLES_ASSIGNED"); WoW.tick()
eq(textOf("role"), HEALER, "healer, with its icon")
check(tip():find("Your group role\t" .. HEALER, 1, true), "tooltip: role")

-- The client's localized name wins over the English fallback.
DAMAGER = "Schaden"
WoW.group.role = "DAMAGER"
WoW.fire("ROLE_CHANGED_INFORM", "Me", "Me", "HEALER", "DAMAGER"); WoW.tick()
eq(textOf("role"), (DAMAGE:gsub("Damage$", "Schaden")), "localized name")
DAMAGER = nil

-- Left-click opens the menu: the four roles, the current one checked.
WoW.group.role = "TANK"
roster()
eq(textOf("role"), TANK, "tank")
click("RightButton")
eq(WoW.menu, nil, "right-click does nothing")
click("LeftButton")
check(WoW.menu ~= nil, "left-click opens the menu")
eq(WoW.menu and WoW.menu.owner, block("role").widget, "anchored to the block")
local radios = WoW.menu and WoW.menu.radios or {}
eq(#radios, 4, "four choices")
local want = { { TANK, "TANK" }, { HEALER, "HEALER" }, { DAMAGE, "DAMAGER" }, { "No Role", "NONE" } }
for i, w in ipairs(want) do
    local r = radios[i] or {}
    eq(r.text, w[1], "item " .. i .. " text")
    eq(r.data, w[2], "item " .. i .. " role")
    eq(r.isSelected and r.isSelected(r.data), w[2] == "TANK", "item " .. i .. " checked")
end
eq(#WoW.roleSets, 0, "opening the menu sets nothing")

-- Choosing an item asks for the role; the bar shows it once the server
-- confirms (ROLE_CHANGED_INFORM), never before.
radios[2].setSelected(radios[2].data)
eq(#WoW.roleSets, 1, "one UnitSetRole")
eq(WoW.roleSets[1][1], "player", "for the player")
eq(WoW.roleSets[1][2], "HEALER", "to healer")
WoW.tick()
eq(textOf("role"), TANK, "not shown before the server confirms")
-- Meanwhile the menu checks the role asked for, not the stale one.
WoW.menu = nil
click("LeftButton")
eq(WoW.menu.radios[2].isSelected("HEALER"), true, "pending role checked")
eq(WoW.menu.radios[1].isSelected("TANK"), false, "stale role unchecked")
WoW.confirmRole(); WoW.tick()
eq(textOf("role"), HEALER, "repainted on confirmation")
eq(#WoW.chat, 0, "nothing printed on success")

-- Refused: one line in chat, the role unchanged.
WoW.roleSetFails = "false"
radios[4].setSelected(radios[4].data)
WoW.tick()
eq(textOf("role"), HEALER, "unchanged when refused")
eq(#WoW.chat, 1, "one line printed")
check((WoW.chat[1] or ""):find("couldn't set your role to No Role", 1, true), "explains")
WoW.roleSetFails = nil

-- Secret role: a grey ?, not a guess; nothing checked in the menu.
WoW.group.role = "secret"
roster()
eq(textOf("role"), "|cff888888?|r", "secret: ?")
check(tip():find("can't be read", 1, true), "tooltip says so")
WoW.menu = nil
click("LeftButton")
for i, r in ipairs(WoW.menu.radios) do eq(r.isSelected(r.data), false, "secret: item " .. i .. " unchecked") end

-- Leaving the group hides it.
WoW.group.role, WoW.group.inGroup = "NONE", false
roster()
eq(block("role").widget._shown, false, "hidden after leaving")

-- Whether we're in a group can't be read: treated as not (hidden).
WoW.group.inGroup = "secret"
roster()
eq(block("role").widget._shown, false, "secret group state: hidden")

check(next(GlassPanel.failures) == nil, "no failures")

-- No menu at all: a click cycles Tank -> Healer -> Damage -> No Role -> Tank,
-- each step from the one just asked for (no server answer in between).
WoW.group.inGroup = true
roster()
local menu = MenuUtil.CreateContextMenu
MenuUtil.CreateContextMenu = nil
check(tip():find("Left-click: next role", 1, true), "tooltip says a click cycles")
WoW.roleSets = {}
for _ = 1, 5 do click("LeftButton") end
local seq = {}
for _, s in ipairs(WoW.roleSets) do seq[#seq + 1] = s[2] end
eq(table.concat(seq, ","), "TANK,HEALER,DAMAGER,NONE,TANK", "cycles without a menu")
-- The server answers: its role is the truth again.
WoW.group.pendingRole = "DAMAGER"
WoW.confirmRole(); WoW.tick()
WoW.roleSets = {}
click("LeftButton")
eq(WoW.roleSets[1] and WoW.roleSets[1][2], "NONE", "next from the confirmed role")
WoW.confirmRole(); WoW.tick()
-- An unanswered request is forgotten after a while.
WoW.group.role = "TANK"
WoW.roleSets = {}
click("LeftButton")                       -- asks HEALER; the server never answers
WoW.now = WoW.now + 6; WoW.tick()
click("LeftButton")
eq(WoW.roleSets[2] and WoW.roleSets[2][2], "HEALER", "stale request forgotten: from the live role")
WoW.confirmRole(); WoW.tick()
-- An unreadable role is never overwritten blindly.
WoW.group.role = "secret"
roster()
WoW.roleSets, WoW.chat = {}, {}
click("LeftButton")
eq(#WoW.roleSets, 0, "unreadable role: nothing set")
check((WoW.chat[1] or ""):find("can't be read", 1, true), "unreadable role: says why")
WoW.group.role = "NONE"
roster()
MenuUtil.CreateContextMenu = menu
check(tip():find("Left-click: set your role", 1, true), "tooltip with a menu")

-- A menu that throws is recorded and explained, and changes nothing.
MenuUtil.CreateContextMenu = function() error("menu broke") end
WoW.roleSets, WoW.chat = {}, {}
click("LeftButton")
MenuUtil.CreateContextMenu = menu
eq(#WoW.roleSets, 0, "menu error: role untouched")
check(GlassPanel.failures["role:menu"] ~= nil, "menu error recorded")
check((WoW.chat[1] or ""):find("role menu couldn't open", 1, true), "menu error explained")

-- UnitSetRole throwing: recorded and explained.
WoW.roleSetFails = "error"
WoW.chat = {}
click("LeftButton")
WoW.menu.radios[1].setSelected(WoW.menu.radios[1].data)
check(GlassPanel.failures["role:set"] ~= nil, "set error recorded")
eq(#WoW.chat, 1, "set error explained")

done("test_role")
