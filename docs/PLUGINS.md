# Writing a GlassPanel block

A block is one item on the bar: an optional icon, a line of text, an optional tooltip and click.
Every block is a plugin: an addon of its own under `Plugins\<Name>\` that registers blocks
through the API below. That includes GlassPanel's own blocks (XP+, Gold, Clock), so a user can
switch any of them off in the AddOns list. Third-party plugins use the same API.

## A plugin addon

```
Plugins\GearScore\GlassPanelGearScore.toc
Plugins\GearScore\GearScore.lua
```

```
## Interface: 16001
## Title: |cff7fd4ffGlass|r Panel |cFF0099FF[GearScore]|r
## Notes: ...
## Author: Spotnick
## Version: @project-version@
## Group: GlassPanel
## IconTexture: Interface\Icons\INV_Misc_Gem_Variety_01
## Dependencies: GlassPanel
## SavedVariables: GlassPanelGearScoreDB

GearScore.lua
```

`## Group: GlassPanel`, the `Glass Panel [X]` title and the core's icon nest it under
`Glass Panel [Core]` in the AddOns list (the AtlasLoot Forever style). The folder is deployed and
packaged under the TOC's name (`GlassPanelGearScore`, AltStable's naming); add its
`move-folders` line to `.pkgmeta` (`tests/test_toc.lua` checks). Every Lua file starts with
`GlassPanel = GlassPanel or {}`.

`## Dependencies: GlassPanel` guarantees `GlassPanel.RegisterBlock` exists when the plugin's
files run. Registering before or after the bar is built both work: an early block is attached
when the bar builds. A plugin keeps its own SavedVariables. The core stores only whether a block
is hidden.

## The contract

```lua
GlassPanel.RegisterBlock({
    id       = "gearscore",            -- required, unique; also the /gpanel show|hide name
    label    = "GearScore",            -- the gold caption "GearScore: " and /gpanel list (default: id)
    showLabel = true,                  -- false: no caption by default (the user can still turn it on)
    caption  = function(block) end,    -- a caption that changes ("Olympus: " for Guild); nil/"" = label
    icon     = 132627,                 -- file ID or path; optional
    side     = "left",                 -- default lane: "left", "center" or "right" (users drag it anywhere)
    order    = 60,                     -- in the default lane, lower sits nearer the bar's end (default 100)
    events   = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    unitEvents = { UNIT_FACTION = "player" },  -- an every-unit event, for one unit only
    interval = nil,                    -- seconds (>= 1), or function(block) -> seconds, for data with no event
    onInit   = function(block) end,    -- once, at registration (before your SavedVariables load!)
    onEvent  = function(block, event, ...) end,  -- every event, immediately: update state here
    text     = function(block) return "GS: 2057" end,  -- plain string, or nil/"" for no space
    tooltip  = function(block, tt) tt:AddLine("GearScore") end,  -- tt is GameTooltip
    onClick  = function(block, mouseButton) end,
    onShown  = function(block, visible) end,     -- appeared on / left the screen (hide, empty text, bar toggle)
})
```

A block that draws more than text (the XP bar, `Plugins\XP\XP.lua`) adds:

```lua
    width = 360,                            -- fixed width in px; "" text then still shows the block, nil hides it
    build = function(block) end,            -- once, when block.widget exists: create your own frames on it
    paint = function(block) end,            -- after every repaint while its text is valid and non-nil and it's on screen
```

`onInit` runs when you call `RegisterBlock`, which is usually while your files load, **before**
your own SavedVariables exist. Read them in your own `ADDON_LOADED` handler (filtered on your
addon's name), then call `GlassPanel.Refresh(id)`.

`RegisterBlock` returns the block (the table you passed, with fields added) or `nil` after
printing why it refused. `GlassPanel.Refresh(id)` repaints a block on the next frame when its
data changed without an event. `GlassPanel.API_VERSION` is `1`.

## Rules the engine enforces

- **Events belong to the engine.** List them in `events` and don't create a frame to listen.
  Each event runs `onEvent` right away, and the block repaints **once** on the next rendered
  frame, however many events arrived. Keep `text` cheap and free of side effects: it may run on
  any frame.
- **An event name the client doesn't know is reported, not fatal.** `/gpanel failures` lists it
  and the block still paints.
- **Every callback runs under `pcall`.** Every failure is recorded in `/gpanel failures`, and
  a failing `text` also shows a red `error` mark on the bar. The rest of the bar keeps working.
- **`text` must return a plain string.** A secret value is refused at the boundary, because the
  bar measures text width and does arithmetic on it. Test reads with `GlassPanel.API.IsSecret`
  and return a label like `"hidden"` instead. `GetMoney` has been measured secret on a PvP
  realm, so assume any number may be.
- **Blocks are not secure.** A click can't cast, use an item or target anything in combat. Open
  a window, print, or toggle state instead.

## Helpers

`GlassPanel.API`: `Print`, `IsSecret`, `Plain`, `CoinText(copper)` (coin icons, `nil` for a secret),
`RegisterEvent(frame, name, owner)` for the rare plugin that must own a frame, and `Fail(key, err)`
to record into `/gpanel failures`, and `Suppressor(globalName)` to hide a Blizzard frame your block
replaces while it's on screen (`s.Want(visible)` from `onShown`, `s.Sync()` when a load-on-demand
Blizzard addon loads). It only shows the frame again if it hid it. Use it only for plain frames,
never for Edit Mode system frames (taint risk, #9). `Plain(v)` returns `v`, or `nil` when it's
secret: use it at every read before comparing or doing arithmetic.

`GlassPanel.Glass` is the material (`Apply`, `Bar`, `Font`, …) for a block that draws more than
text, such as the XP bar. See `..\GlassUnitFrames\docs\GLASS-MATERIAL.md`.
