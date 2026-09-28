# Changelog

## Unreleased

- A liquid-glass bar across the top of the screen, with gold and clock blocks.
- XP+: a glass XP bar with rested and quest XP, and a tooltip with time played, XP per hour and
  time to level. Hidden at the level cap. Left-click refreshes time played, right-click resets
  the session.
- Drag blocks to arrange the bar: drop next to other blocks to join their group, or on empty
  space to start a new group there. Shift-drag moves a whole group. `/gpanel move` does the same
  from the keyboard, and `/gpanel layout reset` starts over.
- The bar stops short of the minimap, buffs and other Blizzard frames at the top of the screen
  instead of covering them, and takes the full width again when they're moved out of the way.
  `/gpanel room full` keeps it full width always.
- Every block is its own addon, grouped under Glass Panel [Core] in the AddOns list: switch off the
  ones you don't want.
- Durability: the lowest durability among your equipped items, coloured, with the repair cost;
  the tooltip lists damaged items.
- Bags: used and total bag slots, coloured as they fill; quivers and soul bags listed apart.
  Click to open your bags.
- `/gpanel` lists, shows and hides blocks.
- Other addons can add blocks with `GlassPanel.RegisterBlock`.
