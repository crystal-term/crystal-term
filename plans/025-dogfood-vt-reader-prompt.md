# Plan 025: Dogfood `term-vt` — reader/prompt integration specs on the Session harness

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: plan 024 must have landed
> (`ls shards/vt/src/vt/captured_tty.cr` exists; validate-shards override
> map covers term-vt). `ls shards/reader/spec/integration` (expect: exists),
> `rg -n "term-vt" shards/reader shards/prompt --glob '!lib'` (expect: 0).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (integration specs against real PTIes are where timing flake
  hides; every wait must be a bounded poll via Session primitives)
- **Depends on**: 022, 023, 024
- **Category**: direction
- **Planned at**: commit `ede43b3` (root), 2026-07-05

## Why this matters

The behaviors that motivated this whole line of work have never been tested
against a real terminal: reader's 50 ms bare-ESC disambiguation (plan 021)
is specced with `IO.pipe` + fiber sleeps; the `tty?` seams from plan 011
(echo simulation, redraw suppression) flip based on exactly the property a
real PTY provides and memory IOs don't; and prompt's specs call `keydown`
et al. directly, so no spec anywhere exercises reader→prompt through actual
terminal input. `Term::VT::Session` closes all three gaps.

## Current state

- `shards/reader/spec/integration/` exists (Spectator suite, 17 files
  total); `escape_handling_spec.cr` fakes ESC timing with pipes.
- Reader branches on `tty?` for echo/redraw (post-plan-011 explicit seam).
- prompt (stdlib spec) simulates keys by direct method calls
  (`spec/spec_helper.cr` spec_* accessors).
- `Term::VT::Session` (vt 0.2.x): spawn/send/press/type/wait_for/wait_idle/
  wait_exit/close; children get a real ctty via the vt-ctty shim.
- Child programs for Session must be real executables: small fixture
  programs compiled from `spec/integration/fixtures/*.cr` (compile once per
  suite run into a temp bin dir — `crystal build` in a `before_all`/setup
  block; a fixture that requires reader/prompt resolves deps via the
  shard's own `lib/`, so build fixtures with `--path lib` semantics from
  the shard root working directory).

## Target design

- **reader** gains `spec/integration/pty_session_spec.cr` (Spectator, match
  existing suite style) + `spec/integration/fixtures/` with 2 tiny
  programs: `echo_keys.cr` (reads keys via Term::Reader, prints
  `key=<name>` lines) and `read_line_demo.cr` (read_line with echo).
  Specs (each PTY-gated like vt's own suite — port/require the
  `with_pty`-style guard):
  1. Arrow keys arrive as single events (send `\e[A` → `key=up`).
  2. Bare ESC resolves as escape after the timeout window (press `:escape`,
     wait_for `key=escape`) — the plan-021 behavior, finally on a real TTY.
  3. ESC immediately followed by `[A` still parses as arrow (no premature
     bare-ESC): `send("\e"); send("[A")` in two writes.
  4. Echo path on a real tty: typed printable chars appear on the Session
     screen exactly once (regression for the plan-011 double-echo class).
- **prompt** gains `spec/integration_pty_spec.cr` (stdlib spec) + one
  fixture: a 3-item `Term::Prompt` select menu. Specs: navigate with
  `press(:down)`, assert the marker moved via `screen.find`; `press(:enter)`,
  assert the fixture prints the chosen value; ESC dismissal if prompt
  supports it (check subscribe(:escape) behavior — if it does not fire,
  record as a finding, do not force it).
- Both shards: `term-vt` as `development_dependencies` github ref
  (override already handled by 024's harness change — verify it applies to
  reader/prompt too; extend the map if 024 scoped it to spinner/progress).
- All waits use `wait_for`/`wait_idle` with ≥5 s deadlines. No sleeps.
- Fixture compile time: keep fixtures minimal; if a fixture build exceeds
  ~30 s in the harness, note it in the report (CI budget concern).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| reader via harness | `scripts/validate-shards.sh --local --shards reader --skip-examples` | exit 0 |
| prompt via harness | `scripts/validate-shards.sh --local --shards prompt --skip-examples` | exit 0 |
| full harness | `scripts/validate-shards.sh --local` | exit 0 |
| format | `crystal tool format --check src spec` in reader, prompt | no diff |

## Steps

1. Verify/extend the validate-shards term-vt override map for reader and
   prompt.
2. reader: fixtures + compile-once setup + the four integration specs.
   Run the reader suite repeatedly (≥5 consecutive runs) — flake gate.
3. prompt: fixture + navigation/selection specs. Same flake gate.
4. Full harness + format. Update `plans/README.md`. Report: any reader
   behavior that only misbehaves on a real TTY (that is signal, not
   noise — file it as a finding, do not patch reader in this plan).

## STOP conditions

- Any integration spec fails intermittently across the 5-run gate after
  reasonable deadline tuning: report the flake with captured snapshots —
  do not paper over with longer settles alone.
- A reader/prompt production bug surfaces (e.g. double echo, dead ESC
  handler): STOP converting, report it as a finding with a minimal repro —
  fixing it belongs in its own plan.
- Fixture programs cannot resolve shard deps cleanly at build time: report
  the mechanism you tried; do not vendor copies of source.

## Git workflow

- **reader**, **prompt**: nested repos — branch `watzon/plan-025-dogfood-vt`
  in each, commit spec-only changes there, leave checked out.
- **root**: harness map tweak (if needed), submodule pointer bumps,
  plans/README.md row — on the root worktree branch. Push nothing.
- Integrator note: submodule branches must be fetched into the primary
  checkout's nested repos before worktree removal.
