# Plan 006: `read_line` records history on submit, key branches are correct, and console reads don't swallow state

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare every excerpt below against live code in
> `shards/reader/src/`. Plans 002/005 touch neighboring code — if they landed,
> line numbers shift but the excerpted logic should still be present.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MED
- **Depends on**: 002 (raw mode), recommended after 005
- **Category**: bug
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

Four independent bugs in reader's line-editing path, all user-visible:

1. History records every **partial keystroke** ("h", "hi", "hi!") and never the submitted line — the Enter branch `break`s before the `add_to_history` call is reached with the final text. Up-arrow offers garbage prefixes.
2. Two broken conditions in the key `case`: `when "delete", DELETE == code` compares a `Bool` against a `String` (dead branch — the Delete key falls through to text insertion), and `a || b && echo` precedence makes the backspace erase sequence print even when `echo` is false.
3. `Console#get_char` sets `@input.blocking = !nonblock` and never restores it, so one non-blocking read leaves stdin non-blocking for all subsequent reads; and its bare `rescue` turns every error (including real bugs) into "no key", which upstream loops interpret as end-of-input.
4. History navigation is off-by-one at the boundaries: `History#previous?` tests `@index < 0`, which can never be true, and `history_previous` returns the entry *before* moving the pointer, so cycling with up-arrow repeats and shifts entries.

## Current state

All files in `shards/reader/src/`.

- `term-reader.cr:180-285` — the `read_line` loop. The history add sits inside the loop, after the Enter `break`:

```266:285:shards/reader/src/term-reader.cr
        if {CARRIAGE_RETURN, NEWLINE}.includes?(code)
          # ... echo handling ...
          break
        end

        if track_history? && echo
          add_to_history(line.text.strip)
        end
      end

      line.text.rstrip('\n').rstrip('\r')
```

- `term-reader.cr:210` — dead delete branch inside `case console.keys[char]?.to_s`:

```210:211:shards/reader/src/term-reader.cr
          when "delete", DELETE == code
            line.delete
```

- `term-reader.cr:235` — precedence bug (`&&` binds tighter than `||`):

```235:241:shards/reader/src/term-reader.cr
        if console.keys[char]? == "backspace" || BACKSPACE == code && echo
          if raw
            output.print("\e[1X") unless line.start?
          else
            output.print(" " + (line.start? ? "" : "\b"))
          end
        end
```

- `reader/console.cr:24-38` — `get_char` (post-plan-002 the mode calls are fixed; the blocking/rescue lines are unchanged):

```crystal
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

- `reader/history.cr` — `push` sets `@index = @history.size - 1`; navigation:

```56:84:shards/reader/src/reader/history.cr
      def next : Nil
        return if size.zero?
        if @index == size - 1
          @index = 0 if @cycle
        else
          @index += 1
        end
      end

      def next? : Bool
        size > 0 && !(@index == size - 1 && !@cycle)
      end
      ...
      def previous : Nil
        return if size.zero?
        if @index.zero?
          @index = size - 1 if @cycle
        else
          @index -= 1
        end
      end

      def previous? : Bool
        size > 0 && !(@index < 0 && !cycle)
      end
```

- `term-reader.cr:364-381` — reader-side navigation helpers; `history_previous` reads then moves:

```373:381:shards/reader/src/term-reader.cr
    def history_previous? : Bool
      @history.previous?
    end

    def history_previous : String?
      line = @history.get
      @history.previous
      line
    end
```

- Reader has 17 spec files (Spectator) including history/read_line coverage that may encode current buggy behavior. Read `spec/unit/` files touching history and read_line before changing them.

## Target semantics for history (item 4)

Adopt tty-reader's convention: after `push`, the index points **one past the newest entry** (`@index = @history.size`). Up-arrow (`previous`): allowed while `@index > 0` (or cycle); decrement first, then `get`. Down-arrow (`next`): allowed while `@index < size - 1` (or cycle); increment first, then `get`; when moving past the newest entry, the caller shows an empty line. Concretely:

- `History#push`: `@index = @history.size`
- `History#previous?`: `size > 0 && (@index > 0 || @cycle)`
- `History#previous`: `return if size.zero?`; if `@index.zero?` then (`@index = size - 1` if cycle, else return) else `@index -= 1`
- `History#next?`: `size > 0 && (@index < size - 1 || @cycle)`
- `History#next`: increment with the mirrored logic
- `History#get`: `return nil if size.zero? || @index >= size`; else `self[@index]`
- `Reader#history_previous`: `@history.previous; @history.get` (move-then-read); `Reader#history_next`: unchanged shape but verify against the new semantics.

