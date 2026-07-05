# Plan 023: `term-vt` phase 2 — PTY spawn + black-box session harness

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: plan 022 must have landed:
> `ls shards/vt/src/vt/screen.cr` (expect: exists),
> `cd shards/vt && crystal spec --no-color` (expect: green),
> `ls shards/vt/src/vt/pty.cr` (expect: missing — else someone started this).

## Status

- **Priority**: P2 (direction)
- **Effort**: M-L
- **Risk**: MED-HIGH (POSIX plumbing: controlling-TTY acquisition is the one
  genuinely hard problem; timing primitives must be flake-proof by design)
- **Depends on**: 022
- **Category**: direction
- **Planned at**: commit `1457d14` (root), 2026-07-05

## Why this matters

Plan 022's emulator covers in-process testing (feed bytes → assert on grid).
What it cannot do: test a real program end-to-end — reader's 50 ms bare-ESC
disambiguation against a real TTY (plan 021's whole subject), raw-mode
behavior, `tty?`-dependent code paths (the exact seams plan 011 fought), or
any non-Crystal CLI. That takes a real PTY with the child process properly
session-led and controlling-terminal-attached, plus wait primitives that
poll conditions instead of sleeping. This is the "Playwright" half:
`Session.spawn("crystal", ["run", "examples/select.cr"])`,
`session.wait_for("❯")`, `session.press(:down)`, `session.wait_idle`,
assert on `session.screen`.

Known prior art for the ctty problem in Crystal: `Process` cannot make the
child a session leader with the PTY slave as controlling terminal.
omarluq/termisu (src/termisu/testing/pty.cr) solved it with a compiled
`ctty_exec` shim binary. Evaluate the options in the order given below.

## Current state

- `shards/vt` (post-022): parser + screen, no IO beyond `feed`.
- Crystal stdlib: `IO::FileDescriptor` has `raw!`/`cooked!`/`noecho!`/`tty?`;
  there is **no** openpty/forkpty/winsize API (crystal-lang/crystal#14396 —
  core team says this belongs in a shard). `Process.fork` exists but is
  unsupported in multithreaded runtimes.
- `shards/reader/spec/unit/escape_handling_spec.cr` fakes ESC timing with
  `IO.pipe` + fiber sleeps — the first integration test to rewrite on top of
  this harness (follow-up plan, not this one).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | all pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |
| Sanity: real TTY | `cd shards/vt && crystal run examples/harness_demo.cr` | demo drives `sh` and prints final screen |

## Scope

**In scope**:
- `shards/vt/src/vt/{libc_pty,pty,session,keys}.cr`, matching specs, an
  `examples/harness_demo.cr`, README section, version bump to `0.2.0`.
- CI caveat handling: specs must skip gracefully (with a visible pending
  message) where a PTY cannot be allocated.

**Out of scope**:
- Windows/ConPTY (README caveat: POSIX-only, matching pexpect/rexpect).
- Spec-framework matcher sugar (`should have_screen_text(...)`) — later plan.
- CLI / recorder / agent-facing verbs — later plan.
- Converting sibling shards' specs — later plans.

## Target design

### `Term::VT::LibCPTY` (`libc_pty.cr`)

Minimal `lib` bindings: `openpty(3)` (link `-lutil` on Linux via
`@[Link("util")]` guarded by flags; in libc on macOS/BSD), `Winsize` struct,
`TIOCGWINSZ`/`TIOCSWINSZ` ioctls, `login_tty(3)` if available. Keep the
`lib` block private to the shard.

### `Term::VT::PTY` (`pty.cr`)

`PTY.open(rows, cols) : PTY` → master/slave `IO::FileDescriptor` pair with
initial winsize; `#resize(rows, cols)` (TIOCSWINSZ on master + SIGWINCH to
child pgid if a Session attached it); `#close`.

### Spawning with a controlling TTY — decision ladder

Try in order; stop at the first that passes the ctty acceptance spec
(`spawn `sh -c 'test -t 0 && tty && stty size'`` sees a TTY and the right
size; a spawned `sh` receives SIGINT semantics via `session.send("\x03")`):

1. **`Process.new` + slave as stdio, no setsid**: child gets the slave on
   fd 0/1/2 but is not session leader. Sufficient for `tty?`-based code and
   most output tests; insufficient for job control/signal semantics. Measure
   what actually fails — if the acceptance spec passes on both macOS and
   Linux, document the limitation set and take it (simplest wins).
2. **Shim binary** (termisu's approach): a ~30-line C-or-Crystal `vt-ctty`
   helper — `setsid(); ioctl(fd, TIOCSCTTY); dup2 slave→0,1,2; execvp(argv)`.
   Built on demand into `.term-vt/bin/` via a `postinstall` script in
   shard.yml (and lazily at first Session.spawn if missing). Robust,
   portable, adds a build step — the proven fallback.
3. **`Process.fork` + exec** with the setsid/TIOCSCTTY dance between: only
   if (1) fails the acceptance spec and (2)'s build step is rejected by the
   operator. Must be documented as incompatible with `-Dpreview_mt`.

Record the chosen rung and why in the README and the completion report.

### `Term::VT::Session` (`session.cr`)

```crystal
session = Term::VT::Session.spawn("sh", ["-c", "printf 'ok\\n'"],
                                  rows: 24, cols: 80, env: {...})
session.wait_for("ok")                      # poll screen.contains?, 5s default deadline
session.send("text")                        # raw bytes to master
session.press(:enter); session.press(:up)   # named keys (keys.cr table)
session.type("hello", delay: 10.milliseconds)
session.wait_idle(settle: 50.milliseconds, deadline: 5.seconds)
session.wait_for { |scr| scr.cursor[:row] == 3 }
session.screen                              # Term::VT::Screen (synchronized copy or mutex-guarded access)
session.resize(rows, cols)
status = session.wait_exit(deadline: 10.seconds)
session.close                               # idempotent; SIGHUP→SIGKILL escalation
```

- A reader **fiber** pumps master → parser/screen under a mutex; all public
  screen access synchronizes on it. `wait_*` methods poll on a channel
  signaled after every feed (no fixed sleeps in the implementation; interval
  fallback 5 ms).
- `wait_idle(settle, deadline)` = screen unchanged (compare a change counter,
  not a grid diff) for `settle`, hard-fail at `deadline` — the
  shell-use/terminal-control convergent primitive.
- All waits raise `Term::VT::TimeoutError` carrying a rendered
  `screen.snapshot` in the message — a failing spec must show the screen.
- `keys.cr`: small internal name→sequence table (enter, tab, escape, arrows,
  home/end, page up/down, F1–F12, ctrl_a..ctrl_z, backspace `\x7f`). Do NOT
  depend on term-reader; duplication here is deliberate (harness must not
  share code with the thing it tests).

### DSR hook (needed by real apps, incl. readline)

`Screen` gains an optional `on_report : Proc(Bytes, Nil)?`. When the screen
consumes `CSI 6 n` (DSR cursor position), it calls back with the CPR reply
`\e[<row>;<col>R` (1-based). `Session` wires this to write to the master.
Unset (plan-022 in-process usage) it stays inert. Spec: spawn
`sh -c 'printf "\\033[6n"; read -r x'`-style probe or a tiny Crystal child
that prints the reply it read.

### Spec strategy

Use only universally-present child programs: `sh`, `printf`, `stty`, `cat`,
`env`. Spec files: `pty_spec.cr` (open/resize/winsize), `ctty_spec.cr` (the
acceptance spec above), `session_spec.cr` (spawn/send/wait_for/wait_idle/
exit/close, ANSI-emitting child via `printf '\e[31mred\e[0m'`), `dsr_spec.cr`,
`keys_spec.cr`. Every wait-based spec uses generous deadlines (≥5 s) with
tight settles — deadlines are failure bounds, not expected durations. Guard
the whole suite with a `{% if flag?(:windows) %}` skip and a runtime
"PTY unavailable" pending path so CI containers without a TTY still pass
the rest.

## Steps

1. `libc_pty.cr` + `pty_spec.cr` (open, winsize get/set, close). Verify on
   macOS (your machine) — note in report that Linux verification happens in
   root CI.
2. Ctty decision ladder: implement rung 1, run the acceptance spec; escalate
   only on failure. `ctty_spec.cr` encodes the acceptance criteria.
3. `keys.cr` + spec.
4. `session.cr`: spawn/pump/send/screen access; then waits; then
   close/exit-status; spec each increment.
5. DSR hook in screen + session wiring + spec.
6. `examples/harness_demo.cr` (drive `sh`: run `ls`, wait, print snapshot).
7. README section ("Black-box testing") + supported-keys table + POSIX-only
   caveat + chosen ctty rung. Bump `version:` and `VERSION` to `0.2.0`.
8. Full verification table; update `plans/README.md` row.

## STOP conditions

- No rung of the ctty ladder passes its acceptance spec on macOS: report
  findings (which check failed per rung) — do not ship a harness whose
  `tty?` story is broken, and do not silently weaken the acceptance spec.
- Any spec needs a bare `sleep` (not a bounded poll) to pass: the design has
  a hole — report it.
- Fiber/mutex deadlock or a zombie-process leak you cannot resolve within
  the session lifecycle design above: report with a minimal repro.

## Git workflow

Root repo only (shards/vt is still a plain directory). Branch from `main`,
conventional commits (`feat(vt): pty layer`, `feat(vt): session harness`).
Nothing gets pushed without operator instruction.
