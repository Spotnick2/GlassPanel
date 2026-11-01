# Audit: the GP1 setup-string parser (untrusted input)

Issue #131, branch `audit/share`; row #5 of the owner's audit list, shared with TitanLayer's
NovaWorldBuffs listener (TitanLayer #1, its own `docs/AUDIT.md`). The question audited, as one
property: **any text given to `Share.Decode` either yields the setup `Share.Clean` would produce from a
valid export, applied exactly as the preview said, or `nil` and a reason with nothing changed; never a
throw; work and memory bounded by `MAX_INPUT` and `MAX_NODES`; and nothing an import plants reaches a
code path that prints or runs it unescaped.** The plan was reviewed with Codex gpt-6-astra (medium) in
three rounds to consensus (2026-10-30/31); section 3 has the summary.

Facts met on the way, not fixed here:
- The newest API dump is **70532** (`References\Forever\api`); `MEASURED_ON_BUILD` is 70338. The bump is
  the `client-update` skill's job.
- `RegisterBlock` accepts ids longer than `MAX_STRING` (128); an export holding one refuses the whole
  setup with a reason ("This setup can't be shared"). Documented, unchanged: no plugin has one.

## 1. Trace

What a pasted string goes through, with the bound or check at each stage.

| Stage | What happens | Bound or check |
|---|---|---|
| The import box | `SetMaxLetters(MAX_INPUT)`, 16384 raw characters; `preview()` runs `Share.Decode` on every `OnTextChanged` | a paste is one preview; typing a 16 k string by hand isn't a case |
| `Share.Decode` | raw length (**G2**, new) → strip whitespace → length → prefix (`GP<n>:` says "made by a newer GlassPanel") → `b64decode` → `deserialize` → `Share.Clean` | raw ≤ 2·MAX_INPUT; stripped ≤ MAX_INPUT; base64 strict (length a multiple of 4, the alphabet only, padding only in the last quad) |
| `deserialize` | our own format: `s<len>:`, `n<num>;`, `T`/`F`, `t…e` | depth 6, 2000 nodes including keys, 128-char strings, numbers through `[%-%+%.%deE]+` (so "nan", "inf", "0x10" can't match) and finite, keys string or number, a repeated key or trailing data refuses |
| `Share.Clean` | allowlists for font, room, glass, tint, window glass; booleans; id maps with a per-key value check; lanes strict (`isList`, `x` in [0,1], ids non-empty strings, none twice, empty lanes dropped); unknown keys dropped, missing ones default | a wrong type refuses the whole string and says why |
| `Share.Apply` → `Settings.ApplyAll` | replaces the four maps (never merges), `Layout.Clean`, one layout pass | keeps glass, tint and window glass while following Glass UI (#96) |
| Afterwards | `GlassPanelDB.layout`, `hidden`, `labelsFor`, `iconsFor` hold the imported ids; `/gpanel list` prints them; the preview and the chat line describe the setup | ids bounded per import by the node cap and replaced by the next import; printed ids escaped (**G1**); the preview says what's kept (**G7**). Options rows are per loaded plugin only; `Describe` prints counts and allowlisted values |

## 2. Findings and fixes

Read first, confirmed by a test that fails with the fix reverted ("witness": run before the fix, red;
after, green). Lines as of this branch.

| # | Finding | Fix | Witness (reverted → red) |
|---|---|---|---|
| G1 | `/gpanel list` printed ids raw in all four of its branches (unloaded, loaded, hidden, replaced-by) and the replacement id, and nothing in the core escapes `\|`: an imported id carrying `\|T…\|t`, `\|H…\|h` or `\|c` painted chat with a texture, a link or a colour. `Share.lua`'s comment said ids are "never shown" | `shown(id)` escapes `\|` as `\|\|` for every printed id (`GlassPanel.lua`, list); the comment corrected. Not refused at import: ids stay anything `RegisterBlock` accepts (what the core exports, it imports) | `test_share` "G1: the unloaded id is escaped", "a loaded id is escaped", "no bare texture escape reaches chat", "no bare colour escape reaches chat" (4) |
| G7 | While following Glass UI, `ApplyAll` keeps our glass, tint and window glass, but the preview ("Ready: …") and the post-import chat line reported the imported ones as applied | `describeImport`: `Describe` plus "(glass, tint and window glass kept: set in Glass UI)" at the two import call sites. `Describe` alone still labels an export, where those values are the exported ones | "G7: the preview says glass, tint and window glass are kept", "the chat line says so too" (2); "Describe itself unchanged" |
| G2 | `Decode` stripped whitespace over the whole input before any length check, so the public API had no work bound for a long whitespace-padded string | the raw length is refused over 2·MAX_INPUT first. Ordinary line wrapping of a full-size export stays under it, and the box caps raw text at MAX_INPUT anyway | "whitespace past twice the cap: rejected", "says why", "too long" (3) |

Pinned, no defect (G5, 15 checks): `nnan;`, `ninf;`, `n0x10;` and `n-;` are "bad number"; `1` and `1.0`
as keys are a "repeated key". A seeded sweep (G3, its own generator so every platform tries the same
inputs: 300 mutations of a real export, 150 random byte payloads, 150 random structures) finds that
`pcall(Share.Decode)` never throws and always says why, and that every accepted setup satisfies
`Clean`'s invariants (3 checks). A sweep, not a witness: it pins "no crash", nothing else.

Read and dropped (not defects):
- **Per-keystroke reparse** is quadratic only while typing a long string by hand; a paste is one preview.
- **Many lanes of unknown ids** (an import can plant ~500): `Bar.Layout` skips an id with no block and
  reads the cached lanes; bounded by the node cap.
- **`shown = false` imported** hides the bar: the preview says "bar hidden"; `/gpanel toggle` brings it back.
- **`hidden`/`keep`/`replaces` (#50)** interact only through `ApplyAll`'s existing path.
- Benchmarks and a larger fuzz campaign: cut after Codex's first round as ceremony.

## 3. Codex rounds

- **R1:** no input makes `Share.Decode` throw. G1 is real and wider than planned (all four list
  branches, the replacement id, the false comment). G7 found (preview vs apply while following). The
  strip-before-length order (G2). For TitanLayer: a part count is the wrong bound, use a byte budget
  per message on every frame kind, before decoding; clear stale spools. Cut the cold extra-agent pass,
  benchmarks, large fuzz runs and per-assertion mutation checks.
- **R2:** G7 belongs at the import call sites, not in `Describe` (it labels an export too), and names
  window glass. G2's witness must be whitespace (a long non-whitespace string already said "too long").
  Stale spools: drop before the GUILD and own-message skips. T4's guard before the first concatenation.
- **R3:** one stale line in the plan's file list. Consensus.

## 4. In game

Two strings built offline from the owner's saved setup (both accounts hold the same layout), in the
session's scratchpad: `gp1-escape.txt` is that setup plus one unloaded id that carries a texture and
a colour escape; `gp1-restore.txt` is the setup as it was.
1. `/gpanel import`, paste `gp1-escape.txt`, Import. The preview says "17 block(s) in 2 lane(s)".
2. `/gpanel list`: the lane at 0% ends with
   `|TInterface\Icons\INV_Misc_QuestionMark:24|t|cffff0000painted|r (not loaded)` shown as **text**, in
   grey: no question-mark icon, nothing painted red.
3. `/gpanel import`, paste `gp1-restore.txt`, Import: the odd id is gone, the layout as before.

_Results: pending the owner's session._
