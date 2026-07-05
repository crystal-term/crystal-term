# Plan 005: Key handlers are scoped to the reader instance and cleared per prompt — no global registry

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: plans 003 and 004 are prerequisites. Confirm
> `rg -n "raise \"Term::Reader.subscribe" shards/reader/src/term-reader.cr` → 1 match
> and `ls shards/prompt/spec/*.cr | wc -l` ≥ 16 before starting. Compare all
> excerpts below against live code.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (event dispatch is the backbone of every prompt type)
- **Depends on**: 003, 004
- **Category**: bug / tech-debt
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

`Term::Reader.subscribe` appends closures capturing `self` to a **class-level** `global_handlers` hash, and nothing ever unsubscribes. Every prompt component instance (List, Slider, Autocomplete, ... — 12 call sites) registers in `initialize` and stays registered forever. Consequences: (1) unbounded memory — no prompt object is ever collectible; (2) O(N) dispatch per keystroke after N prompts; (3) cross-fire — a finished `select`'s handlers keep receiving keys during the next `ask`/`select`, mutating stale state. This cross-fire is the most plausible root cause of the open "selection filtering doesn't work" (crystal-term/prompt#2) and `enum_select` (#3) issues. Reader's own spec helper already works around it (`Term::Reader.global_handlers.clear` before each test), which is the tell.

## Current state

- `shards/reader/src/term-reader.cr:37-39` — the class-level registry:

```37:39:shards/reader/src/term-reader.cr
    class_property global_handlers : Hash(String, Array(HandlerFunc)) = Hash(String, Array(HandlerFunc)).new { |h, k|
      h[k] = [] of HandlerFunc
    }
```

- `term-reader.cr:55-57` — an instance-level `@event_handlers` hash **already exists** (fed by `on_key`, lines 72-85).
- `term-reader.cr:68` — the reader instance itself uses the class-level macro for ctrl-d/ctrl-z: `Term::Reader.subscribe(:ctrl_d, :ctrl_z)`.
- `term-reader.cr:401-411` — dispatch merges instance + global buckets:

```401:411:shards/reader/src/term-reader.cr
    private def trigger_key_event(char : String, line : String = "") : Nil
      event = KeyEvent.from(console.keys, char, line)
      key = event.key.name

      (@event_handlers[key] +
        @event_handlers[""] +
        self.class.global_handlers[key] +
        self.class.global_handlers[""]).each do |proc|
        proc.call(event.key.name, event)
      end
    end
```

- `term-reader.cr:430-441` — the `subscribe` macro (after plan 003 it also has a `{% raise %}` else-branch). It writes into `Term::Reader.global_handlers`.
- Prompt component subscribe sites (all in `initialize`): `list.cr:67`, `multi_list.cr:25` (subclass of List), `enum_list.cr:63`, `slider.cr:35`, `expander.cr:42`, `autocomplete.cr:48`, `file_select.cr:46`, `mask_question.cr:12`, `multiline.cr:14`, `keypress.cr:14`, `enhanced_confirm.cr:39`.
- `Term::Prompt` owns one reader: `shards/prompt/src/term-prompt.cr:36` `getter reader : Term::Reader`, and components hold `@prompt`. Component render loops call `@prompt.read_keypress` (delegated to `@prompt.reader`), e.g.:

```378:389:shards/prompt/src/prompt/list.cr
      private def render
        @prompt.print(@prompt.hide)
        until @done
          question = render_question
          @prompt.print(question)
          @prompt.read_keypress
          ...
```

- Spec workarounds to remove afterwards: `shards/reader/spec/spec_helper.cr:10` and several sites in `shards/reader/spec/unit/multiline_echo_spec.cr` call `Term::Reader.global_handlers.clear`. Plan 003's regression spec in `shards/prompt/spec/list_spec.cr` (or `prompt_spec.cr`) dispatches via `global_handlers` and must be updated here.

## Target design

1. Reader gains a second instance bucket for component handlers:

```crystal
getter component_handlers : Hash(String, Array(HandlerFunc)) = Hash(String, Array(HandlerFunc)).new { |h, k| h[k] = [] of HandlerFunc }

def clear_component_handlers : Nil
  @component_handlers.clear
end
```

