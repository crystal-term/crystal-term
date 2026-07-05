# Plan 012: Render loops stop re-detecting terminal size and recompiling regexes every frame

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: compare excerpts against live code in
> `shards/screen/src/term-screen.cr`, `shards/progress/src/progress/`,
> `shards/spinner/src/term-spinner.cr`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (behavior-preserving; stale-width-until-invalidation is the one semantic change)
- **Depends on**: 007 (spinner TestIO makes the spinner part verifiable; progress parts are independent)
- **Category**: perf
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

`Term::Screen.size` runs its full detection chain on every call — up to three ioctls, and on non-tty streams it shells out to `tput` (twice) and `stty`. The progress bar calls `Term::Screen.width` from `clear_line` **and** `calculate_bar_width` on every `advance`; prompt's List and reader's Line call it per keystroke. Worst case that's multiple subprocess spawns per frame, which dominates the entire render cost. Independently, the token substitution in progress and spinner rebuilds and recompiles a regex per token per frame (`gsub(/:#{key}/, value)`) — ~15 regex compilations plus intermediate strings per bar tick. All of it is fixable without observable output changes.

## Current state

- `shards/screen/src/term-screen.cr:47-66` — the uncached chain; module is `Term::Screen`, `extend self`, has `class_property env` / `class_property output` already:

```47:66:shards/screen/src/term-screen.cr
    # Get terminal dimensions (rows, columns)
    def size
      {% if flag?(:win32) || flag?(:windows) %}
        check_size(size_from_win_api) ||
          ...
      {% else %}
        size_from_ioctl(STDIN) ||
          size_from_ioctl(STDOUT) ||
          size_from_ioctl(STDERR) ||
          check_size(size_from_tput) ||
          check_size(size_from_readline) ||
          check_size(size_from_stty) ||
          check_size(size_from_env) ||
          check_size(size_from_ansicon) ||
          check_size(size_from_default) ||
          size_from_default
      {% end %}
    end
```

- `shards/progress/src/progress/bar.cr` — hot-path callers:

```234:239:shards/progress/src/progress/bar.cr
          # Clear the entire terminal line to prevent leftover characters
          terminal_width = Term::Screen.width
          @output.print "\r" + (" " * terminal_width) + "\r"
          @output.flush
```

  and `calculate_bar_width` (lines ~256-268) dups the token hash, re-formats the whole template, and calls `Term::Screen.width` again — per update. The spinner shard already clears lines with the escape sequence instead (`term-spinner.cr:317-319` uses `Term::Cursor.clear_line`).

- `shards/progress/src/progress/formatters.cr:15-21` — per-token regex:

```crystal
      def format(template : String, tokens : Hash(String, String)) : String
        result = template.dup
        tokens.each do |key, value|
          result = result.gsub(/:#{key}/, value)
        end
        result
      end
```

- `shards/spinner/src/term-spinner.cr:378-383` — same pattern per spin frame:

```378:383:shards/spinner/src/term-spinner.cr
    private def replace_tokens(string)
      @tokens.each do |name, val|
        string = string.gsub(/\:#{name}/, val)
      end
      string
    end
```

- `shards/progress/src/progress/multi.cr:201` (approx.) — `template.gsub(/:content/, content)` per line render.
- `Bar#update_tokens` (`bar.cr:176-201` approx.) computes every token (three bar-string renders, four rate strings, ETA, elapsed...) on every advance regardless of which tokens `@format` actually references.

## Target design

1. **Screen cache**: add to `Term::Screen` a memoized size with explicit invalidation and SIGWINCH hookup:

```crystal
@@size_cache : Tuple(Int32, Int32)? = nil
@@winch_installed = false

def size(cached : Bool = true) : Tuple(Int32, Int32)
  if cached
    install_winch_handler
    @@size_cache ||= detect_size
  else
    detect_size
  end
end

def invalidate_size_cache : Nil
  @@size_cache = nil
end

private def detect_size
  # the existing chain, moved verbatim
end

private def install_winch_handler
  return if @@winch_installed
  {% unless flag?(:win32) || flag?(:windows) %}
    Signal::WINCH.trap { @@size_cache = nil }
  {% end %}
  @@winch_installed = true
end
```

  Caution: `Signal::WINCH.trap` replaces any existing handler an application installed. That's an acceptable library trade-off here but must be documented on the method; `size(cached: false)` remains the escape hatch. Keep `width`/`height`/etc. delegating to `size` (now cached).

