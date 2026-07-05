# Plan 009: Color's setters, operators, inverse, and pretty_print work, and the phantom "Cor" name is gone

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare every excerpt below against
> `shards/color/src/color/color.cr`.

## Status

- **Priority**: P2
- **Effort**: S-M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

`term-color` was ported from the standalone `cor` shard and the port left real bugs behind: `green=` silently corrupts `@red`; all four arithmetic operators compute multiplication *and* don't compile if called; `inverse` returns channel-shifted garbage; `pretty_print` intermittently raises IndexError (successor of open issue crystal-term/color#2); and `to_s`/error messages/doc comments still say "Cor", a dependency that no longer exists. The shard has two trivial specs, so none of this is caught. Color is a leaf dependency of prompt — breakage propagates.

## Current state

All in `shards/color/src/color/color.cr`. The class is `Term::Color`. Current spec suite: `shards/color/spec/cor_spec.cr` (hex construction + a `pretty_inspect` smoke test); spec helper uses stdlib spec. `shard.yml` has no dependencies.

### A. `green=` assigns `@red`

```212:216:shards/color/src/color/color.cr
  # Set the green value for this color
  def green=(value)
    value = validate_color(value)
    @red = value
  end
```

### B. Arithmetic operators: wrong operation + unresolvable `new`

```121:132:shards/color/src/color/color.cr
  {% for operator in ['+', '-', '*', '/'] %}
  def {{ operator.id }}(other : Term::Color)
    arr = self.to_tuple.zip(other.to_tuple).map do |(a, b)|
      num = a * b
      num = 0 if num < 0
      num = 255 if num > 255
      num
    end

    new(arr[0], arr[1], arr[2], arr[3])
  end
  {% end %}
```

Two defects: `a * b` should be `a {{ operator.id }} b`, and bare `new` inside an instance method doesn't resolve (needs `Term::Color.new`). Nothing in the repo calls these, so the compiler never noticed. Also consider `/` by zero: clamp semantics — guard `b == 0` for `/` by returning 0 for that channel (document the choice in a comment).

### C. `hex_string` ignores `alpha`, breaking `inverse`

```134:142:shards/color/src/color/color.cr
  # Outputs this `Cor` instance as a `hex` string.
  def hex_string(prefix = false, alpha = false, upcase = false)
    hex = String.build do |str|
      str << "#" if prefix
      str << [@red, @green, @blue].map { |i| sprintf("%02x", i) }.join
    end
    ...
```

```241:246:shards/color/src/color/color.cr
  # Returns a new `Cor` that's the inverse of self.
  def inverse
    inverted = hex_string(alpha: true).to_i(16) ^ 0x00ffffff
    inverted = sprintf("%08x", inverted)
    Term::Color.new(inverted)
  end
```

With alpha unhonored, `inverse` XORs a 6-digit value then zero-pads to 8 digits, shifting all channels one byte: inverse of `(255,136,0)` yields `(0,0,119)` instead of `(0,119,255)`. Fix `hex_string` to append `sprintf("%02x", @alpha)` when `alpha` is true, and make `inverse` operate on RGB only while preserving alpha: invert as `0xffffff ^ rgb`, rebuild via `Term::Color.new(red: ..., green: ..., blue: ..., alpha: @alpha)` — read the available constructors at the top of the file first and use whichever exists (there is a hex-string constructor and a per-channel one; check exact signatures around lines 20-70).

### D. `pretty_print` random IndexError

```353:364:shards/color/src/color/color.cr
  # Pretty print (it's a rainbow!)
  def pretty_print(pp)
    rainbow = ->(string : String) do
      color_hash = Colors::COLORS.to_a
      colors = 0.upto(string.size - 1).to_a.map { |i| color_hash[i + rand(0..20)][0] }
      string.split("").map_with_index do |c, i|
        Term::Color.truecolor_string(c.to_s, colors[i])
      end.join
    end

    pp.text(rainbow.call("#<Cor: @red: #{@red}, @green: #{green}, @blue: #{blue}, @alpha: #{@alpha}>"))
  end
```

`color_hash[i + rand(0..20)]` indexes past the end for long strings/unlucky rolls. Fix: `color_hash[(i + rand(0..20)) % color_hash.size][0]`.

### E. "Cor" strings and docs

