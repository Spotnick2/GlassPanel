# Changelog

## Unreleased

- New plugin **Combat**: a combat timer. On the bar it shows crossed swords and "Out of Combat", or the fight's time. Double-click the icon to zoom it: a glass pill appears on the screen, only while you're in combat (shift-drag to move it; Options > Plugin options > Combat has a preview to place it). The zoomed XP+ bar and the pill stack so they never overlap; drop one onto the other and it snaps clear. If you use Glass Unit Frames, its portrait timer can be turned off from Combat's options ("Use this timer instead of Glass Unit Frames'").
- Window titles are gold like the stock UI's. If you follow Glass UI, the gold of the bar's captions and the window titles takes Glass UI's accent colour, live.
- Opening Glass Panel's settings from Glass UI's button no longer leaves an empty page the first time.
- The glass is now **Pearl**, the suite's look: the same depth with softer highlights. If you use Glass UI, you can switch Glass Panel to follow its theme on Glass UI's page; the glass, its tint and window choices here are then set there (and come back as you left them when you stop following).
- The RestedXP block is gone (it wasn't good enough). If you installed the alpha, delete the `GlassPanelRestedXP` folder from your AddOns folder, since an update doesn't remove it. Its saved place in your layout is kept harmlessly.
- Windows (Share, Setup, Currencies, Ammo) have a new look, **Reflective**: a smoked glass shell lit from above, with a calm reading area under the title. Options > Windows (or `/gpanel window reflective|smoked`) switches back to the earlier **Smoked** look; a window already open changes after `/reload`.
- Reagents: pick which of your class's reagents to show and in what order (powders, candles,
  runes, seeds, poisons, Ankhs, Fish Oil, Symbols), with a red 0 when you've run out. Left-click to choose.
- A liquid-glass bar across the top of the screen, with gold and clock blocks.
- XP+: a glass XP bar (with TitanPanelXPP's purple XP icon) with rested and quest XP, and a tooltip with time played, XP per hour and
  time to level. Hidden at the level cap. Left-click refreshes time played, right-click resets
  the session. An option (Options > AddOns > Glass Panel > Plugin options) hides Blizzard's own XP
  bar (and the reputation bar under it) while XP+ shows.
- XP+ zooms out of the panel: double-click its icon and it becomes a wide bar at the top centre of
  the screen (time this level and this session above it; XP per hour, time to the next level,
  turn-in quest XP and rested under it). Only the icon stays on the panel; double-click it again to
  put the bar back. Shift-drag the zoomed bar to move it; right-click it for a menu (back to the
  panel, reset session, reset position). It remembers where you left it. Its size: "Zoomed bar's
  scale" in Options > AddOns > Glass Panel > Plugin options, where "Glass behind the zoomed bar" also
  puts a pane of glass behind it, matching the panel's Clear or Smoked and tint. The zoomed bar uses
  LibGlass's clean look (thin rims, no grain).
- XP+ tooltip:
  - your rested cap, with the Well Rested Legacy talent's bonus;
  - while resting, how long until you're fully rested;
  - your XP buffs (Well Fed, Camp Benefits) with their time left;
  - when your Camp Tent can grant rest again.
- Ships LibGlass r7 (was r5).
- Smoked glass: its softer shine now actually applies (it was drawn at full strength).
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
- Ammo (hunters, warriors and rogues): the arrows, bullets or thrown weapons you have left, chosen
  from your ranged weapon. Yellow when low and red when critical; left-click to set when, for your
  class. A red `!` means you have no ammo equipped, or the wrong kind for the weapon.
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
