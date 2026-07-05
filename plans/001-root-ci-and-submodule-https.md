# Plan 001: Root CI runs the validation harness on every push, and submodules clone over HTTPS

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 912c211..HEAD -- .gitmodules .github README.md scripts/validate-shards.sh`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

This monorepo has a complete cross-shard validation harness (`scripts/validate-shards.sh`) that installs, specs, and example-compiles all eight shards in dependency order — but nothing runs it automatically. `.github/workflows/` at the repo root contains zero workflow files. Every cross-shard regression lands silently until someone remembers to run the harness by hand. Additionally, six of seven submodules use SSH-only URLs, which means CI runners (and anyone without GitHub SSH keys) cannot initialize them at all. This plan is the verification baseline every other plan in `plans/` depends on.

## Current state

- `.gitmodules` — six of seven submodule URLs are SSH-only:

```1:6:.gitmodules
[submodule "color"]
	path = shards/color
	url = https://github.com/crystal-term/color.git
[submodule "cursor"]
	path = shards/cursor
	url = git@github.com:crystal-term/cursor.git
```

  (Full list: `color` is HTTPS; `cursor`, `prompt`, `reader`, `screen`, `spinner`, `terminfo` are all `git@github.com:crystal-term/<name>.git`.)

- `.github/workflows/` — the directory exists but is empty.
- `scripts/validate-shards.sh` — the harness. `--local` mode writes managed `shard.override.yml` files so dependent shards resolve family dependencies from this checkout instead of released tags. It runs, per shard, in the order `color, cursor, screen, terminfo, reader, spinner, prompt, progress`: `shards install`, `crystal spec --no-color`, and `crystal build --no-codegen --no-color` on each `examples/**/*.cr`. Exits non-zero if any phase fails.
- `README.md` — documents the harness but never mentions that `shards/` contains submodules or that a fresh clone needs `git submodule update --init`.
- Toolchain verified on this machine: Crystal 1.20.3, Shards 0.20.0.
- The `screen` shard links against libreadline by default (`shards/screen/src/term-screen.cr:5-7`); the flag `-Dwithout_readline` disables it. Ubuntu GitHub runners may need `libreadline-dev` installed.
- This checkout currently has an unmanaged-but-compatible `shards/prompt/shard.override.yml`. It is untracked in the prompt submodule, so a fresh CI clone will not have it; `--local` mode handles it either way (see `write_managed_override` in the script, which leaves compatible unmanaged overrides in place).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Full local validation | `scripts/validate-shards.sh --local` | exit 0, "All selected shard checks passed." |
| Quick subset | `scripts/validate-shards.sh --local --shards color,cursor --skip-examples` | exit 0 |
| Format check (per shard) | `cd shards/<name> && crystal tool format --check src spec` | exit 0, no output |
| Submodule sync | `git submodule sync && git submodule update --init` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `.gitmodules`
- `.github/workflows/ci.yml` (create)
- `README.md` (add a "Getting started" section only)

**Out of scope** (do NOT touch, even though they look related):
- Per-shard `.github/workflows/` inside `shards/*` — those belong to the nested repos and are handled by a separate plan (019).
- `scripts/validate-shards.sh` — no changes needed; the workflow calls it as-is.
- Any source or spec file in `shards/*`.
- Do not run `crystal tool format` in write mode on any shard — a formatting baseline is not part of this plan.

## Git workflow

- All changes here are in the **root repo only** (no submodule commits).
- Branch: `advisor/001-root-ci`
- Commit style: conventional, e.g. `ci: add root workflow running validate-shards.sh` (repo history uses `chore:`, `docs(...):`, plain prefixes).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Normalize submodule URLs to HTTPS

In `.gitmodules`, change every `url = git@github.com:crystal-term/<name>.git` to `url = https://github.com/crystal-term/<name>.git` (six entries: cursor, prompt, reader, screen, spinner, terminfo; color is already HTTPS). Then run `git submodule sync`.

Maintainers who prefer SSH locally can keep using it via git's `url.<base>.insteadOf` rewriting; note this in the README section in Step 3.

**Verify**: `git config --file .gitmodules --get-regexp url` → seven lines, all starting `https://github.com/crystal-term/`. Then `git submodule update --init` → exit 0.

### Step 2: Create the root CI workflow

Create `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: crystal-lang/install-crystal@v1
        with:
          crystal: latest
      - name: Install readline headers
        run: sudo apt-get update && sudo apt-get install -y libreadline-dev
      - name: Validate all shards (local integration mode)
        run: scripts/validate-shards.sh --local

  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: crystal-lang/install-crystal@v1
        with:
          crystal: latest
      - name: Format check all shards
        run: |
          status=0
          for shard in color cursor screen terminfo reader spinner prompt progress; do
            echo "== $shard"
            (cd "shards/$shard" && crystal tool format --check src spec) || status=1
          done
          exit $status
    continue-on-error: true
```

The `format` job is `continue-on-error: true` deliberately: the shards have never had a format gate and may fail it today. A later cleanup can remove that flag after a formatting baseline lands. Do not format the code yourself in this plan.

**Verify**: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml"); puts "ok"'` (or `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"` if ruby is unavailable) → prints `ok`.

### Step 3: Run the harness locally as a proxy for the CI job

Run `scripts/validate-shards.sh --local` from the repo root. This is the same command CI will run.

**Verify**: exit code 0 and the summary line `All selected shard checks passed.` If specific shards fail, record which phase failed for which shard and STOP (see STOP conditions) — a failing harness is a pre-existing condition this plan surfaces, not one it fixes.

### Step 4: Add a "Getting started" section to README.md

Insert after the intro table in `README.md`:

```markdown
## Getting started

Clone with submodules:

    git clone --recurse-submodules https://github.com/crystal-term/crystal-term.git

Or, in an existing clone:

    git submodule update --init

Submodule URLs are HTTPS so anonymous and CI clones work. If you push via
SSH, add a rewrite once: `git config url."git@github.com:".insteadOf "https://github.com/"`.
```

**Verify**: `rg -n "recurse-submodules" README.md` → one match.

## Test plan

No new specs — this plan is infrastructure. The verification is Step 3 (harness green locally) plus YAML validity in Step 2.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `git config --file .gitmodules --get-regexp url | grep -c "https://github.com/crystal-term/"` prints `7`
- [ ] `.github/workflows/ci.yml` exists and parses as YAML
- [ ] `scripts/validate-shards.sh --local` exits 0 (or its failures are documented in the report as pre-existing)
- [ ] `rg -n "recurse-submodules" README.md` → 1 match
- [ ] `git status` shows no modified files outside `.gitmodules`, `.github/workflows/ci.yml`, `README.md` (managed `shard.override.yml` files created by `--local` are expected inside submodules; clean them with `scripts/validate-shards.sh --clean-local-overrides`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `git submodule update --init` fails after the URL change (network/auth issue — do not revert to SSH silently).
- `scripts/validate-shards.sh --local` fails in a phase other than the `format` concerns described above. Report the shard and phase; other plans (002–012) fix code bugs, this plan must not.
- The harness reports an unmanaged-override error for a shard other than `prompt`.

## Maintenance notes

- Once plans 002–010 land and the suite is reliably green, remove `continue-on-error: true` from the format job (after a one-time `crystal tool format` baseline commit in each shard).
- Plan 019 (Windows CI spike) extends this same workflow shape to per-shard matrices; keep the root workflow single-OS until then.
- When the `progress` shard gets its own repo (plan 018), the harness and this workflow keep working as long as `shards/progress` remains checked out (submodule or directory).
