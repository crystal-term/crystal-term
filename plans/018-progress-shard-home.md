# Plan 018: The progress shard has a public home: repo, README, CI, tagged release

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Several steps require GitHub permissions (`gh` auth as the
> crystal-term org owner) — these are marked OPERATOR. If you lack the
> permission, complete everything else, leave OPERATOR steps as a checklist in
> your report, and mark the plan BLOCKED(operator) in `plans/README.md`.
>
> **Drift check (run first)**: `ls shards/progress/README.md` (expect: missing),
> `gh repo view crystal-term/progress` (expect: not found). If either exists,
> reassess — someone started this.

## Status

- **Priority**: P3 (direction)
- **Effort**: M
- **Risk**: LOW (additive)
- **Depends on**: none strictly; better after 007/012 land (they touch progress source)
- **Category**: direction
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

`term-progress` declares itself v1.0.0, ships 7 source files, 7 spec files, and 10+ polished examples, and is the family's equivalent of tty-progressbar — but nobody can install it. It's a plain directory in this root checkout: no public repo, no README (the only shard without one), no CI, no issue tracker, no `shards install` path. Its own `shard.yml` even names GitHub dependencies while being unfetchable itself. `docs/release-validation.md:94-100` flags this explicitly. Publishing it is the highest-value direction item because the work is packaging, not engineering.

## Current state

