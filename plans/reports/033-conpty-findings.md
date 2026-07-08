# Plan 033 findings — `term-vt` on Windows (core CI + ConPTY)

Spike executed 2026-07-08 against monorepo `main` and `shards/vt` at
post-032 source (`v0.5.0` lineage). Deliverables are packaging + CI +
prototype + this report — **not** a merged Windows `Session`.

## Executive summary

| Question | Answer |
| --- | --- |
| Does the in-process core (Parser/Screen/…) load without PTY? | **Yes** after the require-graph split. |
| Do POSIX specs still pass? | **Yes** — 195 examples, 0 failures locally. |
| Windows core CI lane green? | **Not run** — operator-gated (no push). |
| Is a ConPTY `Session` port feasible? | **Yes**, with hand-rolled Win32 spawn (Crystal `Process` cannot attach a ConPTY). |
| Go / no-go for a follow-up? | **Conditional go** — land core packaging now; implement Session only if Windows CI core lane is green and product demand exists. Effort **M–L**. |

## Local baseline (POSIX)

| Check | Result |
| --- | --- |
| `cd shards/vt && crystal spec --no-color` | PASS (195 examples) |
| `crystal tool format --check src spec` | PASS |
| `shards build --no-debug` (CLI) | PASS |
| `scripts/validate-shards.sh --local --shards vt --skip-examples` | PASS |
| Core compile approximation: `crystal build --no-codegen spec/parser_spec.cr` | PASS |

Toolchain: Crystal 1.20.3, Shards 0.20.0, macOS aarch64.

## Require-graph decision

**Chosen: guards inside `src/term-vt.cr` (not a separate `term-vt/core` entry point).**

Rationale:

1. **Single public require.** `require "term-vt"` remains the only documented
   entry point. On Windows it loads the portable core; on POSIX it also
   loads `LibCPTY` / `PTY` / `Session`. Callers do not need dual requires.
2. **No behavior change on POSIX.** Same types, same CLI build, same specs.
3. **CLI fails loud on win32.** `src/cli.cr` uses `{% raise %}` when
   `flag?(:unix)` is false so `shards build` cannot produce a half-working
   binary that would blow up at runtime looking for `Session`.
4. **`term-vt/core` alternative rejected** for this spike: a second entry
   would need README/docs dual-path forever, and Windows users would still
   hit the full require by default via `shard.yml` conventions.

`CapturedTTY` stays in the **core** set: it is pure Crystal (`IO` mock with
`tty?`), has no openpty/signal dependency, and is useful for non-PTY tests.
The plan listed it next to PTY/Session as harness-adjacent; the code graph
does not require gating it.

```
term-vt.cr
├── core (all platforms): version, style, cell, width, keys, mouse,
│   performer, parser, tab_stops, screen(+), snapshot, captured_tty
└── {% if flag?(:unix) %}: libc_pty, pty, session
```

`spec/spec_helper.cr` gates `Term::VT::Spec.with_pty` the same way so the
helper type-references `PTYUnavailable` only when that type exists.

## CI workflow

Added `shards/vt/.github/workflows/crystal.yml`:

| Job | OS | What runs |
| --- | --- | --- |
| `posix` | ubuntu, macos | `shards install`, format check, full `crystal spec`, `shards build` |
| `windows-core` | windows | `shards install`, core-only `crystal spec` file list |

Core-only paths (no Session/PTY/CLI):

```
spec/parser_spec.cr
spec/width_spec.cr
spec/keys_spec.cr
spec/mouse_encoding_spec.cr
spec/snapshot_spec.cr
spec/query_spec.cr
spec/fixture_spec.cr
spec/fuzz_spec.cr
spec/captured_tty_spec.cr
spec/screen/
```

Excluded on purpose: `pty_spec`, `session_spec`, `session_mouse_spec`,
`ctty_spec`, `cli_spec`, `tape_spec`, `dsr_spec` (mixed Screen + Session
integration).

