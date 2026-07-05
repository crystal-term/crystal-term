# Plan 020: SPIKE — design (and prototype) an umbrella `term` meta-shard

> **Executor instructions**: This is a design spike with a small prototype. The
> deliverable is a working prototype under `plans/prototypes/term/` plus a
> decision memo — NOT a published shard. Follow the steps; when done, update
> the status row in `plans/README.md`.
>
> **Drift check (run first)**: confirm no umbrella exists:
> `rg -rn "term-all|crystal-term/term\b" shards docs README.md --glob '!lib'` → 0 matches.

## Status

- **Priority**: P3 (direction)
- **Effort**: S-M
- **Risk**: LOW (additive; the risk is release-process overhead, which the memo must quantify)
- **Depends on**: none (018 improves it — progress joins the umbrella only once installable)
- **Category**: direction
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

Users building a full TUI currently hand-assemble four or five dependency blocks (prompt's own shard.yml pulls four siblings; progress pulls three). The Ruby original ships exactly this convenience: the `tty` gem aggregates the tty-* family. This repo already treats the family as one unit — the harness validates all eight in dependency order and releases go in coordinated layers — so a one-file meta-shard that pins the family at matched versions is cheap to build. What's genuinely open is whether it's worth the recurring release overhead, since no user has asked for it in the issue inventory. Hence: spike, not build-and-publish.

## Current state

- Family (all v1.0.0): term-color, term-cursor, term-screen, term-terminfo, term-reader, term-spinner, term-prompt, term-progress (last one not installable — see plan 018).
- Dependency spec format used family-wide (from `shards/prompt/shard.yml`):

```yaml
dependencies:
  term-color:
    github: crystal-term/color
    version: ~> 1.0.0
```

- Require paths: each shard's entry file is `src/term-<name>.cr` requiring into the `Term::` namespace (`Term::Color`, `Term::Cursor`, `Term::Screen`, `Term::Terminfo`, `Term::Reader`, `Term::Spinner`, `Term::Prompt`, `Term::Progress`).
- Release layering (docs/release-validation.md): leaves → middle → top; an umbrella would be a fourth layer.
- Namespace collision question to check in the spike: the shard would naturally be named `term` with entry `require "term"`; nothing in the family currently owns a bare `src/term.cr`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Prototype install | `cd plans/prototypes/term && shards install` | exit 0 |
| Prototype build | `cd plans/prototypes/term && crystal build --no-codegen src/term.cr` | exit 0 |
| Smoke example | `crystal build --no-codegen examples/smoke.cr` | exit 0 |

## Scope

**In scope**:
- `plans/prototypes/term/` — shard.yml, `src/term.cr`, `examples/smoke.cr`
- `plans/reports/020-term-umbrella-memo.md` — the decision memo

**Out of scope**:
- Creating a `crystal-term/term` GitHub repo, tagging, publishing — operator decisions the memo informs.
- Modifying any existing shard, the harness, or release docs (the memo *proposes* those changes).

## Git workflow

- Root repo branch `advisor/020-term-umbrella`. Prototype lives under `plans/prototypes/` so it's clearly not a shipped artifact. Do NOT push.

## Steps

### Step 1: Prototype the shard

`plans/prototypes/term/shard.yml`:

```yaml
name: term
version: 1.0.0
description: Umbrella shard for the crystal-term family
crystal: ">= 1.0.0"
license: MIT

dependencies:
  term-color:    {github: crystal-term/color,    version: ~> 1.0.0}
  term-cursor:   {github: crystal-term/cursor,   version: ~> 1.0.0}
  term-screen:   {github: crystal-term/screen,   version: ~> 1.0.0}
  term-terminfo: {github: crystal-term/terminfo, version: ~> 1.0.0}
  term-reader:   {github: crystal-term/reader,   version: ~> 1.0.0}
  term-spinner:  {github: crystal-term/spinner,  version: ~> 1.0.0}
  term-prompt:   {github: crystal-term/prompt,   version: ~> 1.0.0}
```

(progress joins after plan 018 makes it fetchable — note in memo.) `src/term.cr` is seven requires. `examples/smoke.cr` touches each namespace (`Term::Color`, `Term::Prompt.new`, `Term::Spinner.new(output: STDERR)`, `Term::Screen.size`, ...) to prove co-requirement works.

For local iteration, use a `shard.override.yml` in the prototype pointing every dep at `../../../shards/<name>` (path overrides), mirroring the harness's technique.

**Verify**: `shards install` then `crystal build --no-codegen src/term.cr` and `examples/smoke.cr` → exit 0.

### Step 2: Probe the collision/versioning questions

Record answers in the memo:
- Does `require "term"` conflict with anything on shardbox/crystal ecosystem named `term`? (Web check.)
- Does resolving all seven together produce any version conflict today? (`shards install` output from Step 1 answers it.)
- Version policy: umbrella tracks family majors (`term 1.x` pins `~> 1.0` for all)? What happens when one member ships 2.0? (Proposal: umbrella majors follow the *family* major, released as the final layer.)

### Step 3: Write the decision memo

`plans/reports/020-term-umbrella-memo.md`: prototype result, the three probe answers, the release-overhead cost (one more tag per cycle, appended as layer 4 in docs/release-validation.md), the demand evidence (currently: none in issues; convenience argument + upstream `tty` precedent only), and a go/no-go recommendation with the criteria that would flip it (e.g. "first user request or the second time someone files a version-skew bug across family members").

**Verify**: memo exists and contains the go/no-go section.

## Test plan

The smoke example is the test: all family namespaces usable from one require, resolved at matched versions.

## Done criteria

- [ ] Prototype installs and both files compile
- [ ] Memo answers the three probe questions with a recommendation
- [ ] No existing shard or doc modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- `shards install` on the prototype reveals a real version conflict among the family — that's a finding in itself; record it and stop (fixing pins crosses into release management).

## Maintenance notes

- If the decision is "go": repo creation, harness addition (`ALL_SHARDS` + a layer-4 note), and docs update become a small follow-up plan; the prototype moves to the new repo nearly as-is.
- If "no-go": keep the memo; re-evaluate on the flip criteria it names.
