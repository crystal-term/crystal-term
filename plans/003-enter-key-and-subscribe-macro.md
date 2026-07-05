# Plan 003: Enter confirms `select`/`multi_select`, and `Reader.subscribe` fails loudly on unknown keys

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare the excerpts below against
> `shards/reader/src/term-reader.cr`, `shards/reader/src/reader/keys.cr`,
> and `shards/prompt/src/prompt/list.cr` before editing.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (coordinates with 005, which reworks the same macro — do 003 first)
- **Category**: bug
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

Pressing Enter in `prompt.select`/`prompt.multi_select` can never confirm the selection through the key-event system. `List` subscribes `:return`, but the Unix key table maps `"\r"`/`"\n"` to `"enter"` — `"return"` only exists in the (unused) Windows table — and the `subscribe` macro *silently skips* key names it doesn't recognize. So the `:return` subscription is dropped at compile time and `List#keyreturn` is unreachable; the render loop spins until interrupted. Specs pass because they call `list.keyreturn` directly. The macro's silent skip is the enabling defect: any typo'd key name disappears without a trace, so it must become a compile-time error.

## Current state

- `shards/reader/src/reader/keys.cr` — Unix tables. `KEYS` maps both newline forms to `"enter"`; `"return"` appears only in `WINDOWS_KEYS` (line ~121), which is not consulted by the macro:

```39:44:shards/reader/src/reader/keys.cr
    KEYS = {
      "\t"      => "tab",
      "\n"      => "enter",
      "\r"      => "enter",
      "\e"      => "escape",
      " "       => "space",
```

- `shards/reader/src/term-reader.cr` — the macro validates against `CONTROL_KEYS.values + KEYS.values` and has no `else` branch, so unknown keys are dropped silently:

```430:441:shards/reader/src/term-reader.cr
    macro subscribe(*keys)
      {% valid_keys = (Term::Reader::CONTROL_KEYS.values + Term::Reader::KEYS.values).uniq %}
      {% for key in keys %}
        {% if key.id.symbolize == :keypress %}
          %kp = Term::Reader::HandlerFunc.new { |k, e| self.keypress(k, e); nil }
          Term::Reader.global_handlers[""] << %kp
        {% elsif valid_keys.includes?(key.id.stringify) %}
          %kp{key.id} = Term::Reader::HandlerFunc.new { |k, e| self.key{{ key.id }}; nil }
          Term::Reader.global_handlers[{{ key.id.stringify }}] << %kp{key.id}
        {% end %}
      {% end %}
    end
```

- `shards/prompt/src/prompt/list.cr:67` — the broken subscription (List is the only component that subscribes `:return` without also subscribing `:enter`; `MultiList` inherits it and adds only `:space`):

```67:67:shards/prompt/src/prompt/list.cr
        Term::Reader.subscribe(:keypress, :return, :up, :down, :left, :right, :backspace, :delete)
```

- `List` defines `keyreturn` (line ~191) but no `keyenter`. Every other component defines both (`multi_list.cr:42/50`, `enum_list.cr:120/134`, `slider.cr:109/113`, `expander.cr:58/79`, `autocomplete.cr:151/165`, `file_select.cr:154/185`, `mask_question.cr:23/27`, `multiline.cr:21/25`, `enhanced_confirm.cr:68/98`).
- All `Term::Reader.subscribe` call sites that pass the dead `:return` symbol (verified by `rg -n 'Term::Reader.subscribe' shards/prompt/src shards/reader/src`):
  - `shards/prompt/src/prompt/list.cr:67`
  - `shards/prompt/src/prompt/enum_list.cr:63`
  - `shards/prompt/src/prompt/slider.cr:35`
  - `shards/prompt/src/prompt/expander.cr:42`
  - `shards/prompt/src/prompt/mask_question.cr:12`
  - `shards/prompt/src/prompt/multiline.cr:14`
  - `shards/prompt/src/prompt/file_select.cr:46`
  - `shards/prompt/src/prompt/autocomplete.cr:48`
  - `shards/prompt/src/prompt/enhanced_confirm.cr:39`

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Reader specs | `cd shards/reader && shards install && crystal spec --no-color` | all pass |
| Prompt specs | `cd shards/prompt && shards install && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` | exit 0 |

Note: prompt resolves reader from a local override in `--local` mode. When running prompt specs directly, first check `shards/prompt/shard.override.yml` exists and points `term-reader` at `../reader` (this checkout already has a compatible one); otherwise the spec run will use the released tag and won't see your macro change.

## Scope

