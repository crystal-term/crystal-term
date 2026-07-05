# Plan 008: Prompt's known small bugs are fixed: ConfirmQuestion options, enum_select bounds, track_history, version macro, dead compile-broken methods

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare every excerpt below against live code in
> `shards/prompt/src/`. If plan 004 landed, `pending` specs for these bugs exist —
> flip them to active as you fix each one.

## Status

- **Priority**: P2
- **Effort**: M (many small S items)
- **Risk**: LOW
- **Depends on**: 004 (pending specs to activate; can run standalone if 004 hasn't landed — then write the specs yourself)
- **Category**: bug / security
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

Five independently small, independently verifiable bugs in `term-prompt`, several matching open GitHub issues (crystal-term/prompt #3 `enum_select` errors, #15 Regex behavior): user-supplied Confirm labels are silently discarded and its regex matches almost anything ending in "y"; `enum_select` crashes with IndexError on routine bad input; `track_history: false` is impossible to express; the compile-time version constant shells out with an unquoted interpolated path (a compile-time command-injection primitive for any consumer whose build path contains shell metacharacters); and three public methods don't compile if anyone calls them (Crystal only type-checks called code).

## Current state

All in `shards/prompt/src/`.

### A. ConfirmQuestion — options discarded + over-broad regex

```17:23:shards/prompt/src/prompt/confirm_question.cr
      def initialize(prompt, default = nil, suffix = nil, positive = nil, negative = nil, **options)
        super(prompt, **options)
        @suffix = suffix
        @positive = suffix
        @negative = suffix
        @_default = default || false
      end
```

`@positive`/`@negative` should come from `positive`/`negative`. Downstream `setup_defaults`/`create_suffix` (lines ~60-91) fill nil values with "yes"/"no" defaults — read them before editing so the nil-flow stays intact.

```93:98:shards/prompt/src/prompt/confirm_question.cr
      def convert_result(value)
        positive_word = Regex.escape(positive.to_s)
        positive_letter = Regex.escape(positive.to_s[0].to_s)
        pattern = Regex.new("^#{positive_word}|#{positive_letter}$", Regex::Options::IGNORE_CASE)
        !value.to_s.match(pattern).nil?
      end
```

Precedence bug: `^yes|y$` parses as `(^yes)|(y$)`, so any input **ending** in "y" ("okay", "definitely no...y") converts to true. Intended: `^(yes|y)$`.

### B. EnumList#keyreturn — unchecked index

```120:132:shards/prompt/src/prompt/enum_list.cr
      def keyreturn
        @failure = false
        num = @input.to_s.to_i? || 0
        choice_disabled = choices[num - 1] && choices[num - 1].disabled?
        choice_in_range = num > 0 && num <= @choices.size
        ...
```

`choices[num - 1]` runs before the range check; `Choices#[]` delegates to `Array#[]` which raises IndexError for out-of-range (`choices.cr:35-37`), and `num = 0` indexes `-1` (the *last* choice). Reorder: compute `choice_in_range` first, then `choice_disabled = choice_in_range && choices[num - 1].disabled?`.

### C. `track_history: false` ignored

```52:52:shards/prompt/src/term-prompt.cr
      @track_history = options[:track_history]? || true
```

`false || true` → `true`. Fix with a nil-check (the codebase pattern for boolean options — see `question.cr` echo handling): `@track_history = options[:track_history]?.nil? ? true : !!options[:track_history]?`. Confirm `@track_history` is actually forwarded to the reader construction at `term-prompt.cr:56` — if it isn't, wire it through (`track_history: @track_history`).

### D. Version macro — compile-time shell-out with unquoted path

```1:5:shards/prompt/src/prompt/version.cr
module Term
  class Prompt
    VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
  end
end
```

Every other shard hardcodes its version string. A build path containing `$(...)`/backticks executes during compilation of any downstream consumer; spaces simply break the build. Replace with `VERSION = "1.0.0"` (match `shard.yml`'s `version: 1.0.0`).

### E. Compile-broken-if-called public methods

1. `enum_list.cr:82-88` — `choice(*value, &block)` does `value << block` on a `Tuple` (no `#<<`):

```82:88:shards/prompt/src/prompt/enum_list.cr
      def choice(*value, &block)
        if block
          @choices << (value << block)
        else
          @choices << value
        end
      end
```

2. `expander.cr:129-138` — the no-arg `choices` getter references `filterable?` and `@filter`, which don't exist on `Expander` (copy-paste from `List`).
3. `paginator.cr:86-90` — block-less `paginate(list, active, page_size)` shadows its own args and calls the block form without required arguments:

```86:90:shards/prompt/src/prompt/paginator.cr
      def paginate(list, active, page_size = nil)
        list = [] of Tuple(Choice, Int32)
        paginate { |e, i| list << {e, i} }
        list
      end
```

Resolution policy: **fix** if the sibling implementation shows clear intent, else **delete**. Concretely: (1) fix EnumList#choice modeled on `List#choice`/`Choices#<<` conversion (read `list.cr`'s `choice` method and `choices.cr` first); (2) delete Expander's no-arg `choices` getter (Expander has no filtering; the inherited/explicit `@choices` accessor suffices — verify nothing in `expander.cr` calls it); (3) delete the block-less `paginate` overload (nothing calls it: `rg -n "paginate\(" shards/prompt/src` and check `BlockPaginator` for the same defect while there).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd shards/prompt && shards install` | exit 0 |
| Specs | `cd shards/prompt && crystal spec --no-color` | all pass |
| Compile check | `cd shards/prompt && crystal build --no-codegen src/term-prompt.cr` | exit 0 |
| Cross-shard | `scripts/validate-shards.sh --local --shards prompt --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/prompt/src/prompt/confirm_question.cr`
- `shards/prompt/src/prompt/enum_list.cr`
- `shards/prompt/src/term-prompt.cr` (track_history lines only)
- `shards/prompt/src/prompt/version.cr`
- `shards/prompt/src/prompt/expander.cr` (dead getter only)
- `shards/prompt/src/prompt/paginator.cr` / `block_paginator.cr` (dead overload only)
- `shards/prompt/spec/` — activate/write specs per fix

**Out of scope**:
- Subscribe/handler lifecycle (plans 003/005), List filtering internals, `question.cr` beyond reading it for conventions, `shard.yml`.

## Git workflow

- Inside `shards/prompt` submodule, branch `advisor/008-bug-sweep`, one commit per lettered item (A–E). Do NOT push.

## Steps

### Step 1 (A): ConfirmQuestion

Change the two assignments to `@positive = positive` / `@negative = negative`, and fix the regex to `Regex.new("^(#{positive_word}|#{positive_letter})$", Regex::Options::IGNORE_CASE)`.

**Verify**: specs — `ConfirmQuestion` with `positive: "ja", negative: "nein"` converts "ja" → true, "nein" → false; default construction converts "okay" → **false** and "y"/"Yes" → true. `crystal spec --no-color` green.

### Step 2 (B): EnumList bounds

Reorder the range check before any indexing; use `choices[num - 1]` only when `choice_in_range`.

**Verify**: spec — 3 choices, `@input` driven to "9" via `keypress` events then `keyreturn` → no raise, `@failure` true (expose via a `spec_failure` wrapper); input "0" → not treated as the last choice.

### Step 3 (C): track_history

Apply the nil-check pattern; wire the option into the `Term::Reader.new(...)` construction if missing.

**Verify**: spec — `Term::Prompt.new(track_history: false).reader.track_history?` is false; default prompt → true.

### Step 4 (D): Version constant

Replace the macro line with `VERSION = "1.0.0"`.

**Verify**: `rg -n '`' shards/prompt/src/prompt/version.cr` → 0 matches; `crystal spec --no-color` (version spec asserts `\d+\.\d+\.\d+`) → passes.

### Step 5 (E): Fix/delete the three dead methods

Per the resolution policy above. After each change run the compile check; then add one minimal spec per surviving method so the compiler forever type-checks it (e.g. EnumList `choice` adds a choice).

**Verify**: `cd shards/prompt && crystal build --no-codegen src/term-prompt.cr` → exit 0; `rg -n "def choices" shards/prompt/src/prompt/expander.cr` shows no no-arg getter; specs green.

### Step 6: Flip plan 004's pending specs

If `pending "fixed by plan 008"` specs exist, convert each to `it` and make them pass.

**Verify**: `rg -n 'pending "fixed by plan 008"' shards/prompt/spec` → 0 matches; full suite green.

## Test plan

One spec per fix as listed in the steps; model on the class-reopen + direct-key-handler pattern in `shards/prompt/spec/` (see `list_spec.cr`/`prompt_spec.cr`). All in stdlib spec.

## Done criteria

- [ ] `rg -n "@positive = suffix|@negative = suffix" shards/prompt/src` → 0 matches
- [ ] `rg -n '\^\(#\{positive_word\}' shards/prompt/src/prompt/confirm_question.cr` → 1 match
- [ ] EnumList out-of-range spec passes without IndexError
- [ ] `Term::Prompt.new(track_history: false)` spec passes
- [ ] `shards/prompt/src/prompt/version.cr` contains a literal version string, no backticks
- [ ] `cd shards/prompt && crystal spec --no-color` exits 0, zero `pending "fixed by plan 008"` remaining
- [ ] `scripts/validate-shards.sh --local --shards prompt --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Excerpts don't match live code (drift).
- `setup_defaults`/`create_suffix` in ConfirmQuestion turn out to *depend* on positive/negative starting equal to suffix (read them first; if the nil-default flow breaks, report before redesigning).
- Deleting the Expander getter or Paginator overload breaks compilation (something does call them) — fix instead of delete, and say so.
- The version constant is consumed somewhere expecting the `shards version` output format rather than a plain string.

## Maintenance notes

- Release note: ConfirmQuestion's `convert_result` semantics tighten — inputs like "okay" no longer count as positive. This resolves the class of bug in crystal-term/prompt#15.
- After this lands, comment on GitHub issues prompt#3 (enum_select) and prompt#15 referencing the fixes (operator action; needs `gh` auth).
- The version.cr change removes the last compile-time shell-out in the family; reviewers should reject future `{{ \`...\` }}` macros that interpolate paths.