### Operator STOP — Actions not run

Per plan STOP condition and repo-wide no-push rule, **no branch was pushed**
to `crystal-term/vt`. Lane results below are therefore skeletons.

| Lane | Status | First failure | Notes |
| --- | --- | --- | --- |
| ubuntu (full) | not-run (operator-blocked) | — | Expected green: matches local full suite. |
| macos (full) | not-run (operator-blocked) | — | Expected green: matches local full suite. |
| windows (core) | not-run (operator-blocked) | — | **Key data point for this spike.** Hypothesis: core pure-Crystal specs pass; first risk areas are Unicode width edge cases or path separators in fixture `File.read` (relative `spec/fixtures/…` should still work). |

To unstick: push the vt submodule branch (or open a draft PR) and paste
Actions URLs into this table.

## ConPTY prototype

Location: `plans/prototypes/033-conpty/`

| Item | Detail |
| --- | --- |
| Program | `src/conpty_echo.cr` — `cmd.exe /c echo ok` under ConPTY → `Term::VT::Screen` → print snapshot |
| Deps | path dependency on monorepo `shards/vt` |
| Host verification | **UNTESTED** — spike machine is macOS; source is `{% raise %}`-gated to win32 |
| References | [MS Create Pseudoconsole](https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session), microsoft/terminal `samples/ConPTY/EchoCon` |

Prototype intentionally omits resize/kill/wait helpers (plan STOP).

### Codex review fixes (post-spike)

Codex review of the working tree flagged two P2s, both addressed:

1. **Pump deadlock** — sequential `ReadFile` then `WaitForSingleObject` can
   hang because ConPTY keeps the output pipe open until `ClosePseudoConsole`.
   Prototype now waits for the child, closes the pseudoconsole (EOF on the
   pipe), then drains. (A real Session needs concurrent overlapped I/O;
   fibers alone do not help when `ReadFile` blocks the OS thread.)
2. **postinstall flag** — `scripts/build_ctty_exec.cr` used only
   `flag?(:windows)`; Crystal's Windows target is `flag?(:win32)`. Guard is
   now `flag?(:win32) || flag?(:windows)` so `shards install` of path-dep
   `term-vt` is a no-op on real Windows toolchains.

## Win32 API surface for a real `Session` port

Crystal’s `Process` cannot attach `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`. A
Windows `Session` must hand-roll spawn (or extend Crystal — out of scope).

| Concern | POSIX today | Windows ConPTY equivalent |
| --- | --- | --- |
| Allocate terminal | `openpty` + winsize ioctl | `CreatePipe` ×2 + `CreatePseudoConsole(COORD, hInput, hOutput, flags, &hPC)` |
| Spawn child on TTY | `vt-ctty` shim (`setsid` + `TIOCSCTTY` + `execvp`) via `Process.new` | `InitializeProcThreadAttributeList` + `UpdateProcThreadAttribute(…, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, hPC, …)` + `CreateProcessW(…, EXTENDED_STARTUPINFO_PRESENT, STARTUPINFOEXW*)` |
| Write input | `pty.master.write` | `WriteFile` on ConPTY input write end |
| Read output | reader fiber on master fd | `ReadFile` on ConPTY output read end (prefer dedicated fiber/thread; MS warns of single-thread deadlock) |
| Resize | `TIOCSWINSZ` + `SIGWINCH` to child pgrp | `ResizePseudoConsole(hPC, COORD)` — **no signals** |
| Child exit | `Process#wait` / status | `WaitForSingleObject(hProcess)` + `GetExitCodeProcess` |
| Kill / close | `SIGHUP`/`SIGKILL` to process group, close master | `ClosePseudoConsole(hPC)` **terminates the attached process tree**; optional `TerminateProcess` |
| Signals | `Process.signal`, Ctrl-C via TTY | No POSIX signals; generate Ctrl-C as input bytes (`\x03`) or use job objects / `GenerateConsoleCtrlEvent` only when appropriate |
| ctty shim | `src/vt/ctty_exec.c` + postinstall `cc` | **N/A** — ConPTY attachment is entirely CreateProcess attributes |
| Encoding | UTF-8 bytes on PTY | ConPTY speaks VT sequences as UTF-8 on the pipes (same feed path into `Screen`) |