- `shards/progress/` — plain directory tracked by the **root** repo (not a submodule; confirmed: absent from `.gitmodules` and `git submodule status`).
- `shards/progress/shard.yml` — name `term-progress`, version `1.0.0`, deps: `term-cursor ~> 1.0.0`, `term-screen ~> 1.0.0`, `term-spinner ~> 1.0.0` (all as `github: crystal-term/<name>`), dev-dep spectator (removed if plan 014 landed).
- Layout: `src/term-progress.cr`, `src/progress/{bar,multi,meter,formatters,spinner_integration,...}.cr`, `spec/unit/*_spec.cr` + `spec/helpers/`, `examples/*.cr`.
- No README, no LICENSE file check — verify: `ls shards/progress` (the other seven shards carry MIT licenses; progress's shard.yml has no license key — check and add).
- Sibling repo conventions to copy: any submodule shard, e.g. `shards/spinner` — README structure, `.editorconfig`, `.github/workflows/crystal.yml` (use prompt's matrix workflow as the modern template, single-OS ubuntu to start).
- The root remote `crystal-term/crystal-term` did not resolve publicly as of 2026-07-04 (documented in `docs/release-validation.md`), so history extraction via GitHub is not an option; the local root repo history is the source.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/progress && shards install && crystal spec --no-color` | all pass |
| Examples compile | `cd shards/progress && for f in examples/*.cr; do crystal build --no-codegen --no-color "$f" || echo "FAIL $f"; done` | no FAIL lines |
| OPERATOR: create repo | `gh repo create crystal-term/progress --public` | repo URL |
| Harness | `scripts/validate-shards.sh --local --shards progress` | exit 0 |

## Scope

**In scope**:
- `shards/progress/README.md` (create), `shards/progress/LICENSE` (create, MIT, match siblings), `shards/progress/.editorconfig` (copy from a sibling), `shards/progress/.github/workflows/crystal.yml` (create)
- `shards/progress/shard.yml` (add `license: MIT` if missing)
- Root: `.gitmodules`, `docs/release-validation.md`, `README.md` ownership table — only in the OPERATOR conversion step
- OPERATOR: the new `crystal-term/progress` repo, tag `v1.0.0`

**Out of scope**:
- Any behavior change in progress source; publishing to shardbox; touching other shards.

## Git workflow

- Pre-OPERATOR file additions: root repo branch `advisor/018-progress-home` (progress is root-tracked today).
- OPERATOR conversion: see Step 4 — this is the one step in all these plans that rewrites repo structure; it is explicitly operator-gated.
- Do NOT push anything without operator instruction.

## Steps

### Step 1: README

Write `shards/progress/README.md` following the sibling pattern (look at `shards/spinner/README.md` for section order: badges, description, installation, usage, options, examples). Installation block:

```yaml
dependencies:
  term-progress:
    github: crystal-term/progress
    version: ~> 1.0.0
```

Source the usage sections from the actual examples in `shards/progress/examples/` (they compile in the harness, so they're trustworthy) — cover: basic bar, tokens/formats, `Multi` bars, meter, spinner integration. Keep it accurate over exhaustive; every code block must come from a compiling example or be compiled yourself.

**Verify**: every fenced code block extracted to a temp file compiles with `crystal build --no-codegen` against the local checkout (add `require "../src/term-progress"` shim as needed for the check).

### Step 2: LICENSE, editorconfig, license key

Copy MIT LICENSE text from `shards/spinner/LICENSE` (update the copyright line only if the operator name differs — keep "Chris Watson"), copy `.editorconfig`, add `license: MIT` to `shard.yml` if absent.

**Verify**: `ls shards/progress/LICENSE shards/progress/.editorconfig` → both exist; `rg -n "license: MIT" shards/progress/shard.yml` → 1 match.

### Step 3: CI workflow file

Create `shards/progress/.github/workflows/crystal.yml` modeled on `shards/prompt/.github/workflows/crystal.yml` but ubuntu-only to start:

```yaml
name: specs
on:
  push:
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: crystal-lang/install-crystal@v1
        with:
          crystal: latest
      - run: shards install
      - run: crystal spec
```

(It only takes effect once the repo exists; committing it now costs nothing.)

**Verify**: YAML parses (same check as plan 001 step 2).

### Step 4 (OPERATOR): Create the repo, seed it, convert to submodule

1. `gh repo create crystal-term/progress --public --description "Terminal progress bars and indicators"`.
2. Seed: either (a) fresh history — copy `shards/progress/*` into a new clone, single initial commit, or (b) extract history from the root repo with `git subtree split --prefix=shards/progress` and push that. Recommendation: (a) fresh — the root repo's progress history is entangled with unrelated root commits and the subtree split's value is low for a first release.
3. Tag `v1.0.0` on the seeded repo.
4. Convert the root checkout: remove `shards/progress` from root tracking, `git submodule add https://github.com/crystal-term/progress.git shards/progress`.
5. Update `docs/release-validation.md` (progress caveat paragraph + issue-inventory row) and the root `README.md` ownership table (progress becomes "nested Git repo, crystal-term/progress").

**Verify**: `git submodule status` lists progress at the v1.0.0 commit; `scripts/validate-shards.sh --local --shards progress` → exit 0 (harness treats submodule and plain dir identically — it only needs the path and `shard.yml`).

### Step 5: Post-conversion sanity

Run the full harness; confirm prompt/spinner unaffected.

**Verify**: `scripts/validate-shards.sh --local --skip-examples` → exit 0.

## Test plan

No new specs. Gates: README code blocks compile (Step 1), progress suite green before and after conversion, harness green (Step 5).

## Done criteria

- [ ] `shards/progress/README.md`, `LICENSE`, `.editorconfig`, `.github/workflows/crystal.yml` exist
- [ ] `license: MIT` in `shard.yml`
- [ ] OPERATOR items done or plan marked BLOCKED(operator) with the checklist in the report
- [ ] After conversion: `git submodule status` includes progress; harness green
- [ ] `docs/release-validation.md` progress caveat updated (or noted as pending operator)
- [ ] `plans/README.md` status row updated

## STOP conditions

- `gh repo create` fails for permission reasons — expected without org access; that's the BLOCKED(operator) path, not an error.
- The examples don't all compile (pre-existing breakage) — fix nothing; report which fail.
- Anyone proposes `git filter-branch`/history rewrite of the **root** repo to extract history — out of bounds; only `subtree split` (read-only derivation) or fresh seeding are allowed.

## Maintenance notes

- After the repo exists, add progress to the same release layering docs as prompt (top layer) — already true in `docs/release-validation.md`.
- Plan 015's AGENTS.md layout section needs its "progress is a plain directory" line updated after conversion.
- Consider shardbox.org registration alongside the other shards (operator, later).
