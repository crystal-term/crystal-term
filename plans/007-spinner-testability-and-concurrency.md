# Plan 007: Spinner accepts any IO, its concurrency bugs are fixed, and its lifecycle has specs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare every excerpt below against
> `shards/spinner/src/term-spinner.cr` and `shards/spinner/src/spinner/multi.cr`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (interval fix visibly changes animation speed; output type widening is API-affecting)
- **Depends on**: none
- **Category**: bug / tests
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

The spinner shard's entire visible behavior — frame animation, stop marks, multi-spinner row bookkeeping — has zero test coverage, because `output` is typed `IO::FileDescriptor` (impossible to inject `IO::Memory`) and every `write` no-ops when the output isn't a TTY. Hidden behind that blind spot are four real bugs: every `auto_spin` leaks a fiber blocked forever on a channel nothing receives; `Multi#synchronize` leaves its mutex locked if the block raises (permanent deadlock of all sibling spinners); the interval math contradicts both the README and upstream tty-spinner (formats with interval 15/20 animate *slower*, not faster); and `stop`'s `ensure` re-emits `:done` on every call, even early-returned ones. The sibling `progress` shard already solved the injection problem with a `TestIO` helper — this plan ports that pattern and fixes the bugs under new specs.

## Current state

All in `shards/spinner/src/` unless noted.

- `term-spinner.cr:26` — the injection blocker:

```26:26:shards/spinner/src/term-spinner.cr
    getter output : IO::FileDescriptor
```

  and `term-spinner.cr:361-375` — `write` gates all rendering on `tty?`; `tty?` (line 329-331) already duck-types: `output.responds_to?(:tty?) ? output.tty? : false`.

- `term-spinner.cr:72-73` — interval math. README documents Hz ("a value of `10` ... 10 animation frames per second"), but the code multiplies:

```72:73:shards/spinner/src/term-spinner.cr
      interval = options[:interval]? || format[:interval]? || 10
      @interval = interval.is_a?(Time::Span) ? interval : (interval * 10).milliseconds
```

  Hz semantics require `(1000 / interval)` ms; the two coincide only at 10. `shards/spinner/src/spinner/formats.cr` presets use intervals like 15 and 20. The same formula is duplicated at `shards/progress/src/progress/spinner_integration.cr:52-60` (`when Int32 → (chosen_interval * 10).milliseconds`, `when Nil → (10 * 10).milliseconds`).

- `term-spinner.cr:218-237` — the fiber leak: the spawned fiber ends with `ch.send(nil)` on an unbuffered channel; `rg -n 'receive' shards/spinner/src` shows the only receive is `multi.cr:106` on a *different* channel (`jobs`). After `stop`, the fiber wakes, exits the loop, and blocks forever in `send`, pinning the fiber and the spinner object:

```223:232:shards/spinner/src/term-spinner.cr
      @channel = Channel(Nil).new.tap do |ch|
        spawn(same_thread: true) do
          sleep(sleep_time)
          until stopped?
            sleep(sleep_time)
            spin unless paused?
          end
          ch.send(nil)
        end
      end
```

- `term-spinner.cr:138-165` — `stop`: `return if done?` at the top does NOT skip the `ensure` block (Crystal runs `ensure` even for early returns), so every call — including repeated stops on a finished spinner — re-runs the completion bookkeeping and `emit(:done)`:

```138:165:shards/spinner/src/term-spinner.cr
    def stop(stop_message = "")
      return if done?
      ...
    ensure
      @done = true
      @state = State::Stopped
      @started_at = nil

      if @hide_cursor
        write(Term::Cursor.show, false)
      end

      emit(:done)
      # kill
      # @mutex.unlock
    end
```

- `term-spinner.cr:294-314` — `success`/`error` hold `@mutex` around `stop` + `emit`; `spin` (256-272) holds it around `emit(:spin)`. Crystal's `Mutex` is not reentrant by default: any user callback registered via `on` that calls `pause`, `resume`, `update`, or `on` (all of which lock `@mutex`) deadlocks. `Multi#observe` (multi.cr:206-244) wires exactly such callbacks.

