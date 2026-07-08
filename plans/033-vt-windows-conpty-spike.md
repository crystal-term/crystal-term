# Plan 033: SPIKE — `term-vt` on Windows (core CI + ConPTY prototype)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done. This is a SPIKE: the deliverable is a
> report and a prototype, not merged Windows support.
>
> **Drift check (run first)**: vt submodule has no CI workflow yet
> (`ls shards/vt/.github/workflows` → missing), no Windows guards in
> source (`rg -n "flag\?\(:win32\)|flag\?\(:unix\)" shards/vt/src` → 0
> matches). Other family shards already ship a Windows matrix job template
> (from the completed Windows CI staging work) — mirror that shape for vt.

## Status

- **Priority**: P3 (operator-gated: CI runs require pushing branches to
  `crystal-term/vt`, and Windows validation needs a Windows environment)
- **Effort**: M-L
- **Risk**: LOW to the codebase (guards + prototype only), HIGH
  uncertainty on outcome — that is why it is a spike
- **Depends on**: — (independent; benefits from running last so guards
  see the post-029/030/031 source)
- **Category**: vt hardening (README "Unsupported" burn-down) + spike
- **Planned at**: root commit `d9f941c`, vt submodule `v0.3.0` (`5c72959`),
  2026-07-06

## Why this matters

"Windows/ConPTY" is the last vt README Unsupported bullet, and it splits
into two very different-sized problems:

- **The core is probably already portable.** `Parser`, `Screen`, `Width`,
  `Style`, `Cell`, `Keys`, and the snapshot code are pure Crystal with no
  libc PTY dependency. If they compile and pass specs on Windows, every
  Crystal project on Windows can already use the in-process emulator —
  half the shard's value — today. What blocks even that is packaging:
  `src/term-vt.cr` unconditionally requires the POSIX PTY stack, and the
  vt repo has **no CI at all** yet (it predates its extraction to a
  submodule; the plan-019 Windows CI staging covered the other eight
  shards only).
- **The harness is a real port.** `PTY`/`Session` need ConPTY
  (`CreatePseudoConsole` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` via
  `STARTUPINFOEX`), which Crystal's `Process` does not expose — a
  prototype must hand-roll `CreateProcessW` bindings. The `vt-ctty` C
  shim and process-group signaling have no Windows equivalent; close
  semantics become `ClosePseudoConsole`. Whether this is worth building
  is exactly what the spike answers.

## Deliverables

1. **vt repo CI** (`shards/vt/.github/workflows/ci.yml`): Linux + macOS
   jobs mirroring the template plan 019 rolled across the other shards
   (install, `crystal spec`, format check, build), plus a Windows job
   running **core specs only**. This also closes the standing "vt has no
   CI" gap noted at v0.2.0.
2. **Require-graph split** so the core loads on Windows: either
   `{% if flag?(:unix) %}` guards inside `src/term-vt.cr` around the
   PTY/Session/CapturedTTY requires (and around `targets:`-built CLI
   code via a build-time error message on win32), or a documented
   `require "term-vt/core"` entry point — pick one, justify in the
   report. No behavior change on POSIX.
3. **ConPTY prototype** under `plans/prototypes/033-conpty/` (root repo):
   smallest possible Crystal program that spawns `cmd /c echo ok` under
   `CreatePseudoConsole`, pumps output into `Term::VT::Screen`, and
   prints the snapshot. Compile-verified on Windows if an environment is
   available; otherwise written against documented APIs and marked
   untested.
4. **Report** `plans/reports/033-conpty-findings.md`: what ran green on
   Windows CI, first failure per lane, the require-split decision, the
   Win32 API surface a real `Session` port needs (spawn, resize via
   `ResizePseudoConsole`, exit detection, kill semantics, no signals),
   and a go/no-go recommendation with effort estimate for a follow-up
   implementation plan.
5. vt README: reword the bullet to "Windows/ConPTY (core compiles on
   Windows; PTY harness POSIX-only — see plan 033 findings)" if and only
   if the Windows core-spec lane is green; otherwise leave it.

## Non-goals

No merged Windows `Session`. No changes to POSIX behavior. No version
bump (CI + guards can ride the next feature release).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| POSIX regression | `cd shards/vt && crystal spec --no-color` | pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |
| Core-only compile check (approximates win32 packaging) | `cd shards/vt && crystal build --no-codegen spec/parser_spec.cr` etc. | compiles |
| CI (operator-gated) | push branch to `crystal-term/vt`, observe Actions | Linux/macOS green; Windows core lane result recorded |

## Steps

1. Require-graph split + POSIX regression (everything still passes, CLI
   still builds).
2. CI workflow (Linux/macOS full, Windows core-only) — copy the plan-019
   template from a sibling shard, e.g. `shards/prompt`.
3. STOP for operator: request permission to push the branch so Actions
   run. Record results per lane in the report skeleton.
4. ConPTY prototype + API-surface writeup.
5. Report, README reword (only if green), `plans/README.md` row.

## STOP conditions

- Pushing any branch: operator instruction required first (repo-wide
  rule) — the spike pauses at step 3 until granted.
- Core specs need more than mechanical fixes on Windows (e.g. `Char`/
  encoding semantics differ): timebox, record the first two failures with
  hypotheses in the report, and stop digging — that data IS the
  deliverable.
- The prototype tempts you into building resize/kill/wait plumbing: STOP —
  echo + snapshot is the whole prototype; the rest is the follow-up
  plan's job.

## Git workflow

`shards/vt` is a git submodule (`crystal-term/vt`), currently detached at
`v0.3.0`. CI + guards: branch in the submodule
(`git -C shards/vt fetch origin && git -C shards/vt checkout -b watzon/plan-033 origin/main`),
conventional commits. Prototype + report: root repo branch from `main`
(they live under `plans/`), plus the `plans/README.md` row and submodule
pointer bump once the vt branch merges. Push nothing without operator
instruction (step 3 explicitly requests it).
