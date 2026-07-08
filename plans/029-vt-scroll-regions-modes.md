# Plan 029: `term-vt` screen model — scroll regions, origin mode, insert mode, tab stops

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: vt at 0.3.x
> (`grep "^version" shards/vt/shard.yml` → `0.3.0` or a later unreleased
> bump), no scroll-region support yet
> (`rg -n "scroll_top|DECSTBM|tab_stops" shards/vt/src` → 0 matches), HT
> still hardcoded to 8 columns
> (`rg -n "8 - \(@cursor_col % 8\)" shards/vt/src/vt/screen.cr` → 1 match).

## Status

- **Status**: DONE
- **Priority**: P2
- **Effort**: M-L
- **Risk**: MED (touches the scroll/print/cursor core paths every other
  feature sits on; `snapshot` goldens elsewhere must not change for inputs
  that use none of the new sequences)
- **Depends on**: — (independent; see coordination note if run alongside 031)
- **Category**: vt hardening (README "Unsupported" burn-down)
- **Planned at**: root commit `d9f941c`, vt submodule `v0.3.0` (`5c72959`),
  2026-07-06
- **Completed**: 2026-07-08 — vt `0.4.0` on branch `watzon/plan-029`

## Why this matters

These four are the biggest reasons real TUIs render wrong in the emulator
today. `less`, `vim`, `fzf`, and anything ncurses-based set scroll regions
(`DECSTBM`) to pin status lines while scrolling content; shells and editors
use back-tab (`CSI Z`) and custom tab stops; readline uses `IRM` bursts.
Right now all of these land in `screen.unhandled` and the grid silently
diverges from what a real terminal shows — which is exactly the failure
mode a testing harness cannot have. The vt README lists all four under
"Unsupported … should be added without changing the public parser/screen
split"; this plan clears them.

All work is in `Screen` (`shards/vt/src/vt/screen.cr`). The parser already
delivers every needed sequence via `esc_dispatch`/`csi_dispatch`; no parser
changes.

## Target design

### State (add to `initialize`, and to `copy_from` + its protected getters — `Session#screen` depends on `dup` copying everything)

- `@scroll_top : Int32` / `@scroll_bottom : Int32` — 0-based inclusive
  margins, default `0` / `rows - 1`. One pair shared by primary and
  alternate screens (xterm behavior).
- `@origin_mode : Bool` — default false. Also add an `origin` field to the
  private `SavedCursor` struct: DECSC/DECRC save and restore origin mode.
- `@insert_mode : Bool` — default false.
- `@tab_stops : Set(Int32)` (or `Array(Bool)` sized `cols`) — default
  stops at every multiple of 8.

`ESC c` (RIS) already re-runs `initialize`, so all of this resets for free.

### DECSTBM — `CSI Pt ; Pb r`

New `when 'r'` in `csi_dispatch` (empty intermediates only). Defaults
`Pt = 1`, `Pb = rows`. Convert to 0-based, clamp to the grid; ignore the
whole sequence unless `top < bottom` after clamping. On success set the
margins and home the cursor (to the top margin when origin mode is set,
else to `0,0`).

Semantics ripple through existing private methods:

- `index` (LF/IND/NEL and `wrap_pending`): at `@scroll_bottom` → scroll
  the region up 1; strictly below the region → move down but never past
  `rows - 1`, no scrolling; otherwise `@cursor_row += 1`.
- `reverse_index` (RI): mirror of the above at `@scroll_top`.
- `scroll_up`/`scroll_down` (SU/SD and the calls above): shift rows within
  `[@scroll_top, @scroll_bottom]` only; blank fill at the vacated edge.
  Push to scrollback **only** when the region spans the full screen and
  `@alt_screen` is false — i.e. exactly today's behavior when no region is
  set. A partial-region scroll never feeds scrollback (xterm behavior).
- `insert_lines`/`delete_lines` (IL/DL): no-op when the cursor is outside
  the margins; otherwise shift within `[@cursor_row, @scroll_bottom]`.
- `resize` resets margins to full screen (xterm behavior).
- ED/EL are **not** margin-limited. `move_cursor` from CUU/CUD (`CSI A`/
  `CSI B`) clamps at the margins when the cursor starts inside them.

### DECOM — `CSI ?6 h` / `CSI ?6 l`

New case in `set_private_modes`. When set: CUP/HVP (`H`/`f`) and VPA (`d`)
row params are relative to `@scroll_top`, and the cursor is clamped to
`[@scroll_top, @scroll_bottom]`. Setting or resetting the mode homes the
cursor (respecting the new mode). CUP row 1 with DECOM on = top margin.

### IRM — `CSI 4 h` / `CSI 4 l`

