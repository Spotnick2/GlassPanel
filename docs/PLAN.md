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
| `Room.lua` | the bar stops short of Blizzard's top frames (#2) |
| `GlassPanel.lua` | SavedVariables, `/gpanel`, boot |
| `Plugins\<Name>\` | **every block**: its own addon `GlassPanel<Name>`, grouped under `[Core]` (#7) |

Contract: `docs/PLUGINS.md`.

## Roadmap: one issue each, every block a plugin (#7)

Done: **XP+** (#3), **Gold**, **Clock**. **Location** is dropped: the minimap already shows it.

The owner's TBC Titan bar, still to port:
- **Durability** (#12): lowest % and repair cost. **In progress.**
- **Bags** (#13): used/total, special bags apart. **In progress.**
- **Professions** (#15): `C:\Projects\TitanProfessions`. `C_SkillInfo.GetSkillLineInfo` returns **a table**;
  `GetProfessions` returns `nil`s.
- **GearScore / iLvl** (#16): `C:\Projects\TitanGearScore`. Vanilla item levels are small.
- **Guild** (#18): online/total, who's online, click opens the guild panel. Data reference:
  `_classic_\Interface\AddOns\TitanClassicGuild`.
- **Layer** (#17): **blocked** on a second-layer `UnitGUID` reading (zone field 18 on the first).

New:
- **PvP flag** (#14): flagged or not, and the time left on the flag.
- **Warlock** (#67): soul shards, Healthstone and Soulstone carried, their cooldowns.

Also: an opt-in Edit Mode layout for a full-width bar (#10); hiding Blizzard's XP bar safely (#9).

## Open questions (measure in game)

- Room for Blizzard's top frames (#2): the bar adapts (`Room.lua`); tune `Room.WATCH` from
  `/gpanel covered` on a Blizzard preset. An opt-in Edit Mode layout for a full-width bar is
  separate.
- Strata `MEDIUM`: check that it sits above the world UI and below bags and dialogs.
- The glass rim is a rounded rect. Does a full-width strip read well with rounded ends at the
  screen edges, or should the bar be inset a few pixels?
- `C_CurrencyInfo.GetCoinTextureString` output and icon size at 12 pt.
