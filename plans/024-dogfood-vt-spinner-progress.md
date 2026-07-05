# Plan 024: Dogfood `term-vt` — spinner and progress specs assert on rendered screens

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `grep -n 'version:' shards/vt/src/vt/version.cr`
> (expect 0.2.x), `ls shards/spinner/spec/helpers/test_io.cr
> shards/progress/spec/helpers/test_io.cr` (expect: both exist),
> `rg -n "term-vt" shards/spinner shards/progress --glob '!lib'` (expect: 0).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED-LOW (spec-only changes in siblings, plus one small additive
  utility in vt; behavior of shipped code does not change)
- **Depends on**: 022 (023 not required — no PTY use here)
- **Category**: tech-debt / direction
- **Planned at**: commit `ede43b3` (root), 2026-07-05

## Why this matters

spinner and progress carry byte-for-byte identical ~30-line `TestIO` doubles
(`shards/spinner/spec/helpers/test_io.cr`, `shards/progress/spec/helpers/test_io.cr`)
and assert on raw escape-byte strings — the brittleness that plans 007 and
011 document. `term-vt` exists precisely so specs can assert on **what a
user sees**. This plan makes the first two siblings consume it, which is
also the shakedown cruise for term-vt's API before publication.

## Current state

- spinner specs (stdlib spec): `TestIO` collects `output : String`; e.g.
  `spinner_spec.cr` asserts `output.output` contains escape substrings.
- progress specs: same `TestIO`, plus `spec/helpers/fixtures.cr` data.
- Both shards' `shard.yml` list only crystal-term github dependencies.
- `term-vt` is a **plain root-tracked directory** (`shards/vt`), not
  published — a `github: crystal-term/vt` ref resolves only after the
  OPERATOR publication step. The family's local dev path for unpublished /
  co-developed deps is `scripts/validate-shards.sh --local`, which writes
  managed `shard.override.yml` files (see the template around line 90 and
  the dependency map; overrides use `path: ../<shard>`).
- `TestIO` fakes `tty? = true` in some specs — grep both shards for `tty`
  to inventory which specs rely on it before deleting anything.

## Target design

1. **`Term::VT::CapturedTTY`** (new, in `shards/vt/src/vt/captured_tty.cr`,
   version bump to the next patch): an in-memory `IO` that reports
   `tty? = true`, records written bytes, and offers
   `screen(rows : Int32 = 24, cols : Int32 = 80) : Screen` — builds a fresh
   Screen fed with everything written so far. This is the shared
   replacement for both `TestIO` copies, living in the right home. Specs
   for it in `shards/vt/spec/captured_tty_spec.cr`.
2. **spinner + progress** each:
   - `shard.yml`: add `development_dependencies:` entry
     `term-vt: {github: crystal-term/vt, version: ~> 0.2.1}`.
   - Delete `spec/helpers/test_io.cr`; specs use `Term::VT::CapturedTTY`.
   - Convert **content assertions** (spinner frames, done messages, bar
     fill, percentages, multi-bar rows) to grid assertions:
     `io.screen.text`, `io.screen.find(...)`, `io.screen.row_text(n)`.
   - Keep **protocol assertions** byte-based only where the sequence
     itself is the contract (e.g. "hides cursor on start" asserting
     `\e[?25l`); each retained byte assertion gets a one-line comment
     saying why it stays byte-level. Everything else converts.
3. **Root harness**: extend `scripts/validate-shards.sh` so `--local` mode
   writes a `term-vt: path: ../vt` override for spinner and progress (add
   `vt` to the override/dependency map the script maintains; released-mode
   behavior for other shards must not change).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| vt specs | `cd shards/vt && crystal spec --no-color` | pass |
| spinner via harness | `scripts/validate-shards.sh --local --shards spinner --skip-examples` | exit 0 |
| progress via harness | `scripts/validate-shards.sh --local --shards progress --skip-examples` | exit 0 |
| full harness | `scripts/validate-shards.sh --local` | exit 0 |
| format (all touched) | `crystal tool format --check src spec` in vt, spinner, progress | no diff |

Note: plain `shards install` inside spinner/progress will fail to resolve
`term-vt` until publication — that is expected; use the harness's `--local`
mode, which writes the path override first.

## Steps

1. Inventory: list every spinner/progress spec assertion on raw output and
   classify content vs protocol. Grep both shards for `tty` reliance.
2. Add `CapturedTTY` + its specs to vt; bump vt patch version.
3. Root: extend the validate-shards override map for `term-vt`; verify a
   `--local --shards spinner` run writes the override and installs.
4. Convert spinner specs; delete its `test_io.cr`; run via harness.
5. Convert progress specs; delete its `test_io.cr`; run via harness.
6. Full harness + format checks.
7. Update `plans/README.md` row; report the content-vs-protocol assertion
   tally and any term-vt API gaps you hit (missing query methods etc. —
   report, do not bolt undesigned API onto vt beyond CapturedTTY).

## STOP conditions

- A spec cannot express its assertion against the Screen API without new
  vt query methods: report the gap instead of adding API ad hoc.
- A converted spec goes flaky (spinner is fiber-based; if a grid assertion
  races frame timing, prefer asserting the stable final state or the set
  of distinct rendered frames — if neither works, report).
- Deleting `TestIO` breaks a spec that depended on non-IO behavior of the
  double (e.g. `read_timeout` stubs): report; do not re-grow CapturedTTY
  into a kitchen-sink mock.

## Git workflow

Three repos are touched — read AGENTS.md first:

- **spinner** and **progress** are nested git repos. In each: create branch
  `watzon/plan-024-dogfood-vt` from the checked-out commit, commit the spec
  changes there (conventional commits), and leave the branch checked out.
- **root**: commit the vt changes (CapturedTTY, version bump), the
  validate-shards.sh change, submodule pointer bumps for spinner/progress,
  and the plans/README.md row on the root worktree branch.
- Push nothing. Integrator note (not your job): the submodule branches must
  be fetched into the primary checkout's nested repos before this worktree
  is removed.

**OPERATOR follow-up (blocks standalone spinner/progress CI, not this
plan)**: publish `crystal-term/vt` (plan-018 pattern) and tag `v0.2.1` so
the github dev-dependency resolves outside this monorepo.