### Structural mapping onto existing types

```
PTY          ≈ HPCON + input write HANDLE + output read HANDLE
Session      ≈ PTY handles + PROCESS_INFORMATION + Screen + reader fiber + mutex
CTTYShim     ≈ prepare STARTUPINFOEX + CreateProcessW (no C helper)
TimeoutError ≈ unchanged (pure Crystal)
```

## Risks / first-failure hypotheses (Windows core lane)

If the windows-core job fails, dig in this order (timebox; first two failures
are the deliverable if non-mechanical):

1. **Spec file selection / require graph** — harness symbol referenced by
   accident → compile error naming `Session`/`PTY`. Fix: trim file list or
   guard the reference.
2. **Unicode / width** — `Width.of` or combining-mark specs disagree with
   Windows libc Unicode tables. Hypothesis only; core uses Crystal `Char`
   properties, not `wcwidth(3)`.
3. **Fixture paths** — unlikely on Actions with `crystal spec` cwd = repo root.
4. **Crystal Windows stdlib quirks** — fiber/channel specs are not in core set.

Harness port risks (follow-up, not this spike): pipe deadlock if reader and
ClosePseudoConsole share one thread; cmd.exe startup banner noise vs bare
`echo`; inheriting parent console when handles are wrong; Windows Server
SKU / older builds without ConPTY (needs Windows 10 1809+).

## Go / no-go recommendation

| Track | Recommendation | Effort |
| --- | --- | --- |
| **Core packaging + CI** (this spike) | **GO — already implemented.** Merge when ready; no version bump required (plan non-goal). | Done (S remaining: push + record Actions) |
| **Windows core lane green on Actions** | **GO once operator pushes.** If green, reword README Unsupported bullet per plan text. If red with only mechanical fixes, fix in-tree; if deep Unicode/encoding issues, stop after two failures. | S–M |
| **Full ConPTY `Session` + CLI** | **CONDITIONAL GO.** Worth a follow-up plan **if** (a) core lane is green and (b) someone needs black-box Windows CLI tests. Otherwise leave harness POSIX-only indefinitely — the core already delivers half the shard’s value on Windows. | **M–L** (estimate 2–4 focused days): Win32 spawn module, `PTY`/`Session` backend split or `flag?(:win32)` implementations, drop ctty on Windows, Windows harness specs with `cmd`/`powershell`, CI job for harness smoke, README. |

Suggested follow-up plan title: **034 — vt ConPTY Session (Windows harness)**.

## README

Unsupported bullet **left unchanged** (`Windows/ConPTY.`) because the Windows
core-spec lane has not been observed green. When it is, reword to:

> Windows/ConPTY (core compiles on Windows; PTY harness POSIX-only — see plan 033 findings)

## Files touched

### `shards/vt` (submodule)

- `src/term-vt.cr` — explicit core requires + `{% if flag?(:unix) %}` harness
- `src/cli.cr` — win32 `{% raise %}`
- `spec/spec_helper.cr` — gate `with_pty`
- `.github/workflows/crystal.yml` — new CI

### monorepo root

- `plans/prototypes/033-conpty/**` — prototype
- `plans/reports/033-conpty-findings.md` — this report
- `plans/README.md` — status row

## Next operator actions

1. Push vt branch / draft PR → record Actions results in the CI table above.
2. If windows-core is green, reword the README bullet and optionally tag a
   note in the next feature release notes (no version bump from this spike).
3. If product demand for Windows black-box tests exists, open plan 034.