2. `trigger_key_event` dispatches `@event_handlers` + `@component_handlers` (both exact-key and `""` buckets). The `global_handlers` terms are deleted, and the `class_property global_handlers` itself is deleted.
3. The `subscribe` macro takes the reader as an explicit first argument and writes into its component bucket (keeping plan 003's `{% raise %}` validation):

```crystal
macro subscribe(reader, *keys)
  {% valid_keys = (Term::Reader::CONTROL_KEYS.values + Term::Reader::KEYS.values).uniq %}
  {% for key in keys %}
    {% if key.id.symbolize == :keypress %}
      {{ reader }}.component_handlers[""] << Term::Reader::HandlerFunc.new { |k, e| self.keypress(k, e); nil }
    {% elsif valid_keys.includes?(key.id.stringify) %}
      {{ reader }}.component_handlers[{{ key.id.stringify }}] << Term::Reader::HandlerFunc.new { |k, e| self.key{{ key.id }}; nil }
    {% else %}
      {% raise "Term::Reader.subscribe: unknown key #{key}" %}
    {% end %}
  {% end %}
end
```

4. Reader's own ctrl-d/ctrl-z registration (line 68) moves off the macro to direct instance registration in `initialize`:

```crystal
on_key(:ctrl_d) { |_k, _e| keyctrl_d }
on_key(:ctrl_z) { |_k, _e| keyctrl_z }
```

(`on_key` already exists and appends to `@event_handlers`, which is never cleared — correct, these are reader-lifetime handlers.)
5. Each prompt component moves its subscription out of `initialize` into a `register_subscriptions` method, invoked at the top of its `render` (after clearing):

```crystal
# in List
private def register_subscriptions
  Term::Reader.subscribe(@prompt.reader, :keypress, :enter, :up, :down, :left, :right, :backspace, :delete)
end

private def render
  @prompt.reader.clear_component_handlers
  register_subscriptions
  @prompt.print(@prompt.hide)
  until @done
    ...
```

`MultiList` overrides `register_subscriptions` as `super` + `subscribe(@prompt.reader, :space)`. Components without a `render` loop of their own (check `mask_question.cr`, `multiline.cr`, `keypress.cr` — they may hook into `Question#call`) get the clear+register at the equivalent entry point where reading begins; read each component to find where `read_keypress`/`read_line` is first invoked.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Reader specs | `cd shards/reader && crystal spec --no-color` | all pass |
| Prompt specs | `cd shards/prompt && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` | exit 0 |
| Leak grep | `rg -n "global_handlers" shards/reader shards/prompt --glob '!lib'` | 0 matches when done |

## Scope

**In scope**:
- `shards/reader/src/term-reader.cr`
- `shards/reader/spec/spec_helper.cr`, `shards/reader/spec/unit/multiline_echo_spec.cr`, and any other reader spec referencing `global_handlers`
- All 11 prompt component files listed above
- `shards/prompt/spec/*.cr` — update the plan 003 Enter-dispatch spec to the new dispatch path; adjust any spec that relied on subscribe-at-initialize

**Out of scope**:
- `read_line` internals (plan 006), test-sniffing (plan 011), keys tables.
- `shards/reader/src/reader/console.cr`, `mode.cr`.

## Git workflow

- Two submodules: `shards/reader` first, then `shards/prompt`. Branches `advisor/005-handler-registry` in each. Reader must compile and pass its own specs before prompt work starts.
- Do NOT push.

## Steps

### Step 1: Reader — add `component_handlers`, rewire dispatch, migrate ctrl_d/ctrl_z, rewrite macro, delete `global_handlers`

Apply items 1–4 of the target design. Note `on_key` accepts `String | Symbol` keys.

**Verify**: `cd shards/reader && crystal build --no-codegen src/term-reader.cr` → exit 0. Expect reader *specs* to fail until Step 2 (they reference `global_handlers`).

### Step 2: Reader specs — remove the workaround and re-baseline

Delete `Term::Reader.global_handlers.clear` from `spec_helper.cr` and `multiline_echo_spec.cr` (all sites). Where a spec registered handlers through the old macro path, use `reader.on_key` or `reader.component_handlers` directly.

**Verify**: `cd shards/reader && crystal spec --no-color` → all pass.

### Step 3: Prompt — move subscriptions to render-time

Apply item 5 across the 11 components. For each: delete the `Term::Reader.subscribe(...)` line from `initialize`, add `register_subscriptions`, and call `clear_component_handlers` + `register_subscriptions` at the start of the component's read loop entry point.

**Verify**: `cd shards/prompt && crystal build --no-codegen src/term-prompt.cr` → exit 0.

### Step 4: Prompt specs

Update the Enter-dispatch regression spec from plan 003 to dispatch through the instance path, e.g.:

```crystal
list = Term::Prompt::List.new(prompt)
...
list.spec_register_subscriptions   # add a spec_ wrapper exposing register_subscriptions
prompt.reader.component_handlers["enter"].each &.call("enter", key_event("\r"))
list.spec_done.should be_true
```

Add one new regression spec proving isolation: create two Lists against the same prompt, register the second, dispatch a key, and assert the *first* list's state did not change.

**Verify**: `cd shards/prompt && crystal spec --no-color` → all pass.

### Step 5: Sweep and cross-validate

**Verify**: `rg -n "global_handlers" shards/reader shards/prompt --glob '!lib'` → 0 matches; `scripts/validate-shards.sh --local --shards reader,spinner,prompt,progress --skip-examples` → exit 0.

## Test plan

- Reader: existing suite green without the `global_handlers.clear` workaround (its absence is itself the leak regression test).
- Prompt: updated Enter-dispatch spec + the new two-list isolation spec; full plan 004 suite green.

## Done criteria

- [ ] `rg -n "global_handlers" shards/reader/src shards/prompt/src shards/reader/spec shards/prompt/spec` → 0 matches
- [ ] `rg -n "clear_component_handlers" shards/prompt/src | wc -l` ≥ number of components with their own read loop
- [ ] `cd shards/reader && crystal spec --no-color` exits 0
- [ ] `cd shards/prompt && crystal spec --no-color` exits 0
- [ ] Two-list isolation spec exists and passes
- [ ] `scripts/validate-shards.sh --local --shards reader,spinner,prompt,progress --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any prompt component's key handling turns out NOT to flow through `Reader#trigger_key_event` (i.e. some component reads keys another way) — the design assumption breaks.
- A component has no identifiable single entry point where reading begins (register/clear placement ambiguous) — report the component instead of guessing.
- `AnswersCollector` (`prompt.collect`) chains multiple questions in ways that break with per-render clearing — if the collect specs fail, stop.
- Reader specs beyond the known `global_handlers` references fail after Step 1.

## Maintenance notes

- The contract after this plan: `@event_handlers` = reader-lifetime subscriptions (via `on_key`); `component_handlers` = current-component subscriptions, cleared by the next component's render. Document this in a comment on the two properties.
- If prompt ever supports nested/concurrent components (e.g. a spinner inside a prompt), the single `component_handlers` bucket needs a stack; note deferred.
- Reviewer: scrutinize the placement of `clear_component_handlers` in components that re-enter render (validation retries in `Question`).
