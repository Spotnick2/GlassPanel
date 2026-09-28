# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassPanel is an **info bar addon for World of Warcraft: Forever 1.60.1** (Interface `16001`),
written in **Lua 5.1**. It's a single-owner project (Spotnick), on the same stack and conventions
as the sibling Forever addons `..\GlassUnitFrames`, `..\AltStable` and `..\Priestly`. When this
file doesn't cover something, check how those handle it before you invent a new idiom.

(The working folder may still be called `GlassXp`. The addon, TOC, namespace and deployed folder
are **GlassPanel** regardless.)

**Goal:** a streamlined, liquid-glass replacement for the owner's Titan Panel setup. It's one bar
across the top of the screen with only the readouts actually used, plus a small plugin API so
the owner's own Titan plugins (`C:\Projects\TitanPanelXPP`, `TitanLayer`, `TitanGearScore`,
`TitanProfessions`) can be ported as separate addons. Plan and roadmap: `docs/PLAN.md`. Plugin
contract: `docs/PLUGINS.md`.

**Titan is a data reference, not an architecture reference.** Read
`C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\Titan*` (TitanBag,
TitanGold, TitanLocation, TitanRepair, TitanXP, TitanClock, …) to learn *which API gives a
number*. Then check that API against the Forever dump, because Titan targets TBC and Classic.
Don't reuse its structure: no global button names, no `TitanGetVar` store, no XML, no
per-plugin option menus, no multiple bars. Titan ships its own license. Write our own code.

**Status: early.** `Glass Panel [Core]` plus plugins; `Plugins\` is the inventory. Work goes through
GitHub issues and PRs at `github.com/Spotnick2/GlassPanel` (private).

## Layout

**Structure (#7):** `Glass Panel [Core]` is the bar, the engine and the API, and has no blocks of
its own. **Every block is a plugin**: its own addon under `Plugins\<Name>\`, named like AltStable's
(`GlassPanelXP.toc`, deployed and packaged as `AddOns\GlassPanelXP`), and shown AtlasLoot-style in
the AddOns list: `## Group: GlassPanel`, title `Glass Panel |cFF0099FF[XP+]|r` under the core's
`[Core]`, the core's icon, `## Dependencies: GlassPanel`. Users switch blocks off in the AddOns
list; the layout keeps a disabled plugin's place. `test_toc.lua` checks every plugin TOC and the
`.pkgmeta` `move-folders` line.

Core TOC load order: `Compat.lua` → `Glass.lua` → `Engine.lua` → `Layout.lua` → `Bar.lua` →
`Room.lua` → `GlassPanel.lua`. Plugins load after the core's `ADDON_LOADED`.