Expected observable behavior (write this as the spec): push "a", "b", "c" → up yields "c", up yields "b", up yields "a", up yields "a" (no cycle; `previous?` false); then down yields "b", down yields "c".

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd shards/reader && shards install` | exit 0 |
| Specs | `cd shards/reader && crystal spec --no-color` | all pass |
| One file | `cd shards/reader && crystal spec spec/unit/history_spec.cr --no-color` | passes |
| Cross-shard | `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/reader/src/term-reader.cr` (read_line loop, history helpers)
- `shards/reader/src/reader/history.cr`
- `shards/reader/src/reader/console.cr` (blocking restore + rescue narrowing only)
- `shards/reader/spec/unit/*` for history/read_line/console

**Out of scope**:
- `mode.cr` (plan 002), the subscribe macro/handlers (005), class-name test sniffing at `term-reader.cr:143,194` (plan 011 — leave those conditionals alone even though you edit around them), `line.cr`, `keys.cr`.

## Git workflow

- Inside `shards/reader` submodule, branch `advisor/006-read-line-history`. Separate commits per item (1–4). Do NOT push.

## Steps

### Step 1: History on submit only

In `read_line`, delete the in-loop `if track_history? && echo / add_to_history` block and add the call inside the Enter branch, before `break`:

```crystal
if {CARRIAGE_RETURN, NEWLINE}.includes?(code)
  add_to_history(line.text.strip) if track_history?
  # ... existing echo handling ...
  break
end
```

(Drop the `echo` guard: whether the line was echoed has no bearing on whether it belongs in history. If an existing spec asserts otherwise, update it and note it in the commit.)

**Verify**: `crystal spec --no-color` in `shards/reader` → failures only in specs that encoded per-keystroke history, which you then update to assert: after typing "hi\n", history contains exactly ["hi"].

### Step 2: Fix the two broken conditions

- Replace `when "delete", DELETE == code` with a plain `when "delete"` branch, and handle the raw escape-code case *before* the case statement if needed. The intent of `DELETE == code` (27 is ESC's ord — the constant is misnamed) appears to be matching a bare escape byte; since bare-ESC handling is explicitly deferred to plan 021, just remove the dead comparison: `when "delete"`.
- Parenthesize the echo condition: `if (console.keys[char]? == "backspace" || BACKSPACE == code) && echo`.

**Verify**: `crystal spec --no-color` → all pass; `rg -n "DELETE == code" src/` → 0 matches.

### Step 3: Console blocking restore and narrowed rescue

In `console.cr#get_char`, save/restore blocking and rescue only IO errors:

```crystal
def get_char(raw : Bool, echo : Bool, nonblock : Bool) : Char?
  char = nil
  previous_blocking = @input.blocking
  begin
    mode.cooked(!raw) do
      mode.raw(raw) do
        mode.echo(echo) do
          @input.blocking = !nonblock
          char = @input.read_char
        end
      end
    end
  ensure
    @input.blocking = previous_blocking
  end
  char
rescue IO::Error
  nil
end
```

**Verify**: `crystal spec --no-color` → all pass.

### Step 4: History navigation semantics

Apply the "Target semantics" block to `history.cr` and `term-reader.cr` helpers. Update/write `spec/unit/history_spec.cr` (or the existing history spec file) with the push-a-b-c walk documented above, plus the cycle-enabled variant.

**Verify**: `crystal spec spec/unit/history_spec.cr --no-color` (adjust filename to the actual one) → passes; full suite passes.

### Step 5: Cross-shard validation

**Verify**: `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` → exit 0.

## Test plan

- New/updated specs: history-on-submit (Step 1), delete/backspace-echo conditions via `read_line` with an `IO::Memory` input (Step 2), the a/b/c navigation walk with and without cycle (Step 4).
- `get_char` blocking restore is only observable on a real fd; assert at least that the method still returns typed chars in specs, and note the manual gate in the commit.

## Done criteria

- [ ] `rg -n "add_to_history" shards/reader/src/term-reader.cr` → exactly 1 call site inside the Enter branch (plus the `def add_to_history`)
- [ ] `rg -n "DELETE == code|BACKSPACE == code && echo" shards/reader/src` → 0 matches
- [ ] `rg -n "rescue IO::Error" shards/reader/src/reader/console.cr` → 1 match
- [ ] `cd shards/reader && crystal spec --no-color` exits 0
- [ ] History navigation spec with the a/b/c walk exists and passes
- [ ] `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts don't match (drift).
- Prompt specs fail after the history changes — prompt may depend on the old navigation semantics somewhere; report the failing specs.
- Narrowing the console rescue surfaces a non-IO exception during reader specs — that's a real hidden bug; report it with backtrace instead of re-widening the rescue.

## Maintenance notes

- Plan 021 (bare-ESC handling spike) builds on Step 2's cleaned-up case statement.
- The misnamed `DELETE = 27` constant (it's ESC) is left in place; renaming it is cosmetic and touches key handling better done in plan 021.
- Reviewer: check that `history_next` at the newest-entry boundary yields empty-line behavior in `read_line`'s "down" branch (`line.replace(history_next? ? ... : "")`) — that branch's semantics interact with the new index convention.