- `multi.cr:179-183` — the unguarded lock:

```179:183:shards/spinner/src/spinner/multi.cr
      def synchronize(&block)
        @mutex.lock
        yield
        @mutex.unlock
      end
```

- The reference pattern for injectable test IO lives at `shards/progress/spec/helpers/test_io.cr` — a `TestIO < IO` with `getter output : String`, `tty?` returning a constructor flag, buffered `write`, no-op `flush`, and `clear`. Copy it.
- Existing spec: `shards/spinner/spec/spinner_spec.cr` covers initial state only and contains the comment "We can't easily test the output without mocking IO". Spec helper requires stdlib `spec` (Spectator is declared in shard.yml but unused — plan 014 removes it; do not touch shard.yml here).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd shards/spinner && shards install` | exit 0 |
| Specs | `cd shards/spinner && crystal spec --no-color` | all pass |
| Progress specs (interval dedup) | `cd shards/progress && shards install && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --shards spinner,progress --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/spinner/src/term-spinner.cr`
- `shards/spinner/src/spinner/multi.cr`
- `shards/spinner/spec/` (new helper + new specs)
- `shards/progress/src/progress/spinner_integration.cr` (interval formula only, keep in sync)
- `shards/spinner/README.md` — only if you finish early; the full README fix is plan 017

**Out of scope**:
- `shards/spinner/shard.yml` (plan 014), spinner token-replacement perf (plan 012), `formats.cr` contents.
- `Multi`'s event-handler design beyond the `synchronize`/emit-under-lock fixes.

## Git workflow

- `shards/spinner` is a submodule: branch `advisor/007-concurrency`; `shards/progress` is a plain directory tracked by the **root** repo: commit its one-file change on a root branch `advisor/007-progress-interval`. Do NOT push either.

## Steps

### Step 1: Widen output to `IO` and port TestIO

Change line 26 to `getter output : IO`. Check constructor typing (`@output = options[:output]? || STDERR` — fine as `IO`). Copy `shards/progress/spec/helpers/test_io.cr` to `shards/spinner/spec/helpers/test_io.cr` (keep the class name `TestIO`; drop `ErrorIO` if unused) and require it from `spec_helper.cr`.

**Verify**: `cd shards/spinner && crystal spec --no-color` → existing examples pass; a smoke spec `Term::Spinner.new(output: TestIO.new).spin` produces non-empty `TestIO#output`.

### Step 2: Fix interval semantics (Hz) in both shards

- `term-spinner.cr:73` → `@interval = interval.is_a?(Time::Span) ? interval : (1000 // interval).milliseconds`
- `spinner_integration.cr` (progress): `when Int32` → `(1000 // chosen_interval).milliseconds`; `when Nil` → `(1000 // 10).milliseconds`

**Verify**: spec asserting `Term::Spinner.new(interval: 20, output: TestIO.new).interval == 50.milliseconds` and `interval: 10 → 100.milliseconds`; `cd shards/progress && crystal spec --no-color` → all pass.

### Step 3: Fix the auto_spin fiber leak

Simplest correct shape: drop the channel entirely and let the fiber exit on its own — nothing reads it today, so there are no join semantics to preserve:

```crystal
def auto_spin
  start
  sleep_time = @interval
  spin
  spawn(same_thread: true) do
    sleep(sleep_time)
    until stopped?
      sleep(sleep_time)
      spin unless paused?
    end
  end
ensure
  ...
end
```

Remove the now-unused `@channel` ivar and its initialization. (If something else references `@channel`, STOP — see conditions.)

**Verify**: `rg -n "@channel" shards/spinner/src` → 0 matches; spec: `auto_spin` then `stop` on a TestIO spinner, `sleep` two intervals, `Fiber.yield`, assert `spinner.done?` and no exception.

### Step 4: `Multi#synchronize` with ensure

```crystal
def synchronize(&block)
  @mutex.synchronize { yield }
end
```

**Verify**: spec — call `multi.synchronize { raise "boom" }` rescuing the error, then assert a second `multi.synchronize { }` completes (no deadlock; guard the spec with a timeout via `spawn` + channel or keep it simple: successful second call is the assertion since a deadlock hangs the suite).

