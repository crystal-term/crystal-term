# Repository Guidelines

## Project Structure & Modules
- Root is a monorepo for Crystal (>= 1.0) terminal libraries.
- Modules live in subfolders under `shards/`: `shards/color/`, `shards/cursor/`, `shards/reader/`, `shards/screen/`, `shards/spinner/`, `shards/progress/`, `shards/prompt/`, `shards/terminfo/`.
- Each module contains `src/` (library code), `spec/` (tests), `examples/` (runnable demos), `assets/` (images), and its own `shard.yml`.
- Root `shard.yml` coordinates versions; build/test inside each module directory.

## Build, Test, and Development
- Install deps (per module): `cd shards/cursor && shards install`
- Run tests (Spectator): `cd shards/cursor && crystal spec`
- Run an example: `cd shards/spinner && crystal run examples/basic.cr`
- Format code: `crystal tool format` or `crystal tool format src/ spec/`
- Local development (root-managed):
  - Install dependencies at the repo root: `shards install`
  - Run tests for a module from the root: `crystal spec shards/<module>/spec`
  - Run an example from the root: `crystal run shards/<module>/examples/<file>.cr`

## Coding Style & Naming
- Indentation: 2 spaces; UTF‑8 files; no tabs.
- Naming: Types/Modules `CamelCase` (e.g., `Term::Cursor`), methods/variables `snake_case`, constants `UPPER_SNAKE`.
- Files: one type per file where practical; file names `snake_case.cr` under `src/` mirroring namespace (e.g., `src/reader/key_event.cr`).
- Prefer small, pure functions; keep IO at edges; avoid global state.

## Testing Guidelines
- Framework: Spectator (`require "spectator"`).
- Location: `spec/` with files ending in `*_spec.cr`; organize by `unit/`, `integration/`, `regression/` as used.
- Write specs for new behavior and bug fixes; cover edge cases (e.g., terminal size, Windows/Unix differences).
- Run: `crystal spec` in the affected module; ensure examples still run.

## Commit & Pull Requests
- Messages: concise, imperative mood; optional scope (e.g., `cursor:`). Example: `progress: fix bar overflow on small widths`.
- One logical change per commit when possible.
- PRs: include description, rationale, module(s) touched, before/after behavior, and test coverage. Link issues (e.g., `Fixes #123`). Attach screenshots/terminal output for visual changes.
- Keep version bumps coordinated at the root; do not publish per‑module versions in PRs unless maintainers request.

## Tips & Notes
- Cross‑platform: `shards/terminfo/` and `shards/screen/` include Windows support; guard OS‑specific code.
- Performance matters in TTY flows—avoid unnecessary allocations in hot paths.
