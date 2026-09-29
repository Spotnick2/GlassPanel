-- Opt-in Edit Mode layout for a full-width bar (#10).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")
PLUGINS = { "GlassPanelGold" }

local T = Enum.EditModeLayoutType
local S = Enum.EditModeSystem
local function anchor(point, x, y, rel)
    return { point = point, relativeTo = rel or "UIParent", relativePoint = point, offsetX = x, offsetY = y }
end
-- The Modern preset's four watched systems, as in Mainline/EditModePresetLayouts.lua.
local function modernSystems()
    return {
        { system = S.Minimap, anchorInfo = anchor("TOPRIGHT", 0, 0), settings = {}, isInDefaultPosition = true },
        { system = S.AuraFrame, systemIndex = 1, anchorInfo = anchor("TOPRIGHT", -255, -10), settings = {},
          isInDefaultPosition = true },
        { system = S.AuraFrame, systemIndex = 2, anchorInfo = anchor("TOPRIGHT", -270, -155), settings = {},
          isInDefaultPosition = true },
        { system = S.DamageMeter, anchorInfo = anchor("TOPLEFT", 0, 0), settings = {}, isInDefaultPosition = true },
        { system = 0, systemIndex = 1, anchorInfo = anchor("BOTTOM", 0, 45), settings = {}, isInDefaultPosition = true },
    }
end
local function presets()
    return {
        { layoutIndex = 0, layoutName = "Modern", layoutType = T.Preset, interfaceStyle = 0, systems = modernSystems() },
        { layoutIndex = 1, layoutName = "Classic", layoutType = T.Preset, interfaceStyle = 0, systems = modernSystems() },
        { layoutIndex = 2, layoutName = "Gamepad", layoutType = T.Preset, interfaceStyle = 1, systems = modernSystems() },
    }
end
local function saved(name, layoutType, systems, style)
    return { layoutName = name, layoutType = layoutType, interfaceStyle = style, systems = systems or modernSystems() }
end
local em
local function session(savedLayouts, active)
    WoW.editMode.presets = presets()
    WoW.editMode.saved = { layouts = savedLayouts or {}, activeLayout = active or 1 }
    WoW.editMode.calls = {}
    WoW.units.player = { guid = "Player-1-0001" }
    em = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
    em._shown = false
    em.accountSettings = {}
end
local function Setup() return GlassPanel.Setup end
local function sys(layout, system, index)
    for _, s in ipairs(layout.systems) do
        if s.system == system and s.systemIndex == index then return s end
    end
end
local function activeLayout()
    local sv = WoW.editMode.saved
    return sv.layouts[sv.activeLayout - 3], sv.activeLayout
end

loadAddon()

-- The Modern preset: the minimap, buffs and damage meter move just below the
-- bar; debuffs (already below) and the action bar (bottom) stay.
session({}, 1)
local plan = Setup().Plan()
eq(plan.mode, "new", "a preset: a new layout")
eq(plan.index, 4, "inserted right after the 3 presets")
local labels = {}
for _, m in ipairs(plan.moves) do labels[#labels + 1] = m.label end
eq(table.concat(labels, ","), "Minimap,Buffs,Damage meter", "moves only the systems in the bar's strip")
local text = table.concat(Setup().Describe(plan), "\n")
check(text:find("Copies your layout |cffffd100Modern|r", 1, true), "the plan names the source")
check(text:find("Minimap: moved down to 26 below the top (was 0)", 1, true), "and each move")
check(text:find("stays after uninstalling", 1, true), "and says it outlives the addon")
eq(#WoW.editMode.calls, 0, "planning saves nothing")
local ok, lines = Setup().Apply(plan)
check(ok, "applied (" .. table.concat(lines, " / ") .. ")")
eq(table.concat(WoW.editMode.calls, ";"), "SaveLayouts;OnLayoutAdded 4 true false",
   "Blizzard's order: save, then announce the new layout (which activates it)")
local gp, idx = activeLayout()
eq(idx, 4, "active: the new layout")
eq(gp.layoutName, "GlassPanel", "named GlassPanel")
eq(gp.layoutType, T.Account, "an account layout")
eq(gp.layoutIndex, nil, "the preset-only layoutIndex dropped")
eq(gp.interfaceStyle, 0, "interfaceStyle kept")
eq(sys(gp, S.Minimap).anchorInfo.offsetY, -26, "minimap: just below the 24-unit bar")
eq(sys(gp, S.Minimap).isInDefaultPosition, false, "marked moved (else Blizzard re-anchors it)")
eq(sys(gp, S.AuraFrame, 1).anchorInfo.offsetY, -26, "buffs: -10 -> -26")
eq(sys(gp, S.AuraFrame, 1).anchorInfo.offsetX, -255, "x untouched")
eq(sys(gp, S.AuraFrame, 2).anchorInfo.offsetY, -155, "debuffs: already below, untouched")
eq(sys(gp, S.AuraFrame, 2).isInDefaultPosition, true, "and still default")
eq(sys(gp, S.DamageMeter).anchorInfo.offsetY, -26, "damage meter moved")
eq(sys(gp, 0, 1).anchorInfo.offsetY, 45, "anything else untouched")
eq(#WoW.editMode.presets[1].systems, 5, "(the presets themselves untouched)")
eq(WoW.editMode.presets[1].systems[1].anchorInfo.offsetY, 0, "(their anchors too)")
check(table.concat(lines, " "):find("active layout now", 1, true), "reports it's active")
check(table.concat(lines, " "):find("/reload", 1, true), "recommends a reload")

-- Run again: GlassPanel is active; nothing left in the strip, nothing saved.
WoW.editMode.calls = {}
plan = Setup().Plan()
eq(plan.mode, "none", "second run: nothing to move")
ok = Setup().Apply(plan)
eq(#WoW.editMode.calls, 0, "and nothing saved")

-- Switch back: to the Modern preset (by its enum), once.
ok, lines = Setup().SwitchBack()
check(ok, "switched back (" .. tostring(lines) .. ")")
eq(WoW.editMode.saved.activeLayout, 1, "Modern is active again")
eq(#WoW.editMode.saved.layouts, 1, "the GlassPanel layout is kept (the player deletes it in Edit Mode)")
ok, lines = Setup().SwitchBack()
eq(ok, false, "nothing recorded any more")

-- GlassPanel exists but isn't active: never overwritten (account-wide).
WoW.editMode.calls = {}
plan = Setup().Plan()
eq(plan.mode, "refuse", "an inactive GlassPanel layout: refused")
check(plan.why:find("select it in Edit Mode", 1, true), "says what to do")
eq(Setup().Apply(plan), false, "Apply refuses too")
eq(#WoW.editMode.calls, 0, "nothing saved")

-- GlassPanel active but a system back in the strip (moved in Edit Mode):
-- adjusted in place.
local gpSystems = modernSystems()
for _, s in ipairs(gpSystems) do if s.system == S.Minimap or s.system == S.DamageMeter or s.systemIndex == 1 then
    s.anchorInfo.offsetY, s.isInDefaultPosition = -26, false end end
gpSystems[1].anchorInfo.offsetY = -5
session({ saved("Mine", T.Account), saved("GlassPanel", T.Account, gpSystems) }, 5)
plan = Setup().Plan()
eq(plan.mode, "inplace", "active GlassPanel: adjusted in place")
eq(#plan.moves, 1, "only what's in the strip again")
ok = Setup().Apply(plan)
check(ok, "applied in place")
eq(table.concat(WoW.editMode.calls, ";"), "SaveLayouts;SetActiveLayout 5", "saved, still active")
eq(#WoW.editMode.saved.layouts, 2, "no new layout")
eq(WoW.editMode.saved.layouts[2].systems[1].anchorInfo.offsetY, -26, "moved in place")

-- A custom layout with Character layouts: inserted after the last Account
-- layout, before the Character ones (MakeNewLayout's rule).
session({ saved("Mine", T.Account), saved("Alt", T.Character) }, 5)
plan = Setup().Plan()
eq(plan.index, 5, "after the last Account layout (4), before Character (5)")
Setup().Apply(plan)
eq(WoW.editMode.saved.layouts[2].layoutName, "GlassPanel", "GlassPanel between them")
eq(WoW.editMode.saved.layouts[3].layoutName, "Alt", "the character layout after it")
eq(table.concat(WoW.editMode.calls, ";"), "SaveLayouts;OnLayoutAdded 5 true false", "announced at its index")
-- ...and switch back finds the character layout by name and type.
ok, lines = Setup().SwitchBack()
check(ok, "switched back to a saved layout by name (" .. tostring(lines) .. ")")
eq(WoW.editMode.saved.activeLayout, 6, "Alt, now one index later")

-- Only top-to-top anchors on UIParent move; others are listed, not moved.
local odd = modernSystems()
odd[1].anchorInfo = anchor("TOPRIGHT", 0, 0, "UIParentRightManagedFrameContainer")   -- snapped elsewhere
odd[2].anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "TOP", offsetX = 0, offsetY = -8 }
session({ saved("Custom", T.Account, odd) }, 4)
plan = Setup().Plan()
eq(#plan.moves, 1, "only the damage meter moves")
text = table.concat(Setup().Describe(plan), "\n")
check(text:find("Minimap: not moved, follows UIParentRightManagedFrameContainer", 1, true), "snapped: follows")
check(text:find("Buffs: not moved, not anchored to the top of the screen", 1, true), "other anchors: listed")
-- Two anchors (both top-to-top): shifted equally, so it moves, not resizes.
local two = modernSystems()
two[4].anchorInfo2 = anchor("TOPRIGHT", 200, 0)
session({ saved("Custom", T.Account, two) }, 4)
plan = Setup().Plan()
Setup().Apply(plan)
local dm = sys(WoW.editMode.saved.layouts[2], S.DamageMeter)
eq(dm.anchorInfo.offsetY, -26, "first anchor moved")
eq(dm.anchorInfo2.offsetY, -26, "second anchor by the same amount")
-- A gamepad-style source keeps its interfaceStyle.
session({ saved("Pad", T.Account, nil, 1) }, 4)
plan = Setup().Plan()
Setup().Apply(plan)
eq(WoW.editMode.saved.layouts[2].interfaceStyle, 1, "gamepad interfaceStyle kept")

-- Nothing in the strip (the owner's own layout): nothing to do, nothing saved.
local clear = modernSystems()
for _, s in ipairs(clear) do if s.anchorInfo.offsetY > -26 then s.anchorInfo.offsetY = -40 end end
session({ saved("Custom", T.Account, clear) }, 4)
plan = Setup().Plan()
eq(plan.mode, "none", "nothing in the strip: nothing to do")
Setup().Open()
eq(Setup()._test.window().apply._shown, false, "no Apply button")

-- Guards.
session({}, 1)
WoW.combat = true
eq(Setup().Plan().mode, "refuse", "in combat: refused")
WoW.combat = false
em._shown = true
check(Setup().Plan().why:find("close Edit Mode", 1, true), "Edit Mode open: refused")
em._shown = false
em.accountSettings = nil
check(Setup().Plan().why:find("hasn't loaded", 1, true), "layouts not loaded: refused")
em.accountSettings = {}
em.overrideLayoutInfo = {}
check(Setup().Plan().why:find("override", 1, true), "override layout active: refused")
em.overrideLayoutInfo = nil
local five = {}
for i = 1, 5 do five[i] = saved("A" .. i, T.Account) end
session(five, 1)
check(Setup().Plan().why:find("5 account layouts", 1, true), "account layouts full: refused")

-- A plan that changed since the preview isn't applied.
session({}, 1)
plan = Setup().Plan()
WoW.editMode.saved.activeLayout = 2   -- switched to Classic meanwhile
ok, lines = Setup().Apply(plan)
eq(ok, false, "changed plan: not applied")
check(lines[1]:find("review it again", 1, true), "says so")
eq(#WoW.editMode.calls, 0, "nothing saved")

-- Saved but activation failed: reported apart, recorded.
session({}, 1)
plan = Setup().Plan()
WoW.editMode.failActivate = true
ok, lines = Setup().Apply(plan)
WoW.editMode.failActivate = false
eq(ok, false, "activation failed: not ok")
check(table.concat(lines, " "):find("Saved, but switching to it failed", 1, true), "saved and activation reported apart")
check(GlassPanel.failures["setup:activate"] ~= nil, "recorded")
GlassPanel.failures["setup:activate"] = nil
-- Save failed: nothing switched.
session({}, 1)
plan = Setup().Plan()
WoW.editMode.failSave = true
ok, lines = Setup().Apply(plan)
WoW.editMode.failSave = false
eq(ok, false, "save failed")
check(lines[1]:find("Nothing was switched", 1, true), "says nothing was switched")
eq(table.concat(WoW.editMode.calls, ";"), "SaveLayouts", "no activation attempted")
GlassPanel.failures["setup:save"] = nil

-- The window: Apply, then Reload.
session({}, 1)
GlassPanelDB.editModeReturn = nil
GlassPanel._test.slash("setup")
local w = Setup()._test.window()
eq(w._shown, true, "/gpanel setup opens the plan")
eq(w.apply._shown, true, "with Apply")
w.apply._scripts.OnClick(w.apply)
eq(WoW.editMode.saved.activeLayout, 4, "applied from the window")
eq(w.reload._shown, true, "then offers a reload")
w.reload._scripts.OnClick(w.reload)
eq(WoW.reloads, 1, "Reload reloads")
WoW.chat = {}
GlassPanel._test.slash("setup back")
check((WoW.chat[1] or ""):find("Switched back to Modern", 1, true), "/gpanel setup back")

rawset(_G, "EditModeManagerFrame", nil)
check(next(GlassPanel.failures) == nil, "no failures")
done("test_setup")