### Step 5: `stop` early-return must skip the completion bookkeeping

Restructure so the guard sits outside the `ensure`'s reach:

```crystal
def stop(stop_message = "")
  return if done?
  begin
    clear_line
    return if @clear
    data = message.gsub(MATCHER, next_char)
    data = replace_tokens(data)
    data += " " + stop_message unless stop_message.empty?
    write(data, false)
    write("\n", false) unless @clear || @multispinner
  ensure
    @done = true
    @state = State::Stopped
    @started_at = nil
    write(Term::Cursor.show, false) if @hide_cursor
    emit(:done)
  end
end
```

Also delete the dead `# kill` / `# @mutex.unlock` comment lines.

**Verify**: spec — register `on(:done)` counter, call `stop` twice, counter is 1.

### Step 6: Emit callbacks outside the spinner mutex

In `spin`, `success`, `error`: collect what's needed under `@mutex.synchronize`, then call `emit` after releasing. Shape for `success`:

```crystal
def success(stop_message = "")
  return if done?
  @mutex.synchronize { @succeeded = true }
  stop(stop_message)
  emit(:success)
end
```

(`stop` itself doesn't lock `@mutex`, verified above.) For `spin`, move `emit(:spin)` after the `synchronize` block, skipping it when the block early-returned because `@done`.

**Verify**: spec — `on(:spin) { spinner.update(title: "x") }` (re-entrant lock use), call `spin`; completes without deadlock. Full suite green.

### Step 7: Lifecycle specs and cross-validation

Add specs: frame progression over 3 `spin` calls renders 3 different frames into TestIO; `success` renders the ✔ mark; `error` renders ✖; `pause`/`resume` state transitions; `Multi` registers two spinners and `stop` stops both.

**Verify**: `cd shards/spinner && crystal spec --no-color` → all pass, ≥ 12 examples total. `scripts/validate-shards.sh --local --shards spinner,progress --skip-examples` → exit 0.

## Test plan

Covered in steps 1–7; structural pattern: stdlib spec + `TestIO` (modeled on `shards/progress/spec/unit/bar_spec.cr`'s use of TestIO). Avoid wall-clock assertions; assert on state and TestIO contents, using `Fiber.yield`/short sleeps only where the auto_spin fiber must run.

## Done criteria

- [ ] `rg -n "IO::FileDescriptor" shards/spinner/src/term-spinner.cr` → 0 matches
- [ ] `rg -n "@channel" shards/spinner/src` → 0 matches
- [ ] `rg -n "\(1000 // " shards/spinner/src/term-spinner.cr shards/progress/src/progress/spinner_integration.cr` → 2 matches
- [ ] `rg -n "@mutex.synchronize \{ yield \}" shards/spinner/src/spinner/multi.cr` → 1 match
- [ ] Double-`stop` emits `:done` once (spec passes)
- [ ] `cd shards/spinner && crystal spec --no-color` exits 0 with ≥ 12 examples
- [ ] `cd shards/progress && crystal spec --no-color` exits 0
- [ ] `scripts/validate-shards.sh --local --shards spinner,progress --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Anything outside `auto_spin` references `@channel` (join semantics exist somewhere after all).
- Widening `output` to `IO` breaks compilation in `multi.cr` or `progress` (typed call sites) — list them; do not re-narrow.
- The Step 6 re-entrancy spec still deadlocks after moving emits out of the lock — the lock design needs a deeper rework than this plan specifies.
- Progress specs fail for reasons unrelated to the interval formula.

## Maintenance notes

- The interval change alters animation speed for any consumer that passed a non-default integer interval — call this out in the changelog/release notes as the intended Hz semantics (matches README and upstream tty-spinner).
- Plan 017 updates the spinner README; it assumes Hz semantics from this plan.
- Plan 012 optimizes `replace_tokens`; it should land after this so its perf specs can use TestIO.
- Reviewer: scrutinize `Multi#observe` callback chains (`done_handler` → `top_spinner.stop`) against the new emit-outside-lock ordering for missed duplicate-emission paths.
