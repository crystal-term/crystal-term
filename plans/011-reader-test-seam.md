# Plan 011: Reader branches on an explicit seam, not on test-double class names

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: plans 002, 005, 006 must have landed (this plan
> re-baselines behavior they fixed). Verify:
> `rg -n "if is_on && @input.tty\?" shards/reader/src/reader/mode.cr` → 2 matches,
> `rg -n "global_handlers" shards/reader/src` → 0 matches. Compare excerpts below
> against live code (line numbers will have shifted).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (the class-name checks were papering over real echo/redraw bugs; removing the seam may resurface them)
- **Depends on**: 002, 005, 006
- **Category**: tech-debt
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

`Term::Reader` decides its echo and screen-clearing behavior by string-matching the **class names** of its IO objects against test-double names ("Mock", "KeyboardSimulator", "Detector", "OutputTracker"). Production code paths therefore differ from what the specs exercise — which is exactly how the raw-mode inversion (plan 002) and the unreachable Enter handler (plan 003) shipped unnoticed. Any consumer whose IO class name happens to contain those substrings silently gets test-mode behavior. The seam should be an explicit, documented property.

## Current state

In `shards/reader/src/term-reader.cr` (line numbers pre-plans-005/006; locate by content):

```143:145:shards/reader/src/term-reader.cr
      if echo && char && (@input.class.name.includes?("Mock") || @input.class.name.includes?("KeyboardSimulator"))
        @output.print(char)
      end
```

```194:196:shards/reader/src/term-reader.cr
        if raw && echo && @output.is_a?(IO::FileDescriptor) && @output.as(IO::FileDescriptor).tty? && !@output.class.name.includes?("Mock") && !@output.class.name.includes?("Detector") && !@output.class.name.includes?("OutputTracker")
          clear_display(line, screen_width)
        end
```

Plus comment-guarded logic around lines 247-263 ("For test scenarios, avoid full line redraw to prevent duplication").

Semantics being encoded, untangled:
- **Echo simulation**: real terminals echo typed characters themselves (when termios echo is on); memory/mock IOs don't, so specs need the reader to print the char manually or assertions on output fail.
- **Screen clearing / redraw**: ANSI clear/redraw sequences confuse string-equality assertions in specs, so they're suppressed for doubles.

Both reduce to one question: *is the output a real terminal?* — which `tty?` already answers. `@input.tty?`/`@output.tty?` are false for `IO::Memory` and test doubles, true for real terminals.

Reader's test doubles live in `shards/reader/spec/support/test_helpers.cr` (names like the ones string-matched above). The reader suite is Spectator, 17 files.

## Target design

Replace class-name checks with tty-based decisions plus one explicit override for exotic cases:

1. Add a constructor option: `@echo_simulation : Bool? = nil` — `nil` means "auto": simulate echo iff `!@input.tty?`.
2. `private def simulate_echo? : Bool` → `@echo_simulation.nil? ? !input_tty? : @echo_simulation.not_nil!` where `input_tty?` is `@input.responds_to?(:tty?) && @input.tty?` (IO::Memory responds to tty? returning false, so this is just `@input.tty?` guarded for non-fd IOs).
3. Echo site: `if echo && char && simulate_echo?` — applies to both the FileDescriptor and non-FileDescriptor branches of `get_codes` (the non-fd branch at ~line 129 already prints unconditionally under `echo`; unify them through `simulate_echo?`).
4. Clear/redraw site: `if raw && echo && output_tty?` — where `output_tty?` is the tty-duck-typed check; delete the three `includes?` clauses.
5. The redraw-suppression branch at ~247-263: gate on `output_tty?` (real terminal → full redraw behavior; non-tty → suppressed), delete the test-scenario comments.
6. Update `spec/support/test_helpers.cr` doubles to return `false` from `tty?` (they almost certainly already do — verify) and, where a spec intends to exercise the real-terminal path, construct the reader with `echo_simulation: false` and a double whose `tty?` returns true.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/reader && crystal spec --no-color` | all pass |
| Sniff grep | `rg -n 'class.name.includes' shards/reader/src` | 0 matches when done |
| Cross-shard | `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/reader/src/term-reader.cr`
- `shards/reader/spec/support/test_helpers.cr`
- Reader spec files whose assertions change because echo/redraw output changes

**Out of scope**:
- `console.cr`, `mode.cr`, `history.cr` (already fixed by earlier plans)
- Prompt sources — but its specs must stay green (prompt drives reader with IO::Memory, i.e. the auto/simulate path, which preserves current spec-visible behavior)

## Git workflow

- Inside `shards/reader`, branch `advisor/011-test-seam`. Do NOT push.

## Steps

### Step 1: Introduce the seam

Add the constructor option and the two private predicates; leave the old checks in place. Compile only.

**Verify**: `crystal build --no-codegen src/term-reader.cr` → exit 0.

### Step 2: Switch the echo site(s)

Replace the class-name echo condition with `simulate_echo?`; unify the non-FileDescriptor branch.

**Verify**: `crystal spec --no-color` → all pass (doubles are non-tty, so simulation still happens for them).

### Step 3: Switch the clear/redraw sites

Replace the class-name clauses with `output_tty?`; simplify the 247-263 branch accordingly.

**Verify**: `crystal spec --no-color`. If assertions fail because output now contains (or lacks) ANSI sequences, update the assertions to the *tty-based* expectation and record each change in the commit message — these are re-baselines, not regressions, but each one must be listed.

### Step 4: Delete the dead names and sweep

Remove any remaining `includes?("Mock"|"KeyboardSimulator"|"Detector"|"OutputTracker")` and the test-scenario comments.

**Verify**: `rg -n 'includes\?\("(Mock|KeyboardSimulator|Detector|OutputTracker)"' shards/reader/src` → 0 matches; full suite green.

### Step 5: Cross-validate

**Verify**: `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` → exit 0.

## Test plan

- Existing 17-file suite re-baselined where necessary (each re-baseline listed in commits).
- New specs: (a) reader with IO::Memory echoes typed chars to output (simulation auto-on); (b) reader constructed with `echo_simulation: false` and a tty-true double does NOT print the char itself; (c) tty-true double receives clear sequences during `read_line`, non-tty double does not. Model on the existing Spectator specs in `spec/unit/read_line_spec.cr` (or nearest equivalent).

## Done criteria

- [ ] `rg -n 'class\.name\.includes' shards/reader/src` → 0 matches
- [ ] `rg -n "echo_simulation" shards/reader/src/term-reader.cr` → ≥ 2 matches (option + predicate)
- [ ] New seam specs (a)/(b)/(c) exist and pass
- [ ] `cd shards/reader && crystal spec --no-color` exits 0
- [ ] `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- More than ~10 spec assertions need re-baselining in Step 3 — the output model diverges more than expected; report the diff pattern before continuing.
- Prompt specs break in ways that aren't plain output re-baselines (behavioral coupling to the old seam).
- You find a *fourth* semantics hidden in the class-name checks beyond echo-simulation and redraw-suppression.

## Maintenance notes

- The seam contract to document in code: "echo simulation is for non-tty inputs; real terminals echo via termios". Future doubles must implement `tty?` honestly instead of relying on their class name.
- Plan 021 (escape handling) will add timing-sensitive reads; it should use this same seam for its test IO.
- Reviewer: diff the spec re-baselines one by one — anything that changed direction (echo appearing where it didn't before) needs a human eye.
