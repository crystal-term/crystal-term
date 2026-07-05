# Plan 002: Reader actually enters raw mode when raw mode is requested

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git -C shards/reader diff --stat HEAD -- src/reader/mode.cr src/reader/console.cr spec/` plus compare the excerpts below against the live files.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: MED (changes real-TTY behavior for every consumer of reader)
- **Depends on**: 001 (CI baseline; can proceed without it, but validate manually)
- **Category**: bug
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

`Term::Reader::Mode#raw` has inverted logic: when the caller asks for raw mode (`is_on == true`) it yields *without* touching the terminal, and when the caller asks for non-raw it wraps the block in `@input.raw`. `Mode#cooked` is inverted the same way. The composed effect in `Console#get_char` is that `read_keypress(raw: true)` — the basis of every interactive prompt in the family — runs the terminal in cooked mode on a real TTY: input requires Enter, and echo/interrupt behavior is wrong. The spec suite passes because it drives reader through `IO::Memory`, which skips the TTY path entirely (`mode.cr` checks `@input.tty?`).

## Current state

- `shards/reader/src/reader/mode.cr` — the three mode wrappers. `echo` is correct (echo is the terminal default, so "on" means "do nothing"). `raw` and `cooked` copied `echo`'s shape, but for them "on" means "change the terminal", so the condition is backwards:

```16:32:shards/reader/src/reader/mode.cr
      # Use raw mode in the given block
      def raw(is_on : Bool = true, & : ->)
        if is_on || !@input.tty?
          yield
        else
          @input.raw { yield }
        end
      end

      # Enable character processing for the given block
      def cooked(is_on : Bool = true, & : ->)
        if is_on || !@input.tty?
          yield
        else
          @input.cooked { yield }
        end
      end
```

- `shards/reader/src/reader/console.cr` — `get_char` composes the three. With the current inversion, `raw: true` produces `cooked(false)` → *enters cooked mode* and `raw(true)` → no-op:

```24:38:shards/reader/src/reader/console.cr
      def get_char(raw : Bool, echo : Bool, nonblock : Bool) : Char?
        char = nil
        mode.cooked(!raw) do
          mode.raw(raw) do
            mode.echo(echo) do
              @input.blocking = !nonblock
              char = @input.read_char
            end
          end
        end

        char
      rescue
        nil
      end
```

- Crystal stdlib provides `IO::FileDescriptor#raw(&)`, `#cooked(&)`, `#noecho(&)` which save and restore termios state around the block — the wrappers just need to call them under the right condition.
- Reader spec suite: `cd shards/reader && crystal spec --no-color`. Specs use Spectator; `spec/unit/mode_spec.cr` exists and may assert the current (inverted) behavior — read it before editing and update assertions to the corrected semantics if needed.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install (reader) | `cd shards/reader && shards install` | exit 0 |
| Specs (reader) | `cd shards/reader && crystal spec --no-color` | all pass |
| Downstream check | `scripts/validate-shards.sh --local --shards reader,prompt,progress --skip-examples` | exit 0 |
| Format | `cd shards/reader && crystal tool format src spec` | exit 0 |

## Scope

**In scope** (the only files you should modify):
- `shards/reader/src/reader/mode.cr`
- `shards/reader/spec/unit/mode_spec.cr` (update assertions if they encode the inverted behavior)
- `shards/reader/examples/` — add one small manual-test example (see Step 3)

**Out of scope** (do NOT touch, even though they look related):
- `shards/reader/src/reader/console.cr` — after `mode.cr` is fixed, `get_char`'s composition is correct as written; its `blocking` restore and bare `rescue` are handled by plan 006.
- `shards/reader/src/term-reader.cr` — the class-name test-sniffing there is plan 011.
- Anything in `shards/prompt` — it consumes the fix transitively.

## Git workflow

- Work happens **inside the `shards/reader` submodule** (its own git repo). Branch there: `advisor/002-raw-mode`. Commit style: `fix: enter raw/cooked mode when requested in Mode wrappers`.
- Do NOT push, and do not commit the submodule pointer bump in the root repo unless the operator asks.

## Steps

### Step 1: Fix the two inverted wrappers

In `shards/reader/src/reader/mode.cr`, change `raw` and `cooked` so that "on" means "apply the mode":

```crystal
# Use raw mode in the given block
def raw(is_on : Bool = true, & : ->)
  if is_on && @input.tty?
    @input.raw { yield }
  else
    yield
  end
end

# Enable character processing for the given block
def cooked(is_on : Bool = true, & : ->)
  if is_on && @input.tty?
    @input.cooked { yield }
  else
    yield
  end
end
```

Leave `echo` exactly as it is (its inversion is correct for echo semantics).

**Verify**: `cd shards/reader && crystal build --no-codegen src/term-reader.cr` → exit 0.

### Step 2: Reconcile the spec suite

Read `shards/reader/spec/unit/mode_spec.cr`. If any example asserts that `raw(true)` yields without entering raw mode (or the `cooked` equivalent), update the assertion to the corrected semantics. Since specs run with non-TTY IO, most likely they only cover the `!tty?` path, which is unchanged.

**Verify**: `cd shards/reader && crystal spec --no-color` → all pass, 0 failures.

### Step 3: Add a manual TTY smoke example

Create `shards/reader/examples/raw_mode_check.cr`:

```crystal
require "../src/term-reader"

reader = Term::Reader.new
puts "Press any single key (should register WITHOUT pressing Enter):"
key = reader.read_keypress
puts "\ngot: #{key.inspect}"
```

This cannot be asserted in CI, but it must compile, and the plan reviewer can run it in a real terminal to confirm a single keypress registers immediately.

**Verify**: `cd shards/reader && crystal build --no-codegen examples/raw_mode_check.cr` → exit 0.

### Step 4: Cross-shard validation

Run `scripts/validate-shards.sh --local --shards reader,prompt,progress --skip-examples` from the repo root to confirm dependents still build and pass.

**Verify**: exit 0.

## Test plan

- Update/extend `spec/unit/mode_spec.cr` with examples documenting the intent for the non-TTY path (raw/cooked/echo all yield unchanged when input is not a TTY) so the semantics are pinned.
- The real-TTY path is untestable in CI; the example in Step 3 is the manual gate. State this in the commit message.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `rg -n "if is_on && @input.tty\?" shards/reader/src/reader/mode.cr` → 2 matches (raw and cooked)
- [ ] `cd shards/reader && crystal spec --no-color` exits 0
- [ ] `crystal build --no-codegen shards/reader/examples/raw_mode_check.cr` (run from `shards/reader`) exits 0
- [ ] `scripts/validate-shards.sh --local --shards reader,prompt,progress --skip-examples` exits 0
- [ ] `git -C shards/reader status` shows no modified files outside the in-scope list
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- `mode.cr` no longer matches the excerpt above (someone fixed or changed it already).
- Reader specs fail in files *other than* `mode_spec.cr` after the change — that means production code paths depended on the inversion; report which specs and stop rather than patching call sites.
- You find call sites in `shards/prompt` or `shards/reader` that pass `raw: false` expecting raw behavior (compensating for the bug). Search first: `rg -n "raw: false" shards/reader/src shards/prompt/src`. If any exist, list them in the report.

## Maintenance notes

- Plan 011 (removing test-class-name sniffing) re-baselines reader specs against real behavior; it assumes this fix has landed.
- Reviewer: manually run `examples/raw_mode_check.cr` in a real terminal — single-keypress capture without Enter is the acceptance test that CI cannot provide.
