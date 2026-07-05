# Plan 016: One canonical home each for escape sequences, ANSI stripping, size detection, and key tables

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: plans 010 and 012 should have landed (they fix
> bugs in code this plan consolidates). Compare each excerpt/claim below with
> live code before starting.

## Status

- **Priority**: P3
- **Effort**: M-L
- **Risk**: MED (output-sequence changes can break reader/prompt screen-line math)
- **Depends on**: 010, 012; do after the bug-fix plans, not before
- **Category**: tech-debt
- **Planned at**: commit `912c211`, 2026-07-04

## Why this matters

The tty-* port re-implemented the same terminal vocabulary in five shards. Cursor movement/clearing exists in both `term-cursor` and `terminfo/sequences.cr` (already drifted: different save/restore sequences, different clear-line behavior). Three incompatible strip-ANSI regexes live in color, terminfo, and reader. Terminal-size detection exists in both `term-screen` (ioctl-first, now cached) and `terminfo/size.cr` (whose Unix path is a stub that always shells out, with the opposite tuple convention). Keyboard escape-sequence tables exist in both `reader/keys.cr` (load-bearing) and `terminfo/keyboard.cr` (no consumer in the family). Every fix in this domain currently needs to be applied N times, and isn't.

## Current state

Duplication inventory (verify each with the given command):

