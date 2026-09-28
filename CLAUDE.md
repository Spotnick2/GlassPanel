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

**Status: scaffold.** The core runs with the gold and clock blocks. Work goes through GitHub
issues and PRs (the repo name will be GlassPanel).

## Layout

TOC load order: `Compat.lua` → `Glass.lua` → `Engine.lua` → `Bar.lua` → `Blocks\*.lua` →
`GlassPanel.lua`.

- **`Compat.lua`**: `GlassPanel.API`, the only route to client APIs that moved or may be absent.
  It has `IsSecret`, `RegisterEvent` (reports throws and refusals, naming the block that asked),
  `Fail(key, err)` (**the one failure recorder**, `GlassPanel.failures`, read by
  `/gpanel failures`), `CoinText`, and `Suppressor(globalName)`, which hides a Blizzard frame
  while our block replaces it and only restores what it hid (the clock's
  `TimeManagerClockButton`). **Only for plain frames**: not Edit Mode system frames like
  `MainStatusTrackingBarContainer` (#9). `API.Plain(v)` is the one "secret becomes nil" guard;
  use it at every read. The global `GetCoinTextureString` is **absent** on 70009;
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
  - one shared 1 s clock drives `interval` blocks;
  - every block callback runs under `pcall` via `Engine.Call`;
  - `text` must return a plain string. Secrets and non-strings are refused and recorded.
  - A relayout runs only when some text changed.
- **`Bar.lua`**: the strip (`GlassPanelBar`, full width at the top of `UIParent`, strata
  `MEDIUM`, `Glass.Apply(..., "small")`, mouse-less so empty space clicks through), one plain
  `Button` per block (icon, `Glass.Font` label, `HIGHLIGHT` hover), and the layout. There are two
  lanes, `left` and `right`, sorted by `order` then registration. Hidden and empty blocks take
  no space. **Nothing is secure**, so the bar may be touched in combat.
- **`Blocks\XP.lua`**: XP+ (#3), the only graphical block so far (`width`/`build`/`paint`).
  Four layered bars on one `Glass.Bar` host. A level crossing is detected by the level or max
  changing (not by XP going down). Blizzard's XP bar is left alone (#9).
  `/played` is requested with `TIME_PLAYED_MSG` muted on the chat frames, one request at a time
  (a token ties the unmute, the next frame after the answer or after 10 s, to its own request),
  **never** by replacing `ChatFrame_DisplayTimePlayed`. Graphical blocks aren't painted while off
  screen; `Bar.Layout` marks them dirty when they come back.
- **`Blocks\*.lua`**: built-in blocks. They register through the **public** API, exactly as a
  plugin would, so the built-ins keep the contract honest.
- **`GlassPanel.lua`**: `GlassPanelDB` (`font`, `shown`, `hidden[id]`). The bar is built at
  `ADDON_LOADED`, and every block repaints at `PLAYER_ENTERING_WORLD`. `/gpanel` handles
  `list | show <id> | hide <id> | toggle | font | failures`.
- **`Plugins\<Name>\`**: each is a separate addon (`## Dependencies: GlassPanel`). Deploy puts
  each at the AddOns top level, and `.pkgmeta` `move-folders` does the same when packaging (the
  AltStable pattern).

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

- One plain `GlassPanel.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**).
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

- **The stub is an allowlist**, with strict globals. Before stubbing a global, confirm it's in
  the dump and copy its signature. Defining something Forever lacks lets a broken call pass.
- Event names are validated against the dump. `test_methods.lua` checks every widget method
  called against the dump's widget-method list.
- Secrets are `newproxy` userdata that throw on use. `WoW.moneySecret = true` makes `GetMoney`
  secret. No Lua 5.1 value can make a truth test or `==` throw, so those misuses are caught only
  in game and in review.
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
