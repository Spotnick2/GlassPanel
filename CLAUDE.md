# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassPanel is an **info bar addon for World of Warcraft: Forever 1.60.1** (Interface `16001`),
written in **Lua 5.1**. It's a single-owner project (Spotnick), on the same stack and conventions
as the sibling Forever addons `..\GlassUnitFrames`, `..\AltStable` and `..\Priestly`. When this
file doesn't cover something, check how those handle it before you invent a new idiom.

**Goal:** a streamlined, liquid-glass replacement for the owner's Titan Panel setup. It's one bar
across the top of the screen with only the readouts actually used, plus a small plugin API so
the owner's own Titan plugins (`C:\Projects\WoW\TitanPanelXPP`, `TitanLayer`, `TitanGearScore`,
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

Core TOC load order: `Libs\LibGlass-1.0\LibGlass-1.0.xml` → `Compat.lua` → `Suite.lua` → `Glass.lua` → `Engine.lua` → `Layout.lua` → `Bar.lua` →
`Room.lua` → `Edge.lua` → `Floats.lua` → `Settings.lua` → `Share.lua` → `Setup.lua` → `Options.lua` → `GlassPanel.lua`. Plugins load after the
core's `ADDON_LOADED`.

- **`Compat.lua`**: `GlassPanel.API`, the only route to client APIs that moved or may be absent.
  It has `IsSecret`, `RegisterEvent` (reports throws and refusals, naming the block that asked),
  `Fail(key, err)` (**the one failure recorder**, `GlassPanel.failures`, read by
  `/gpanel failures`), `CoinText`, and `Suppressor(globalName)`, which hides a Blizzard frame
  while our block replaces it and only restores what it hid (the clock's
  `TimeManagerClockButton`). **Only for plain frames.** Frames Blizzard manages (#9) go through
  `SystemHider(globalName)`: reparented to a hidden frame, **never `Hide()`** (protected
  `SetShownBase` on Edit Mode systems), on a timer (never inside Blizzard's call), **given back
  while `EditModeManagerFrame` is shown** (its `OnShow`/`OnHide` hooks only schedule) so it can be
  seen and moved there, after combat if protected,
  re-checked on `EDIT_MODE_LAYOUTS_UPDATED`; Blizzard's own `SetParent` is noticed via
  `hooksecurefunc` and undone the same way; `Set(false)` gives it back to the parent Blizzard last
  gave it. **Never reparent a frame whose children call it through `GetParent()`** (Edit Mode's
  status bar containers do). `Button(parent, text, width, onClick)` is the
  one push-button helper, and `Window(name, w, h)` the one glass dialog (FULLSCREEN_DIALOG,
  Escape, a title and a wrapping hint; the look is the `windowGlass` setting (#93): `reflective`, the default,
  is LIBGLASS-WINDOW-STYLING's shell on `CleanGlass()` with r9's `Glass.Reflect`, a masked backing (#36)
  and a masked reading region `win.pane` under the hint; `smoked`, and a library older than r9, the
  earlier opaque masked backing. Read when a window is built: a built one keeps its look until /reload): Share, Setup and
  Currencies use it. `API.Plain(v)` is the one "secret becomes nil" guard;
  use it at every read. `API.Returned(v)` asks "did the client return anything" without comparing:
  **never write `raw ~= nil` on a raw read**, since comparing a secret (even with nil) throws on
  the client, and the offline stub can't catch it. The global `GetCoinTextureString` is **absent** (70009, still in the 70338 dump);
  use `C_CurrencyInfo`'s. `MEASURED_ON_BUILD` lives here too; the login notice for another build
  speaks only in a **development copy** (`API.IsDevelopmentCopy`: version `dev` from deploy, or the
  raw `@project-version@`), never in a release (Priestly #76: what flags an addon out of date is the
  TOC's Interface, not this notice), and **once per new build** (`GlassPanelDB.notedBuild`), not at
  every login.
- **`Suite.lua`** (#96): Glass UI's suite theme (`GlassUI\docs\SUITE.md`; Glass UI is optional, `## OptionalDeps: GlassUI`). Asked **once per session**, by `Glass.lua` at file scope before any glass is built: `rawget(_G, "GlassUI")`, `Suite` a table with `API == 1` exactly and `Theme`/`Report` functions (anything else is absent), then `pcall(Suite.Theme, "GlassPanel")`; a table with `preset == "pearl"` means **following** (opt-in, on Glass UI's page). Following suspends `glass` (the bar's body: the built look shows), `glassTint` (#102: painted neutral) and `windowGlass` (windows are Reflective): both stay saved untouched, `Settings.SetGlass`/`SetGlassTint`/`SetWindowGlass` refuse, `/gpanel glass|tint|window` say "set in Glass UI", an import keeps them, the options radios are greyed with a note and an "Open Glass UI" button (`Suite.Open`, feature-detected with `rawget`, called under pcall). Still local: the font. **The accent** (#106): the stock UI's gold text (bar captions, window titles) goes through `Suite.Accented(fs)`: Blizzard's gold, or `Suite.Accent()` (feature-detected, under pcall, three plain numbers 0-1 else gold) while following, repainted live on `EventRegistry` `GlassUI.Suite.LookChanged` (registered only when following). Status colours (yellow low counts, "waiting") are not accent. `Suite.Report` (under pcall, `suite:report`) tells Glass UI `{ api = 1, built, reason, minor, options }`: `built = "pearl"` only when following and built, `reason` `"library-too-old"`/`"build-failed"` when it was following and couldn't. Never reads or writes Glass UI's data.
- **`Glass.lua`**: `GlassPanel.Glass` is this addon's instance of
  the material (#57; see "The glass material" below), built **Pearl** (LibGlass r11's preset, our own default look and the suite's, #96) with `{ preset = "pearl" }`; a library older than r11 (checked by MINOR) or a `New` that errors falls back to the earlier look (`lib:New()`), recorded as `glass:pearl` and reported. No retry: LibGlass never restyles a built instance. `GlassPanel.CleanGlass()` (public, #78): a
  second instance (Pearl when the main glass is Pearl, else r6's clean preset), made once on demand, `nil` when the loaded copy's MINOR is
  under 6 (the newest copy among glass addons runs). Surfaces only: text stays on `GlassPanel.Glass`
  (the font setting). The panel itself stays classic.
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
  - A relayout runs only when some text changed, or a width or what a block displays (#78).
  - `width` may be a function (#78), asked once per repaint in `Bar.SetText` (before its
    unchanged-text return) and cached as `b.fixedWidth`: a number >= 16 is a fixed width, a plain
    nil sizes the block to its content; anything else (secret, NaN, inf, < 16, a throw) is recorded
    as `<id>:width` and sized to content. A content-sized graphical block with empty text and its
    icon off displays its label (else its id) so it never shrinks to padding (`syncDisplay`, also
    run by `UpdateIcon`; `b.text` stays the block's own answer).
  - `onDoubleClick(block, button)` (#78): `OnDoubleClick` is wired only for a block that has it
    (the others keep two `onClick`s), behind the same after-a-drag guard as `onClick`.
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
  `MEDIUM`, `Glass.Apply(..., "small")` painted by `Bar.ApplyGlass` (#65: `Bar.GLASS` and
  `Bar.GLASS_TINTS` are the one allowlist. Clear is the surface **as built** (`SetSurfaceTint(g)`,
  the instance's grain and wash), so it follows the library; smoked is AltStable's body, its grain
  and wash as region-alpha scales of the built ones; the class colour from `C_ClassColor` × the
  preset's `classShade` through `Glass.SetSurfaceTint` (**LibGlass r3+**, embedded r7). Painted last
  in `Bar.Build`, under pcall (`API.Fail("bar:glass")`); a class colour not readable yet sets
  `Bar.glassPending`, is said once by the setter, and is retried at `PLAYER_ENTERING_WORLD`), mouse-less so
  empty space clicks through), one plain
  `Button` per block (icon, a gold **caption** `b.caption` "Label: " (#23; `Bar.ShowsCaption`: never
  on graphical blocks, then `labelsFor[id]`, then `labels`, then the spec's `showLabel`), the
  value `b.label`, `HIGHLIGHT` hover), placing them from
  `Layout.lua`, and dragging: a marker shows the drop slot, shift-drag moves a lane by the
  cursor's displacement, a drag under 10 px is a wobbly click (no move), the release that ends a
  drag isn't a click, and the drop target is recomputed after any relayout mid-drag. Hidden and empty blocks take no space. **Nothing is secure**, so the bar may be touched in combat.
- **`Edge.lua`** (#97): the top edge GlassPanel occupies, announced for the suite (GAB's EdgeState / EdgesChanged pattern). `GlassPanel.EdgeState()` returns a fresh `{ top = n }` (UIParent units down from the screen's top to the lowest bottom of what we occupy there: 0 for nothing, `Bar.HEIGHT` for the bar), nil before the first measure, and EventRegistry `"GlassPanel.EdgeChanged"` `(top)` fires at the first measure, then out of combat on a move over 0.5 (a combat change at `PLAYER_REGEN_ENABLED`; `EdgeState` still has it). The bar counts while shown; a plugin's frame counts through `API.TrackTopEdge(frame)` (XP+'s zoomed bar) while visible and in the top band (its top within `MARGIN` 40 of the screen's top or the bar's bottom), converted from its own scale; any unreadable value skips the frame. `API.UpdateTopEdge()` after it moves; a measure runs on the next frame, coalesced, on the engine's 1 s clock and on scale/display events. Additive: `API_VERSION` unchanged.
- **`Floats.lua`** (#108): zoomed plugins that float on the screen (XP+'s bar, the combat pill) never overlap. `API.RegisterFloat(frame, { order, placed, place })` (once per frame; it tracks the frame for the top edge too): an **unplaced** float (no saved spot) sits in a **default slot**, `API.FloatDefaultY(frame)`, stacked down from the top (`Floats.TOP` -40) under every shown, unplaced float of lower `order` (XP+ 1, the pill 2), with `Floats.GAP` between; a float that declares `topRow` (XP+: its text row) lets an `overlay` float (the pill) sit between the bar and the float's own bar instead when it fits there (else it stacks under it), clear of the game's red error text; `API.PlaceFloats()` (after one shows or hides) places the others again; `API.SnapFloat(frame)` (after a drop, before saving the spot) moves the frame clear of any overlapping shown float by the smallest shift (`Floats.Snap`, pure). **A saved spot stays exactly where the player put it**: nothing moves it but a drop onto another float. Additive: `API_VERSION` unchanged.
- **`Room.lua`**: making room for Blizzard's top frames (#2) **without moving any of them**. The
  bar measures a short watch list (`Room.WATCH`: minimap cluster, buffs, debuffs, ticket status,
  unit frames) and pulls its ends in to stop short of any that reach into its band. A frame hidden
  **on its own** (no target, no buffs) still counts, so the width doesn't jump; one whose
  **parent** is hidden has been replaced by an addon and doesn't. Frames centred in the middle
  fifth are ignored. **Buffs and debuffs (#33) count by their icons, not the frame**
  (`BuffFrame`'s rect is Edit Mode's whole grid). Measured on 70009: the icons hang off
  `BuffFrame.AuraContainer` / `DebuffFrame.AuraContainer`, a **1x1 anchor** that doesn't size to
  them; `BuffFrame` also holds a visible `CollapseAndExpandButton` (15x30). So the icons are the
  outermost visible frames under `AuraContainer` between `ICON_MIN` (8) and `ICON_MAX` (100)
  units a side (bigger containers and smaller anchors are looked into, `DEPTH` 4), plus the
  collapse button while shown (a live button). Their union only grows within a session (the bar
  steps in once, then doesn't jiggle); a new session: layout/scale/display events
  (`Room.NewSession`), Edit Mode closing, or the aura frame's rect changing. Nothing is recorded while `EditModeManagerFrame` is shown
  (example auras). No icon yet: they take no room. **`DamageMeter`** (#40, Blizzard's built-in
  meter, `TOPLEFT` 0,0 in both presets, measured) is watched too, with its session windows
  (`Room.EXTRA`: the secondary ones can sit anywhere, so each shown one is **its own rect**, never
  merged with the meter's, and counts only when the meter does). **Shown, it always counts** (Edit Mode shows
  a switched-off meter); hidden and switched off (`damageMeterEnabled` not true, or Visibility
  Hidden; `Room.OFF`, probes under pcall) it takes no room. InCombat/InGroup and "not available yet"
  (level-gated) keep its place. `/gpanel room why` reports the last check
  (read-only). Pure `Room.Insets`; read-only `GetRect`/`IsShown`/`IsVisible`/`GetChildren` under pcall,
  every number through `API.Plain`; `Room.Update` never throws (failures go to `API.Fail`).
  Checked on layout, scale and display events and on the engine's clock (`Engine.EverySecond`:
  one clock for everything). `/gpanel room full` opts out; `/gpanel covered` lists frames in the
  band as "under" or "beside" the bar. Moving Blizzard's frames at runtime was rejected after
  research and a Codex review (see #2 and the porting guide's Edit Mode note); an opt-in Edit
  Mode layout setup is #10.
- **`Plugins\XP\XP.lua`**: XP+ (#3), the only graphical block so far (`width`/`build`/`paint`).
  Four layered bars on one `Glass.Bar` host, after TitanPanelXPP's icon (`Interface\Icons\XP_Icon`, #43;
  the host anchors to the block's empty caption, so the Icon toggle gives the space back). A level crossing is detected by the level or max
  changing (not by XP going down). **Plugin option "Hide Blizzard's XP bar"** (#9, off by default,
  `GlassPanelXPDB.hideBlizzard`): `StatusTrackingBarManager` is hidden through `API.SystemHider`
  only while XP+ is on screen (`onShown`), and given back otherwise. **Not
  `MainStatusTrackingBarContainer`** (measured: its `UpdateShownState` calls
  `GetParent():CheckForLayoutChange()`, so under our frame Edit Mode threw a nil call); the manager
  doesn't use its parent. A watched rep bar (the secondary container) hides with it, as in Titan.
  **Zoomed (#78):** a left double-click on the block (its icon) toggles `GlassPanelXPDB.detached`.
  Zoomed, `width` returns nil (the panel keeps the icon alone, the handle that docks it back) and
  `paint` hides the panel's host and draws the **float**: a plain `Button` on UIParent built on the
  first zoom (`makeBar` + rows above/below, after the owner's WeakAura; the outer frame holds the rows
  so clamping covers them), shown while zoomed **and** XP+ is on screen (`onShown`: hiding XP+, the
  panel or the level cap hides it). Shift-drag moves it (`moving` tracked; a plain drag saves nothing;
  hidden mid-move stops unsaved); the spot is CENTER offsets from UIParent's centre in
  `GlassPanelXPDB.spot`, checked whole (a bad field: the default, TOP 0,-40) and from live
  `GetCenter()` values checked plain and finite before subtracting. Right-click: a `MenuUtil` menu
  (`CreateButton`: back to the panel, reset session, reset position; no `MenuUtil`: right-click
  docks). Its bar and its optional **glass backing** (`GlassPanelXPDB.backing`, off by default: a
  `Glass.Apply(back, "small")` on its own frame at the float's level, so the body is under the bar
  and the rims around it; clamp insets grow with it) are built on `GlassPanel.CleanGlass()` when
  there is one; the backing is painted like the panel through the public `API.MatchPanelGlass(g,
  glass)` (`Bar.surfaces`, repainted by `Bar.ApplyGlass` with **its own instance's** style, so a
  clean surface gets no grain). **Scale** 0.5-2 (0.05 steps; the plugin's slider option, `GlassPanelXPDB.scale`, 1 stored
  as nothing, a corrupt one reads 1): the spot stays in screen units, so SetPoint offsets are divided
  by it and `GetCenter()` multiplied by it (GUF's `PlaceAt`). A 1 s `C_Timer` ticker repaints it only while shown. Its scripts, ticker and menu items
  run under `guarded` (`xp:float`). Figures from one `stats()` snapshot (the tooltip's too).
  **Rested lines** (#81; measured on 70374 by RestProbe, `docs/FOREVER-PROBE.md`):
  - **The cap:** Well Rested's rank from its Legacy node (tree 1188, node 110301, `C_Traits`;
    `ID ~= 110301` or a secret means unknown, so no cap line). Cap = 1.5 levels × (1 + 0.04 × rank)
    (unmeasured: the talent's text at 5/5).
  - **"Full in (resting)"** while `IsResting()`, at the measured 5% × (1 + 0.04 × rank) of a level
    per 8 h.
  - **XP buffs by spell ID**, since tooltip data loads lazily: Well Fed 1248406, Camp Benefits
    1229741, and the Camp Tent lockout Boosted Rest 1229451, a debuff. Another buff counts only if
    its tooltip says "experience". Secret auras are skipped.
  - Drawn under `pcall` (`xp:rested`).
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
- **`Plugins\Combat`** (#108): a combat timer. On the bar, crossed swords (`Ability_DualWield`, unmeasured) and "Out of Combat", or the fight's time from our own `GetTime()` stamp at `PLAYER_REGEN_DISABLED` (Glass Unit Frames' format: `00:07`, `1:00:05`; a /reload mid-fight counts from the reload, entering the world inside a fight keeps its start). **Zoomed** (left double-click, `GlassPanelCombatDB.detached`, as XP+): the bar says "In Combat"/"Out of Combat" (docked it shows the timer) and a **glass pill** (92x26, text 12, scaled by `GlassPanelCombatDB.scale`, default 1.5 = XP+'s usual, spot in screen units as XP+; painted like the panel through `MatchPanelGlass`) floats on UIParent **only while in combat** (or a 30 s preview from the plugin's option, to place it); shift-drag moves it (spot in `GlassPanelCombatDB.spot`, a float of order 2, see `Floats.lua`), right-click a menu. **Glass Unit Frames' own timer**: the plugin's option "Use this timer instead of Glass Unit Frames'" calls `GlassUF.Settings.SetCombatTimer(not on)` (feature-detected, under pcall) **from the click only** and reads `GlassUF.Timer.enabled` each time the options open; the state is never copied, never applied at login (one printed hint, once ever, when both would show).
- **`Plugins\Role`** (#20): the group role (`UnitGroupRolesAssigned`) with its inline icon, hidden
  when not `IsInGroup`. Left-click: a `MenuUtil.CreateContextMenu` of radio items (Tank, Healer,
  Damage, No Role) calling `UnitSetRole`. A menu that throws changes nothing (it's reported); only
  a client with no `MenuUtil` gets the fallback, a click that cycles the role (never from an
  unreadable one). A picked role stays pending until `ROLE_CHANGED_INFORM` /
  `PLAYER_ROLES_ASSIGNED` (5 s). A refused or throwing `UnitSetRole` prints one line.
- **`Plugins\Layer`** (#17): the zone field of creature GUIDs (not on a taxi or in an instance;
  secret GUIDs skipped via `API.Plain`, readable ones count in combat), numbered by rank among the
  zone ids seen **on the same uiMapID** (local numbers: nothing says how many layers exist). A new
  id is filed only from the target or mouseover, never when known on another map; nameplates only
  confirm (border creatures). `GlassPanelLayerDB.realms[realm][map][zone] = GetServerTime()`
  (nil time: nothing saved), forgotten after 2 h. Rescans target > mouseover > nameplates on
  entering the world, combat end, taxi end, a uiMapID change (`ZONE_CHANGED[_INDOORS]`) and
  5/15/30 s after a group change. The current layer holds only while the live uiMapID is the one it
  was seen on (checked at every read). Map and player phase changes make it unknown. No NWB listener (#26). Left-click forgets the current map's layers.
- **`Plugins\GearScore`** (#16): TitanGearScore's per-item formula on a fixed 200-point bracket
  scale (not derived from `GetBuildInfo`), plus Blizzard's `GetAverageItemLevel()` equipped value.
  Items via `GetInventoryItemID`/`Link` and `C_Item.GetItemInfo` (the global `GetItemInfo` is
  absent), looked up by id. An uncached item is requested once, left out and flagged with a grey
  `?`; `ITEM_DATA_LOAD_RESULT`/`GET_ITEM_INFO_RECEIVED` fire for every item the client loads, so
  they're registered on the plugin's own frame only while one of ours is pending (a failed load
  makes it unreadable until the next gear change). Score `nil` until known.
  `PLAYER_AVG_ITEM_LEVEL_UPDATE` repaints without a rescan. No click.
- **`Plugins\Currencies`** (#47): the currencies the player picks, in their order (icon + amount),
  from `C_CurrencyInfo`'s list, not a hardcoded table (TitanCurrenciesMulti's way). Forever's five
  (Wowhead Forever: Merchant's Favor 3402, Tarnished Undermine Real 3469, Honor Points 1792, Rank
  Points 3468, Darkmoon Prize Ticket 515) are offered by id even before owning any. The currency tab
  is never expanded by us (collapsed headers hide rows); ids come from the list rows' `currencyID`.
  Picks per character (`## SavedVariablesPerCharacter: GlassPanelCurrenciesDB`); never chosen: up
  to 3 owned ones, **saved once found** (the bar doesn't change by itself). A chooser window (tick,
  Up/Down on the shown ones; unresolved saved ids kept at the end) from a left-click or the plugin's
  option **button**; refreshed at most once per frame. Secret amount: grey `?`; measured plain for
  Honor Points (36 / 15,000).
- **`Plugins\Reagents`** (#68): the class reagents the player picks, in their order (after the block's
  own icon and caption "Reagents: ", as Bags; then icon + count each, a red `0` when none are left), Currencies' chooser on a **hardcoded per-class table** of item ids
  (`CLASS`, keyed by `UnitClass`'s file name; nothing in the client says which items a class uses).
  Poisons are in the client's consumables list; the other ids are Vanilla's (Informant: class
  Reagent), unmeasured. Icons from `C_Item.GetItemInfoInstant` (no item data needed), else
  `GetItemIconByID`; a class id with neither (or the question mark, 134400) is **pending, not
  unknown** (a fresh cache): requested through the name loader, kept (bar, chooser, default picks)
  drawn as the question mark, and left out only once its load fails with still no icon (#71).
  Counts from `C_Item.GetItemCount` (bags);
  names from `C_Item.GetItemNameByID`, **asked for only by the tooltip and the chooser** (the bar
  and the default search read counts and icons), requested only while `IsItemDataCachedByID` says
  not cached, once, and listened for on the plugin's own frame only while pending (GearScore's
  pattern); an **answered** id (loaded or failed) is never re-requested (a nameless load would loop
  through the open tooltip), and a missing name only costs the name: a grey `item <id>`, icon and
  count kept. Sharing the chooser with Currencies and the loader with GearScore: #74. **No ammo, soul shards,
  healthstones or soulstones** (their own plugins, #66/#67). Hunters and warriors have no list, so
  no block (not registered when `UnitClass` reads plainly at load; a class unreadable then gets the
  block, hidden and offering nothing while it stays unreadable). Picks per character
  (`GlassPanelReagentsDB`), never chosen: up to 3 carried, worked out again until the session's first
  `BAG_UPDATE_DELAYED` (bags fill after `PLAYER_ENTERING_WORLD`), then saved once found.
- **`Plugins\AltStable`** (#46): a **bridge** to the sibling addon AltStable (`## Dependencies:
  GlassPanel, AltStable`, so it loads only with it): total gold of the characters AltStable knows,
  a tooltip by realm (class colour, level, gold, the logged-in one marked, hidden ones left out and
  counted), left-click `AltStable.ToggleSheet()`. Reads **only AltStable's public API**
  (`..\AltStable\docs\PUBLIC-API.md`, `PUBLIC_API_VERSION` 1), never `AltStableDB`; any other
  version: no block, one printed line and a failure. Repaints on its `CharactersChanged` callback
  (no events). Default scope is every character, `GetTotals()` (the sheet's own figure); the plugin
  option "Only this realm and faction" (`GlassPanelAltStableDB.realmOnly`) sums the logged-in
  character's realm and faction itself, unknown until AltStable has this character; a record with no
  realm or faction isn't counted but is flagged and said. Unknown money is a grey `?`, never 0 (no
  known gold at all: only `?`). AltStable's own icon (file ID 8197123), never a coin (Gold's reason);
  `replaces = "gold"` (#50: **live**, `Bar.ReplacedBy` inside `Bar.IsHidden`: Gold is hidden
  while this block is registered and not hidden, never stored, so a character with the plugin off or
  a refused block keeps Gold; an explicit Show of Gold stores `keep.gold` whatever Alts is
  doing, an explicit Hide clears it; the chat line is said once, with the bar on, at
  `PLAYER_ENTERING_WORLD` or when a setting change brings the replacement on). The bar text reads
  only `GetTotals()`.
  GlassPanel keeps no character list (forgetting is AltStable's).
- **`Plugins\Bags`** (#13): used/total over normal bags (family 0; ids from `Enum.BagIndex`);
  special bags (quiver, soul bag, the reagent slot) are listed apart and not counted. An unreadable
  bag (free count or family) is left out and flagged with a grey `?`. Left-click: `ToggleAllBags`.
- **`Plugins\Warlock`** (#67): warlocks only: another class **doesn't register the block** (class read at
  load; unreadable then: registered, nil text until it reads WARLOCK, then kept). Soul Shards (6265,
  `C_Item.GetItemCount`; yellow under 5, red at 0) and a mark per stone carried, any rank (healthstones
  incl. the talented 19004-19013, soulstones; best rank named in the tooltip). An unreadable count is
  a grey `?` for shards and no mark for a stone (the tooltip says unknown); an unreadable better rank
  makes the best stone unknown too, never a lower rank guessed. Counts are a snapshot (Durability's
  stale pattern). Cooldowns from `C_Container.GetItemCooldown(itemID)`, read only when the tooltip is
  drawn, so `BAG_UPDATE_COOLDOWN` (most casts) isn't registered; an unreadable one is a grey `?` and
  the footnote says so. `enable == 0` with a duration is "waiting" (held, greyed in the bags), <= 1.5 s
  is the GCD (ready). No `interval`: a 1 s `C_Timer` ticker runs only while the tooltip is open on the
  block with a cooldown counting down ("waiting" alone doesn't tick). Names from `C_Item.GetItemNameByID` (localised), English fallback. No click
  (using a stone is secure).
- **`Plugins\Ammo`** (#66): hunters, warriors and rogues only. On the bar, as Bags: its own
  icon, the caption "Ammo: " and the count (which ammo it is: the tooltip). The ranged slot (18) decides the
  kind from `C_Item.GetItemInfoInstant` (Weapon: Bows/Crossbow → arrows, Guns → bullets, Thrown →
  the slot's own stack; anything else: no block). Projectile subclasses Arrow 2 / Bullet 3 have no
  enum (item data). `UnitUsesAmmo` (**new in 70338**; Blizzard shows `CharacterAmmoSlot` on it) is
  the client's gate: a plain `false` hides arrows/bullets (thrown ignores it); absent or unreadable,
  the weapon decides. Count: `GetInventoryItemCount("player", 0)`, or that ammo in the bags when
  the count can't be read (an unreadable thrown stack: its bags, with a grey `?`); none equipped or
  the wrong kind: the matching projectiles in the bags with a red `!`. `GetItemInfoInstant` may
  return nothing for an item the client hasn't seen: that item is **pending**, never definite (#73).
  Its data is requested (Reagents'/GearScore's loader: `IsItemDataCachedByID` guard, load events on
  the plugin's own frame only while one is pending, an `answered` id never asked again) and the
  block rescans on arrival. Meanwhile an unresolved weapon shows no block, an unresolved bag item
  makes the count unsure (grey `?`), and equipped ammo of unknown kind is counted (the slot) with a
  grey `?`, never "wrong". Item classes are cached per id once resolved (never a nil). The
  scan runs under pcall (Durability's pattern: `ammo:scan` recorded, still stale). Yellow under low, red under critical (strictly below), per class in
  `GlassPanelAmmoDB.thresholds[CLASS]` (defaults hunter 600/200, warrior and rogue 100/40; a
  corrupt pair falls back), set in a small window (left-click or the plugin option button).
  **Measured (70338, hunter):** the ammo slot's count totals that ammo across the bags (1,100 =
  six quiver stacks), as in Vanilla. **Unmeasured:** `UnitUsesAmmo` for warriors and rogues; the thrown count, and whether it includes the same weapon
  in the bags (the tooltip would count those twice). stubs/ammo.lua wraps `C_Item.GetItemInfoInstant`
  and `IsItemDataCachedByID` once at the first reset: `WoW.items` first (`pending = true`: not
  seen yet), else the other stubs'.
- **`Plugins\Durability`** (#12): lowest durability and repair cost. Events only mark the
  cache stale; it's rebuilt at most once per repaint (tooltip data is heavy, and only for damaged
  items). An unreadable item marks the figure with a grey `?` and makes the cost unknown; the cost comes from
  `C_TooltipInfo.GetInventoryItem(...).repairCost` (TitanRepair's Retail path, not in the dump:
  unknown is shown as unknown). Secret numbers keep type `"number"` on the client, so
  `type(x) == "number"` is no secrecy check: `API.Plain` first.
- **`Settings.lua`**: `GlassPanelDB`'s defaults (`EnsureDefaults`) and **the one place a setting
  is changed and applied** (`SetFont`, `SetShown`, `SetRoom`, `SetGlass`, `SetGlassTint`, `SetLabels`, `SetLabelFor`,
  `SetIconFor`, `SetHidden`, `ResetLayout`, and `ApplyAll` for a whole imported setup, with one
  layout pass). `/gpanel`, the options panel and an import all call these, so they can't drift
  apart. Each calls `Settings.listener` after a change: an open options panel re-reads its controls.
- **`Share.lua`** (#34): the setup (`font`, `shown`, `room`, `glass`, `glassTint`, `windowGlass`, `labels`, `hidden`, `labelsFor`,
  `iconsFor`, and the **effective** layout from `Layout.Lanes`) as `GP1:` + base64 of our own
  serialisation (sorted keys: same setup, same string). The input is **never run as code**: hard
  limits (16k chars, depth 6, 2000 values, 128-char strings), then `Share.Clean` checks every key
  and type: ids are any non-empty string (**what `RegisterBlock` accepts: anything the core
  exports, it imports**), lanes are checked strictly (a bad lane or a block listed twice rejects;
  empty lanes are dropped). Unknown keys dropped, missing ones default, a wrong type rejects the
  whole string and says why. Applied at once through `Settings.ApplyAll`, no reload. An export is
  decoded again before it's shown, so an oversized setup says so instead of handing out a string
  the import would refuse. The window is a glass frame with a multi-line EditBox (selected for
  Ctrl+C: addons have no clipboard), in `UISpecialFrames` for Escape; Import is enabled only for a
  string that parses, and previews what it holds.
- **`Setup.lua`** (#10): the **opt-in** full-width alternative to Room: `/gpanel setup` (or the
  panel's "Make room in Edit Mode...") shows a plan, then writes an Edit Mode layout. Designed from
  the forever UI source and a Codex review: copies the **active** layout whole (keeps
  `interfaceStyle`, drops the preset-only `layoutIndex`) into a new **Character** layout
  "GlassPanel" (**not Account**: measured, a new Account layout lands before every character's own
  layouts and characters keep their active layout by index, so another character switched to it),
  inserted where Blizzard's `MakeNewLayout` puts one (last), saved with
  `C_EditMode.SaveLayouts` (presets + saved, active index unchanged) then `OnLayoutAdded(i, true,
  false)`. Moves only systems anchored top-to-top on UIParent (minimap, buffs, debuffs, damage
  meter) by clamping the **saved** `offsetY` to `-(bar height + 2)` and `isInDefaultPosition =
  false` (StatusTrayManager re-anchors a default-position BuffFrame): a second run is a no-op. An
  existing "GlassPanel" is **never written to** (a save from outside Edit Mode leaves Blizzard's
  in-memory `layoutInfo` stale, and its next save would put the old offsets back): the player is told
  to move things in Edit Mode, or delete it and run again. Refused in combat,
  with Edit Mode open or not loaded, under an override layout, or at 5 Character layouts; the plan is rebuilt at Apply. "Saved" and "activated" are reported apart.
  `/gpanel setup back` returns this character to its recorded source (a preset by enum, a saved one
  by name and type), written only after a new GlassPanel is saved (replacing any stale one) and
  kept after switching back. A reload is recommended. Measured in game: the Modern preset result, switch
  back, and no taint reports.
- **`Options.lua`** (#24): Options > AddOns > Glass Panel, a canvas panel on Retail's Settings
  framework (as GlassUnitFrames #39), registered at `PLAYER_LOGIN`. **Our `Settings` local shadows
  Blizzard's global `Settings`**: the framework is read with `rawget(_G, "Settings")`. Bar (shown,
  captions, font, width, glass, tint), Layout (reset), Share setup (Export / Import), plugin options
  (checkbox, button, or slider: hand-built after GUF's, `min`/`max`/`step`/`fmt`, validated in
  `RegisterBlock`; a refresh never writes back), and a row per loaded plugin
  (Shown, Caption, Icon; Caption greyed for graphical blocks, Icon for blocks without one), all in
  name order (a plugin registered later gets its row on the next open, where its name sorts).
  Every open, and every setting change while it's open, re-reads the state.
- **`GlassPanel.lua`**: `GlassPanelDB` (`font`, `shown`, `hidden[id]`, `layout`, `room`, `glass`
  (`clear`|`smoked`), `glassTint` (`neutral`|`class`), `windowGlass` (`reflective`|`smoked`, #93), `labels`,
  `labelsFor[id]`, `iconsFor[id]` (only `false` is stored), `keep[id]` and `replaced["new>old"]` (#50: the player showed a
  replaced block again; the one-time "replaces" line was said) and `notedBuild` (the last client build
  the dev notice was said for), none of them part of a shared setup). The bar is built at
  `ADDON_LOADED`, and every block repaints at `PLAYER_ENTERING_WORLD`. `/gpanel` handles
  `list | move <id> <lane> [n] | layout reset | labels | label <id> | icon <id> | show <id> |
  hide <id> | toggle | font | glass | tint | window | room | options | export | import | covered | failures`.
- **`Plugins\<Name>\`**: deploy puts each at the AddOns top level under its TOC name, and
  `.pkgmeta` `move-folders` does the same when packaging (the AltStable pattern).

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume Vanilla
content and the Retail API. Advice that cites a TBC or Classic API is usually stale, and that
includes Titan's code and the owner's TBC plugins.

## The glass material

The material is **LibGlass-1.0**, an embedded LibStub library (`..\LibGlass`,
github.com/Spotnick2/LibGlass, public, MIT) that every glass addon embeds (#57; the migration
guide is `C:\Projects\WoW\References\Docs\LIBGLASS-MIGRATION.md`). Its repo owns the code, the textures,
the generator (`Tools/make_textures.py`) and the write-up (`docs/GLASS-MATERIAL.md`: layers,
parameters, gotchas, history), and its `CLAUDE.md` holds the contract (the API, region fields and
texture names only grow; instances; upgrade rules).

- **Material changes are LibGlass PRs**, never edits here. A bug or a need found here goes on a
  LibGlass issue. Never edit `..\LibGlass` from this repo's session.
- **How it's embedded:** in the **core only** (plugins depend on the core and use
  `GlassPanel.Glass`). `.pkgmeta` externals put it in `Libs\LibGlass-1.0\` (the only supported
  path: `MEDIA` is derived from it), and the core TOC loads its XML first. `Libs/` is gitignored;
  a dev copy comes from the LibGlass checkout (`$env:LIBGLASS`, default `..\LibGlass`) through its
  own `Tools\deploy.ps1`, which `Tools\deploy.ps1` here calls first (a refusal leaves the deployed
  addon untouched). The tests load the same checkout and fail loudly without one.
- **The pin:** `.pkgmeta` pins a commit or tag (`r11` since #96: Pearl; r9 since #93: `API.Window`'s reflective shell is r9's `Glass.Reflect`; r7: the smoked wash goes through r7's `SetWash`; r6's clean preset for the zoomed XP+ bar; the bar's tint needs r3's
  `SetSurfaceTint`), **never `tag: latest`**, and **no comment on a
  value line** (the packager keeps it in the value). Bump it only in a release made anyway: players
  get library fixes earlier through whichever glass addon ships the newest copy (LibStub runs that
  one). `tests\run.ps1` and deploy warn when the checkout isn't at the pin (one check,
  `Tools\LibGlassPin.ps1`, reading the LibGlass entry as `fetch_libglass.sh` does). CI
  (`.github/workflows/package-check.yml`) fetches the pin (`tests/fetch_libglass.sh`), tests
  against it, and asserts the zip holds exactly the core, its library (that commit's shipped files)
  and each plugin folder.
- **`GlassPanel.Glass` is an instance**: `STYLE`, the setters and the font registry are this
  addon's own, so our font setting never touches another glass addon. `Glass.MEDIA` resolves to
  the winning copy's `Media\`; use it only for library textures (`bar_fill`, `bar_edge`, ...). A
  plugin's own art goes under its own path.
- **Colours passed to a glass bar's `SetStatusBarColor` must be plain** (the library's hook
  compares them): never a secret.

## References: read these before touching an unfamiliar API

- `C:\Projects\WoW\References\Docs\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact. Other sessions edit this file, so
  write new addon-agnostic findings there, not into a copy here. Read "False friends" before
  porting any TBC call: several moved APIs return a struct instead of a tuple
  (`C_SkillInfo.GetSkillLineInfo`, `C_Container.GetContainerItemInfo`).
- `C:\Projects\WoW\References\Forever\api\forever-api-1.60.1.70338.md` is the full API dump: functions, events,
  **widget methods** (the only list of those) and the `_G` walk. It proves a name exists, not
  that it works. `GetProfessions` is listed but returns `nil x7`. **The `_G` walk includes the
  globals of whatever addons were loaded** (70124 and 70338 list `GetMapID`, `GetTalentData`, `ConvertID`,
  absent from 70009): before stubbing a global, find it in `wow-ui-source` or the documented
  functions, not only in "Global functions".
- `C:\Projects\WoW\wow-ui-source` is Blizzard's UI source (Gethe/wow-ui-source), on the **`forever`**
  branch: the client's own FrameXML, with the same paths and line numbers as BugSack traces. Read the
  exact Blizzard line there before guessing, and check what a Blizzard frame expects of its parent
  before hiding or reparenting it (#39). Other sessions share it, so check the branch first.
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
- Tooltips hooking items use `TooltipDataProcessor`. Options go through
  `Settings.RegisterCanvasLayoutCategory` + `RegisterAddOnCategory` (`Options.lua`). **Edit Mode is live.**
- **SavedVariables persist as of 70009.** Code must still cope when they're absent. Verify
  persistence only with a full client exit.

## Toolchain and commands

There's no build system. The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\`
(`lua.exe`, `luac.exe`). Use it, not a newer Lua that may be first on `PATH`.

```powershell
pwsh tests\run.ps1                                                 # luac -p on every TOC's .lua files (core + plugins) + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_engine.lua  # one test, run from the repo root
pwsh Tools\deploy.ps1                                              # LibGlass -> AddOns\GlassPanel\Libs, core -> AddOns\GlassPanel, each Plugins\X -> AddOns\<toc name>
pwsh Tools\deploy.ps1 -Probe                                       # ...and ForeverProbe + each Tools\<X>Probe (-ProbeOnly: just those)
```

Both need the LibGlass checkout at `..\LibGlass` (or `$env:LIBGLASS`).

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to override).
- Deploy rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token.
- In game: `/console scriptErrors 1`, then `/reload`. Check the AddOns list shows the addon
  enabled and **not flagged out of date**. `/reload` loads a brand-new addon folder too; exit the
  client fully only to test persistence.
- **Probes** (`Tools\<X>Probe`) are ForeverProbe modules (`References\Docs\PROBES.md`, the host's
  `docs/GUIDE.md`): `/fp` console and their own saved log, never chat; guided procedures with
  `Probe:Steps`; results read from `WTF\...\SavedVariables\<X>Probe.lua` and `ForeverProbe.lua`
  after the owner's `/reload`, and written to `docs/FOREVER-PROBE.md`. `.pkgmeta` ignores `Tools`, so
  they never ship. **Probe tests run locally only** (ForeverProbe is private: no token, no pin, no
  secret): a test of a probe loads the host from `..\ForeverProbe` (or `$env:FOREVERPROBE`), where a
  missing checkout is an **error**, and CI sets `FOREVERPROBE_OPTIONAL=1` and skips it (none exists
  now: RXPProbe's went with the RestedXP plugin, #98). **RestProbe** (#81): the rested pool against the cap, **Well Rested** (a node in Forever's
  account-wide Legacy trees, read through `C_Traits` as Blizzard_MicroMenu's Camelot override does:
  Adventure 1188, Progression 1189, Professions 1187; matched by spell name), XP buffs (auras with
  their IDs) and the rested build-up rate: `/fp steps rest rested`.

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
  called against the dump's widget-method list. Without the dump (CI: it's local only) every
  event name is accepted and `test_methods` skips; a test that needs an unknown name marks it
  (`WoW.KNOWN_EVENTS.X = false`).
- The tests run on Windows and on CI's Linux: list folders through `WoW.list(dir, ext)`, never a
  bare `dir` or `ls`, and match file names' case exactly.
- `loadAddon()` expands the core TOC's LibGlass XML line from the checkout (`libGlassScripts`) and
  drops `LibStub` with the old session, so each session loads the library afresh.
- Secrets are `newproxy` userdata that throw on use. `WoW.moneySecret = true` makes `GetMoney`
  secret. No Lua 5.1 value can make a truth test or `==` throw, so those misuses are caught only
  in game and in review.
- `loadAddon()` loads the core, then every plugin (after the core's `ADDON_LOADED`), **like the
  client only when its `## Dependencies` are installed**: the core, and `WoW.installed` for the
  others (AltStable's stub always). A test file
  that asserts on lanes sets `PLUGINS = { ... }` to pin which plugins load, so a new plugin
  doesn't reshuffle them; `opts.plugins = false` loads the core alone.
- `loadAddon()` starts a fresh session (new namespace, new frames) and keeps client data the
  test set on `WoW`. `opts.before` runs between file load and `ADDON_LOADED`.
- **Mutation-test a new test**: break the behaviour and confirm it goes red.
- Offline tests can't cover rendering, real secret behaviour or layout on screen. Those need
  the game.

## Workflow (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review → squash-merge. **The owner merges,
  closes PRs and launches reviews.** Never commit to `main`, and no `gh pr merge` before the owner's
  approval (say "merge N"), except for a documentation-only PR. Commit or push only when asked, with one exception: **a fix for review
  findings (Codex, `/code-review`) on an open PR is committed and pushed to that PR's branch at
  once, without asking**, and reported. Before committing, `pwsh tests\run.ps1` must be green.
- Adversarial review goes through `/codex-consult` (`.claude/skills/codex-consult/`), launched
  by the owner, with Fable as the fallback. Verify its claims before acting, and push back on
  complexity for a single-owner addon.
- Releases are built by CurseForge's packager from the tag webhook, reading `.pkgmeta`. Every
  tag needs a `CHANGELOG.md` section `## vX.Y.Z` (written for players; off a tag the check reads
  `## Unreleased`). `package-check.yml` is the one workflow (`References\Docselease`'s template, RELEASING.md §2):
  `check` on every run (tests, dry-run package, allowlist, `tests/release_files.sh` writing `notes.md` and
  `release.json`, the file WoWUp reads), then on a `v*` tag `release` (a GitHub Release: that same zip, `release.json`,
  the tag's notes) and `wago` (the same zip to Wago project `n6VYw3Nd`, the TOC's `X-Wago-ID`, with the
  `WAGO_API_TOKEN` secret). `alpha`/`beta` tags are pre-releases. `workflow_dispatch` (tag, both|github|wago)
  publishes an existing tag again.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config. Grow the block contract when a real block needs it (the XP bar will
  need a fixed width), not before.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
