# Plan 028: prompt list questions honor the Escape key

> **Executor instructions**: Follow this plan step by step. Run every
> verification command. Honor STOP conditions. Update the 028 row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: the gap still exists:
> `rg -n "escape" shards/prompt/src/prompt/list.cr` → no `:escape`
> subscription in `register_subscriptions` (plan-025 finding, 2026-07-05).
> Reader-side ESC works (plan 021 landed):
> `rg -n "keyescape" shards/prompt/src` to inventory what already listens.

## Status

- **Priority**: P2
- **Effort**: S-M
- **Risk**: MED (new public behavior on a shipped prompt type; semantics
  must be decided once and documented)
- **Depends on**: 025 (PTY spec infra); independent of 027
- **Category**: bug / direction
- **Planned at**: commit `e26c58d` (root), 2026-07-05

## Why this matters

ESC-to-dismiss is table stakes for interactive menus, and plan 021 built
reliable bare-ESC delivery in reader precisely so prompt could use it. It
never did: `List#register_subscriptions` subscribes navigation and Enter
but not `:escape`, so pressing ESC in a select menu does nothing (confirmed
end-to-end on a real PTY during plan 025 — the executor declined to force a
dismissal spec against unwired behavior, correctly).

## Target design

Semantics (decide once, document in prompt README + report as a release
note): pressing ESC in `List`/`MultiList` (and `EnumList` if it shares the
keypress loop) **aborts the question**: rendering cleans up the menu, the
question's result is `nil`, and `Prompt#select`/`#multi_select` return
`nil`. No exception — matching how the family treats default-less returns;
callers opt into treating `nil` as cancellation. Add an opt-out knob only
if one already exists for similar behavior (do not invent new config
surface otherwise; report if you think one is needed).

Specs:
- Unit (stdlib spec, existing direct-keypress style): `keyescape` on a
  List marks it done/aborted; return value nil; renders a clean exit (no
  dangling menu rows).
- PTY integration (extend `spec/integration_pty_spec.cr`, plan-025 infra):
  fixture prints `result=<value.inspect>` after the select returns;
  `press(:escape)` → `wait_for("result=nil")` → child exits 0. Subject to
  the 5-run flake gate.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Prompt suite | `scripts/validate-shards.sh --local --shards prompt --skip-examples` | exit 0 |
| Flake gate | same command, 5 consecutive runs | 5× exit 0 |
| Format (spec + touched src) | `cd shards/prompt && crystal tool format --check src spec` | see note |

Note: prompt `src/` has pre-existing format drift (plan-025 report). Format
only the files you touch; do not reformat the shard wholesale in this plan.

## Steps

1. Inventory ESC handling across prompt question types; confirm List is
   representative and find where `keyenter` finalizes — mirror that path
   for abort.
2. Unit specs first (red), then wire `:escape` in `register_subscriptions`
   + the abort path.
3. PTY integration spec + fixture change; 5-run flake gate.
4. README section ("Press Esc to cancel — returns nil") + release note in
   the report. Update `plans/README.md`.

## STOP conditions

- Abort-as-nil conflicts with existing typed return values (e.g. a
  non-nilable return type on `Prompt#select` would force an API-breaking
  signature change): report the exact signatures and wait.
- ESC events do not reach the question's keypress loop at all (reader
  subscription plumbing gap): that is a reader/prompt integration bug —
  report as a finding; do not hack around it with timeouts.

## Git workflow

- **prompt**: branch `watzon/plan-028-prompt-escape`, conventional commits.
- **root**: pointer bump + plans/README.md row. Push nothing.