**In scope** (the only files you should modify):
- `shards/reader/src/term-reader.cr` (macro only)
- `shards/prompt/src/prompt/list.cr`
- The eight other prompt files listed above (only the `subscribe(...)` argument lists)
- `shards/prompt/spec/prompt_spec.cr` (add regression specs)

**Out of scope** (do NOT touch, even though they look related):
- `global_handlers` lifecycle/leak — that is plan 005. Keep this plan to the macro's validation behavior and the key names.
- `WINDOWS_KEYS` in `keys.cr` — leave the table as-is.
- `keyreturn` method bodies.

## Git workflow

- Two submodules are touched: `shards/reader` and `shards/prompt` (each its own repo). Branch `advisor/003-enter-subscribe` in each. Reader change must be committed first (prompt compiles against it via the local override path).
- Do NOT push either submodule.

## Steps

### Step 1: Make the macro raise on unknown keys

In `shards/reader/src/term-reader.cr`, add an `{% else %}` branch to the macro's inner conditional:

```crystal
{% else %}
  {% raise "Term::Reader.subscribe: unknown key #{key} — valid keys are :keypress plus the values of CONTROL_KEYS/KEYS" %}
{% end %}
```

**Verify**: `cd shards/reader && crystal spec --no-color` → all pass (reader's own `subscribe(:ctrl_d, :ctrl_z)` uses valid names, so nothing breaks in-shard).

### Step 2: Remove the dead `:return` symbol from all nine prompt call sites and add `:enter` to List

- `list.cr:67` becomes:

```crystal
Term::Reader.subscribe(:keypress, :enter, :up, :down, :left, :right, :backspace, :delete)
```

- In the other eight files, delete `:return` from the argument list (they already subscribe `:enter`).

**Verify**: `rg -n ':return' shards/prompt/src` → 0 matches in `subscribe(...)` calls.

### Step 3: Give List a `keyenter`

In `shards/prompt/src/prompt/list.cr`, next to `keyreturn` (~line 191), add:

```crystal
def keyenter
  keyreturn
end
```

(The macro generates `self.keyenter` for an `:enter` subscription; without this, prompt fails to compile — which is the macro doing its new job.)

**Verify**: `cd shards/prompt && crystal spec --no-color` → all pass.

### Step 4: Regression spec

In `shards/prompt/spec/prompt_spec.cr`, add to the `Term::Prompt::List` describe block a spec that drives Enter through the *event system* rather than calling `keyreturn` directly. Pattern (the file already defines `spec_done` and `key_event` helpers):

```crystal
it "marks the list done when the enter key event fires" do
  list = Term::Prompt::List.new(Term::Prompt.new)
  list.choices %w(a b c)
  list.spec_setup_defaults

  Term::Reader.global_handlers["enter"].each &.call("enter", key_event("\r"))
  list.spec_done.should be_true
end
```

(Plan 005 will replace `global_handlers` with instance-scoped handlers and update this spec; that is expected.)

**Verify**: `cd shards/prompt && crystal spec --no-color` → all pass including the new example.

### Step 5: Cross-shard validation

**Verify**: `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` → exit 0.

## Test plan

- New: the Step 4 regression spec (Enter dispatch reaches `List#keyreturn` via the event path).
- Existing prompt specs and reader specs must stay green.
- Deliberate negative check: temporarily add `Term::Reader.subscribe(:bogus_key)` to any prompt class and confirm compilation *fails* with the new macro error; remove it. (Do not commit the temporary line.)

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `rg -n "raise \"Term::Reader.subscribe" shards/reader/src/term-reader.cr` → 1 match
- [ ] `rg -n "subscribe\(.*:return" shards/prompt/src shards/reader/src` → 0 matches
- [ ] `rg -n "def keyenter" shards/prompt/src/prompt/list.cr` → 1 match
- [ ] `cd shards/reader && crystal spec --no-color` exits 0
- [ ] `cd shards/prompt && crystal spec --no-color` exits 0, including the new Enter-dispatch spec
- [ ] `scripts/validate-shards.sh --local --shards reader,prompt --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The macro or `list.cr:67` doesn't match the excerpts (drift).
- After Step 2, prompt fails to compile at a subscribe site for a key *other than* the ones listed here — that's the macro exposing another latent invalid key; report the site rather than silently removing the key.
- Prompt specs fail in components you did not touch.

## Maintenance notes

- Plan 005 rewrites this same macro to register on a reader instance instead of `global_handlers`; the `{% raise %}` validation must be preserved through that rewrite.
- Reviewer: the acceptance test that matters is interactive — run any `shards/prompt/examples` select example in a terminal (after plan 002 lands) and confirm Enter completes the prompt.
