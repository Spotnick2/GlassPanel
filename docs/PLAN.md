# GlassPanel plan

## Goal

A streamlined, liquid-glass replacement for the owner's Titan Panel setup on WoW: Forever: one
bar across the top of the screen with the handful of readouts the owner's TBC Titan bar
actually showed (location, XP/hr, gold, layer, GearScore and item level, professions,
durability, bags, clock), plus a small plugin API so the owner's own Titan plugins can
be ported as separate addons.

**Not** a Titan port. Titan is a reference for *how each piece of data is read*
(`C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Titan*`); none of its
architecture is reused: no global button names, no `TitanGetVar`-style per-plugin variable
store, no XML templates, no per-plugin right-click option menus, no multiple bars, no bottom
bar, no auto-hide, no LibDataBroker host (yet).

## Architecture (scaffolded)

| file | role |
|---|---|
| `Compat.lua` | `GlassPanel.API`: client quirks, the failure recorder, `CoinText` |
| `Glass.lua` | the material, copied from GlassUnitFrames (a test keeps it in sync) |
| `Engine.lua` | block registry, event fan-out, one repaint per frame, 1 s interval clock, `pcall` isolation |
| `Bar.lua` | the strip, one plain Button per block, two lanes, width follows text |
| `Blocks\*.lua` | built-in blocks, registered through the same public API as plugins |
| `GlassPanel.lua` | SavedVariables, `/gpanel`, boot |
| `Plugins\<Name>\` | separate addons (`## Dependencies: GlassPanel`), moved out by the packager |

Contract: `docs/PLUGINS.md`.

## Roadmap: one issue each

Built-in blocks (core):
1. **XP+**: port of `C:\Projects\TitanPanelXPP` as a block that draws a `Glass.Bar` (XP, rested,
   completed and incomplete quest XP), XP/hr, time to level, the tooltip breakdown. Hidden at
   max level (`UnitXPMax` returns 0 there, and 0 is truthy). Needs the contract to grow then,
   not now: a fixed `width`, a hook that builds custom content on the attached widget (it
   runs after `Bar.Attach`, unlike `onInit`), a paint hook for it, and a rule that a
   graphical block with empty text still shows.
2. **Location**: zone, subzone and coordinates (`C_Map.GetBestMapForUnit` +
   `C_Map.GetPlayerMapPosition`; check what they return inside instances).
3. **Durability**: lowest percentage across equipped slots (`GetInventoryItemDurability`), and
   repair cost in the tooltip if an API for it exists here.
4. **Bags**: free and total slots (`C_Container.GetContainerNumFreeSlots` /
   `GetContainerNumSlots`, bags 0–4).
5. Performance (FPS/latency)? Only if the owner wants it.

Plugins (separate addons, ported from the owner's Titan plugins):
6. **GearScore**: `C:\Projects\TitanGearScore`. `GetItemInfo` → `C_Item.GetItemInfo`.
7. **Professions**: `C:\Projects\TitanProfessions`. `GetSkillLineInfo` →
   `C_SkillInfo.GetSkillLineInfo`, which returns **a table** (porting guide "False friends").
   `GetProfessions` exists but returns `nil`s.
8. **Layer**: `C:\Projects\TitanLayer`. **Blocked on an in-game measurement**: does a creature
   GUID's zone field (`Creature-0-<server>-<instance>-<zoneUID>-…`) differ between layers on
   Forever, and is `UnitGUID` on an NPC plain? If not, drop the plugin.

## Open questions (measure in game)

- The bar covers the top 24 units of the screen. Titan shifts Blizzard frames down to make
  room. Does Forever's default layout put anything there (buffs, minimap cluster), and is Edit
  Mode enough to move it? Decide after seeing it in game; don't port Titan's frame-adjust code
  first.
- Strata `MEDIUM`: check that it sits above the world UI and below bags and dialogs.
- The glass rim is a rounded rect. Does a full-width strip read well with rounded ends at the
  screen edges, or should the bar be inset a few pixels?
- `C_CurrencyInfo.GetCoinTextureString` output and icon size at 12 pt.
