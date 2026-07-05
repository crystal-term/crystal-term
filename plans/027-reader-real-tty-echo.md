# Plan 027: reader echoes and repaints correctly on real TTYs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status rows for 027 AND 025
> in `plans/README.md` when done (see step 8).
>
> **Drift check (run first)**: plan 025 landed:
> `ls shards/reader/spec/integration/pty_session_spec.cr` (exists) and it
> contains exactly one pending/skip example about the real-tty echo path
> (`rg -n "pending|skip" shards/reader/spec/integration/pty_session_spec.cr`).
> The bug still reproduces: build
> `shards/reader/spec/integration/fixtures/read_line_demo.cr` (from the
> reader shard root), spawn it with `Term::VT::Session`, `wait_for("value>")`,
> `type("xyz")`, `wait_idle` → `screen.text` is `""` (blank, prompt erased).

## Status

- **Priority**: P1 (user-visible production bug in the family's highest
  fan-in interactive shard)
- **Effort**: M
- **Risk**: MED-HIGH (touches read_line's keypress loop; plans 002/003/011
  all trace shipped bugs to this area — the PTY suite is the safety net now)
- **Depends on**: 025
- **Category**: bug
- **Planned at**: commit `e26c58d` (root), 2026-07-05

## Why this matters

On a real terminal, `Term::Reader#read_line(prompt: "value> ")` erases what
the user is typing: the prompt paints, and each keypress **blanks the line**.
Input still works (Enter returns the typed value), so the bug is purely
visual — which is exactly why a decade of `IO::Memory` specs never saw it
and plan 025's first real-PTY spec did.

Byte-level evidence (captured 2026-07-05 via `Term::VT::PTY` raw dump —
reproduce with the drift check):

- Prompt phase: child writes `value> ` — correct.
- Per typed character, child writes `\e[2K` (erase line) + `\e[1G` (cursor
  to column 1) — **and nothing else**. No echoed character, no repaint of
  prompt + buffer. Three keystrokes → three erase-and-home pairs → blank.

Root cause shape (verify precisely in code — this is the map, not the
territory): two post-plan-011 decisions interact.

1. The echo seam (`simulate_echo?` ≈ `!input_tty?` in auto mode) assumes a
   real terminal echoes typed characters itself. But `read_line` puts the
   terminal in **raw mode**, which disables termios echo. So on a real TTY
   nobody echoes: reader skips simulation, the terminal is muted.
2. The keypress redraw path emits clear-line + column-1 — which is only
   correct when followed by repainting `prompt + current buffer`. On the
   real-tty path the repaint never happens (find the guard — likely the
   same or inverse tty/echo condition suppressing it).

## Target behavior (match Ruby tty-reader's model)

When reader itself has the terminal in raw mode, **reader owns echo**. In
`read_line` with `echo: true`: on each keypress, clear the line, return to
column 1, print `prompt + line buffer`, leaving the cursor at the correct
position (this repaint also serves backspace and mid-line edits — one path,
no special cases). With `echo: false` (passwords): the prompt stays painted;
typed characters change the buffer but never the screen. The IO::Memory
simulation path (non-tty inputs) must keep its current observable behavior —
the 216-example suite and the multiline echo regression spec define it.

## Scope

**In scope**: `shards/reader/src/term-reader.cr` (and mode/console helpers
if the echo decision moves), the pending PTY spec (activate it), new PTY
specs below, `plans/README.md` rows for 027 and 025.

**Out of scope**: prompt's missing `:escape` subscription (plan 028), any
reader API surface changes beyond the internal echo/repaint decision (STOP
if needed), multiline `read_multiline` if it turns out to use a distinct
code path (report; do not fork this plan's scope silently).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Reader suite | `scripts/validate-shards.sh --local --shards reader --skip-examples` | exit 0 |
| Flake gate | the same command, 5 consecutive runs | 5× exit 0 |
| Format | `cd shards/reader && crystal tool format --check src spec` | no diff |
| Full harness | `scripts/validate-shards.sh --local` | exit 0 |

## Steps

1. Root-cause precisely: locate the echo decision and the clear/repaint
   emission in `read_line`'s keypress loop; write down (for the report)
   which guard suppresses the repaint on real TTYs.
2. Activate the pending echo spec in `pty_session_spec.cr`. Confirm what it
   asserts — after typing `xyz` at `value> `, the visible screen shows
   `value> xyz` with the cursor after the `x`. Fix the expectation only if
   it encodes something weaker; do not weaken it. Run it: it must FAIL
   against current code (red first).
3. Implement the fix per Target behavior. Prefer making the echo decision
   mode-aware (raw ⇒ reader echoes) over adding another constructor flag.
4. Add two PTY specs: (a) `echo: false` — prompt remains visible, typed
   characters never appear, Enter still returns the value; (b) backspace —
   type `xyz`, press backspace, screen shows `value> xy`.
5. Full reader suite: the 216 existing examples (IO::Memory paths,
   multiline regression) must pass unchanged. If any fails, understand it
   before touching the expectation — see STOP conditions.
6. 5-run flake gate on the reader suite.
7. Full harness + format.
8. `plans/README.md`: 027 → DONE; 025 → DONE with note
   "(echo spec activated by 027)".

## STOP conditions

- The fix requires changing an existing spec's expectation on the
  IO::Memory path: that is a behavior change for library consumers —
  report it with the before/after and wait; do not commit it silently.
- The repaint approach flickers or misplaces the cursor for wide
  characters at the prompt boundary: report with a snapshot; wide-char
  cursor math may need `Term::VT::Width` — do not hand-roll a second
  width table inside reader.
- You find yourself re-introducing any class-name or IO-type sniffing
  (the plan-011 antipattern): STOP.

## Git workflow

- **reader**: branch `watzon/plan-027-reader-tty-echo`, conventional
  commits (`fix(reader): ...`), leave checked out.
- **root**: submodule pointer bump + plans/README.md rows on the root
  worktree branch. Push nothing.
- Release note (record in the report; operator handles publication):
  behavior change on real TTYs — read_line input is now visible while
  typing (bugfix; previously blanked).