1. **Escape/cursor sequences** — `shards/cursor/src/term-cursor.cr` (canonical: used by reader, spinner, prompt, progress) vs `shards/terminfo/src/terminfo/sequences.cr` (~281 lines; overlapping `CSI`/`ESC` constants, cursor movement, save/restore, show/hide, clears). Check drift: cursor's `save` uses `ESC 7`-style vs sequences' CSI variant; cursor's `clear_line` includes a column reset, sequences' doesn't. `rg -n "def (cursor_)?(save|restore|clear_line|move)" shards/cursor/src shards/terminfo/src/terminfo/sequences.cr`
2. **Strip-ANSI** — three regexes with different coverage:
   - `shards/color/src/color/color.cr:8` `ANSI_COLOR_REGEXP` (color codes only — arguably correct for color's documented "only color codes" contract)
   - `shards/terminfo/src/terminfo/sequences.cr` (~line 270) `strip_ansi` (CSI only)
   - `shards/reader/src/reader/line.cr:4` `ANSI_MATCHER` (broadest, matches stray brackets)
3. **Size detection** — `shards/screen/src/term-screen.cr` (canonical, cached after plan 012) vs `shards/terminfo/src/terminfo/size.cr` (`unix_size` stub returns nil → always subprocess; returns `NamedTuple(width:, height:)` — opposite convention).
4. **Key tables** — `shards/reader/src/reader/keys.cr` (`CONTROL_KEYS`/`KEYS`, string-keyed; the prompt subscribe macro validates against it) vs `shards/terminfo/src/terminfo/keyboard.cr` (`Key` enum + `KEY_SEQUENCES`; `rg -n "Keyboard|KEY_SEQUENCES" shards/*/src --glob '!lib'` to confirm no family consumer).

Constraint that shapes the design: **terminfo is a leaf shard** (no family dependencies), and cursor/screen are leaves too. Making terminfo depend on cursor+screen adds edges to the release graph — acceptable, but it must be explicit and `docs/release-validation.md` + the harness's dependency table must be updated to match.

## Target design

- **Sequences**: `term-cursor` is canonical. `Terminfo::Sequences` keeps its public API but delegates every overlapping method to `Term::Cursor` (`def cursor_save; Term::Cursor.save; end` etc.), keeping only genuinely terminfo-specific sequences (alternate screen, mouse tracking, bracketed paste) local. terminfo gains a dependency on `term-cursor ~> 1.0`.
- **Strip-ANSI**: add `Term::Cursor.strip_ansi(string)` (or a small `Term::ANSI` module inside cursor) with the reader's broad regex *corrected* (match `\e\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]` CSI form plus lone `\e.` two-byte forms; write known-answer specs). Reader's `Line` and terminfo delegate to it. Color's `ANSI_COLOR_REGEXP` stays (different documented contract) but gets a comment pointing at the shared helper.
- **Size**: `terminfo/size.cr` delegates to `Term::Screen.size` and converts to its NamedTuple shape (or is deprecated outright if its API has no external users — decision: delegate, keep API). terminfo gains `term-screen ~> 1.0`.
- **Key tables**: leave reader's as canonical and **delete** `terminfo/keyboard.cr` if `rg` confirms no consumer inside the family and nothing in terminfo's own specs/examples/README exercises it beyond trivially; otherwise leave it and only add a doc comment cross-referencing reader. (Bias to delete-with-evidence; restoring is cheap.)

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Terminfo specs | `cd shards/terminfo && shards install && crystal spec --no-color` | all pass |
| Reader specs | `cd shards/reader && crystal spec --no-color` | all pass |
| Full harness | `scripts/validate-shards.sh --local --skip-examples` | exit 0 |
| Consumer grep | `rg -n "Sequences\.|Keyboard\." shards/*/src shards/*/examples --glob '!lib'` | inventory before deleting anything |

## Scope

**In scope**:
- `shards/terminfo/shard.yml` (add term-cursor, term-screen deps), `sequences.cr`, `size.cr`, `keyboard.cr` (delete or annotate), terminfo specs
- `shards/cursor/src/term-cursor.cr` (add `strip_ansi`), cursor specs
- `shards/reader/src/reader/line.cr` (delegate ANSI_MATCHER usage), reader specs
- `docs/release-validation.md` + `scripts/validate-shards.sh` local-override table (add terminfo's new deps so `--local` writes overrides for it)
- `shards/color/src/color/color.cr` — comment only

**Out of scope**:
- Changing any emitted sequence that consumers currently receive from `Term::Cursor` (cursor is canonical *as-is*, post-plan-010).
- The terminfo capability/database stub, `attributes.cr` color detection (noted in plan 013 maintenance), prompt.

## Git workflow

- Submodules: terminfo, cursor, reader (branches `advisor/016-dedup`); root repo for docs/harness changes. terminfo's shard.yml gains family deps — commit that with the delegation in one commit so terminfo never has a dangling require. Do NOT push.

## Steps

### Step 1: Inventory and decide keyboard.cr

Run the consumer greps. Record results in the commit message. Delete `keyboard.cr` (plus its requires/specs) only if zero non-trivial consumers.

**Verify**: `cd shards/terminfo && crystal spec --no-color` → all pass after deletion.

### Step 2: terminfo depends on cursor + screen; sequences/size delegate

Add to `shards/terminfo/shard.yml`:

```yaml
dependencies:
  term-cursor:
    github: crystal-term/cursor
    version: ~> 1.0.0
  term-screen:
    github: crystal-term/screen
    version: ~> 1.0.0
```

Update `scripts/validate-shards.sh` — `local_dependency_lines` gains a `terminfo)` case writing overrides for `term-cursor`/`term-screen` (mirror the `spinner)` case), and `docs/release-validation.md`'s table + layer text move terminfo out of the leaves layer (it now releases with the middle layer). Rewrite `sequences.cr` overlapping methods as delegations; rewrite `size.cr#get` to wrap `Term::Screen.size` (convert `{rows, cols}` → `{width: cols, height: rows}` — note the tuple order carefully).

**Verify**: `scripts/validate-shards.sh --local --shards terminfo --skip-examples` → exit 0 (proves override plumbing works); terminfo suite green; terminfo size specs updated to the delegated behavior.

### Step 3: Shared strip_ansi in cursor; reader delegates

Add `Term::Cursor.strip_ansi` with known-answer specs (plain text unchanged; `"\e[31mred\e[0m"` → `"red"`; `"\e[2K\e[1;5H"` stripped; lone `"\e7"` stripped; `"[not-an-escape]"` **unchanged** — this last case is where reader's current broad `ANSI_MATCHER` misbehaves). Then point `reader/line.cr`'s sanitize path at it and delete/alias `ANSI_MATCHER`.

**Verify**: cursor suite green with the new specs; reader suite green — if reader's screen-line-count specs fail, the stricter regex changed `Line.sanitize` behavior; investigate each failure individually (expected direction: previously-over-stripped strings now keep literal brackets).

### Step 4: Full harness + docs

**Verify**: `scripts/validate-shards.sh --local --skip-examples` → exit 0; `rg -n "terminfo" docs/release-validation.md` reflects the new dependency layer.

## Test plan

- New: `strip_ansi` known-answer specs (cursor); terminfo delegation specs (sequences methods return identical strings to `Term::Cursor` equivalents; size returns screen-consistent values).
- Regression: full reader + terminfo suites; harness.

## Done criteria

- [ ] terminfo `shard.yml` depends on term-cursor and term-screen; harness writes overrides for terminfo in `--local`
- [ ] `rg -n "def cursor_save|def cursor_restore" shards/terminfo/src/terminfo/sequences.cr` shows delegation (no literal escape strings for overlapping methods)
- [ ] `rg -n "unix_size" shards/terminfo/src` → 0 matches (stub gone)
- [ ] One shared `strip_ansi`; `rg -n "ANSI_MATCHER" shards/reader/src` → 0 matches
- [ ] keyboard.cr deleted or annotated, with grep evidence in the commit message
- [ ] Full harness exits 0; `docs/release-validation.md` updated
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- terminfo's sequences API is consumed externally with semantics that differ from cursor's (the drift cases: save/restore style, clear-line column reset) — delegation would change published behavior; list the differing methods and stop for a decision.
- Reader's line-math specs fail in more than a handful of places after Step 3.
- Adding family deps to terminfo creates a cycle (it shouldn't — cursor/screen depend on nothing).

## Maintenance notes

- After this plan, the rule is: escape sequences live in cursor, size lives in screen, keys live in reader. Reject future PRs that add a fourth copy.
- terminfo's release-layer move (leaf → middle) must be respected in the next release cycle; `docs/release-validation.md` is the source of truth.
- Deferred: making terminfo's `attributes.cr` color heuristic delegate to `Term::Color` (needs plan 013's `enabled?` shipped first).
