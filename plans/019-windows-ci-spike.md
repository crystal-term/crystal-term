# Plan 019: SPIKE — Windows CI across the family, surfacing what actually breaks

> **Executor instructions**: This is a spike: the deliverable is working CI
> matrices where cheap, plus a **written findings report** for what isn't cheap
> — not necessarily green Windows builds everywhere. Follow the steps; where a
> step says "record", append to `plans/reports/019-windows-findings.md`. STOP
> conditions still apply. When done, update the status row in `plans/README.md`.
>
> **Drift check (run first)**: plan 001 should have landed (root CI exists).
> Confirm the per-shard workflow inventory below is still accurate:
> `ls shards/*/.github/workflows/ 2>/dev/null`.

## Status

- **Priority**: P3 (direction)
- **Effort**: M (spike-bounded)
- **Risk**: MED — win32 code paths that have never run in CI will surface real bugs
- **Depends on**: 001; benefits from 010 (ANSICON fix)
- **Category**: direction
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

Windows support has been requested since 2022 (crystal-term/screen#5, open) and the code is *mostly there*: screen has winapi bindings (`shards/screen/src/screen/libs/winapi.cr`, win32 branches in `term-screen.cr:49-113`), terminfo has `windows/console.cr`, reader's keys table has a `WINDOWS_KEYS` variant, cursor's specs carry "TODO: Skip on Windows" markers. Prompt's CI workflow already runs a `windows` matrix — meaning the top of the dependency stack claims Windows while none of its foundations test it. This spike extends the matrix down the stack and produces an honest inventory of what breaks, so "Windows support" can become a closable milestone instead of a four-year-old issue.

## Current state

- Per-shard workflows: `cursor`, `screen`, `spinner`, `reader`, `prompt` have `.github/workflows/crystal.yml`; `color`, `terminfo`, `progress` have none. The prompt one is the modern template (checkout@v4, install-crystal@v1, os matrix `["ubuntu", "macos", "windows"]`); the others are checkout@v2-era, push-to-`master`-triggered.
- Six shards also carry dead `.travis.yml` files.
- Windows-relevant code: `shards/screen/src/term-screen.cr` `{% if flag?(:win32) %}` branches (win_api size, ansicon); `shards/terminfo/src/terminfo/windows/console.cr`; `shards/reader/src/reader/keys.cr` `WINDOWS_KEYS`; `shards/color/src/color/env.cr` (windows checks). Reader's raw-mode path (`IO::FileDescriptor#raw`) depends on Crystal's Windows console support (stdlib-gated, generally available in recent Crystal).
- Known constraint: nested shard repos run their own CI on GitHub — this monorepo can only *stage* workflow files in submodules; runs happen when pushed to the shard repos. The spike therefore validates what it can locally (cross-compile checks are not practical; Windows runners are the real test) and stages the workflows.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Stage check | YAML parse per new workflow (plan 001 method) | ok |
| Local suite (per shard) | `cd shards/<name> && crystal spec --no-color` | all pass (Linux/macOS baseline) |
| OPERATOR: trigger runs | push branches to shard repos / open draft PRs | Actions runs visible |

## Scope

**In scope**:
- `shards/{color,terminfo}/.github/workflows/crystal.yml` (create, ubuntu+windows matrix), `shards/progress` equivalent if plan 018 landed (else skip, note it)
- `shards/{cursor,screen,spinner,reader}/.github/workflows/crystal.yml` (modernize to the prompt template incl. windows matrix)
- Delete `.travis.yml` in all shards that carry one
- `plans/reports/019-windows-findings.md` (create)

**Out of scope**:
- Fixing the Windows failures themselves — each fix becomes its own follow-up; this spike inventories.
- The root workflow (stays ubuntu-only).

## Git workflow

- One branch per submodule: `advisor/019-windows-ci`. Do NOT push (OPERATOR triggers actual runs). Root repo branch for the findings report.

## Steps

### Step 1: Template the workflow

Copy `shards/prompt/.github/workflows/crystal.yml` verbatim as the template (name `specs`, os matrix ubuntu/macos/windows, `fail-fast: false`). Apply to the seven other shards (create or replace). For `screen`, add the flag note: if `shards install`/spec fails on readline linking in any OS job, the fix is building specs with `-Dwithout_readline` on that OS — record, don't improvise beyond adding the documented flag.

**Verify**: all eight (or seven, if progress skipped) workflow files parse as YAML; `.travis.yml` count is zero (`ls shards/*/.travis.yml 2>/dev/null` → no matches).

### Step 2: Local baseline

Run each shard's suite on this machine (macOS) to confirm the workflow modernization didn't change local behavior (it can't, but the baseline matters for comparing Windows failures).

**Verify**: `scripts/validate-shards.sh --local --skip-examples` → exit 0.

### Step 3 (OPERATOR): Trigger Windows runs bottom-up

Push the branches in dependency order — leaves first: color, cursor, screen, terminfo; then reader, spinner; then prompt (and progress). For each, record in the findings report: compile result, spec result, failure classes (linker? stdlib API? escape-sequence assertions? tty detection?).

### Step 4: Findings report

`plans/reports/019-windows-findings.md` gets, per shard: status (green/compile-fail/spec-fail/not-run), the first error, a one-line hypothesis, and an S/M/L estimate for the fix. Close with a recommended fix order (expect: screen and reader carry the real work; color/cursor/terminfo likely near-green).

**Verify**: report exists with an entry for every shard, even not-run ones.

## Test plan

The CI matrices *are* the test. No new specs in this spike; per-shard Windows-specific specs belong to the follow-up fix plans the report proposes.

## Done criteria

- [ ] Modern matrix workflow staged in all seven submodule shards (+ progress if applicable)
- [ ] Zero `.travis.yml` files remain
- [ ] Local harness green (Step 2)
- [ ] `plans/reports/019-windows-findings.md` exists with per-shard entries (or OPERATOR steps listed as blocked)
- [ ] `plans/README.md` status row updated (DONE for the staging, or BLOCKED(operator) for runs)

## STOP conditions

- A workflow change would alter what the existing green CI tests on ubuntu (beyond action version bumps) — keep behavior-identical on Linux.
- More than trivial (flag-level) changes to *source* seem needed to even compile on Windows — that's the follow-up plan's job; record and move on.

## Maintenance notes

- Screen issue #5 should be updated with a link to the findings report once runs complete; it only closes when the follow-up fixes land.
- Once all shards are green on Windows, extend the root workflow (plan 001) with a windows job running the harness under bash (Git Bash provides bash on runners; the harness is bash-only — note `#!/usr/bin/env bash`).
