# Plan 010: Cursor emits correct CUP coordinates; screen and terminfo survive odd environments and restore the terminal

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare every excerpt below against live code in
> `shards/cursor/src/`, `shards/screen/src/`, `shards/terminfo/src/`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED for the `move_to` fix (callers may have compensated); LOW for the rest
- **Depends on**: none
- **Category**: bug / security-hardening
- **Planned at**: commit `912c211` (root), 2026-07-04

## Why this matters

Five verified defects across the three low-level shards: `Cursor.move_to(row:, column:)` emits the ANSI CUP sequence transposed, so named-argument callers position the cursor at swapped coordinates; `Screen.size_from_ansicon` returns `{cols, rows}` while every other source returns `{rows, cols}`, and raises on malformed `ANSICON` values; terminfo's path table dereferences `ENV["HOME"]` at constant-initialization time, crashing any HOME-less daemon/container on first use; terminfo's raw-mode helpers claim to save termios state but restore a hardcoded guess; and terminfo's file lookup joins unsanitized `TERM` into filesystem paths — harmless today (the parser is a stub) but a traversal primitive the moment parsing is implemented.

## Current state

### A. `shards/cursor/src/term-cursor.cr:53-58` — CUP is `ESC[<row>;<col>H`, this emits column first:

```52:58:shards/cursor/src/term-cursor.cr
    # Set the cursor absolute position
    def move_to(row : Int32? = nil, column : Int32? = nil) : String
      return CSI + "H" if row.nil? && column.nil?
      row = row.try(&.abs) || 0
      column = column.try(&.abs) || 0
      CSI + "#{column + 1};#{row + 1}H"
    end
```

Callers to audit before fixing (run `rg -n "move_to" shards --glob '!lib'`): if any call site passes swapped values to compensate, fix the call site in the same change and list it in the report.

### B. `shards/screen/src/term-screen.cr:115-121` — transposed return + raising `to_i`:

```115:121:shards/screen/src/term-screen.cr
    # Detect terminal size from Windows ANSICON
    def size_from_ansicon
      return unless ENV["ANSICON"]?.to_s =~ /\((.*)x(.*)\)/

      rows, cols = [$2, $1].map(&.to_i)
      {cols, rows}
    end
```

Every other source (`size_from_ioctl`, `size_from_tput`, `size_from_stty`, `size_from_env`, `DEFAULT_SIZE = {27, 80}`) returns `{rows, cols}`. Fix: return `{rows, cols}`, and use `.to_i?` with a nil-guard so a malformed `ANSICON` yields `nil` (letting the chain fall through) instead of raising. Note this method also reads `ENV` directly while the rest of the module uses the `env` class property (line 44) — switch to `env["ANSICON"]?` for consistency and testability.

### C. `shards/terminfo/src/terminfo/database.cr:8-16` — `ENV["HOME"]` raises `KeyError` when unset:

```8:16:shards/terminfo/src/terminfo/database.cr
      TERMINFO_PATHS = [
        ENV["TERMINFO"]?,
        "#{ENV["HOME"]}/.terminfo",
        "/etc/terminfo",
        ...
      ].compact
```

Fix: `ENV["HOME"]?.try { |home| "#{home}/.terminfo" },` (stays compatible with the `.compact`).

### D. `shards/terminfo/src/terminfo/modes.cr:27-54` — no state actually saved:

```27:40:shards/terminfo/src/terminfo/modes.cr
      # Enable raw mode (disable echo, canonical mode, etc.)
      def enable_raw_mode(io = STDOUT)
        return unless io.tty?

        {% if flag?(:unix) || flag?(:linux) %}
          # Save current termios settings
          system("stty -echo -icanon min 1 time 0")
          ...
```

`disable_raw_mode` runs a hardcoded `system("stty echo icanon")`, which neither undoes `min 1 time 0` nor restores whatever settings the user had. Fix: capture `stty -g` output before changing and restore that exact state:

```crystal
@@saved_stty : String? = nil

def enable_raw_mode(io = STDOUT)
  return unless io.tty?
  {% if flag?(:unix) || flag?(:linux) %}
    @@saved_stty = `stty -g 2> /dev/null`.chomp.presence
    system("stty -echo -icanon min 1 time 0")
    ...
end

def disable_raw_mode(io = STDOUT)
  return unless io.tty?
  {% if flag?(:unix) || flag?(:linux) %}
    if saved = @@saved_stty
      system("stty #{saved}")
      @@saved_stty = nil
    else
      system("stty echo icanon")
    end
    ...
end
```

(`stty -g` output is a machine-readable settings string designed for exactly this round-trip; it contains only `[0-9a-f:,]` characters, so interpolation is safe — assert that with a regex guard `saved =~ /\A[0-9a-fx:,]+\z/i` before interpolating, falling back to the hardcoded restore otherwise.)

### E. `shards/terminfo/src/terminfo/database.cr:120-137` — unsanitized `TERM` in path join:

```120:131:shards/terminfo/src/terminfo/database.cr
      private def find_terminfo_file(term : String) : Entry?
        return nil if term.empty?

        # Terminfo files are stored as /path/to/terminfo/t/term
        # where 't' is the first character of the term name
        first_char = term[0]

        TERMINFO_PATHS.each do |path|
          file_path = File.join(path, first_char.to_s, term)
          if File.exists?(file_path)
```

Add at the top: `return nil if term.includes?('/') || term.includes?("..")` (the same normalization ncurses applies).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Cursor specs | `cd shards/cursor && shards install && crystal spec --no-color` | all pass |
| Screen specs | `cd shards/screen && shards install && crystal spec --no-color` | all pass |
| Terminfo specs | `cd shards/terminfo && shards install && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --skip-examples` | exit 0 |

