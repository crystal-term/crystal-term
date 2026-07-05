# Plan 013: Color output respects terminal capabilities and NO_COLOR

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare excerpts against
> `shards/color/src/color/support.cr`, `mode.cr`, `env.cr`, and
> `shards/prompt/src/term-prompt.cr` (decorate).

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (changes visible output on non-truecolor terminals — that's the point)
- **Depends on**: 009 (color bug sweep)
- **Category**: bug / tech-debt
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

The color shard ships ~170 lines of capability detection (`Support`, `Mode` classes) that **nothing instantiates** — grep across all `shards/*/src` finds zero uses. Meanwhile `Prompt#decorate` emits 24-bit truecolor escapes unconditionally, ignoring `NO_COLOR`, `TERM=dumb`, and non-truecolor terminals; and terminfo carries a third, cruder detector (`attributes.cr`) that *is* live. Users on limited terminals get raw garbage bytes, and `NO_COLOR` (a de-facto standard the unused `Support#disabled?` already implements) is silently violated.

## Current state

- `shards/color/src/color/support.cr` — full `Term::Color::Support` class: `support?`, sourced from env vars, `tput colors` shell-out, and `disabled?` (checks `NO_COLOR`). Never instantiated anywhere (`rg -n 'Support' shards/*/src` → only the definition).
- `shards/color/src/color/mode.cr` — `Term::Color::Mode` detecting color depth (8/16/256/truecolor) from `TERM`/`COLORTERM` patterns. Also dead.
- `shards/color/src/color/env.cr` — env plumbing used by the two above.
- `shards/prompt/src/term-prompt.cr:430-434` — the one live emitter:

```430:434:shards/prompt/src/term-prompt.cr
    # Decorate the provided `message` using the given `color`. Color can be
    # a symbol, a `Term::Color` instance, or an `{R, G, B}` tuple.
    def decorate(message, color = @palette.enabled)
      Term::Color.truecolor_string(message, fore: color)
    end
```

- `Term::Color.truecolor_string` (`color.cr:165-204`) builds `\033[38;2;R;G;Bm...` unconditionally.
- `shards/terminfo/src/terminfo/attributes.cr:21-40` — a third detector with a hardcoded terminal list (live within terminfo; leave it in place, plan 016 owns cross-shard dedup).

## Target design

Scope discipline: wire the existing detectors in, don't rewrite them.

1. In `shards/color/src/color/color.cr` (or a new `term-color.cr`-level module method), add memoized module-level state:

```crystal
module Term::Color
  @@enabled : Bool? = nil

  def self.enabled? : Bool
    @@enabled ||= compute_enabled
    @@enabled.not_nil!
  end

  def self.enabled=(value : Bool?)  # nil resets to auto-detect
    @@enabled = value
  end

  private def self.compute_enabled : Bool
    support = Support.new(ENV.to_h)   # match Support's actual constructor — read support.cr first
    !support.disabled? && support.support?
  end
end
```

  (Adjust to `Support`'s real API — read `support.cr` and `env.cr` before writing; the sketch above is intent, not verbatim.)

2. `truecolor_string` honors it: first line `return string unless enabled?` — plain text passthrough when color is off. (Do NOT attempt depth degradation to 256/16 colors in this plan; that's a bigger design. Binary on/off + `NO_COLOR` compliance is the deliverable. `Mode` stays available for a future depth plan — add a one-line comment saying so instead of deleting it.)
3. `Prompt#decorate` needs no change (it flows through `truecolor_string`).
4. Specs: `Term::Color.enabled = false` / `= true` overrides for deterministic tests; reset to `nil` in an `after_each`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Color specs | `cd shards/color && crystal spec --no-color` | all pass |
| Prompt specs | `cd shards/prompt && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --shards color,prompt --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/color/src/color/color.cr` (enabled? plumbing + the `truecolor_string` guard)
- `shards/color/src/color/support.cr` / `env.cr` — only what's needed to call them (e.g. visibility, constructor defaults)
- `shards/color/spec/` — new `support_spec.cr` + `enabled_spec.cr`
- `shards/prompt/spec/` — one spec: decorate returns plain text when `Term::Color.enabled = false`

**Out of scope**:
- Deleting or rewriting `Mode`; depth degradation; `terminfo/attributes.cr` (plan 016); `string.cr` helpers beyond what the guard touches.

## Git workflow

- Submodules `shards/color` (branch `advisor/013-capability`) and `shards/prompt` (spec only, same branch name). Do NOT push.

## Steps

### Step 1: Read and wire `Support`

Read `support.cr` and `env.cr` fully. Implement `Term::Color.enabled?`/`enabled=` per the target design, adapted to the real constructor/API. If `Support#support?` shells out to `tput`, make sure `compute_enabled` runs at most once (memoized) and never raises (wrap the shell-out path in a rescue returning a conservative `true` for tty / `false` for non-tty).

**Verify**: `cd shards/color && crystal build --no-codegen src/term-color.cr` → exit 0.

### Step 2: Guard `truecolor_string`

Add the `return string unless enabled?` first line.

**Verify**: color spec — with `Term::Color.enabled = false`, `truecolor_string("x", fore: :red) == "x"`; with `= true`, output contains `"\e[38;2;"`.

### Step 3: Support/NO_COLOR specs

Table-driven specs on `Support` with injected env hashes: `NO_COLOR=1` → disabled; `TERM=dumb` → no support; `COLORTERM=truecolor` → support (align cases with what `support.cr` actually implements — characterize it).

**Verify**: `cd shards/color && crystal spec --no-color` → all pass.

### Step 4: Prompt decorate spec + cross-validate

**Verify**: prompt spec passes (`decorate("hi", :red) == "hi"` when disabled); `scripts/validate-shards.sh --local --shards color,prompt --skip-examples` → exit 0. Note: prompt/color spec helpers or CI may run with non-tty output, where auto-detect yields `false` — specs must always set `enabled=` explicitly rather than relying on auto-detection.

## Test plan

Steps 2–4. Reset discipline: every spec file touching `Term::Color.enabled=` restores `nil` in `after_each` (stdlib spec `Spec.after_each` or per-describe hooks).

## Done criteria

- [ ] `rg -n "def self.enabled\?" shards/color/src` → 1 match
- [ ] `rg -n "return string unless enabled\?" shards/color/src/color/color.cr` → 1 match
- [ ] `Support` is instantiated by non-spec code (`rg -n "Support.new" shards/color/src` ≥ 1)
- [ ] Color + prompt suites exit 0; cross-shard validation exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `Support`'s implementation is broken when actually exercised (it has never run) — characterize the failures and report before fixing beyond trivial repairs; a rewrite is out of scope.
- Making `truecolor_string` conditional breaks prompt rendering specs that assert exact escape-laden strings in numbers that suggest a design conflict (>10 re-baselines).
- `string.cr`'s `String#fore/#back` extensions bypass `truecolor_string` (check first: `rg -n "def fore|def back" shards/color/src/color/string.cr`) — if they emit escapes directly, they need the same guard; report if that expands scope materially.

## Maintenance notes

- Deferred deliberately: depth degradation (truecolor → 256 → 16) using `Mode`; delete `Mode` instead if nobody builds that within a release cycle.
- Terminfo's `attributes.cr` detector should eventually delegate to `Term::Color` (plan 016 territory).
- Release note: output is now plain text under `NO_COLOR`/dumb terminals — a behavior change users asked standards-compliance for.
