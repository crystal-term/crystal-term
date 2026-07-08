# Plan 033 — ConPTY echo prototype

**Status: written against documented Win32 APIs; not compile-verified on
Windows** (no Windows environment in the spike workstation). Mark
results in `plans/reports/033-conpty-findings.md` when a runner is
available.

## Goal

Smallest Crystal program that:

1. Creates a ConPTY via `CreatePseudoConsole`
2. Spawns `cmd /c echo ok` with `CreateProcessW` +
   `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`
3. Reads the output pipe into `Term::VT::Screen`
4. Prints `screen.snapshot`

This is **not** a `Session` port. No resize, no kill plumbing, no wait
helpers — those belong in a follow-up implementation plan.

## Layout

| Path | Role |
| --- | --- |
| `src/conpty_echo.cr` | Prototype main + Win32 bindings |
| `shard.yml` | Path dep on monorepo `shards/vt` |

## Run (Windows only)

```powershell
cd plans/prototypes/033-conpty
shards install
# postinstall for term-vt is a no-op on win32 (skips vt-ctty C shim).
shards build --no-debug
.\bin\conpty_echo.exe
```

Expected: a snapshot containing `ok` (cmd may also emit a prompt / CRLF
noise — the spike only asserts that *some* ConPTY output reaches the
screen model).

On non-Windows hosts, `crystal build` fails with a clear `{% raise %}`
message (by design).

## API surface for a real Session port

See the findings report. Summary: spawn (`CreatePseudoConsole` +
`CreateProcessW`/`STARTUPINFOEX`), resize (`ResizePseudoConsole`), close
(`ClosePseudoConsole` terminates the tree), exit via
`WaitForSingleObject`/`GetExitCodeProcess`, no POSIX signals.
