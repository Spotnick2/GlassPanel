# GlassPanel plan

## Goal

A streamlined, liquid-glass info bar for WoW: Forever: one bar across the top of the screen
with only the readouts the owner actually uses, plus a small plugin API so the owner's own
Titan plugins could be ported as separate addons. It began as a replacement for the owner's
TBC Titan Panel setup.

It stays small on purpose. For a full data-bar experience (a big plugin catalogue, per-plugin
menus) the README points to Titan Panel.

**Not** a Titan port. Titan is a reference for *how each piece of data is read*
(`C:\Projects\WoW\References\Addons\Plugins\TitanPanel`); none of its architecture is reused: no
global button names, no `TitanGetVar`-style per-plugin variable store, no XML templates, no
per-plugin right-click option menus, no multiple bars, no bottom bar, no auto-hide, no
LibDataBroker host (yet).

## Status: v1.0.0

Released 2026-10-21 on CurseForge, GitHub and Wago. The core and 17 plugins ship in one package
(the core's folder plus one folder per plugin).

## Architecture

| file | role |
|---|---|
| `Compat.lua` | `GlassPanel.API`: client quirks, the failure recorder, `CoinText`, `SystemHider`, `Window` |
| `Suite.lua` | Glass UI's suite theme (opt-in): Pearl, the accent colour (#96, #106) |
| `Glass.lua` | this addon's LibGlass instance, built Pearl |
| `Engine.lua` | block registry, event fan-out, one repaint per frame, 1 s interval clock, `pcall` isolation |
| `Layout.lua` | free lanes (#6): anchors as fractions of the width, drop to join or start a lane |
| `Bar.lua` | the strip, one plain Button per block, placement and drag and drop, width follows text |
| `Room.lua` | the bar stops short of Blizzard's top frames (#2) |
| `Edge.lua` | the top edge GlassPanel occupies, announced for the suite (#97) |
| `Floats.lua` | zoomed floats (XP+'s bar, the combat pill, the flight bar) stack and snap apart (#108) |
| `Settings.lua` | `GlassPanelDB` defaults and the one place a setting is changed |
| `Share.lua` | export/import of a setup as a string (#34) |
| `Setup.lua` | opt-in Edit Mode layout with room for the bar (#10) |
| `Options.lua` | Options > AddOns > Glass Panel (#24) |
| `GlassPanel.lua` | SavedVariables, `/gpanel`, boot |
| `Plugins\<Name>\` | **every block**: its own addon `GlassPanel<Name>`, grouped under `[Core]` (#7) |

Contract: `docs/PLUGINS.md`. The detail of each file is in `CLAUDE.md`.

## Shipped in v1.0.0

Plugins (every block is one): **XP+** (#3, zoomable), **Combat** (#108, zoomable pill),
**Gold**, **Clock**, **Durability** (#12), **Bags** (#13), **PvP** (#14), **Professions** (#15),
**GearScore** (#16), **Layer** (#17), **Guild** (#18), **Role** (#20), **Currencies** (#47),
**AltStable** bridge (#46), **Warlock** (#67), **Reagents** (#68), **Ammo** (#66).
Location was dropped: the minimap already shows it. RestedXP was dropped (#98).

Core: free lanes and drag and drop, room made for Blizzard's top frames without moving them,
the opt-in Edit Mode layout, the options page, export/import, three glass looks, windows in
the same glass, following Glass UI's theme (opt-in), and the XP+ / Combat floats that never
overlap.

## What's open

Merged, unreleased: **Flight** (#124, zoomable bar under XP+'s; times from the client's path lengths, then landings). Its timing moves to the shared embedded library **LibTaxiTime-1.0** (#127, with Glass Unit Frames).

Issues: **#74** share the picker window between Currencies and Reagents (and the item-name
loader with GearScore); **#45** Gold without AltStable (postponed); **#26** Layer from
NovaWorldBuffs guild messages (postponed).

Not measured yet:
- Build 70338 is what the code and the offline stubs were checked against
  (`API.MEASURED_ON_BUILD`); the newest API dump is higher (up to 70532).
- Ammo for warriors and rogues (`UnitUsesAmmo`) and the thrown count; the Well Rested cap at
  5/5 (XP+ rested lines).
- Flight (#124): `UnitOnTaxi` at `PLAYER_CONTROL_LOST` (EllesmereUI found it false at takeoff),
  `C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())` giving node ids on the flight map, Frequent
  Flier (Legacy node 110300) and its 20%, and the flight master icon.
- The first open of the options page from Glass UI's button (#104/#105) was fixed from
  Blizzard's source, not measured.

Ideas, not planned: a LibDataBroker host, a bottom bar, auto-hide (all out of scope for now).

## Open questions (measure in game)

- Room for Blizzard's top frames (#2): the bar adapts (`Room.lua`); tune `Room.WATCH` from
  `/gpanel covered` on a Blizzard preset.
- Strata `MEDIUM`: check that it sits above the world UI and below bags and dialogs.
- The glass rim is a rounded rect. Does a full-width strip read well with rounded ends at the
  screen edges, or should the bar be inset a few pixels?