- `to_s` (lines 348-351) returns `"Cor{...}"` → change to `"Term::Color(...)"` format: `"Term::Color{#{@red}, #{@green}, #{@blue}, #{@alpha}}"` (note the current body also calls the `blue` getter inconsistently — use ivars uniformly).
- The `pretty_print` string `#<Cor: ...>` → `#<Term::Color: ...>` (and use `@green` now that the getter bug is fixed — the current call to `green` was reading the *getter* while `green=` wrote `@red`).
- Error message at line 67: `"the color #{color} has not been defined in \`Cor\`"` → reference `Term::Color::Colors::COLORS`.
- Doc comments mentioning `Cor` (15+ occurrences: lines 22, 33, 65, 71, 92, 111, 116, 134, 144, 163, 241, 328, 333, 338 area) → say `Term::Color`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Install | `cd shards/color && shards install` | exit 0 (no deps; instant) |
| Specs | `cd shards/color && crystal spec --no-color` | all pass |
| Compile | `cd shards/color && crystal build --no-codegen src/term-color.cr` | exit 0 |
| Cross-shard | `scripts/validate-shards.sh --local --shards color,prompt --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/color/src/color/color.cr`
- `shards/color/spec/` (new spec file `color_spec.cr`; keep `cor_spec.cr`'s regression examples, renaming the file to match if you touch it)

**Out of scope**:
- `support.cr`, `mode.cr`, `env.cr` (plan 013 wires those), `string.cr`, `colors.cr` contents.
- Public constructor signatures — do not change them.

## Git workflow

- Inside `shards/color` submodule, branch `advisor/009-color-bugs`, one commit per lettered item. Do NOT push.

## Steps

### Step 1 (A): Fix `green=`

**Verify**: spec — set `green=` on a color, `red` unchanged, `green` updated.

### Step 2 (B): Fix the operator macro

Use `a {{ operator.id }} b` and `Term::Color.new(...)`; guard division by zero. Add specs that *call all four operators* (this is what forces the compiler to check them).

**Verify**: `crystal spec --no-color` → operator specs pass: e.g. `(Color.new(100,100,100,255) + Color.new(200,200,200,0))` clamps to 255s; `-` floors at 0; `/` by a zero-channel color doesn't raise.

### Step 3 (C): `hex_string` alpha + `inverse`

**Verify**: specs — `hex_string(alpha: true)` on `(255,136,0,255)` ends with `"ff"` and has length 8; `inverse` of `(255,136,0)` is `(0,119,255)` with alpha preserved.

### Step 4 (D): `pretty_print` bounds

**Verify**: spec — `pretty_inspect` called 50 times in a loop raises nothing (exercises the random offset).

### Step 5 (E): Cor → Term::Color sweep

**Verify**: `rg -n "Cor" shards/color/src` → 0 matches. `to_s` spec asserts the new format.

### Step 6: Cross-validate

**Verify**: `scripts/validate-shards.sh --local --shards color,prompt --skip-examples` → exit 0.

## Test plan

New `shards/color/spec/color_spec.cr`, table-driven where natural: setters (all four channels), four operators, `hex_string` variants (prefix/alpha/upcase), `rgb_string`, `inverse` known-answer tests, `to_s`, repeated `pretty_inspect`. Model file structure on the existing `cor_spec.cr`.

## Done criteria

- [ ] `rg -n "Cor" shards/color/src` → 0 matches
- [ ] `rg -n "@red = value" shards/color/src/color/color.cr` → 1 match (inside `red=` only)
- [ ] Operator, inverse, hex_string, and pretty_print specs exist and pass
- [ ] `cd shards/color && crystal spec --no-color` exits 0 with ≥ 12 examples
- [ ] `scripts/validate-shards.sh --local --shards color,prompt --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Constructor signatures around lines 20-70 don't offer a way to build from channels + alpha (Step 3 assumption).
- Anything in `shards/prompt` or elsewhere depends on the old `to_s` format (`rg -n '"Cor\{' shards/ --glob '!lib'` first).
- Fixing the operators reveals `to_tuple` ordering issues (alpha position) that make the clamp logic wrong — report rather than guessing channel order.

## Maintenance notes

- After landing, comment on crystal-term/color#2: the `Cor` constant reference is gone as of v1.0.0 and the residual `pretty_print` IndexError is fixed here (operator action; needs `gh`).
- Plan 013 (color support detection) builds on a correct `truecolor_string`; no interaction with these fixes expected.
- Release note: `to_s` output format changed.
