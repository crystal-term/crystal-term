# Plan 031: `term-vt` — stop dropping zero-width marks (combining chars, VS16)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: `Screen#print` still drops zero-width
> characters (`rg -n "return if width == 0" shards/vt/src/vt/screen.cr` →
> 1 match), `Cell` has no extras/grapheme field
> (`rg -n "extras|grapheme" shards/vt/src/vt` → 0 matches).

## Status

- **Priority**: P2 (this is a data-loss bug for assertions, not just a
  feature gap)
- **Effort**: M
- **Risk**: MED (changes `text`/`snapshot` output for inputs containing
  zero-width chars — that is the point — and adds a field to the public
  `Cell` struct)
- **Depends on**: — (independent; touches `Screen#print`, same as 029 —
  see coordination note)
- **Category**: vt hardening (README "Unsupported" burn-down)
- **Planned at**: root commit `d9f941c`, vt submodule `v0.3.0` (`5c72959`),
  2026-07-06

## Why this matters

Today `Screen#print` returns early for width-0 characters, so decomposed
text loses its marks: feeding `"e\u{301}"` (e + combining acute) yields
screen text `"e"`, and `screen.contains?("é")` is false no matter which
normalization the assertion uses. Any TUI that emits NFD text (common on
macOS filenames), Arabic/Hebrew diacritics, Indic scripts, or emoji
variation selectors renders assertions untrustworthy. The vt README lists
"Grapheme clusters; width-0 combining marks are dropped" under
Unsupported.

Scope is deliberately the *attachment* half of that bullet: keep every
zero-width char by attaching it to the cell it modifies. Full grapheme
clustering (UAX #29 segmentation, ZWJ emoji joining into one cell,
mode-2027-style width changes) stays out of scope — see STOP conditions —
and the README bullet gets rewritten, not deleted.

## Target design

### Cell (`shards/vt/src/vt/cell.cr`)

Add `property extras : String? = nil` — the zero-width characters attached
to this cell, in feed order. `char` stays `Char` (public contract
unchanged); the common no-marks case costs one nil pointer per cell.
`blank?` is unaffected (a cell with extras has a non-space char in
practice; if a space gains extras it is legitimately not blank — guard
`blank?` with `@extras.nil?`).

### Screen (`shards/vt/src/vt/screen.cr`)

Replace the `return if width == 0` early-out in `print` with attachment:

- Find the target cell: normally `(@cursor_row, @cursor_col - 1)`; when
  `@pending_wrap` is true the last-printed cell is at
  `(@cursor_row, @cursor_col)` (cursor pinned to the last column); if the
  target is a `continuation` cell, step left once more to the wide lead
  cell.
- Append the char to that cell's `extras` (cells are structs — write the
  modified copy back into the row).
- No target (cursor at column 0 of a fresh row, nothing printed there):
  drop the char, as xterm does.
- Uniform rule: **every** width-0 char attaches (combining marks, VS16
  `U+FE0F`, ZWSP, directional marks). One rule, no special cases; the
  goal is byte-preservation for assertions.
- VS16 does **not** change the cell width (wcwidth-compatible; matches
  xterm). Document this explicitly in the README.
- Cursor, `@pending_wrap`, and grid geometry are untouched by a width-0
  print. Overwriting a cell (`print`, erase, `clear_wide_pair_at`) already
  replaces the whole struct, so extras clear naturally — verify, don't
  add code.

### Output surfaces

- `row_to_text` (feeds `row_text`/`rows_text`/`text`/`find`/`contains?`):
  emit `char` then `extras`. Note `find`/`contains?` remain exact-match —
  no normalization; document that assertions must match the app's byte
  form.
- `snapshot` (`shards/vt/src/vt/snapshot.cr` + wherever padding is done):
  include extras. The "every row padded to `screen.cols`" contract means
  padding counts **cells**, not codepoints — a row with marks has more
  codepoints but the same cell count; state this in the README snapshot
  section.
- `styled_snapshot`: extras join their cell's segment text.

### Docs + version

- README: rewrite the Unsupported bullet to
  "Grapheme clustering (UAX #29): zero-width marks attach to the preceding
  cell, but ZWJ sequences occupy multiple cells and VS16 does not widen."
  Update the Supported Sequences UTF-8 row and the snapshot-format section.
- `shard.yml`: bump to `0.4.0` unless this wave already bumped it.

## Specs

New `spec/screen/combining_spec.cr` (+ additions to `snapshot_spec.cr`):

- `"e\u{301}"` → `text == "e\u{301}"`, `contains?("e\u{301}")` true, cell
  at (0,0) has `char == 'e'`, `extras == "\u{301}"`.
- Multiple marks on one base; marks on a wide (CJK) lead cell; mark
  arriving while `pending_wrap` is true attaches to the last column's
  cell; mark at column 0 of an untouched row is dropped.
- VS16 after a narrow emoji: attached, width still 1, cursor unmoved.
- Overwrite clears extras; ED/EL clear extras.
- `dup` (Session snapshot path) deep-copies rows already — assert a
  post-dup feed does not mutate the copy's extras.
- Snapshot padding: row with marks still has exactly `cols` cells' worth
  of padding; styled_snapshot emits marks inside the segment.
- Fuzz suite (`spec/fuzz_spec.cr`) still passes.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Build CLI | `cd shards/vt && shards build --no-color` | `bin/term-vt` exists |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |
| Smoke | `cd shards/vt && ./bin/term-vt snapshot -- sh -c 'printf "e\xcc\x81\n"'` | `é` (NFD) in output |

## Steps

1. `Cell#extras` + `blank?` guard.
2. `print` attachment logic (target-cell resolution first — it is the
   only subtle part; write the pending-wrap and continuation specs before
   the code).
3. Output surfaces (`row_to_text`, snapshot, styled_snapshot) + specs.
4. README rewrite, version, full verification, `plans/README.md` row.

## STOP conditions

- Any pre-existing spec expectation must change: STOP — no current spec
  feeds zero-width chars, so churn means a regression.
- You are tempted to implement ZWJ joining, UAX #29 segmentation, or
  VS16 width promotion (mode 2027): STOP — rewrite the README bullet
  instead; that is a separate, larger plan.
- `Cell` needs to grow beyond the single `extras` field (e.g. a `String`
  grapheme replacing `char`): STOP and report — that is a breaking API
  redesign the operator must approve.

## Git workflow

`shards/vt` is a git submodule (`crystal-term/vt`), currently detached at
`v0.3.0`. Work there first:
`git -C shards/vt fetch origin && git -C shards/vt checkout -b watzon/plan-031 origin/main`,
conventional commits. Then in the root repo branch from `main`, commit the
submodule pointer bump + `plans/README.md` row. Push nothing without
operator instruction.

Coordination: 029 also edits `Screen#print` (insert mode). Either order;
second to merge rebases. Note for 029's insert-mode shift: a width-0 char
must never trigger the insert shift (it writes no cell).
