# Improvement plans

Open executable plans left after pruning the completed 001–028 audit
wave. Each plan is self-contained: an executor should be able to complete
it with no context beyond the plan file and the repo. Executors update
their plan's status row here when they finish (statuses: TODO,
IN PROGRESS, DONE, BLOCKED(reason)).

Submodule note: `shards/*` are mostly separate git repos. Each plan's
"Git workflow" section says which repo(s) it commits to. Nothing gets
pushed without operator instruction.

## Recommended execution order

- **029, 030, 031** are independent and can run in parallel (029 and 031
  both touch `Screen#print` — merge sequentially, second rebases; 029
  and 030 share a few lines in `set_private_modes`).
- **032** runs after 029+031.
- **033** (spike) is anytime but operator-gated (CI pushes) and best last
  so its Windows guards see the final source.

## Index

| # | Plan | Priority | Effort | Depends on | Repos touched | Status |
|---|------|----------|--------|------------|---------------|--------|
| 029 | [vt: scroll regions, origin/insert mode, tab stops](029-vt-scroll-regions-modes.md) | P2 | M-L | — | vt, root | DONE |
| 030 | [vt: mouse protocols, bracketed paste, focus](030-vt-input-modes.md) | P2 | M | — | vt, root | TODO |
| 031 | [vt: stop dropping combining marks / VS16](031-vt-combining-marks.md) | P2 | M | — | vt, root | TODO |
| 032 | [vt: opt-in resize reflow](032-vt-resize-reflow.md) | P3 | L | 029, 031 | vt, root | TODO |
| 033 | [SPIKE: vt on Windows (core CI + ConPTY)](033-vt-windows-conpty-spike.md) | P3 | M-L | — (operator) | vt, root | TODO |

## Cross-cutting notes

- Verification baseline for every plan: `scripts/validate-shards.sh --local`
  (subset via `--shards a,b --skip-examples`). Root CI runs the same harness.
- Spike outputs (findings reports, prototypes) go under `plans/reports/` and
  `plans/prototypes/` when created — those dirs are recreated as needed.
- Completed plans 001–028 (audit through prompt ESC dismissal / vt CLI /
  dogfood) were pruned 2026-07-08; history lives in git.
