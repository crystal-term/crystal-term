# Plan 030: `term-vt` input modes — mouse protocols, bracketed paste, focus reporting

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. Honor STOP conditions. Update the status row in
> `plans/README.md` when done.
>
> **Drift check (run first)**: vt at 0.3.x+ with Session and CLI present
> (`ls shards/vt/src/vt/session.cr shards/vt/src/cli/tape.cr`), no mouse
> support yet (`rg -n "mouse|1006|2004" shards/vt/src` → 0 matches in
> `src/`).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (new public Session/tape surface — mouse method names, the
  `click`/`paste` directives, and the mode getters become contracts)
- **Depends on**: — (independent of 029/031; touches `set_private_modes`,
  which 029 also edits — small, mergeable overlap)
- **Category**: vt hardening (README "Unsupported" burn-down)
- **Planned at**: root commit `d9f941c`, vt submodule `v0.3.0` (`5c72959`),
  2026-07-06

## Why this matters

"Mouse protocols" is on the vt README Unsupported list, and it is two
distinct gaps:

1. **Tracking**: when an app under test enables mouse reporting
   (`CSI ?1000h` etc.), the sequences land in `screen.unhandled` noise and
   a test cannot assert "the app turned mouse mode on".
2. **Driving**: there is no way to click a button in a TUI under the
   harness — `Session` can only send keys. fzf, htop, and every
   mouse-aware TUI are untestable beyond keyboard paths.

The same tracking-plus-sender shape covers two adjacent modes that
readline-family programs enable constantly: bracketed paste (`?2004`) and
focus reporting (`?1004`). Folding them in here removes the three loudest
`unhandled` noise sources at once.

## Target design

### Screen: mode tracking (`shards/vt/src/vt/screen.cr`)

Handle these in `set_private_modes` instead of `record_unhandled`, storing
state that `copy_from` must also carry (plus protected getters, as with
every Screen ivar):

- Tracking modes `?9` (X10), `?1000` (normal), `?1002` (button-event),
  `?1003` (any-event) — expose as
  `screen.mouse_tracking : MouseTracking` with
  `enum MouseTracking; Off; X10; Normal; Button; Any; end`. Setting one
  replaces the previous; resetting the active one returns to `Off`
  (resetting an inactive one is a no-op — xterm behavior).
- Encoding modes `?1005` (UTF-8), `?1006` (SGR), `?1015` (urxvt) — expose
  as `screen.mouse_encoding : MouseEncoding`
  (`Default`/`Utf8`/`Sgr`/`Urxvt`); last one set wins, reset falls back to
  `Default`.
- `?1004` → `screen.focus_reporting? : Bool`.
- `?2004` → `screen.bracketed_paste? : Bool`.

`ESC c` resets all of these via `initialize`. No grid behavior changes.

### Session: input senders (`shards/vt/src/vt/session.cr`)

All coordinates 0-based (matching `screen.cursor` / `screen.find`),
encoded 1-based on the wire. Buttons: `:left`, `:middle`, `:right`,
`:wheel_up`, `:wheel_down`.

- `mouse_down(row, col, button = :left)` / `mouse_up(row, col, button = :left)`
- `click(row, col, button = :left)` — down + up.
- `mouse_move(row, col, button = :left)` — motion event (only meaningful
  under `Button`/`Any` tracking; encode with the motion flag, bit 32).
- `scroll(row, col, direction)` — wheel press events (buttons 64/65).
- `paste(text)` — wraps in `\e[200~…\e[201~` when the live screen has
  `bracketed_paste?`, else sends raw.
- `focus(focused : Bool)` — sends `\e[I`/`\e[O`.

Encoding choice reads the **live** screen state under the existing mutex
(not the `screen` dup): SGR (`\e[<b;x;yM` / trailing `m` for release) when
`mouse_encoding.sgr?`, else legacy X10 bytes (`\e[M` + three
`value + 32` bytes, coordinates capped at 223). Fail loud, matching the
harness ethos: raise `ArgumentError` when `mouse_tracking.off?` (for mouse
senders) or `focus_reporting?` is false (for `focus`) — a test clicking
into an app that never enabled the mode is a test bug. `paste` is the
exception: it degrades to raw send because plain paste is always
meaningful.

### CLI tape directives (`shards/vt/src/cli/tape.cr`, runner)

- `click ROW COL [left|middle|right]` → `Session#click`.
- `paste "TEXT"` → `Session#paste`.
- Malformed args → exit 2 with line number, like every other directive.
  An `ArgumentError` from the senders at run time → exit 1 with snapshot.

### Docs + version

- README: remove "Mouse protocols" from Unsupported; document the mode
  getters, the Session senders (with the fail-loud rule), the two new tape
  directives, and add the tracked private modes to "Supported Sequences".
- `shard.yml`: bump to `0.4.0` unless this wave already bumped it.

## Specs

- `spec/screen/input_modes_spec.cr` (pure, no PTY): each mode
  set/reset/replacement, `unhandled` no longer collects them, `dup`
  carries the state.
- `spec/mouse_encoding_spec.cr`: if encoding lives in a small pure helper
  (recommended — e.g. `Term::VT::Mouse.encode(...) : Bytes` used by
  Session), unit-test SGR and X10 byte-for-byte, including the 223 cap and
  release encoding.
- Session PTY-gated specs (mirror the patterns in `spec/session_spec.cr` /
  `spec/query_spec.cr`, pending when PTY unavailable): child enables SGR
  mouse then `od`s stdin back to the screen
  (`sh -c 'printf "\e[?1000h\e[?1006h"; dd bs=1 count=9 2>/dev/null | od -An -c'`),
  assert the encoded click appears; `paste` with `?2004h` shows the
  bracket markers; `click` against a child that never enabled mouse raises.
- Tape e2e: one tape using `click`/`paste` (compiled-binary spec, mirrors
  `spec/cli_spec.cr`).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Specs | `cd shards/vt && crystal spec --no-color` | pass |
| Format | `cd shards/vt && crystal tool format --check src spec` | no diff |
| Build CLI | `cd shards/vt && shards build --no-color` | `bin/term-vt` exists |
| Harness | `scripts/validate-shards.sh --local --shards vt --skip-examples` | exit 0 |

## Steps

1. Screen mode tracking + `copy_from` + pure specs.
2. Encoding helper + unit specs (locks the wire format).
3. Session senders + PTY-gated specs.
4. Tape `click`/`paste` + parser rejections + e2e tape spec.
5. README, version, full verification table, `plans/README.md` row.

## STOP conditions

- You want Screen to *interpret* incoming mouse sequences from the child
  (apps echoing mouse bytes): STOP — Screen consumes app *output*; mouse
  events only flow child-ward from Session. Report the confusion instead.
- Highlight tracking (`?1001`) or DEC locator mode shows up as needed:
  STOP — leave in `unhandled`, note in README.
- PTY specs flake across 5 consecutive runs: report with snapshots.

## Git workflow

`shards/vt` is a git submodule (`crystal-term/vt`), currently detached at
`v0.3.0`. Work there first:
`git -C shards/vt fetch origin && git -C shards/vt checkout -b watzon/plan-030 origin/main`,
conventional commits. Then in the root repo branch from `main`, commit the
submodule pointer bump + `plans/README.md` row. Push nothing without
operator instruction.

Coordination: 029 also edits `set_private_modes`; overlap is a few `when`
arms — whichever merges second rebases trivially.