`csi_dispatch` currently only routes `?`-intermediates `h`/`l`; add plain
ANSI SM/RM handling for empty intermediates: mode `4` toggles
`@insert_mode`, all other ANSI modes keep going to `record_unhandled`.
When insert mode is on, `print` shifts the current row right by the glyph
width from `@cursor_col` before writing (reuse the `insert_chars` cell
shuffle), then writes as today. Take care at the row edge: a wide pair
pushed past `cols - 1` must not leave a dangling continuation cell (reuse
`clear_wide_pair_at` on the last column after shifting).

### Tab stops — HT, HTS, TBC, CHT, CBT

- HT (`execute` byte `0x09`): move to the next stop after `@cursor_col`,
  else to `@cols - 1`. Replaces the hardcoded `% 8` math.
- HTS (`ESC H`): new `when {"", 'H'}` in `esc_dispatch` — set a stop at
  `@cursor_col`.
- TBC (`CSI g`): param `0`/default clears the stop at the cursor column;
  param `3` clears all stops; other params → `record_unhandled`.
- CHT (`CSI I`): advance `Pn` (default 1) stops. CBT (`CSI Z`): move back
  `Pn` stops, stopping at column 0. Both are cheap once the table exists
  and CBT (back-tab) is common in TUIs.
- `resize` keeps existing stops that still fit; columns gained beyond the
  old width get default stops at multiples of 8.

### Docs + version

- README: delete the DECSTBM, tab-stop, IRM, and DECOM bullets from
  "Unsupported"; add rows to "Supported Sequences" (CSI scroll region,
  tab-stop family, SM/RM `4`, private mode `?6`).
- `shard.yml`: if version is still `0.3.0`, bump to `0.4.0`; if another
  plan in this wave already bumped past 0.3.0 unreleased, leave it.

## Specs

New files under `shards/vt/spec/screen/` following the existing style
(`crystal spec`, plain asserts on `snapshot`/`cursor`/`unhandled`):

- `scroll_region_spec.cr` — set region, LF at bottom margin scrolls only
  the region; RI at top margin; IL/DL inside vs outside margins; SU/SD;
  scrollback untouched by partial-region scrolls but still fed by
  full-screen scrolls; `CSI r` reset; invalid (`Pt >= Pb`) ignored; resize
  resets margins; a `vim`-shaped smoke: region rows 1..N-1, status line at
  row N survives content scroll.
- `origin_mode_spec.cr` — CUP relative addressing, clamping to margins,
  home on set/reset, DECSC/DECRC round-trips origin mode.
- `insert_mode_spec.cr` — overwrite vs insert, wide-char insert at row
  edge leaves no dangling continuation cell, mode off restores overwrite.
- `tab_stops_spec.cr` — default stops, HTS/TBC 0/TBC 3, CHT/CBT, HT with
  no stops left lands on last column, resize behavior.
- Regression: full existing suite passes unchanged — none of the current
  specs use these sequences, so no golden churn is acceptable.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Build CLI | `cd shards/vt && shards build --no-color` | `bin/term-vt` exists |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |
| Smoke | `cd shards/vt && ./bin/term-vt run --expect-exit 0 -- sh -c 'printf "\033[2;5r\033[2;1Hx\n\n\n\ny"'` | exit 0 |

## Steps

1. Tab stops (self-contained, lowest risk): state + HT/HTS/TBC/CHT/CBT +
   `copy_from` + specs.
2. DECSTBM state + `index`/`reverse_index`/`scroll_up`/`scroll_down`/
   IL/DL/resize changes + specs.
3. DECOM + `SavedCursor.origin` + specs.
4. IRM (SM/RM routing + insert-aware `print`) + specs.
5. README tables, version bump, full suite + format + harness.
6. Update `plans/README.md` status row.

## STOP conditions

- Any pre-existing spec needs its expectation changed: STOP — that means a
  default behavior regressed; report instead of adjusting the spec.
- You find yourself adding left/right margins (DECSLRM) or rectangle ops:
  STOP — out of scope, note it in the README Unsupported list instead.
- `copy_from` drift: if you add an ivar and cannot express it in
  `copy_from`, STOP and report (Session snapshot correctness depends on it).

## Git workflow

`shards/vt` is a git submodule (`crystal-term/vt`), currently detached at
`v0.3.0`. Work there first:
`git -C shards/vt fetch origin && git -C shards/vt checkout -b watzon/plan-029 origin/main`,
conventional commits. Then in the root repo branch from `main`, commit the
submodule pointer bump + `plans/README.md` row. Push nothing without
operator instruction.

Coordination: this plan and 031 both touch `Screen#print`. They may run in
parallel but must merge sequentially (either order); the second to merge
rebases.