Note: cursor and screen specs use **Spectator** (`expect(...).to eq(...)` DSL); terminfo uses stdlib spec. Match each shard's existing style.

## Scope

**In scope**:
- `shards/cursor/src/term-cursor.cr` (`move_to` only) + its spec
- `shards/screen/src/term-screen.cr` (`size_from_ansicon` only) + its spec
- `shards/terminfo/src/terminfo/database.cr` (TERMINFO_PATHS + find_terminfo_file guard) + spec
- `shards/terminfo/src/terminfo/modes.cr` (raw-mode save/restore) + spec
- Compensating `move_to` call sites elsewhere in `shards/*/src`, if the audit finds any

**Out of scope**:
- The duplicated escape helpers in `terminfo/sequences.cr` (plan 016), terminfo's stub parser itself (documented debt), screen's detection-chain caching (plan 012), everything in reader/prompt.

## Git workflow

- Three submodules: `shards/cursor` (branch `advisor/010-move-to`), `shards/screen` (`advisor/010-ansicon`), `shards/terminfo` (`advisor/010-env-and-modes`). Independent commits; do NOT push.

## Steps

### Step 1 (A): Audit `move_to` callers, then fix the emission order

`rg -n "move_to" shards --glob '!lib'` — record every call site and whether it uses named or positional args. Then change the last line to `CSI + "#{row + 1};#{column + 1}H"`. Fix compensating call sites if found.

**Verify**: cursor spec — `Term::Cursor.move_to(row: 5, column: 10)` returns `"\e[6;11H"`; `move_to` with no args returns `"\e[H"`. Suite green.

### Step 2 (B): Fix `size_from_ansicon`

Target shape:

```crystal
def size_from_ansicon
  return unless env["ANSICON"]?.to_s =~ /\((.*)x(.*)\)/

  rows = $2.to_i?
  cols = $1.to_i?
  return unless rows && cols
  {rows, cols}
end
```

**Verify**: screen spec — with `Term::Screen.env = {"ANSICON" => "199x9999 (199x50)"}`, `size_from_ansicon` returns `{50, 199}`; with `"garbage"` it returns nil (no raise). Restore `Term::Screen.env` after each example.

### Step 3 (C): HOME-safe TERMINFO_PATHS

**Verify**: `rg -n 'ENV\["HOME"\]' shards/terminfo/src` shows only the nil-safe form. Spec: hard to unset HOME in-process for a constant — instead add a spec asserting `Term::Terminfo::Database::TERMINFO_PATHS` is an `Array(String)` and compilation/type-check passes; note in the commit that the KeyError-at-load is eliminated by construction.

### Step 4 (D): stty save/restore

Apply the Current-state design including the settings-string regex guard.

**Verify**: terminfo suite green; `rg -n "stty -g" shards/terminfo/src/terminfo/modes.cr` → 1 match. (Real-TTY round-trip is a manual reviewer step; specs run non-TTY where these methods no-op.)

### Step 5 (E): TERM sanitization

**Verify**: spec — `Database.get_entry("../../etc/passwd")` (or the module's public lookup API; read `database.cr:100-120` for the entry point) returns the generic fallback entry without probing outside terminfo dirs; direct spec on the private method via a test wrapper is fine, matching the shard's existing spec conventions.

### Step 6: Cross-validate

**Verify**: `scripts/validate-shards.sh --local --skip-examples` → exit 0.

## Test plan

Per-step specs above. Cursor/screen: extend existing Spectator spec files (`shards/cursor/spec/unit/cursor_spec.cr`, `shards/screen/spec/unit/width_height_spec.cr` or a new sibling). Terminfo: stdlib-spec files under `shards/terminfo/spec/`.

## Done criteria

- [ ] `rg -n '"\#\{column \+ 1\};\#\{row \+ 1\}H"' shards/cursor/src` → 0 matches
- [ ] Cursor spec asserts `"\e[6;11H"` for `(row: 5, column: 10)` and passes
- [ ] Screen ANSICON specs (valid → `{rows, cols}`, garbage → nil) pass
- [ ] `rg -n 'ENV\["HOME"\]\?' shards/terminfo/src/terminfo/database.cr` → 1 match
- [ ] `rg -n 'includes\?\(.\.\.\.?' shards/terminfo/src/terminfo/database.cr` → traversal guard present (or equivalent grep for the guard line)
- [ ] All three shards' spec suites exit 0
- [ ] `scripts/validate-shards.sh --local --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The `move_to` audit finds compensating call sites in shards other than cursor — fixing them crosses submodule boundaries; list them all first, then proceed only if the fixes are mechanical swaps.
- Cursor's existing Spectator specs assert the transposed emission (they encode the bug) AND external consumers might rely on it — flag the compatibility question in the report; the plan's position is: fix to match the parameter names, note in release notes.
- `stty -g` output on the target platform fails the character-class guard (platform variance) — report the observed string format.

## Maintenance notes

- Release notes must call out `move_to`'s behavior change for named-argument users.
- Plan 016 consolidates cursor/terminfo escape helpers; it must pick up the *fixed* `move_to` as canonical.
- Plan 019 (Windows CI) will exercise `size_from_ansicon` on real Windows runners; the `{rows, cols}` convention fixed here is what its assertions should use.
- The terminfo parser stub (returns nil after finding a file) is known, documented debt — deliberately not addressed here.
