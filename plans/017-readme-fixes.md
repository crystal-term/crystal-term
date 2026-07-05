# Plan 017: The spinner and prompt READMEs stop lying

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: check whether plan 007 landed
> (`rg -n "1000 // " shards/spinner/src/term-spinner.cr` → 1 match if it did).
> The interval documentation below assumes 007's Hz semantics; if 007 has NOT
> landed, STOP — the doc fix depends on that decision.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 007 (interval semantics decision)
- **Category**: docs
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

The spinner README is actively wrong in four places — Ruby (`TTY::Spinner`) namespaces in copy-paste examples, a dead file link, a copy-paste intro referencing `Term::Screen`, and interval semantics that contradicted the code by 4x (plan 007 makes the code match the documented Hz; this plan cleans the remaining prose). The prompt README has one non-compiling DSL example. These are the most-read files in the family; broken copy-paste is the first-contact experience.

## Current state

- `shards/spinner/README.md`:
  - ~line 87: "The interval is a number in hertz, or `(n * 100) milliseconds`." — the parenthetical is wrong under Hz semantics (interval n → `1000/n` ms per frame).
  - ~line 184: example uses `TTY::Spinner.new("[:spinner] :status")` — wrong namespace (should be `Term::Spinner`).
  - ~line 226: links to `/src/spinner/format.cr` — actual file is `src/spinner/formats.cr`.
  - ~line 365: `TTY::Spinner::Multi.new("[:spinner] top")` — wrong namespace.
  - ~line 11 area: intro sentence says "**Term::Screen** provides an independent spinner component" — copy-paste from another shard's README.
  - ~lines 240-243: `:interval` section says Hz — after plan 007 this is *correct*; ensure the surrounding example (`interval: 20 # 20 Hz (20 times per second)`) stays and the `(n * 100) milliseconds` phrasing at ~87 is fixed to `1000/n milliseconds per frame`.
- `shards/prompt/README.md`:
  - ~line 998: missing comma — `q.choice key: "y", name: "Overwrite"      value: "ok"` (syntax error if pasted).
  - ~line 1009: `prompt.expand('Overwrite shard.yml?', ...)` — Ruby single-quoted string; Crystal needs double quotes.
- Everything else in the prompt README was spot-verified against `src/term-prompt.cr:77-432` (all documented methods exist); no other changes needed.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Namespace sweep | `rg -n "TTY::" shards/spinner/README.md shards/prompt/README.md` | 0 matches when done |
| Link check | `test -f shards/spinner/src/spinner/formats.cr && echo ok` | ok |
| Example compile spot-check | extract the fixed prompt DSL snippet into `/tmp/x.cr` with the require line and run `crystal build --no-codegen` | exit 0 |

## Scope

**In scope**:
- `shards/spinner/README.md`
- `shards/prompt/README.md`

**Out of scope**:
- All other READMEs (spot-checks found no actionable staleness); source files; the root README (plan 001 touches it).

## Git workflow

- Submodules `shards/spinner` and `shards/prompt`, branch `advisor/017-readme` in each; commits `docs: fix namespaces, interval semantics, and broken link in README` / `docs: fix expander DSL example syntax`. Do NOT push.

## Steps

### Step 1: Spinner README

Apply the five fixes listed above. For every remaining code fence in the file, scan for `TTY::` while you're there (`rg -n "TTY::" shards/spinner/README.md` must end at 0).

**Verify**: `rg -n "TTY::|format\.cr|Term::Screen provides" shards/spinner/README.md` → 0 matches; `rg -n "n \* 100" shards/spinner/README.md` → 0 matches.

### Step 2: Prompt README

Add the missing comma at ~998; fix the single-quoted string at ~1009. Extract the fixed expander snippet to a temp file with `require "term-prompt"` context and confirm it parses: `crystal tool format /tmp/x.cr` (parse check without needing deps).

**Verify**: `rg -n "Overwrite\"      value" shards/prompt/README.md` → 0 matches; `rg -n "expand\('" shards/prompt/README.md` → 0 matches.

## Test plan

Not applicable beyond the parse spot-check in Step 2.

## Done criteria

- [ ] `rg -n "TTY::" shards/spinner/README.md shards/prompt/README.md` → 0 matches
- [ ] Spinner README links to `formats.cr` and describes interval as Hz with `1000/n` ms framing
- [ ] Prompt README expander example parses
- [ ] `plans/README.md` status row updated

## STOP conditions

- Plan 007 has not landed (interval semantics undecided) — the code and README must change together.
- You find the spinner README documents an API that doesn't exist in `src/` (beyond the items listed) — inventory it in the report; rewriting the README wholesale is out of scope.

## Maintenance notes

- The `TTY::` residue suggests these READMEs were ported by find-replace that missed code fences; when adding new examples, copy from `examples/*.cr` files (which compile in CI via the harness) rather than writing prose-only snippets.
