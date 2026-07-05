# Plan 021: SPIKE — bare Escape keypresses are handled correctly in reader

> **Executor instructions**: This is an investigate-and-prototype spike on the
> hardest input-handling problem in the family. The deliverable is a working
> prototype branch in `shards/reader` plus a findings report — merging is a
> follow-up decision. Follow the steps; honor STOP conditions; update the
> status row in `plans/README.md` when done.
>
> **Drift check (run first)**: plans 002, 005, 006 must have landed (they change
> `get_codes`' surroundings). Confirm the FIXME still exists:
> `rg -n "FIXME: Fails to handle escape" shards/reader/src/term-reader.cr` → 1 match.

## Status

- **Priority**: P3 (direction)
- **Effort**: M
- **Risk**: MED — timing-based escape disambiguation can regress arrow-key parsing across terminals
- **Depends on**: 002, 005, 006; 011 recommended (test seam)
- **Category**: direction
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

The Escape key is table stakes for TUI cancel flows (dismiss a menu, abort a prompt), and reader's own code admits it doesn't work: `term-reader.cr:121` carries `# FIXME: Fails to handle escape '\e' all by itself`. The problem is classic: `\e` is both a complete keypress *and* the prefix of every arrow/function-key sequence, so a reader must decide "bare ESC or sequence prefix?" — solvable only with a short read timeout after seeing `\e`. Reader is the highest-fan-in interactive shard (prompt sits on it), and prompt currently subscribes `:escape` handlers that can't fire reliably. This spike builds and evaluates the timeout approach.

## Current state

- `shards/reader/src/term-reader.cr` — `get_codes` accumulates escape sequences by looping while the collected codes still prefix-match a known escape pattern, using **recursive non-blocking reads**:

```120:167:shards/reader/src/term-reader.cr
    # Get input code points
    # FIXME: Fails to handle escape '\e' all by itself
    def get_codes(echo : Bool, raw : Bool, nonblock : Bool, interrupt : Symbol | Proc = @interrupt) : Array(Int32)?
      ...
      codes = [char.ord] of Int32
      condition = ->(escape : Array(UInt8)) do
        (codes - escape).empty? ||
        (escape - codes).empty? &&
        !(64..126).covers?(codes.last)
      end

      while console.escape_codes.any? { |escape| condition.call(escape) }
        char_codes = get_codes(echo, raw, true)
        break if char_codes.nil?
        codes.concat char_codes
      end

      codes
    end
```

  The `while` loop's exit relies on the non-blocking follow-up read returning nil — but between a human's ESC press and "no more bytes", nil can arrive *instantly* (bare ESC, correct) or the terminal may still be mid-burst on a slow pty (sequence bytes arrive a moment later, and a too-eager nil mis-parses an arrow key as ESC + garbage letters).
- `shards/reader/src/reader/console.cr` — `TIMEOUT = 100.milliseconds` constant exists but is **unused** (`rg -n "TIMEOUT" shards/reader/src` — defined, never referenced). `escape_codes` = `[[27], CSI bytes, [27, 79]]` (ESC, `\e[`, `\eO`).
- `keys.cr` maps `"\e" => "escape"` plus many `\e[...` sequences.
- How upstream solves it: tty-reader (Ruby) wraps the post-ESC read in a ~50-100ms `Timeout`/select; if no byte arrives, it's a bare ESC. Crystal equivalents: `IO::FileDescriptor#read_timeout=`, or a `select` with a `timeout` branch on a channel-wrapped read, or `Crystal::System::FileDescriptor` wait primitives. The prototype should prefer `read_timeout` (simplest) with `IO::TimeoutError` rescue.
- Test infrastructure: after plan 011, reader has an explicit non-tty seam; simulating *timing* still needs a controllable IO — an `IO::Memory` won't block, so bare-ESC-vs-sequence timing can be simulated with a pipe (`IO.pipe`) written from a fiber with deliberate delays.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/reader && crystal spec --no-color` | all pass |
| Prototype spec file | `cd shards/reader && crystal spec spec/unit/escape_handling_spec.cr --no-color` | passes |
| Downstream | `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` | exit 0 |

## Scope

**In scope** (on a prototype branch):
- `shards/reader/src/term-reader.cr` (`get_codes` escape path)
- `shards/reader/src/reader/console.cr` (use the `TIMEOUT` constant; possibly expose a knob)
- `shards/reader/spec/unit/escape_handling_spec.cr` (create)
- `shards/reader/examples/escape_check.cr` (create; manual TTY gate)
- `plans/reports/021-escape-findings.md` (create, root repo)

**Out of scope**:
- Prompt-side `:escape` behaviors (they light up automatically once events fire); Windows console input; rewriting `get_codes`' recursion wholesale (unless the findings say it's unavoidable — then that's the report's recommendation, not this spike's implementation).

## Git workflow

- `shards/reader` branch `advisor/021-escape-spike` — explicitly a prototype branch; the merge decision follows the report. Root branch for the report. Do NOT push.

## Steps

### Step 1: Characterize current behavior with a pipe-based harness

Write `escape_handling_spec.cr` using `IO.pipe`: writer fiber feeds (a) `"\e"` alone then closes; (b) `"\e[A"` in one write; (c) `"\e"` then 5ms later `"[A"` (split-burst arrow key); (d) `"\e\e"` (double ESC). Record what `read_keypress` currently returns for each. Mark the failing ones `pending` initially — this is the characterization baseline for the report.

**Verify**: spec file runs; findings recorded in the report ("current behavior" table).

### Step 2: Prototype timeout disambiguation

In the escape-accumulation loop, when `codes == [27]` (a lone ESC so far) and the non-blocking follow-up read returned nil, do a **bounded blocking wait**: set `@input.read_timeout = Console::TIMEOUT` (use 50ms; make `TIMEOUT` 50.milliseconds and actually use it), attempt one more read, rescue `IO::TimeoutError` → bare ESC confirmed; a byte arriving → continue sequence accumulation. Restore `read_timeout = nil` in an `ensure`. Non-fd IOs (specs with IO::Memory) skip the wait — nil means bare ESC immediately, preserving existing spec behavior.

**Verify**: Step 1's cases (a), (b), (d) pass un-pended; (c) passes when the split delay is under the timeout.

### Step 3: Regression sweep

Full reader suite + prompt suite (arrow-key navigation specs are the regression risk).

**Verify**: `crystal spec --no-color` in reader and prompt → all pass; `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` → exit 0.

### Step 4: Manual TTY example + report

`examples/escape_check.cr`: loop printing named keypresses (`escape`, `up`, `down`, letters) until `q`. The report (`plans/reports/021-escape-findings.md`) records: the characterization table, the chosen timeout value and why, measured behavior in at least one real terminal (operator step if the executor has no TTY), latency implications (ESC registers after 50ms — acceptable? tmux users' `escape-time` precedent says yes), and a merge/no-merge recommendation.

**Verify**: example compiles; report contains all four sections.

## Test plan

The pipe-based spec file is the durable artifact: cases (a)-(d) plus one no-regression case for a fast full-sequence arrow key. Timing-based — keep delays generous (5ms vs 50ms timeout) to avoid flakiness, and gate the timing cases so they can be skipped on overloaded CI if they prove flaky (report should note if they do).

## Done criteria

- [ ] `escape_handling_spec.cr` exists; cases (a), (b), (d) pass; (c) passes or is documented-flaky
- [ ] `rg -n "read_timeout" shards/reader/src` ≥ 1 match; `TIMEOUT` constant is used
- [ ] Reader + prompt suites green; harness subset green
- [ ] `plans/reports/021-escape-findings.md` complete with merge recommendation
- [ ] `plans/README.md` status row updated

## STOP conditions

- The recursive structure of `get_codes` makes the bounded wait unimplementable without restructuring (the recursion passes `nonblock: true` unconditionally at the accumulation site) — if restructuring exceeds ~40 lines of change, stop and put the redesign sketch in the report instead.
- `read_timeout` is unavailable/broken for the input fd type on this platform — document and evaluate the `select`-based alternative in the report without implementing it.
- Prompt arrow-key specs regress and the fix isn't obvious within the timeout design.

## Maintenance notes

- If merged, expose the timeout as a Reader constructor option (power users and tmux-style low-latency configs will want it); default 50ms.
- Windows console input does not deliver ANSI byte sequences by default — the whole approach is Unix-scoped; plan 019's findings will say whether Windows needs a parallel path.
- The `DELETE = 27` misnamed constant (noted in plan 006) should be renamed `ESC_CODE` if this branch touches those lines anyway.
