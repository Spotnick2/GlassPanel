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
| `Layout.lua` | free lanes (#6): anchors as fractions of the width, drop to join or start a lane |
| `Bar.lua` | the strip, one plain Button per block, placement and drag and drop, width follows text |
| `Blocks\*.lua` | built-in blocks, registered through the same public API as plugins |
| `GlassPanel.lua` | SavedVariables, `/gpanel`, boot |
| `Plugins\<Name>\` | separate addons (`## Dependencies: GlassPanel`), moved out by the packager |

Contract: `docs/PLUGINS.md`.

## Roadmap: one issue each

Built-in blocks (core):
1. **XP+**: port of `C:\Projects\TitanPanelXPP` as a block that draws a `Glass.Bar` (XP, rested,
   completed and incomplete quest XP), XP/hr, time to level, the tooltip breakdown. Hidden at
   max level (`UnitXPMax` returns 0 there, and 0 is truthy). **In progress (#3)**: the contract
   grew `width`, `build` and `paint`.
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

- Room for Blizzard's top frames (#2): the bar adapts (`Room.lua`); tune `Room.WATCH` from
  `/gpanel covered` on a Blizzard preset. An opt-in Edit Mode layout for a full-width bar is
  separate.
- Strata `MEDIUM`: check that it sits above the world UI and below bags and dialogs.
- The glass rim is a rounded rect. Does a full-width strip read well with rounded ends at the
  screen edges, or should the bar be inset a few pixels?
- `C_CurrencyInfo.GetCoinTextureString` output and icon size at 12 pt.