- **`Compat.lua`**: `GlassPanel.API`, the only route to client APIs that moved or may be absent.
  It has `IsSecret`, `RegisterEvent` (reports throws and refusals, naming the block that asked),
  `Fail(key, err)` (**the one failure recorder**, `GlassPanel.failures`, read by
  `/gpanel failures`), `CoinText`, and `Suppressor(globalName)`, which hides a Blizzard frame
  while our block replaces it and only restores what it hid (the clock's
  `TimeManagerClockButton`). **Only for plain frames**: not Edit Mode system frames like
  `MainStatusTrackingBarContainer` (#9). `API.Plain(v)` is the one "secret becomes nil" guard;
  use it at every read. `API.Returned(v)` asks "did the client return anything" without comparing:
  **never write `raw ~= nil` on a raw read**, since comparing a secret (even with nil) throws on
  the client, and the offline stub can't catch it. The global `GetCoinTextureString` is **absent** on 70009;
  use `C_CurrencyInfo`'s. `MEASURED_ON_BUILD` lives here too.
- **`Glass.lua`**: the material, **copied** from GlassUnitFrames' **`main`** branch
  (`git -C ..\GlassUnitFrames show main:Glass.lua`), with only the namespace lines and header
  changed. `test_toc.lua` fails when the two drift. It reads `main` through git on purpose,
  because other sessions switch that repo's working tree between feature branches. Change the
  material in GlassUnitFrames first (with its `docs/GLASS-MATERIAL.md`), and copy it back once
  it merges.
  `Tools\make_textures.py` and `Media\` are copies too.
- **`Engine.lua`**: the block registry (`GlassPanel.RegisterBlock`, `GlassPanel.Refresh`) and
  repaint scheduling:
  - one event frame for all blocks; `onEvent` runs immediately and marks the block dirty;
  - dirty blocks repaint **once per rendered frame** (the flush frame is shown only while work
    is pending);
  - one shared 1 s clock drives `interval` blocks (seconds, or a function returning them, asked
    each time the block comes due); `unitEvents = { EVENT = "player" }` lets an event that fires
    for every unit reach a block only for the unit it names;
  - after a repaint, a tooltip open on that block is redrawn (`Bar.RefreshTooltip`, on-screen
    blocks only);
  - every block callback runs under `pcall` via `Engine.Call`;
  - `text` must return a plain string. Secrets and non-strings are refused and recorded.
  - A relayout runs only when some text changed.
- **`Layout.lua`**: where blocks go (#6), a pure model. **Free lanes**: `{ x = 0..1, ids }`,
  where `0` packs left, `1` packs right and anything else is centred on the anchor. **Lanes never
  overlap**: `Place` pushes them `LANE_GAP` apart (they only overlap when nothing fits). A drop
  over a block joins that block's lane; within `SNAP` px of a gap joins that gap; elsewhere it
  starts a lane where the block was released (grab offset kept). One edge rule, `Layout.Anchor`
  (in px): a span within `SNAP` of an end snaps to it. Lanes within `SNAP` of each other merge.
  Empty lanes are pruned, duplicate saved ids dropped. Saved in `GlassPanelDB.layout`, ids in
  visual order. Ids of blocks that aren't loaded are kept. Blocks never placed follow
  `side`/`order`. `Layout.Current()` is the cached read; mutators use `Lanes()` then `Save`.
- **`Bar.lua`**: the strip (`GlassPanelBar`, full width at the top of `UIParent`, strata
  `MEDIUM`, `Glass.Apply(..., "small")`, mouse-less so empty space clicks through), one plain
  `Button` per block (icon, a gold **caption** `b.caption` "Label: " (#23; `Bar.ShowsCaption`: never
  on graphical blocks, then `labelsFor[id]`, then `labels`, then the spec's `showLabel`), the
  value `b.label`, `HIGHLIGHT` hover), placing them from
  `Layout.lua`, and dragging: a marker shows the drop slot, shift-drag moves a lane by the
  cursor's displacement, a drag under 10 px is a wobbly click (no move), the release that ends a
  drag isn't a click, and the drop target is recomputed after any relayout mid-drag. Hidden and empty blocks take no space. **Nothing is secure**, so the bar may be touched in combat.
- **`Room.lua`**: making room for Blizzard's top frames (#2) **without moving any of them**. The
  bar measures a short watch list (`Room.WATCH`: minimap cluster, buffs, debuffs, ticket status,
  unit frames) and pulls its ends in to stop short of any that reach into its band. A frame hidden
  **on its own** (no target, no buffs) still counts, so the width doesn't jump; one whose
  **parent** is hidden has been replaced by an addon and doesn't. Frames centred in the middle
  fifth are ignored. Pure `Room.Insets`; read-only `GetRect`/`IsShown`/`IsVisible` under pcall,
  every number through `API.Plain`; `Room.Update` never throws (failures go to `API.Fail`).
  Checked on layout, scale and display events and on the engine's clock (`Engine.EverySecond`:
  one clock for everything). `/gpanel room full` opts out; `/gpanel covered` lists frames in the
  band as "under" or "beside" the bar. Moving Blizzard's frames at runtime was rejected after
  research and a Codex review (see #2 and the porting guide's Edit Mode note); an opt-in Edit
  Mode layout setup is #10.
- **`Plugins\XP\XP.lua`**: XP+ (#3), the only graphical block so far (`width`/`build`/`paint`).
  Four layered bars on one `Glass.Bar` host. A level crossing is detected by the level or max
  changing (not by XP going down). Blizzard's XP bar is left alone (#9).
  `/played` is requested with `TIME_PLAYED_MSG` muted on the chat frames, one request at a time
  (a token ties the unmute, the next frame after the answer or after 10 s, to its own request),
  **never** by replacing `ChatFrame_DisplayTimePlayed`. Graphical blocks aren't painted while off
  screen; `Bar.Layout` marks them dirty when they come back.
- **`Plugins\Gold`, `Plugins\Clock`**: gold (secret-safe) and the clock (hides Blizzard's
  minimap clock). Plugins use the **public** API only, the same one third-party plugins get.
- **`Plugins\Professions`** (#15): icon + coloured rank/max per primary profession (secondary ones in the
  tooltip), from `C_SkillInfo.GetSkillLineInfo(i)` (a struct) matched by **skillID**, not name
  (`GetProfessions` returns nils). Stale/ensure like Durability. Left-click (out of combat) opens a
  **palette** of `SecureActionButtonTemplate` spell buttons (Mining opens Smelting, spell 2656). The
  palette is parented to `UIParent` and placed by coordinates, **never parented or anchored to the
  bar**: a secure descendant would make the bar protected and freeze its layout in combat. This is
  the pattern for any future secure click (Codex review on #15).
- **`Plugins\PvP`** (#14): flagged / FFA / off and the flag's countdown (`GetPVPTimer` ms); a
  function `interval` (1 s while the timer runs, else 30 s). **No click: `C_PvP.TogglePVP` is
  protected** (measured: `ADDON_ACTION_FORBIDDEN` from a block click); the tooltip says `/pvp`.
- **`Plugins\Guild`** (#18): online/total from `GetNumGuildMembers` (no loop to count). The roster
  is requested with `C_GuildInfo.GuildRoster` at login and on a guild change (at once), on tooltip
  open (>= 15 s apart) and every 90 s from a `C_Timer.NewTicker` that runs only while the block is on
  screen (`onShown`); counts of 0/0 (no roster yet) show `?`; the scan stops once every online
  member is found; the tooltip's roster scan runs only after `GUILD_ROSTER_UPDATE` marks it stale.
  Names through `Ambiguate(name, "guild")`, never split on spaces. Left-click: `ToggleGuildFrame`. Its caption is
  the guild's name (`caption`, re-read on every repaint; `Bar.UpdateCaption`, secrets refused).
- **`Plugins\Role`** (#20): the group role (`UnitGroupRolesAssigned`) with its inline icon, hidden
  when not `IsInGroup`. Left-click: a `MenuUtil.CreateContextMenu` of radio items (Tank, Healer,
  Damage, No Role) calling `UnitSetRole`. A menu that throws changes nothing (it's reported); only
  a client with no `MenuUtil` gets the fallback, a click that cycles the role (never from an
  unreadable one). A picked role stays pending until `ROLE_CHANGED_INFORM` /
  `PLAYER_ROLES_ASSIGNED` (5 s). A refused or throwing `UnitSetRole` prints one line.
- **`Plugins\Layer`** (#17): the zone field of creature GUIDs (target, mouseover, nameplates;
  not in combat, on a taxi or in an instance; secret GUIDs skipped), numbered by rank among the
  zone ids seen **on the same uiMapID**. `GlassPanelLayerDB.maps[map][zone] = GetServerTime()`,
  forgotten after 2 h. Group, map and player phase changes make it unknown. No NWB listener (#26).
  Left-click forgets the current map's layers.
- **`Plugins\Layer`** (#17): the zone field of creature GUIDs (not on a taxi or in an instance;
  secret GUIDs skipped via `API.Plain`, readable ones count in combat), numbered by rank among the
  zone ids seen **on the same uiMapID** (local numbers: nothing says how many layers exist). A new
  id is filed only from the target or mouseover, never when known on another map; nameplates only
  confirm (border creatures). `GlassPanelLayerDB.realms[realm][map][zone] = GetServerTime()`
  (nil time: nothing saved), forgotten after 2 h. Rescans target > mouseover > nameplates on
  entering the world, combat end, taxi end and 5/15/30 s after a group change. Map and player
  phase changes make it unknown. No NWB listener (#26). Left-click forgets the current map's layers.
- **`Plugins\Bags`** (#13): used/total over normal bags (family 0; ids from `Enum.BagIndex`);
  special bags (quiver, soul bag, the reagent slot) are listed apart and not counted. An unreadable
  bag (free count or family) is left out and flagged with a grey `?`. Left-click: `ToggleAllBags`.
- **`Plugins\Durability`** (#12): lowest durability and repair cost. Events only mark the
  cache stale; it's rebuilt at most once per repaint (tooltip data is heavy, and only for damaged
  items). An unreadable item marks the figure with a grey `?` and makes the cost unknown; the cost comes from
  `C_TooltipInfo.GetInventoryItem(...).repairCost` (TitanRepair's Retail path, not in the dump:
  unknown is shown as unknown). Secret numbers keep type `"number"` on the client, so
  `type(x) == "number"` is no secrecy check: `API.Plain` first.
- **`GlassPanel.lua`**: `GlassPanelDB` (`font`, `shown`, `hidden[id]`, `layout`, `room`, `labels`, `labelsFor[id]`). The bar is built at
  `ADDON_LOADED`, and every block repaints at `PLAYER_ENTERING_WORLD`. `/gpanel` handles
  `list | move <id> <lane> [n] | layout reset | show <id> | hide <id> | toggle | font | room |
  covered | failures`.
- **`Plugins\<Name>\`**: deploy puts each at the AddOns top level under its TOC name, and
  `.pkgmeta` `move-folders` does the same when packaging (the AltStable pattern).

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. Advice that cites a TBC or Classic API is usually stale, and that
includes Titan's code and the owner's TBC plugins.

## References: read these before touching an unfamiliar API

- `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact. Other sessions edit this file, so
  write new addon-agnostic findings there, not into a copy here. Read "False friends" before
  porting any TBC call: several moved APIs return a struct instead of a tuple
  (`C_SkillInfo.GetSkillLineInfo`, `C_Container.GetContainerItemInfo`).
- `C:\Projects\References\forever-api-1.60.1.70009.md` is the full API dump: functions, events,
  **widget methods** (the only list of those) and the `_G` walk. It proves a name exists, not
  that it works. `GetProfessions` is listed but returns `nil x7`.
- In game: `/api search <name>`.

## Forever facts that matter for a data bar

- **Secret values.** Some numbers come back as values you can hold but not read: arithmetic,
  comparison, `tostring`, concatenation and truth-testing all throw. **`GetMoney` was measured
  secret** on a PvP realm, along with `UnitStat`, `UnitArmor` and `UnitAttackPower`. `UnitXP`,
  `UnitXPMax`, `GetXPExhaustion` and `UnitLevel` were plain in the same scan. Treat secrecy as
  per-API and situational: test every number with `API.IsSecret` before touching it, and show an
  honest "hidden" instead of a guess. Store `nil` for unknown, never `0`.
- `UnitXPMax(...) or 1` doesn't guard against zero at the level cap (0 is truthy).
  `GetMaxPlayerLevel()`, not `MAX_PLAYER_LEVEL` (nil). `GetAverageItemLevel()` returns
  fractions.
- `UnitName(unit)` returns only the first name for anyone but the player. Use
  `GetUnitName(unit, false)` and key on `UnitGUID`.
- `RegisterEvent` throws on unknown names and returns `false` for refusals. The engine wraps
  both. `COMBAT_LOG_EVENT_UNFILTERED` can't be registered.
- `GetInstanceInfo()` returns the continent outdoors, so gate on `instanceType ~= "none"`.
- Tooltips hooking items use `TooltipDataProcessor`. Options, if ever needed, go through
  `Settings.RegisterAddOnCategory`. **Edit Mode is live.**
- **SavedVariables persist as of 70009.** Code must still cope when they're absent. Verify
  persistence only with a full client exit.

## Toolchain and commands

There's no build system. The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\`
(`lua.exe`, `luac.exe`). Use it, not a newer Lua that may be first on `PATH`.

```powershell
pwsh tests\run.ps1                                                 # luac -p on every TOC's files (core + plugins) + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_engine.lua  # one test, run from the repo root
pwsh Tools\deploy.ps1                                              # core -> AddOns\GlassPanel, each Plugins\X -> AddOns\<toc name>
python Tools\make_textures.py                                      # regenerate Media\*.tga (prefer doing it in GlassUnitFrames)
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to override).
- Deploy rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token.
- In game: `/console scriptErrors 1`, then `/reload`. Check the AddOns list shows the addon
  enabled and **not flagged out of date**. A brand-new addon folder needs a client restart.

## Addon basics

- One TOC per addon: the core's `GlassPanel.toc` and each plugin's
  `Plugins\<Name>\GlassPanel<Name>.toc`. No `_Forever`/`_Camelot` suffix; every one has
  `## Interface: 16001` (**`11601` is a transposed-digit bug**) and `## Version: @project-version@`.
- One global namespace table, `GlassPanel`. Every file starts `GlassPanel = GlassPanel or {}`.
- Plugins reach the core only through `GlassPanel.RegisterBlock`, `GlassPanel.Refresh`,
  `GlassPanel.API` and `GlassPanel.Glass`. Anything else is internal and may change. Bump
  `GlassPanel.API_VERSION` on an incompatible contract change and update `docs/PLUGINS.md` in the
  same commit.
- Keep a `_test` seam table at the bottom of a file to expose internals to tests. Don't promote
  internals to globals.

## Testing

`tests\` follows GlassUnitFrames': plain Lua 5.1, `tests\wow_stubs.lua` (driven through `WoW`),
`tests\harness.lua` (`check` / `eq` / `loadAddon` / `block` / `textOf`), and `tests\run.ps1`.

- **Each plugin's stubs live in `tests\stubs\<plugin>.lua`**, loaded automatically, with a
  `WoW.resetHooks` entry for per-session state, so plugins built in parallel don't all edit
  `wow_stubs.lua`.
- **The stub is an allowlist**, with strict globals. Before stubbing a global, confirm it's in
  the dump and copy its signature. Defining something Forever lacks lets a broken call pass.
- Event names are validated against the dump. `test_methods.lua` checks every widget method
  called against the dump's widget-method list.
- Secrets are `newproxy` userdata that throw on use. `WoW.moneySecret = true` makes `GetMoney`
  secret. No Lua 5.1 value can make a truth test or `==` throw, so those misuses are caught only
  in game and in review.
- `loadAddon()` loads the core, then every plugin (after the core's `ADDON_LOADED`). A test file
  that asserts on lanes sets `PLUGINS = { ... }` to pin which plugins load, so a new plugin
  doesn't reshuffle them; `opts.plugins = false` loads the core alone.
- `loadAddon()` starts a fresh session (new namespace, new frames) and keeps client data the
  test set on `WoW`. `opts.before` runs between file load and `ADDON_LOADED`.
- **Mutation-test a new test**: break the behaviour and confirm it goes red.
- Offline tests can't cover rendering, real secret behaviour or layout on screen. Those need
  the game.

## Workflow (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review → squash-merge. **The owner merges,
  closes PRs and launches reviews.** Never commit to `main`, never `gh pr merge`. Commit or push
  only when asked. Before committing, `pwsh tests\run.ps1` must be green.
- Adversarial review goes through `/codex-consult` (`.claude/skills/codex-consult/`), launched
  by the owner, with Fable as the fallback. Verify its claims before acting, and push back on
  complexity for a single-owner addon.
- Releases are built by CurseForge's packager from the tag webhook, reading `.pkgmeta`. Every
  tag needs a `CHANGELOG.md` entry, written for players.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config. Grow the block contract when a real block needs it (the XP bar will
  need a fixed width), not before.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
