# crystal-term

Root checkout for the crystal-term shard family.

This repository contains eight nested shard repositories and one root-tracked
plain shard directory:

| Shard | Path | Ownership |
| --- | --- | --- |
| `color` | `shards/color` | nested Git repo, `crystal-term/color` |
| `vt` | `shards/vt` | plain directory, pre-publication |
| `cursor` | `shards/cursor` | nested Git repo, `crystal-term/cursor` |
| `screen` | `shards/screen` | nested Git repo, `crystal-term/screen` |
| `terminfo` | `shards/terminfo` | nested Git repo, `crystal-term/terminfo` |
| `reader` | `shards/reader` | nested Git repo, `crystal-term/reader` |
| `spinner` | `shards/spinner` | nested Git repo, `crystal-term/spinner` |
| `prompt` | `shards/prompt` | nested Git repo, `crystal-term/prompt` |
| `progress` | `shards/progress` | nested Git repo, `crystal-term/progress` |

## Getting started

Clone with submodules:

    git clone --recurse-submodules https://github.com/crystal-term/crystal-term.git

Or, in an existing clone:

    git submodule update --init

Submodule URLs are HTTPS so anonymous and CI clones work. If you push via
SSH, add a rewrite once: `git config url."git@github.com:".insteadOf "https://github.com/"`.

## Cross-shard validation

Use the root harness in local integration mode:

```sh
scripts/validate-shards.sh --local
```

The harness validates shards in dependency order:

```text
color, vt, cursor, screen, terminfo, reader, spinner, prompt, progress
```

For each selected shard it runs `shards install` sequentially, then
`crystal spec --no-color`, then compiles examples with
`crystal build --no-codegen --no-color` where an `examples/` directory exists.
The install phase is intentionally not parallelized because all nested shards
can share Crystal/Shards caches.

`--local` writes `shard.override.yml` files for dependent shards so `reader`,
`spinner`, `prompt`, and `progress` resolve crystal-term dependencies from this
checkout instead of released GitHub tags. Generated overrides can be removed
with:

```sh
scripts/validate-shards.sh --clean-local-overrides
```

Released-mode validation is also available:

```sh
scripts/validate-shards.sh
```

Released-mode validation refuses unmanaged `shard.override.yml` files so it
does not accidentally test local paths while claiming to test released tags.
This checkout currently has a compatible unmanaged prompt override; remove it
or pass `--allow-existing-overrides` when that behavior is intentional.

More details, including release order and current issue inventory, are in
[docs/release-validation.md](docs/release-validation.md).
