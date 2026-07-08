# Plan 032: `term-vt` — opt-in resize reflow

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: no reflow support yet
> (`rg -n "reflow|wrapped" shards/vt/src` → 0 matches), `resize_grid`
> still truncates/pads
> (`rg -n "def resize_grid" shards/vt/src/vt/screen.cr` → 1 match), plans
> 029 and 031 are DONE in `plans/README.md` (their print/wrap changes land
> before this plan touches the same paths).

## Status

- **Priority**: P3
- **Effort**: L
- **Risk**: MED-HIGH (the hardest item on the list: cursor repositioning
  and scrollback interaction have many edge cases; mitigated by being
  strictly opt-in — default behavior must stay byte-identical)
- **Depends on**: 029, 031 (both rework `print`/wrap paths this plan
  instruments; sequencing avoids three-way merge pain)
- **Category**: vt hardening (README "Unsupported" burn-down)
- **Planned at**: root commit `d9f941c`, vt submodule `v0.3.0` (`5c72959`),
  2026-07-06

## Why this matters

The vt README lists "Resize reflow; `resize` truncates/pads and clamps the
cursor" under Unsupported. Truncation is the right default for a
golden-file harness (deterministic, simple contract), but it diverges from
what every modern terminal (iTerm2, kitty, GNOME Terminal, Windows
Terminal) shows users when a window narrows: soft-wrapped lines re-wrap.
A tape that does `resize 24 40` against a program that already printed
80-column output asserts against a screen no real user would ever see.
Opt-in reflow closes that gap without touching the default contract.

## Target design

### Opt-in surface

- `Screen.new(rows:, cols:, scrollback:, reflow: false)` — constructor
  flag, stored, exposed as `screen.reflow?`.
- `Session.spawn(..., reflow: false)` passes through.
- CLI: global flag `--reflow` (run/snapshot/script) and tape directive
  `reflow` (before `run`, like `rows`/`cols`).
- `reflow: false` (default) keeps today's truncate/pad behavior exactly —
  existing `spec/screen/resize_spec.cr` must pass unmodified.

### Soft-wrap tracking

Reflow requires knowing which rows are continuations. Track a per-row
"wrapped" flag set when `wrap_pending`/autowrap pushes the cursor to the
next line (the row being *left* is marked as wrapping into the next), and
cleared when the row is scrolled blank, erased whole (EL 2 / ED variants
that cover it), or replaced. Storage is implementer's choice; recommended:
parallel `Array(Bool)` alongside `@primary` and a `Deque(Bool)` alongside
`@scrollback` (alt screen never reflows — xterm behavior — so `@alternate`
needs no flags). Every place that shifts rows (`scroll_up`, `scroll_down`,
`insert_lines`, `delete_lines`, `push_scrollback`, DECSTBM region scrolls
from plan 029) must move flags in lockstep — this is the invasive part;
audit `screen.cr` for every `grid.` mutation. Flags participate in
`copy_from`. Track flags unconditionally (cheap) so a screen constructed
with `reflow: true` after content exists is not a special case.

### Reflow algorithm (only when `reflow?` and `cols` changes; pure
rows-change with reflow on additionally pulls rows back from scrollback
when growing taller, xterm-style)

1. Record the cursor's logical position: walk from the top of scrollback
   through the primary grid, joining wrapped runs into logical lines
   (strip trailing blank cells of each physical row when joining, except
   a fully-wrapped row keeps its cells); note which logical line and
   character-cell offset the cursor sits at.
2. Re-wrap every logical line at the new width. Never split a wide pair:
   a width-2 cell that would straddle the boundary moves whole to the
   next row (leaving one trailing blank), matching `print`'s autowrap
   rule. Rows produced beyond the visible grid go to scrollback
   (respecting `@scrollback_limit`); the visible grid holds the tail.
3. Restore the cursor to its logical position, clamped; recompute
   `@pending_wrap` (only true if the cursor landed on the last column via
   a wrap); rebuild wrapped flags from the re-wrap.
4. Alt screen: truncate/pad as today, even with reflow on. Scroll-region
   margins (plan 029) reset on resize regardless — already the rule.

### Docs + version

- README: remove the reflow bullet from Unsupported; document `reflow:`
  on Screen/Session, `--reflow`, the tape directive, and the contract
  ("default remains truncate/pad; reflow re-wraps primary + scrollback,
  never the alternate screen").
- `shard.yml`: bump minor (to `0.5.0` if 029–031 shipped as `0.4.0`,
  else fold into the pending minor).

## Specs

New `spec/screen/reflow_spec.cr` + a tape e2e case:

- Narrow: 1 logical 80-col line at 24×80 → resize to 24×40 → two rows,
  cursor follows its character.
- Widen back: re-joins (lossless round-trip for content that fits).
- Wide-char boundary: CJK pair never splits; the pushed cell lands on the
  next row.
- Scrollback: narrowing overflows the top of the grid into scrollback;
  growing taller pulls rows back out.
- Hard newlines never join: two `printf` lines stay two logical lines.
- Cursor at pending-wrap position survives round-trip.
- Alt screen with reflow on still truncates.
- Default-off regression: full existing suite, especially
  `spec/screen/resize_spec.cr`, passes unmodified.
- Flag-lockstep: scroll/IL/DL under a scroll region keep wrapped flags
  aligned (assert via reflow correctness after such operations).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Build CLI | `cd shards/vt && shards build --no-color` | `bin/term-vt` exists |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |

## Steps

1. Wrapped-flag tracking + lockstep audit of every grid mutation
   (no behavior change yet; assert flags via a spec-only accessor or
   reflow round-trips later).
2. `reflow:` plumbing (Screen → Session → CLI/tape), default-off, no-op.
3. Logical-line join/re-wrap core as pure private methods + unit specs
   (cols narrow/widen, wide pairs, blanks).
4. Cursor logical-position restore + pending_wrap recompute.
5. Scrollback overflow/pull-back; alt-screen exemption.
6. README, version, full verification, `plans/README.md` row.

## STOP conditions

- Default-path (`reflow: false`) golden output changes anywhere: STOP —
  the opt-out contract is the whole design.
- Cursor restoration needs heuristics you cannot specify deterministically
  (e.g. cursor inside trailing blanks that joining stripped): pick the
  documented clamp (end of logical line), write it in the README, and if
  that still feels wrong, STOP and report rather than invent cleverness.
- Reflow of the *alternate* screen seems necessary for some app: STOP —
  report the app; xterm does not reflow alt either.

## Git workflow

`shards/vt` is a git submodule (`crystal-term/vt`), currently detached at
`v0.3.0`. Work there first:
`git -C shards/vt fetch origin && git -C shards/vt checkout -b watzon/plan-032 origin/main`
(after 029/031 have merged), conventional commits. Then in the root repo
branch from `main`, commit the submodule pointer bump +
`plans/README.md` row. Push nothing without operator instruction.
