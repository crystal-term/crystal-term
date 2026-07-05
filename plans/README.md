# Improvement plans

Generated from a full-codebase audit at root commit `912c211` (2026-07-04).
Each plan is self-contained: an executor should be able to complete it with no
context beyond the plan file and the repo. Executors update their plan's
status row here when they finish (statuses: TODO, IN PROGRESS, DONE,
BLOCKED(reason)).

Submodule note: `shards/*` are mostly separate git repos. Each plan's "Git
workflow" section says which repo(s) it commits to. Nothing gets pushed
without operator instruction.

## Recommended execution order

Waves group plans whose prerequisites are satisfied by the prior wave.
Within a wave, plans are independent and can run in parallel.

- Wave 1 — foundation: 001, 003, 007, 009, 010, 014, 015
- Wave 2 — needs wave 1 pieces: 002 (after 001), 004 (after 003), 012 (after 007), 017 (after 007)
- Wave 3: 005 (after 003+004), 008 (after 004), 013 (after 009)
- Wave 4: 006 (after 002+005), 016 (after 010+012)
- Wave 5: 011 (after 002+005+006), 021 (after 002+005+006, ideally 011)
- Anytime (operator-gated): 018, 019 (after 001), 020

## Index

| # | Plan | Priority | Effort | Depends on | Repos touched | Status |
|---|------|----------|--------|------------|---------------|--------|
| 001 | [Root CI + submodule HTTPS](001-root-ci-and-submodule-https.md) | P1 | S | — | root | DONE |
| 002 | [Reader raw-mode inversion](002-reader-raw-mode-inversion.md) | P1 | S | 001 | reader | DONE |
| 003 | [Enter key + subscribe macro fail-loud](003-enter-key-and-subscribe-macro.md) | P1 | S | — | reader, prompt | DONE |
| 004 | [Prompt characterization tests](004-prompt-characterization-tests.md) | P1 | L | 003 | prompt | DONE |
| 005 | [Reader handler registry (leak fix)](005-reader-handler-registry.md) | P1 | M | 003, 004 | reader, prompt | DONE |
| 006 | [read_line + history fixes](006-reader-read-line-and-history.md) | P2 | M | 002, 005 | reader | DONE |
| 007 | [Spinner testability + concurrency](007-spinner-testability-and-concurrency.md) | P2 | M | — | spinner, root (progress) | DONE |
| 008 | [Prompt small-bug sweep](008-prompt-small-bug-sweep.md) | P2 | M | 004 | prompt | DONE |
| 009 | [Color bug sweep](009-color-bug-sweep.md) | P2 | S-M | — | color | DONE |
| 010 | [Cursor/screen/terminfo fixes](010-cursor-screen-terminfo-fixes.md) | P2 | M | — | cursor, screen, terminfo | DONE |
| 011 | [Reader test seam](011-reader-test-seam.md) | P2 | M | 002, 005, 006 | reader | DONE |
| 012 | [Render-loop performance](012-render-loop-performance.md) | P2 | M | 007 | screen, spinner, root (progress) | DONE |
| 013 | [Color capability detection + NO_COLOR](013-color-capability-detection.md) | P3 | M | 009 | color, prompt | DONE |
| 014 | [Spectator hygiene](014-spectator-hygiene.md) | P3 | S | — | 6 submodules + root | DONE |
| 015 | [Root AGENTS.md](015-root-agents-md.md) | P3 | S | — | root | DONE |
| 016 | [ANSI/size/keys dedup](016-ansi-dedup.md) | P3 | M-L | 010, 012 | terminfo, cursor, reader, root | DONE |
| 017 | [README fixes (spinner, prompt)](017-readme-fixes.md) | P3 | S | 007 | spinner, prompt | DONE |
| 018 | [Progress shard public home](018-progress-shard-home.md) | P3 | M | — (operator) | root, new repo | DONE |
| 019 | [SPIKE: Windows CI](019-windows-ci-spike.md) | P3 | M | 001 (operator) | all submodules, root | DONE (staging; CI runs operator-gated) |
| 020 | [SPIKE: `term` umbrella shard](020-term-umbrella-spike.md) | P3 | S-M | — | root (prototype only) | DONE |
| 021 | [SPIKE: bare-Escape handling](021-reader-escape-key-spike.md) | P3 | M | 002, 005, 006 | reader, root | TODO |

## Cross-cutting notes

- Verification baseline for every plan: `scripts/validate-shards.sh --local`
  (subset via `--shards a,b --skip-examples`). Plan 001 wires it into CI.
- Behavior changes requiring release notes: 002 (raw mode on real TTYs),
  007 (interval → Hz), 008 (ConfirmQuestion matching), 009 (`to_s` format),
  010 (`move_to` coordinates), 013 (NO_COLOR compliance).
- GitHub issues likely resolved along the way: prompt#2/#3 (005, 008),
  prompt#15 (008), color#2 (009), screen#5 (019 + follow-ups).
- Reports and prototypes produced by spikes live under `plans/reports/` and
  `plans/prototypes/`.
