# Plan 026: `term-vt` phase 3 — CLI (`run` / `snapshot` / `script` verbs)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: vt at 0.2.x with Session present
> (`ls shards/vt/src/vt/session.cr`), no CLI yet
> (`rg -n "targets:" shards/vt/shard.yml` → 0 matches,
> `ls shards/vt/src/cli` → missing).

## Status

- **Priority**: P3 (direction)
- **Effort**: M-L
- **Risk**: MED (new public surface: verb names, tape DSL, and exit codes
  are compatibility contracts once published)
- **Depends on**: 023 (024/025 recommended first — they harden the library
  API the CLI freezes)
- **Category**: direction
- **Planned at**: commit `ede43b3` (root), 2026-07-05

## Why this matters

The library serves Crystal projects; a CLI serves **everyone else** —
shell scripts, CI pipelines for non-Crystal tools, and (the direction the
whole 2025–2026 field moved: microsoft/shell-use, phantom) AI agents that
need to drive TUIs. Snapshot-testing any CLI from a shell one-liner, with
no Crystal code written, is the adoption wedge for the shard.

**Deliberately out of scope**: a long-lived daemon / `open`+`send` session
verbs / MCP server — that is phase 4, needs IPC design, and must not be
smuggled in here. This plan ships single-shot verbs only.

## Target design

Binary `term-vt` (shard.yml `targets:`, entry `src/cli.cr`, code under
`src/cli/`). Global flags: `--rows N` (24), `--cols N` (80),
`--timeout SPAN` (10s, accepts `5s`/`500ms`), `--styled`, `--quiet`.
Version bump to `0.3.0`.

Exit codes (contract, document in README): `0` success/assertions held,
`1` assertion or expectation failed (incl. wait timeout), `2` usage error /
spawn failure. On code 1, print the final screen snapshot to stderr.

### Verbs

- **`term-vt run [flags] [--expect TEXT ...] [--expect-exit N] -- CMD ARGS…`**
  Spawn under a PTY, pump until exit or `--timeout`. Each `--expect` is
  checked against the final screen; `--expect-exit` against the status.
  With no expectations: exit 0 iff child exited 0 within timeout.
- **`term-vt snapshot [flags] [--golden FILE] [--update] -- CMD ARGS…`**
  Run to exit (or `--idle SETTLE` for long-running apps: capture once the
  screen settles, then close). Print the snapshot (plain, or run-length
  styled with `--styled`) to stdout. `--golden FILE`: compare instead of
  print — mismatch prints a unified diff and exits 1; `--update` rewrites
  the golden file and exits 0. Golden-file snapshot testing for any CLI.
- **`term-vt script FILE.tape`** — run a tape line-by-line, fail-loud.

### Tape DSL (line-based; `#` comments; strings double-quoted with the
same escapes Crystal string literals support)

```
rows 24                  cols 80
run vim --clean -u NONE  # exactly one run per tape, must be first action
wait "~" 5s              # wait_for text with deadline
idle 50ms 5s             # wait_idle settle deadline
type "iHello"            press escape       press enter
expect "Hello"           # screen.contains? now — no wait — else exit 1
expect-not "Error"
snapshot out.txt         # write snapshot; bare `snapshot` prints to stdout
resize 40 120
send-exit                # close session; assert child exited
expect-exit 0
```

Unknown directive, malformed argument, or action-before-`run` → exit 2
naming the line number. Every `wait`/`idle` requires an explicit deadline
(no silent defaults inside tapes — tapes are CI artifacts).

### Implementation shape

`src/cli/{main,options,runner,tape}.cr` — a `Tape` parser producing an
array of typed directives, executed against one `Session`; `run` and
`snapshot` verbs are thin wrappers over the same runner. No new deps
(hand-rolled option parsing is fine at this scale, stdlib `OptionParser`
is fine too — pick one, stay consistent).

### Specs

- Tape parser unit specs (pure, no PTY): every directive, every rejection.
- End-to-end specs (PTY-gated like the session suite): build the binary
  once into a temp dir, then drive it with `Process.run` — `run` happy
  path + failed expectation (assert exit 1 and snapshot on stderr),
  `snapshot --golden` match/mismatch/`--update` round-trip, one tape
  exercising type/press/wait/expect against `sh`.
- `examples/` gains one runnable tape + README section with the verb
  table, DSL reference, and exit-code contract.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | pass |
| Build binary | `cd shards/vt && shards build --no-color` | `bin/term-vt` exists |
| Smoke | `cd shards/vt && ./bin/term-vt snapshot -- sh -c 'printf hi'` | prints `hi` grid, exit 0 |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |

## Steps

1. Tape parser + unit specs (no PTY dependency; do this first — it locks
   the DSL).
2. Runner over Session; `script` verb.
3. `run` and `snapshot` verbs as wrappers; exit-code contract; stderr
   snapshot on failure.
4. shard.yml target + build + smoke test.
5. E2E specs (PTY-gated, compiled-binary driven).
6. Example tape, README (verbs, DSL, exit codes), version 0.3.0.
7. Full verification table; update `plans/README.md`.

## STOP conditions

- The DSL grows a conditional/loop/variable during implementation: STOP —
  tapes are assertions, not programs; report the use case instead.
- You need daemon-ish state (backgrounded session reused across verb
  invocations): that is phase 4 — report, do not build.
- E2E specs flake across 5 consecutive runs: report with snapshots.

## Git workflow

Root repo only (`shards/vt` + `plans/README.md`). Branch from `main`,
conventional commits, push nothing.
