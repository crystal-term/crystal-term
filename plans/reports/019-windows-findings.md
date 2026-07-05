# Plan 019 Windows CI Findings

## Summary

Workflow staging is complete for all eight shards. The prompt workflow template
was copied to `color`, `cursor`, `screen`, `terminfo`, `reader`, `spinner`, and
`progress`; `prompt` already matched the template. Legacy `.travis.yml` files
were removed from the submodule shards that still had them.

No shard branches were pushed. Per executor instructions, GitHub Actions Windows
runs are operator-blocked until the shard branches are pushed or draft PRs are
opened.

## Local Baseline

- Toolchain: Crystal 1.20.3, Shards 0.20.0.
- Command: `scripts/validate-shards.sh --local --skip-examples`
- Result: PASS for install and spec across `color`, `cursor`, `screen`,
  `terminfo`, `reader`, `spinner`, `prompt`, and `progress`.
- Notes: `terminfo` emitted `/dev/tty` warnings on macOS but passed. `prompt`
  retained its existing 7 pending specs and passed.

## Windows Run Inventory

| Shard | Windows status | First error | Hypothesis | Estimate |
| --- | --- | --- | --- | --- |
| color | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Likely near-green; any failure should be in environment/color capability detection. | S |
| cursor | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Escape sequence specs are likely portable, though existing Windows TODO markers may need explicit Windows expectations or skips. | S |
| screen | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Highest-risk foundation shard: WinAPI console sizing, ANSICON branches, or readline linking may fail. If `shards install` or specs fail on readline linking, try the documented `-Dwithout_readline` spec flag in that OS job. | M |
| terminfo | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Windows console support exists; likely issues are tty detection or terminal capability fallback behavior. | S |
| reader | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Raw-mode handling and `WINDOWS_KEYS` are the likely failure points, especially around Crystal stdlib console behavior and key sequence assertions. | M |
| spinner | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Mostly depends on cursor behavior; failures should be small unless cursor exposes Windows-specific output differences. | S |
| prompt | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Existing Windows matrix may surface propagated failures from color, cursor, screen, or reader. | M |
| progress | not-run (operator-blocked) | No GitHub Actions run captured; branch was not pushed per no-push rule. | Depends on cursor, screen, and spinner; likely blocked by whatever fails first in those lower shards. | M |

## Recommended Fix Order

1. Push and observe leaf shards first: `color`, `cursor`, `terminfo`.
2. Run `spinner` after `cursor` is known.
3. Triage `screen` before `reader`, since reader depends on screen behavior.
4. Run `reader` after screen has a known result.
5. Finish with `prompt` and `progress`, which should mostly expose propagated
   dependency issues.

