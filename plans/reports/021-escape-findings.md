# Plan 021 Escape Key Findings

## Current Behavior

Pipe-based characterization before the prototype showed the reader's escape path
depends on the next read returning or the writer closing. On this macOS/Crystal
1.20.3 setup, `IO::FileDescriptor#read_char` can still wait for readability even
after `blocking = false`, so bare Escape has no bounded latency without an
explicit timeout.

| Case | Input timing | Before prototype | After prototype |
| --- | --- | --- | --- |
| Bare Escape | `"\e"` then writer remains open | Waits until the writer closes | Returns `"\e"` after the 50ms timeout |
| Full up arrow | `"\e[A"` in one write | Returns `"\e[A"` | Returns `"\e[A"` |
| Split up arrow | `"\e"`, then `"[A"` after 5ms | Returns `"\e[A"` on this platform, but latency is unbounded by reader logic | Returns `"\e[A"` because the second byte arrives before timeout |
| Double Escape | `"\e\e"` in one write | Returns `"\e\e"` after the final continuation read resolves | Returns `"\e\e"` after the final 50ms timeout |

## Timeout Choice

`Term::Reader::Console::TIMEOUT` now uses `50.milliseconds` and is applied while
reading bytes immediately after an initial Escape byte. That matches the
50-100ms precedent used by terminal readers and tmux-style escape
disambiguation, while keeping perceived Escape latency low enough for cancel
flows.

The implementation keeps `get_codes`' public behavior but replaces recursive
escape accumulation with a one-byte continuation loop. Each byte after an
initial Escape is read with `IO::FileDescriptor#read_timeout`, the prior timeout
is restored in `ensure`, and `IO::TimeoutError` confirms that the keypress was a
bare Escape. Non-file-descriptor IO keeps the existing immediate behavior.

One platform-specific detail mattered during the spike: on this macOS build,
rewriting the descriptor's blocking flag after setting `read_timeout` neutralized
the timeout. `Console#get_char` now avoids redundant blocking-mode writes so the
timeout survives into the continuation read.

## Manual Terminal Check

`shards/reader/examples/escape_check.cr` was added for operator testing in a real
TTY. The expected manual observations are:

- Pressing Escape prints `escape: "\e"` after about 50ms.
- Pressing Up/Down prints `up: "\e[A"` and `down: "\e[B"` immediately.
- Pressing ordinary letters prints their key name or inspected character.
- Pressing `q` exits.

This execution environment did not provide an interactive TTY for manual key
presses, so the real-terminal step remains an operator verification item.

## Latency And Risk

Bare Escape now intentionally waits up to 50ms before being emitted. That is the
cost of distinguishing a standalone Escape key from the prefix of an ANSI escape
sequence. Arrow/function-key reads should not pay that timeout when the sequence
bytes arrive in the same burst, and split bursts under 50ms are preserved.

The main regression risk is terminals or multiplexers that delay continuation
bytes by more than 50ms; those sequences will be reported as Escape followed by
later literal bytes. If this prototype is merged, expose the timeout as a reader
option so users can tune low-latency or high-latency environments.

## Recommendation

Merge after review. The prototype is small, uses Crystal's file descriptor
timeout directly, restores prior timeout state, and the pipe spec covers bare
Escape, complete arrow sequences, split-burst arrow sequences, double Escape,
and a fast-sequence no-regression case.
