# Changelog

## Unreleased

- Reagents: pick which of your class's reagents to show and in what order (powders, candles,
  runes, seeds, poisons, Ankhs, Fish Oil, Symbols), with a red 0 when you've run out. Left-click to choose.
- A liquid-glass bar across the top of the screen, with gold and clock blocks.
- XP+: a glass XP bar (with TitanPanelXPP's purple XP icon) with rested and quest XP, and a tooltip with time played, XP per hour and
  time to level. Hidden at the level cap. Left-click refreshes time played, right-click resets
  the session. An option (Options > AddOns > Glass Panel > Plugin options) hides Blizzard's own XP
  bar (and the reputation bar under it) while XP+ shows.
- Drag blocks to arrange the bar: drop next to other blocks to join their group, or on empty
  space to start a new group there. Shift-drag moves a whole group. `/gpanel move` does the same
  from the keyboard, and `/gpanel layout reset` starts over.
- The bar stops short of the minimap, buffs and other Blizzard frames at the top of the screen
  instead of covering them, and takes the full width again when they're moved out of the way.
  `/gpanel room full` keeps it full width always. Or, opt-in: "Make room in Edit Mode" (Options, or
  `/gpanel setup`) makes a GlassPanel Edit Mode layout with the minimap, buffs and damage meter just
  below the bar, after showing what it will change; "Switch back" returns to your old layout. Buffs and debuffs count by the icons actually
  shown, so on a default layout the bar reaches your buffs instead of stopping at their empty grid.
  It also makes room for Blizzard's damage meter (top left on the default layouts), unless it's
  turned off.
- Every block is its own addon, grouped under Glass Panel [Core] in the AddOns list: switch off the
  ones you don't want.
- Durability: the lowest durability among your equipped items, coloured, with the repair cost;
  the tooltip lists damaged items.
- Bags: used and total bag slots, coloured as they fill; quivers and soul bags listed apart.
  Left-click opens or closes your bags.
- Gold captions before values, Titan-style ("Bags: 45/74"). `/gpanel labels on|off`, or
  `/gpanel label <id> on|off|default` for one block.
- PvP: whether you're flagged, with the countdown before the flag drops (type /pvp to toggle it).
- Guild: your guild's name and its members online out of the total, with who's online (level, class colour, zone, AFK/DND)
  in the tooltip. Left-click opens the guild panel. Hidden when you're not in a guild.
- Professions: an icon and your skill level for each primary profession, coloured by how close it is to
  the cap; the tooltip adds Cooking, First Aid and Fishing. Left-click (out of combat) opens a small
  palette: click a profession to open it.
- Role: your group role with its icon, while you're in a group. Left-click to set Tank, Healer,
  Damage or No Role.
- Layer: which layer of the realm you're on, detected from the NPCs you target or mouse over
  (nameplates confirm a known layer), numbered per zone and per realm. Left-click forgets the
  layers seen in your zone.
- Currencies: pick which currencies to show and in what order (Tarnished Undermine Reals, Honor
  Points, Merchant's Favor and the rest), each with its icon and amount; left-click to choose.
- GearScore: your GearScore, coloured along the item-quality ramp (its bracket in the tooltip), and your average item level; the tooltip
  breaks it down by slot.
- AltStable (needs the AltStable addon): the gold of all your characters that AltStable knows,
  with each character's level and gold in the tooltip, grouped by realm. Left-click opens
  AltStable's sheet. An option counts only this realm and faction. While it shows, the Gold block
  is hidden (your gold is in its total); it says so once, and showing Gold again keeps it.
- Warlock (warlocks only): your soul shards, yellow when few and red at none, with a mark for a
  Healthstone and a Soulstone in your bags; the tooltip names them and counts down their cooldowns.
- Options panel under Game Menu > Options > AddOns > Glass Panel (`/gpanel options`): show the bar,
  captions, font and width, reset the layout, and for each plugin whether it's shown and shows its
  caption and icon (`/gpanel icon <id> on|off` too).
- Share your setup between accounts: Export gives one string with your layout and settings to copy
  (Ctrl+C); paste it into Import on the other account and it's applied at once. From the options
  panel, or `/gpanel export` and `/gpanel import`.
- `/gpanel` lists, shows and hides blocks.
- Other addons can add blocks with `GlassPanel.RegisterBlock`.
- The glass look now comes from LibGlass, a small library shared by the Glass addons, included in
  the download. Nothing changes on screen.
- The bar's glass can be clear (as before) or smoked, and neutral or tinted in your class colour:
  Options > AddOns > Glass Panel > Bar, or `/gpanel glass clear|smoked` and
  `/gpanel tint neutral|class`. Applied at once, and part of a shared setup.
