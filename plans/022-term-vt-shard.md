# Plan 022: New shard `term-vt` — VT/ANSI parser + cell-grid screen model

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: confirm the shard does not exist yet:
> `ls shards/vt` (expect: missing), `rg -n "term-vt" shards scripts --glob '!lib'`
> (expect: 0 matches outside plans/). If either hits, reassess — someone
> started this.

## Status

- **Priority**: P2 (direction; unblocks a family-wide testing upgrade)
- **Effort**: L
- **Risk**: MED (new surface area; correctness risk is contained by the
  documented sequence subset and a fuzz spec — nothing existing depends on it
  yet)
- **Depends on**: none (fully independent of the other eight shards)
- **Category**: direction
- **Planned at**: commit `1457d14` (root), 2026-07-05

## Why this matters

Every interactive shard in this family tests by asserting on raw escape-byte
strings, and the plans history documents the damage: plan 011 removed
production code that string-matched test-double class names to suppress redraw
sequences; plans 002/003 were bugs that shipped *because* spec paths diverged
from production paths; `shards/reader/spec/regression/multiline_echo_regression_spec.cr:31`
strips ANSI with a regex; `TestIO` is duplicated verbatim in
`shards/spinner/spec/helpers/test_io.cr` and `shards/progress/spec/helpers/test_io.cr`;
prompt's specs bypass IO entirely (`list.keydown` et al.), so the
reader→prompt input path is never exercised.

The fix is structural: an in-process terminal emulator — feed any shard's
output bytes into a VT parser that maintains a cell grid, then assert on
**what a user would see** (`screen.text`, `screen.find("❯ Select")`,
`screen.cursor`) instead of which bytes were emitted. This is the converged
2025–2026 industry design (microsoft/shell-use, termless, terminal-control,
phantom, ratatui-testlib all: parser → cell grid → query API), and the one
cautionary counterexample (charm's teatest, which diffs raw bytes and is
flaky in CI by its own author's admission) confirms the parser is the
non-negotiable piece.

The Crystal niche is empty (no VT-parsing shard exists; all ANSI shards are
write-only), so this shard also has ecosystem value beyond the family. Plan
023 builds the PTY/subprocess harness on top; this plan is deliberately
in-process only.

## Current state

- No parsing exists anywhere in the family: `cursor`/`color` only emit
  sequences, `screen` only detects size, `terminfo` maps capability names to
  sequences, `reader` matches input escape *prefixes*
  (`shards/reader/src/reader/keys.cr`) but does not parse output.
- Precedent for a new shard: plan 018 — `shards/progress` began as a **plain
  directory tracked by the root repo** (not a submodule), with GitHub
  repo/submodule conversion as a later OPERATOR step. This plan follows that
  exactly: `shards/vt/` is a plain directory; publication is out of scope.
- Harness: `scripts/validate-shards.sh` hardcodes
  `ALL_SHARDS=(color cursor screen terminfo reader spinner prompt progress)`
  (line 6) plus per-shard `case` arms for path (line ~50) and validity
  (line ~64). The new shard must be added to all three.
- Conventions to match: stdlib `spec` (not Spectator — see AGENTS.md; new
  shards use stdlib), `src/term-vt.cr` entry requiring `src/vt/*.cr`,
  namespace `Term::VT`, MIT license, `.editorconfig` copied from a sibling,
  `crystal tool format` clean. Author line as in
  `shards/progress/shard.yml`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | all pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |
| Full harness still green | `scripts/validate-shards.sh --local` | exit 0 |

(`shards install` inside `shards/vt` is a no-op — the shard has zero
dependencies. Do not add any.)

## Scope

**In scope**:
- New plain directory `shards/vt/` (shard name `term-vt`, namespace
  `Term::VT`, version `0.1.0`): parser, screen model, style/cell types,
  char-width table, snapshot + query API, spec suite, README.
- Root: `scripts/validate-shards.sh` (add `vt`), `AGENTS.md` (layout +
  dependency-order mentions), root `README.md` ownership table (add row,
  marked "plain directory, pre-publication"), `plans/README.md` status row.

**Out of scope** (do not do):
- PTY, subprocess spawning, wait/timing primitives, spec matcher sugar → plan 023.
- Converting sibling-shard specs to use `term-vt` → later plans.
- GitHub repo creation / submodule conversion / release → OPERATOR, later.
- Scroll regions (DECSTBM), tab-stop set/clear (HTS/TBC), insert mode (IRM),
  origin mode (DECOM), mouse protocols, DSR/CPR responses, grapheme clusters,
  resize reflow. Each must be **listed in the README as unsupported**. The
  design must not preclude adding them later.

## Target design

### File layout

```
shards/vt/
  shard.yml                 # name: term-vt, version: 0.1.0, no dependencies
  LICENSE                   # MIT, copy from sibling
  README.md
  .editorconfig             # copy from sibling
  src/term-vt.cr            # requires ./vt/*
  src/vt/version.cr         # Term::VT::VERSION = "0.1.0"
  src/vt/style.cr           # Style struct + Color union
  src/vt/cell.cr            # Cell struct
  src/vt/width.cr           # Term::VT::Width.of(Char) : Int32
  src/vt/parser.cr          # byte state machine → Performer callbacks
  src/vt/performer.cr       # Performer module (callback interface)
  src/vt/screen.cr          # Screen — includes Performer, owns grid state
  src/vt/snapshot.cr        # plain + styled snapshot rendering
  spec/spec_helper.cr
  spec/parser_spec.cr
  spec/width_spec.cr
  spec/screen/print_wrap_spec.cr
  spec/screen/cursor_movement_spec.cr
  spec/screen/erase_edit_spec.cr
  spec/screen/sgr_spec.cr
  spec/screen/modes_spec.cr      # DECTCEM, DECAWM, alt screen
  spec/screen/osc_scrollback_spec.cr
  spec/screen/resize_spec.cr
  spec/snapshot_spec.cr
  spec/query_spec.cr
  spec/fuzz_spec.cr
  spec/fixtures/                 # captured real-output byte fixtures
```

### Parser (`Term::VT::Parser`)

Implement Paul Williams' DEC ANSI parser state machine (the vtparse/xterm
reference): states `ground`, `escape`, `escape_intermediate`, `csi_entry`,
`csi_param`, `csi_intermediate`, `csi_ignore`, `osc_string`, and a combined
consume-and-discard state for DCS/SOS/PM/APC strings. Rules that matter:

- `feed(Bytes)` / `feed(String)`; state persists across calls — sequences and
  UTF-8 code points split across `feed` boundaries must parse identically to
  unsplit input (spec this explicitly).
- UTF-8 decoding happens in ground state; invalid bytes emit U+FFFD and
  resynchronize (never raise).
- C0 controls execute immediately in most states (per the reference machine);
  `CAN`/`SUB` abort a sequence; `ESC` restarts one.
- CSI params: semicolon-separated, max 16 params, each clamped to 0..65535,
  missing → 0. Colon sub-parameters (`38:2::r:g:b`) must be tolerated:
  split params on `;`, keep sub-params attached to their param for SGR
  handling, never crash.
- OSC terminated by BEL or ST (`ESC \`); cap accumulated OSC/DCS payload at
  4 KiB (discard beyond, still track termination).
- The parser knows nothing about screens: it calls a `Performer` —
  `print(Char)`, `execute(UInt8)`, `esc_dispatch(intermediates, final)`,
  `csi_dispatch(params, intermediates, final)`, `osc_dispatch(String)`.
  Parser specs use a recording performer; Screen is just one Performer.

### Style / Cell

- `Term::VT::Color` — union-style struct: `Default | Indexed(UInt8) | RGB(r,g,b)`.
- `Term::VT::Style` — value struct: `fg`, `bg` (Color), flags `bold`, `dim`,
  `italic`, `underline`, `blink`, `inverse`, `hidden`, `strikethrough`.
  `Style::DEFAULT` constant; equality is structural.
- `Term::VT::Cell` — value struct: `char : Char` (default `' '`),
  `style : Style`, `width : Int8` (1 or 2), `continuation : Bool` (true for
  the shadow cell right of a wide char).

### Width (`Term::VT::Width.of(char) : Int32`)

Returns 0 (combining marks Mn/Me, zero-width chars incl. ZWJ/ZWNJ, C0/C1),
2 (East Asian Wide `W` and Fullwidth `F` per Unicode EastAsianWidth, plus
emoji-presentation ranges), else 1. Implement as a compact sorted
`{Int32, Int32}` range table with binary search — port the ranges from a
well-known wcwidth implementation (musl or go-runewidth); do not pull a
dependency and do not attempt full UAX #11 machinery. Spec the notorious
cases: `'あ'` → 2, `'ａ'` → 2, `'e' + U+0301` → 1 total when printed,
`'😀'` → 2, plain ASCII → 1.

### Screen (`Term::VT::Screen`)

Constructor `Screen.new(rows : Int32 = 24, cols : Int32 = 80, scrollback : Int32 = 1000)`.
Owns: primary + alternate grid (`Array(Array(Cell))`), scrollback
(`Deque(Array(Cell))`, primary only, capped), cursor (row, col, visible,
`pending_wrap`), saved cursor per buffer (DECSC state: position + style),
current `Style` (SGR state), `title : String?`, `bell_count : Int32`,
autowrap flag, `alt_screen? : Bool`, and `unhandled : Array(String)` — a
bounded (cap 100) debug list of consumed-but-unimplemented sequence
descriptors. Unknown sequences are ALWAYS consumed silently; the list exists
so a failing spec can print what the emulator skipped.

Semantics (match xterm where ambiguity exists):

- **Print**: write at cursor with current style; advance by char width.
  DECAWM on (default): printing in the last column sets `pending_wrap`
  instead of moving; the next printable wraps to col 0 of the next line
  first (the classic xterm last-column quirk — spec it). A width-2 char that
  doesn't fit in the remaining columns wraps first; its continuation cell is
  marked. Overwriting either half of a wide pair blanks the orphaned half.
  Width-0 chars are dropped in phase 1 (no grapheme clusters — README note).
- **C0**: BS moves left (clamped, clears `pending_wrap`); HT advances to the
  next fixed 8-column stop (no overflow past last column); LF = index (down
  one; at bottom row, scroll up — top row pushed to scrollback on primary
  buffer, discarded on alt); CR → col 0; BEL increments `bell_count`.
- **ESC**: `7`/`8` DECSC/DECRC; `D` IND; `M` RI (reverse index — at top,
  scroll down); `E` NEL; `c` RIS (full reset incl. scrollback, title kept);
  charset designations (`ESC ( X` etc.) consumed and ignored.
- **CSI** (final byte, with params `Pn` defaulting per spec):
  `A`/`B`/`C`/`D` CUU/CUD/CUF/CUB (default 1, clamp to edges);
  `E`/`F` CNL/CPL; `G` CHA; `d` VPA; `H`/`f` CUP (1-based, clamped);
  `J` ED 0/1/2 (+`3` also clears scrollback); `K` EL 0/1/2;
  `@` ICH, `P` DCH, `X` ECH, `L` IL, `M` DL (IL/DL operate on full screen —
  no regions in this phase); `S` SU, `T` SD;
  `s`/`u` save/restore cursor position;
  `m` SGR: 0 reset; 1/2/3/4/5/7/8/9 set; 21..29 resets (22 clears bold+dim);
  30–37/40–47, 90–97/100–107; 38;5;n / 48;5;n indexed; 38;2;r;g;b /
  48;2;r;g;b truecolor (and colon-subparam equivalents); 39/49 default.
  Private modes via `?` intermediate on `h`/`l`: `?25` DECTCEM cursor
  visibility; `?7` DECAWM; `?1049` alt screen + save/restore cursor + clear
  alt on entry; `?47`/`?1047` legacy alt screen. Anything else → consumed,
  recorded in `unhandled`.
- **OSC**: `0`/`2` set `title`; others consumed.
- **resize(rows, cols)**: truncate/pad on the right and bottom; clamp cursor;
  no reflow (README note).

### Snapshot + query API (what specs will consume)

- `screen.row_text(n) : String` — visible row, styling ignored, continuation
  cells skipped, trailing whitespace trimmed.
- `screen.rows_text : Array(String)`; `screen.text : String` — rows joined
  with `\n`, trailing blank lines trimmed. `to_s` delegates to `text`.
- `screen.snapshot : String` — exact grid: every row padded to `cols`, all
  rows present (golden-file stable).
- `screen.styled_snapshot : String` — run-length styled rendering, one line
  per row, segments as `{attrs}text` with `{}` for default style, e.g.
  `{bold fg=2}Done{} in 3s`. Document the format in the README; it is a
  stability contract for golden files. Attr names: `bold dim italic underline
  blink inverse hidden strike fg=<n|#rrggbb> bg=<...>`.
- `screen.cell(row, col) : Cell`; `screen.cursor : {row: Int32, col: Int32}`;
  `screen.cursor_visible?`; `screen.alt_screen?`; `screen.title`;
  `screen.bell_count`; `screen.scrollback_text : Array(String)`.
- `screen.find(text) : {row: Int32, col: Int32}?` — first visible-grid match
  scanning row-major over `row_text`; `screen.contains?(text) : Bool`.
- `screen.feed(bytes_or_string) : self` — the one input; chaining-friendly.

### Spec strategy

- Parser specs via recording performer, including split-feed identity
  (`feed("\e[")` then `feed("2J")` ≡ `feed("\e[2J")`) and UTF-8 split bytes.
- One spec file per sequence family (see layout) asserting on grid text,
  cursor, and styles — not on internal state where avoidable.
- Fixture specs: `spec/fixtures/*.bin` holding captured real output from the
  sibling shards (generate once by running e.g. spinner/progress writing to a
  file, commit the bytes); assert final `screen.text` snapshots. These are
  the seeds of the family dogfooding.
- `fuzz_spec.cr`: deterministic PRNG (`Random.new(seed)`), ≥100_000 random
  bytes fed in random-sized chunks → assert no raise, cursor in bounds, grid
  dimensions intact. Also a targeted-garbage variant (random *valid-looking*
  CSI with absurd params: `\e[99999999A` etc.).

## Steps

1. Scaffold `shards/vt/` per the layout above (shard.yml with
   `name: term-vt`, `version: 0.1.0`, description
   "Terminal (VT/ANSI) emulation: escape-sequence parser and cell-grid screen
   model, built for testing terminal apps", `crystal: ">= 1.0.0"`,
   `license: MIT`, author line matching siblings, **no dependencies**).
   Verify: `cd shards/vt && crystal spec --no-color` runs (0 examples).
2. Implement `width.cr` + `width_spec.cr`. Verify specs pass.
3. Implement `style.cr`, `cell.cr` (+ inline specs in `sgr_spec.cr` come
   later). Verify format clean.
4. Implement `performer.cr` + `parser.cr` + `parser_spec.cr` (recording
   performer; split-feed and UTF-8 resync specs). Verify.
5. Implement `screen.cr` incrementally with its spec files in this order:
   print/wrap → cursor movement → erase/edit → SGR → modes/alt-screen →
   OSC/scrollback → resize. Run the relevant spec file after each.
6. Implement `snapshot.cr` + `snapshot_spec.cr` + `query_spec.cr`.
7. Generate fixture files (script or one-off; keep the generator under
   `spec/fixtures/README.md` documentation) + fixture specs.
8. Add `fuzz_spec.cr`. Run the full shard suite.
9. Write `shards/vt/README.md`: what it is, the supported-sequence table,
   the explicit unsupported list, snapshot-format contract, quickstart
   example (feed spinner output → assert `screen.text`), roadmap pointer to
   plan 023.
10. Wire into root: `scripts/validate-shards.sh` (`ALL_SHARDS`, path case,
    validity case — insert `vt` after `color` alphabetically-ish in the leaf
    group; it needs no overrides and depends on nothing), `AGENTS.md`
    (9 shards; note vt is a plain directory like progress pre-018; add to
    test-framework list under stdlib spec), root `README.md` table row.
11. Full verification: all four commands in the table above.
12. Update `plans/README.md`: add/flip the 022 row to DONE; leave 023 TODO.

## STOP conditions

- Crystal stdlib lacks something assumed here (e.g. `Char` API needed for
  width table) — report, don't work around with a dependency.
- The fuzz spec finds a hang (not a crash — a hang): report the input seed.
- `scripts/validate-shards.sh --local` breaks for a *sibling* shard after
  your root-script edit: revert the script change and report.
- You find yourself wanting scroll regions/IRM to make a fixture pass:
  STOP — the fixture is out of subset; swap the fixture, note it in the
  report, do not implement regions.

## Git workflow

Everything in this plan commits to the **root repo only** (shards/vt is a
plain directory; no submodule exists). Branch from `main`, conventional
commits (`feat(vt): ...`, `chore(root): ...`). If the plans/022+023 docs are
present but untracked in your worktree, include them in your first commit
(`docs(plans): add plans 022–023 (term-vt shard)`). Nothing gets pushed
without operator instruction.
