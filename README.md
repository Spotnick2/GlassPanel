# Glass Panel

A liquid-glass info bar for **World of Warcraft: Forever**: one slim strip across the top of the
screen with only the readouts you actually use, and a glass XP bar and combat timer you can pull
out onto the screen.

![The Glass Panel bar across the top with the XP+ bar zoomed under it and the combat pill between them](https://raw.githubusercontent.com/Spotnick2/GlassPanel/main/docs/screenshots/bar.png)

**Looking for the full experience?** Glass Panel is deliberately small: a handful of readouts
and nothing else. If you want a data bar with a huge catalogue of plugins and per-plugin menus,
use [Titan Panel](https://www.curseforge.com/wow/addons/titan-panel). Glass Panel is for people
who find that too much.

## Install

Install **Glass Panel** from CurseForge, either with the CurseForge app or by unzipping it into
the `Interface\AddOns` folder inside your Forever game folder. The download holds the core and
every plugin as its own folder. Then start the game, or `/reload` if it was running; a brand-new
addon folder needs no more than that.

Every readout is a plugin, so switch the ones you don't want off in the AddOns list (they keep
their place on the bar if you turn them on again).

## What it does

**One bar, free of Blizzard's frames.** The bar sits at the top of the screen, and instead of
moving the game's own frames it stops short of whatever reaches into its band (the minimap
cluster, buffs, debuffs, the unit frames, the damage meter). `/gpanel room full` turns that off
for a full-width bar; `/gpanel setup` can also write an Edit Mode layout that makes room.

**Readouts, each its own plugin.** Click, hover or double-click a block as noted:

- **XP+**: a glass XP bar with rested and quest XP; the tooltip has time played, XP per hour and
  time to level. Double-click its icon to **zoom** it out onto the screen as a bar you can
  shift-drag anywhere and scale.
- **Combat**: "Out of Combat", or the fight's time. Zoomed, the bar says "In Combat" and a glass
  **pill** with the timer shows on the screen, only during a fight.
- **Gold** (what you gained or spent this session), **Bags**, **Durability** (lowest item and the
  repair cost), **GearScore** and item level, **Professions**, **Guild** (online and who),
  **Currencies** (the ones you pick), **Reagents** (your class's, the ones you pick), **Ammo**,
  **PvP** (flag and its countdown), **Role**, **Layer**, **Clock**, **Warlock** (soul shards,
  Healthstone, Soulstone) and **AltStable** (your alts' gold, needs
  [AltStable](https://www.curseforge.com/wow/addons/altstable)).

**Zoomed blocks never overlap.** The XP+ bar and the combat pill each have a default spot
(the pill sits between the bar and XP+), and dropping one onto another snaps it clear. A spot you
choose yourself is never moved.

**Arrange it your way.** Shift-drag a block to move it; blocks sit in lanes you can pack left,
right or centre. Captions, icons and each plugin's visibility are options, and
**Share setup** exports your layout as a string you can paste to a friend.

**Glass.** Clear or smoked, neutral or class-coloured, with Glass Panel's windows (the options
dialogs) matching. If you use [Glass UI](https://github.com/Spotnick2/GlassUI) you can
opt into its theme from its page: the glass, tint, windows and the gold of captions and window
titles then follow it.

## Commands

`/gpanel` (or its options page: Esc > Options > AddOns > Glass Panel).

| Command | What it does |
|---|---|
| `/gpanel list` | The blocks, with their lanes |
| `/gpanel show <id>` / `hide <id>` / `toggle` | A block, or the whole bar |
| `/gpanel move <id> left\|center\|right\|0-100 [position]` | Place a block |
| `/gpanel layout reset` | Back to the default order |
| `/gpanel labels`, `label <id>`, `icon <id>` | Captions and icons |
| `/gpanel font arial\|friz` | The text face |
| `/gpanel glass clear\|smoked`, `tint neutral\|class`, `window reflective\|smoked` | The look |
| `/gpanel room auto\|full\|why` | How the bar makes room |
| `/gpanel setup` | Opt-in Edit Mode layout with room for the bar (`setup back` undoes it) |
| `/gpanel export` / `import` | Share your setup |
| `/gpanel covered`, `failures` | Diagnostics |

## Good to know

- Forever is Vanilla content on the modern client, so some readouts are honest about what the
  game won't tell an addon: a number the client hides shows as `?`, never a made-up figure.
- The glass is [LibGlass](https://github.com/Spotnick2/LibGlass), shared with the other Glass
  addons. The newest copy among them runs, so a library fix reaches you through whichever Glass
  addon updated last.
- Glass Unit Frames has a combat timer of its own over the portrait. To use this one instead,
  tick "Use this timer instead of Glass Unit Frames'" in the Combat plugin's options.

## Reporting a problem

Open an issue on [GitHub](https://github.com/Spotnick2/GlassPanel/issues) with what you did, what
you expected and what happened instead. Lua errors are hidden by default on this client: type
`/console scriptErrors 1`, do it again, and send the error text, plus the output of
`/gpanel failures`.

## Development

The code, the plugin contract (`docs/PLUGINS.md`) and the plan (`docs/PLAN.md`) are in this
repository. Tests run with `pwsh tests\run.ps1` (Lua 5.1).

## License

MIT, see [LICENSE](LICENSE). The bundled LibGlass-1.0 keeps its own MIT license.