2. **Progress `clear_line`**: replace the space-padding with the erase-line escape, dropping the width call: `@output.print "\r\e[2K"` (or `Term::Cursor.clear_line` — progress already depends on term-cursor).
3. **String-pattern gsub**: in all three token loops, `gsub(":#{key}", value)` (string pattern — no regex compilation, and token names can no longer be misread as regex metacharacters). Byte-identical output for existing token names.
4. **Token gating**: in `Bar#initialize` (and wherever `@format` is assigned), precompute `@format_tokens : Set(String)` by scanning the format string for `:name` occurrences (`@format.scan(/:(\w+)/)`); in `update_tokens`, skip computing any token not in the set. `calculate_bar_width`: compute the static (non-bar) width once per format/total change instead of re-formatting the whole template each tick — acceptable minimal version: keep the re-format but reuse the cached `Term::Screen.width`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Screen specs | `cd shards/screen && crystal spec --no-color` | all pass |
| Progress specs | `cd shards/progress && crystal spec --no-color` | all pass |
| Spinner specs | `cd shards/spinner && crystal spec --no-color` | all pass |
| Cross-shard | `scripts/validate-shards.sh --local --skip-examples` | exit 0 |

## Scope

**In scope**:
- `shards/screen/src/term-screen.cr` + specs
- `shards/progress/src/progress/bar.cr`, `formatters.cr`, `multi.cr` + specs
- `shards/spinner/src/term-spinner.cr` (`replace_tokens` only) + specs

**Out of scope**:
- Prompt/reader call sites of `Screen.width` — they benefit automatically via the cache; do not edit them.
- The duplicate size implementation in `terminfo/size.cr` (plan 016).
- Progress `update_tokens` refactors beyond gating (no restructuring of the token hash type).

## Git workflow

- `shards/screen` and `shards/spinner` are submodules (branches `advisor/012-size-cache`, `advisor/012-token-gsub`); `shards/progress` is a plain dir committed on a root branch `advisor/012-progress-perf`. Do NOT push.

## Steps

### Step 1: Screen cache + WINCH invalidation

Apply target design item 1. Update screen specs: existing size specs should call `size(cached: false)` or `invalidate_size_cache` in a `before_each` so env-manipulating examples aren't poisoned by the cache. Add specs: two consecutive `size` calls return the same object without re-detection (assert via `Term::Screen.env` mutation between calls being *ignored* when cached, honored after `invalidate_size_cache`).

**Verify**: `cd shards/screen && crystal spec --no-color` → all pass.

### Step 2: Progress clear_line via escape

**Verify**: progress spec (TestIO-based) — `clear_line` output contains `"\e[2K"` and no run of spaces; suite green.

### Step 3: String-pattern gsub in formatters, spinner, multi

**Verify**: `rg -n 'gsub\(/:' shards/progress/src shards/spinner/src` → 0 matches. Formatter spec: format `":current/:total [:bar]"` with tokens renders identically to before (write the expected literal). Spinner spec: token replacement still substitutes `:title` etc.

### Step 4: Token gating in Bar

**Verify**: progress spec — a bar with format `":bar"` only, after `advance`, has computed only the bar token (assert indirectly: specs pass and a spec with format `":current/:total"` renders without bar computation errors). Full progress suite green.

### Step 5: Cross-validate

**Verify**: `scripts/validate-shards.sh --local --skip-examples` → exit 0.

## Test plan

Specs listed per step. The perf claim itself needs no benchmark gate; the correctness gate is byte-identical rendering, which the formatter/bar specs pin with literal expected strings.

## Done criteria

- [ ] `rg -n "size_cache" shards/screen/src/term-screen.cr` → ≥ 2 matches; `Signal::WINCH` handler present (non-Windows)
- [ ] `rg -n '" " \* terminal_width' shards/progress/src` → 0 matches
- [ ] `rg -n 'gsub\(/:' shards/progress/src shards/spinner/src` → 0 matches
- [ ] All three shards' suites exit 0; `scripts/validate-shards.sh --local --skip-examples` exits 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Screen specs depend on per-call re-detection in ways `invalidate_size_cache` can't cleanly handle (pervasive env stubbing) — report before rewriting the spec file wholesale.
- Any format template in the repo relies on regex behavior of token names (e.g. a token name that's a regex metacharacter) — string-pattern gsub would change output; report the template.
- `Signal::WINCH.trap` interferes with reader/prompt specs (signal handling in test env).

## Maintenance notes

- Document on `Term::Screen.size`: cached by default; WINCH invalidates; `cached: false` forces re-detection; the trap replaces prior WINCH handlers.
- If prompt later needs resize-reactive rendering, it should subscribe to WINCH itself and call `invalidate_size_cache` — noted here so nobody re-adds per-frame detection.
- Plan 016 should delete `terminfo/size.cr`'s duplicate chain in favor of this cached one.
