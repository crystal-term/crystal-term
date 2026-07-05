# Cross-shard release validation

This document describes root-level validation for the crystal-term shard
family. It is intended for release checks and local integration checks across
the nested repositories in this checkout.

## Harness

Run all shards against the local checkout:

```sh
scripts/validate-shards.sh --local
```

Run a safe subset:

```sh
scripts/validate-shards.sh --shards color,cursor --skip-examples
```

Run released-mode validation:

```sh
scripts/validate-shards.sh
```

Released-mode validation refuses unmanaged `shard.override.yml` files unless
`--allow-existing-overrides` is passed. This is intentional: released-tag
checks should not silently resolve dependencies from local paths. The current
checkout has a compatible unmanaged `shards/prompt/shard.override.yml`, so use
`--local` for monorepo integration checks or remove that file before a strict
released-mode run.

Clean managed local override files:

```sh
scripts/validate-shards.sh --clean-local-overrides
```

The harness validates shards in this order:

```text
color, cursor, screen, terminfo, reader, spinner, prompt, progress
```

For each selected shard, the harness runs:

1. `shards install`
2. `crystal spec --no-color`
3. `crystal build --no-codegen --no-color <example>` for each
   `examples/**/*.cr`, when the shard has examples

The install step is intentionally sequential. The nested checkouts can share
Crystal and Shards caches, and sequential installs avoid cache races during
cross-shard validation.

Released-mode validation refuses to run when a selected shard has a
`shard.override.yml`, unless `--allow-existing-overrides` is passed. This keeps
released-tag validation distinct from local-checkout validation.

Local integration mode writes managed `shard.override.yml` files for dependent
shards:

| Shard | Local dependencies |
| --- | --- |
| `terminfo` | `term-cursor`, `term-screen` |
| `reader` | `term-cursor`, `term-screen` |
| `spinner` | `term-cursor` |
| `prompt` | `term-color`, `term-cursor`, `term-reader`, `term-screen` |
| `progress` | `term-cursor`, `term-screen`, `term-spinner` |

If an existing override already matches the expected local dependency paths,
the harness leaves it in place. If an unmanaged override differs, `--local`
stops unless `--force-overrides` is supplied.

## New major release order

For a new major version, publish leaves first, then direct dependents, then
top-level consumers:

1. Leaves: `color`, `cursor`, `screen`
2. Middle layer: `terminfo`, `reader`, `spinner`
3. Top layer: `prompt`, `progress`

After each layer is tagged, run the harness in released mode for the next layer.
Before cutting the final top-layer releases, run `scripts/validate-shards.sh
--local` from the root checkout so dependent shards are checked against the
local major-version changes rather than the previous released tags.

## Nested repo and remote caveat

`color`, `cursor`, `screen`, `terminfo`, `reader`, `spinner`, and `prompt` are
nested Git repositories with their own `crystal-term/<name>` GitHub remotes.

`progress` is different: `shards/progress` is a local directory tracked by this
root checkout, not a nested Git repo. The root remote currently points at
`git@github.com:crystal-term/crystal-term.git`, but GitHub did not resolve that
repository during the inventory check on 2026-07-04, and `gh repo list
crystal-term` did not list a public `crystal-term/crystal-term` repository.
Treat progress issue tracking and release ownership as a root-checkout concern
until a dedicated progress repository or working root remote exists.

## Current GitHub issue inventory

Inventory queried on 2026-07-04 with `gh issue list --state open --limit 100`
for each public crystal-term shard repository.

| Repository | Open issues |
| --- | --- |
| `crystal-term/color` | [#2 NameError: undefined constant Cor in Color#pretty_print](https://github.com/crystal-term/color/issues/2), updated 2026-05-23 |
| `crystal-term/cursor` | None |
| `crystal-term/screen` | [#5 Windows support](https://github.com/crystal-term/screen/issues/5), updated 2022-08-01; [#4 Make linking against readline/termcap/libedit optional?](https://github.com/crystal-term/screen/issues/4), updated 2022-04-10 |
| `crystal-term/terminfo` | None |
| `crystal-term/reader` | [#8 Tagged version 0.3.2 does not compile with Crystal 1.18.2](https://github.com/crystal-term/reader/issues/8), updated 2026-05-23 |
| `crystal-term/spinner` | None |
| `crystal-term/prompt` | [#15 Prompt error - Regex.escape](https://github.com/crystal-term/prompt/issues/15), updated 2026-05-19; [#3 Error with enum_select](https://github.com/crystal-term/prompt/issues/3), updated 2021-10-27; [#2 The selection filtering doesn't work](https://github.com/crystal-term/prompt/issues/2), updated 2020-06-12 |
| `progress` / root | No queryable public GitHub issue tracker found for `crystal-term/crystal-term` on 2026-07-04 |
