# Plan 004: Every prompt component type has characterization specs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git -C shards/prompt log --oneline -5` and compare
> `shards/prompt/spec/` contents against the "Current state" description. If plans
> 003/005/008 already landed, their behavior changes are the *intended* baseline —
> characterize the code as it stands when you run.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: LOW (tests only)
- **Depends on**: 003 (Enter dispatch fix — otherwise event-driven specs can't confirm)
- **Category**: tests
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

`term-prompt` is the largest shard (~3,600 lines across 26 source files) and the top-level consumer of four other shards, yet its entire spec suite is one file with 8 examples covering four classes. Roughly 20 source files have zero coverage — including `slider.cr`, `expander.cr`, `autocomplete.cr`, `file_select.cr`, `enhanced_confirm.cr`, `question.cr` (the ask/validation pipeline), `mask_question.cr`, `keypress.cr`, `multiline.cr`, `answers_collector.cr`, `paginator.cr`, `block_paginator.cr`, `choices.cr`, and `question/validators.cr`. Crystal only type-checks methods that are *called*, so untested code here isn't just unverified — some of it doesn't even compile (see plan 008). This plan is also the safety net required before plan 005 reworks event handling across every component.

## Current state

- `shards/prompt/spec/spec_helper.cr` — two lines: `require "spec"` then `require "../src/term-prompt"`. Stdlib spec, not Spectator.
- `shards/prompt/spec/prompt_spec.cr` — the whole suite. It establishes the testing pattern to reuse:
  - Reopen the class to expose private state with `spec_`-prefixed wrappers:

```3:27:shards/prompt/spec/prompt_spec.cr
class Term::Prompt::List
  def spec_setup_defaults
    setup_defaults
  end

  def spec_active
    @active
  end

  def spec_done
    @done
  end

  def spec_visible_names
    choices.map(&.name)
  end

  def spec_render_menu
    render_menu
  end

  def spec_answer
    answer
  end
end
```

  - Build key events with a bare helper:

```39:41:shards/prompt/spec/prompt_spec.cr
private def key_event(value)
  Term::Reader::KeyEvent.from({} of String => String, value)
end
```

  - Drive components by calling their key handlers directly (`list.keypress("k", key_event("k"))`, `list.keyreturn`, `list.keybackspace`) and assert on `spec_*` accessors — no TTY needed.
- Component key-handler inventory (all public, callable from specs): every component defines `keyenter`/`keyreturn`; `List` adds `keyup/keydown/keyleft/keyright/keypress/keydelete/keybackspace/keynum`; `Slider` has `keyleft/keyright/keyup/keydown`; `Expander` has `keypress`; `Autocomplete` has `keypress/keyup/keydown/keybackspace/keydelete/keytab`; etc. Read each component's `def key...` methods before writing its specs.
- Known-buggy behaviors with fixes planned elsewhere (write these specs as `pending` with the *intended* behavior so they activate when the fix lands):
  - `ConfirmQuestion#initialize` assigns `suffix` to `@positive`/`@negative` (plan 008)
  - `EnumList#keyreturn` raises IndexError on out-of-range numeric input (plan 008)
  - `Prompt` option `track_history: false` is ignored (plan 008)
  - `Expander#choices` (no-arg getter), `EnumList#choice(*value, &block)`, and `Paginator#paginate(list, active, page_size)` don't compile if called (plan 008) — do NOT call these from specs until 008 lands; note them instead.
- Prompt run command: `cd shards/prompt && shards install && crystal spec --no-color`. The local `shard.override.yml` (already present) resolves family deps from this checkout.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd shards/prompt && shards install` | exit 0 |
| Specs | `cd shards/prompt && crystal spec --no-color` | all pass |
| One file | `cd shards/prompt && crystal spec spec/slider_spec.cr --no-color` | passes |
| Format | `cd shards/prompt && crystal tool format spec` | exit 0 |

## Scope

**In scope** (create only; plus the two listed edits):
- `shards/prompt/spec/slider_spec.cr`
- `shards/prompt/spec/expander_spec.cr`
- `shards/prompt/spec/autocomplete_spec.cr`
- `shards/prompt/spec/file_select_spec.cr`
- `shards/prompt/spec/enhanced_confirm_spec.cr`
- `shards/prompt/spec/question_spec.cr` (validation pipeline, defaults, required, convert)
- `shards/prompt/spec/mask_question_spec.cr`
- `shards/prompt/spec/multiline_spec.cr`
- `shards/prompt/spec/keypress_spec.cr`
- `shards/prompt/spec/enum_list_spec.cr` (move/extend the existing EnumList examples here)
- `shards/prompt/spec/list_spec.cr` (move/extend the existing List/MultiList examples here)
- `shards/prompt/spec/paginator_spec.cr` (Paginator + BlockPaginator, block overloads only)
- `shards/prompt/spec/choices_spec.cr` (Choices/Choice conversion: strings, named tuples, disabled)
- `shards/prompt/spec/validators_spec.cr` (`question/validators.cr`: RequiredValidator, LengthValidator, PatternValidator behaviors)
- Edit: `shards/prompt/spec/prompt_spec.cr` (shrink to the version example, or delete after moving content)
- Edit: `shards/prompt/spec/spec_helper.cr` (move the shared `key_event` helper and shared class-reopening here)

**Out of scope** (do NOT touch):
- Any file under `shards/prompt/src/` — this plan is tests only. If a spec you write exposes a source bug not listed above, mark the spec `pending` with a comment naming the observed behavior and report it; do not fix source.
- Other shards' specs.

## Git workflow

- All work inside the `shards/prompt` submodule. Branch: `advisor/004-characterization-specs`. One commit per spec file or logical group; style: `test: add slider characterization specs`.
- Do NOT push.

## Steps

### Step 1: Restructure the harness

Move `key_event` and the `spec_` class-reopenings from `prompt_spec.cr` into `spec_helper.cr` (make `key_event` a top-level `def key_event` so all spec files can use it — the current `private def` scoping works per-file in stdlib spec, so a shared non-private helper in spec_helper is fine). Split existing examples into `list_spec.cr`, `enum_list_spec.cr`, and a minimal `prompt_spec.cr` (version + ConfirmQuestion examples).

**Verify**: `cd shards/prompt && crystal spec --no-color` → same example count as before the move (8), all pass.

### Step 2: Per-component characterization specs

For each in-scope component, write specs following the `list_spec.cr` pattern: construct with `Term::Prompt.new`, set choices/options, call `setup_defaults` (via a `spec_` wrapper where private), drive key handlers directly, assert on state and `answer`/`render_menu` output. Minimum coverage per component:

- happy path to a confirmed answer (drive keys, then `keyenter`, assert `spec_done` and `answer`)
- default handling (explicit default option respected)
- one boundary case per component (first/last item navigation wrap or clamp, empty filter, out-of-range slider step, autocomplete with zero matches, file_select on an empty temp dir, multiline terminating on ctrl_d semantics, mask_question echo masking in rendered output, keypress returning on any key)
- `question_spec.cr`: required-question re-asks on empty, validator rejection message, `convert` (e.g. `:int`) conversion, default returned on empty input.
- `validators_spec.cr`: each validator's accept/reject pairs, table-driven.
- `choices_spec.cr`: conversion from `String`, `NamedTuple` with `disabled:`, and `Choice` instances; `Choices#[]` delegation.
- `paginator_spec.cr`: block-form `paginate(list, active, page_size) { }` windows correctly at start/middle/end. Do not call the block-less overload (compile-broken; plan 008).

For the four known bugs listed in "Current state", write the intended-behavior spec and mark it `pending "fixed by plan 008"` (stdlib spec: use `pending` instead of `it`).

**Verify after each file**: `cd shards/prompt && crystal spec spec/<file> --no-color` → passes.

### Step 3: Full-suite run and count

**Verify**: `cd shards/prompt && crystal spec --no-color` → all pass; total examples ≥ 50; pending count equals the number of intended-behavior specs you wrote for known bugs.

## Test plan

This plan *is* the test plan. Structural pattern: the class-reopen + direct-key-handler style already in `prompt_spec.cr` (excerpted above). No mocking framework — stdlib spec only.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] All 14 new spec files exist under `shards/prompt/spec/`
- [ ] `cd shards/prompt && crystal spec --no-color` exits 0 with ≥ 50 examples
- [ ] `ls shards/prompt/spec/*.cr | wc -l` ≥ 16
- [ ] No file under `shards/prompt/src/` modified (`git -C shards/prompt status`)
- [ ] `crystal tool format --check spec` (in `shards/prompt`) exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- A component's constructor or `setup_defaults` raises for a plain construction like the List examples — that's an unknown source bug; report it with the backtrace.
- More than three components turn out to have compile-broken public methods beyond the four already catalogued — the plan 008 scope needs revisiting first.
- `file_select` specs require touching the real filesystem outside a tmp dir.

## Maintenance notes

- Plan 005 (handler-registry rework) will move `subscribe` calls from `initialize` to `render`; these specs call key handlers directly, so they should survive unchanged — that's deliberate.
- Once plan 008 lands, flip its `pending` specs to `it` in the same PR.
- Future prompt features should add a spec file per component following this layout; reviewers should reject prompt PRs that touch a component without touching its spec file.
