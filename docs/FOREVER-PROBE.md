# Measured on Forever

What GlassPanel's probes measured in game. Each entry names its build. Addon-agnostic findings are
copied to `C:\Projects\WoW\References\PORTING-TBC-TO-FOREVER.md`.

## RestedXP Guides (RXPProbe, #80): 1.60.1.70374, 2026-10-15

The owner ran `/fp steps rxp arrow`: a Horde character in The Barrens, guide "12-17 The Barrens"
(196 steps), RXPGuides **v4.11.23**. Every step except the dungeon was done. The raw log is in
`WTF\Account\<account>\SavedVariables\RXPProbe.lua`.

**RestedXP is reachable.**
- `C_AddOns.GetAddOnInfo("RXPGuides")`: loadable, `INSECURE`; `IsAddOnLoaded`: `true, true`.
- `GetAddOnMetadata(..., "Interface")` returns `nil`, so which TOC the client picked can't be read
  that way.
- `RXP` is a table, the same object as `AceAddon:GetAddon("RXPGuides")`. `RXP.game == "FOREVER"`.
- Present: every call the plugin needs (`RXP.settings.ToggleActive`, `SetStepListShown`,
  `IsStepListShown`, `RXP.arrowFrame`, `RXP.currentGuide`, `RXPFrame`, `RXPG_ARROW`), plus
  HereBeDragons-2.0, LibDataBroker-1.1 and AceEvent-3.0.
- The LDB object `"RXPGuides"` exists with `OnClick` and `OnTooltipShow`.

**Our bearing equals RestedXP's, to the last digit.** Outdoors, out of combat:
- `HBD:GetPlayerWorldPosition()`, `GetPlayerFacing()`, `UnitPosition("player")` and
  `C_Map.GetBestMapForUnit` all read **plainly** (no secrets).
- `angle - facing` from `HBD:GetWorldVector` gave orientation 3.7780679398381 and distance 3423.37.
  RestedXP's own `af.orientation` and `af.distance` (floored) were identical.
- 121 two-second samples over the run matched. The only differences came while RestedXP's arrow
  was switched off, and they're listed below.
- The owner confirmed by eye that the blue test arrow pointed the same way, followed retargets,
  and kept working with RestedXP's arrow off.

**The target (`RXP.arrowFrame.element`):**
- It holds `wx`, `wy`, `instance`, `x`, `y`, `zone` and `radius`.
- **This guide's targets were `textOnly = true` yet had world coordinates**, so `textOnly` doesn't
  mean "no position".
- **`step.title` and `step.arrowtext` were nil** on every step, and so was `element.title`.
  RestedXP's arrow then shows "Step N", so the plugin needs the same fallback.
- Retargets showed up within about 0.3 s of the `RXP_STEP_ACTIVATED` messages.

**RestedXP's arrow switched off (its "hide the waypoint arrow" option):**
- `RXPG_ARROW` **stayed shown**: only its drawing stopped.
  - **Correction from the source** (Codex on #84): that's only until the next retarget.
    `updateArrowData` then hides it (`map.lua:1047-1051`).
  - The guide toggle leaves it alone while drawing is off (`IsFeatureEnabled`, `map.lua:61-64`).
  - So with drawing off the frame's visibility says nothing. The plugin checks the waypoint is
    still live, and that the guide is shown.
- `af.orientation` and `af.distance` **went stale** (unchanged for about 17 s while ours moved).
- `af.element` kept the target.
- So the plugin computes its own bearing, never reads RestedXP's numbers, and doesn't treat
  `RXPG_ARROW:IsShown()` as "the arrow is on".

**The guide toggle**, through the LDB `OnClick(_, "LeftButton")` (its minimap button's
left-click):
- It hid and showed the guide and its arrow (`showEnabled` flipped), out of combat and **in
  combat**.
- **Nothing was blocked:** the host logged no `ADDON_ACTION_*`, and the owner saw no error. This
  matches `ToggleActive` skipping its secure frames in combat.

**Folding the step list doesn't work as a "minimize":** `SetStepListShown(false)` set
`RXPFrame`'s height to 10 and `IsStepListShown()` returned false, but the owner saw **no visible
fold**. The toggle is the minimize.

**Messages:**
- `RXP_STEP_ACTIVATED` / `RXP_STEP_DEACTIVATED` arrive in bursts (a step change sends several),
  with the step table.
- `RXP_GUIDE_LOADED` arrives at login with the guide table (`.name`).

**Progress:** `RXP.GetGuideProgress()` returned `16, 3309049918`. The second value isn't a total,
so it's not usable as "x of y". Use the step index and `#RXP.currentGuide.steps` (196).

**Not measured:** a dungeon (skipped), and whether the bearing reads plainly there.

## Rested XP (RestProbe, #81): 1.60.1.70374, 2026-10-15, run 1

The owner ran `/fp steps rest rested`. The raw log is in `RestProbe.lua` (SavedVariables).

**Well Rested is a Legacy talent, readable exactly:**
- Adventure tree **1188**, node **110301**, spell **1225478**.
- `C_Traits.GetNodeInfo(C_Traits.GetConfigIDByTreeID(1188), 110301)` gives `activeRank = currentRank = ranksPurchased = 5`, `maxRanks = 5`. The owner confirmed 5/5 in the Legacy window.
- Its spell description is "Your rested experience accumulates 20% faster and your rested experience cap is increased by 20%."
- `Constants.LegacyConsts` exists: trees 1187/1188/1189, currency 4225, faction 2802.
- All three Legacy trees share one configID (15132781) and have 9 nodes each, every one named.

**The pool reads plainly:**
- `GetXPExhaustion`, `UnitXP`, `UnitXPMax`, `GetRestState` (`1, "Rested", 2`) and `IsResting` all read normally.
- The cap wasn't reached: the most seen was 6,760 / 16,000, about 0.42 of a level.

**Well Fed is spell 1248406** (20 min). Its aura tooltip reads "Experience gained from kills increased by 5%" (owner's screenshot), but `C_Spell.GetSpellDescription` didn't contain "experience". **Read an XP buff's effect from the aura's tooltip** (`C_TooltipInfo.GetUnitBuffByAuraInstanceID`), not the spell description. The probe now does; run 2 checks it.

**Camping, 13 minutes with "Campfire Nearby" and "Welcoming Campfire":**
- It added **0** rested, and `IsResting()` was false, apart from one brief true.
- "Welcoming Campfire" grants its benefits only "after 1 min spent sitting near the campfire", depending on the camp objects placed. Run 2 measures sitting.

**Not measured:**
- **The inn build-up rate:** a `/reload` restarted the in-memory sampler; the start is now saved.
- **The cap.**
