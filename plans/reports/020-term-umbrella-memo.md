# Plan 020 Decision Memo: `term` umbrella shard

## Prototype result

The prototype under `plans/prototypes/term/` models a meta-shard named `term`
that depends on seven installable crystal-term shards:

- `term-color`
- `term-cursor`
- `term-screen`
- `term-terminfo`
- `term-reader`
- `term-spinner`
- `term-prompt`

`term-progress` is intentionally excluded until plan 018 gives it a fetchable
shard home. The prototype entry point is just the seven `require "term-*"`
statements, and `examples/smoke.cr` type-checks representative calls for each
namespace from one `require "../src/term"`.

## Probe answers

### 1. Bare-name collision

There is a real ecosystem collision risk for publishing this as `term`.
`https://shardbox.org/shards/term` returned `404 Shard not found`, but
`shards.info` indexes `bmmcginty/term`, and its upstream `shard.yml` declares
`name: term` at version `0.1.1`.

Because Shards dependencies are decentralized, this does not block a GitHub repo
named `crystal-term/term` mechanically. It does mean users cannot combine both
projects under the same dependency name, and search/docs would be ambiguous.
The lower-risk publish name is `term-all` or another explicit umbrella name.

Sources checked:

- https://shardbox.org/shards/term
- https://shards.info/github/bmmcginty/term/
- https://raw.githubusercontent.com/bmmcginty/term/master/shard.yml
- https://api.github.com/repos/crystal-term/term

### 2. Version resolution

Resolving the seven installable family shards together with the prototype's
local path overrides did not reveal a version conflict. The dependency graph is
compatible today:

- `term-reader` pulls `term-cursor` and `term-screen`
- `term-spinner` pulls `term-cursor`
- `term-prompt` pulls `term-color`, `term-cursor`, `term-reader`, and
  `term-screen`

The umbrella points at the same `v1.0.0` family release layer, so no additional
transitive constraint conflict appears.

### 3. Version policy

The umbrella should track the family major. A `1.x` umbrella release should
only pull `1.x` family shards, and a family member moving to `2.0` should force
the umbrella to wait for a coordinated `2.0` release as the final release layer.

The prototype uses the family-wide convention from existing shard manifests:
`~> 1.0.0`. If the project wants the umbrella to represent "compatible family
major" rather than "matched release train", publish with `~> 1.0` constraints
instead. Either way, do not allow a `term 1.x` release to resolve a `term-* 2.x`
member.

## Release overhead

Publishing an umbrella creates a fourth release layer after the existing leaves,
middle, and top layers:

1. leaves: `color`, `cursor`, `screen`, `terminfo`
2. middle: `reader`, `spinner`
3. top: `prompt`, `progress`
4. umbrella: `term` or `term-all`

The recurring cost is one more repository, one more tag per coordinated release
cycle, one harness entry, and a small docs update to `docs/release-validation.md`.
There is no meaningful runtime cost because the shard is only dependency
metadata plus require aggregation.

## Demand evidence

There is no known user request in the issue inventory. The positive evidence is
convenience: full TUI consumers currently assemble several dependency blocks,
and Ruby's `tty` gem uses an umbrella package pattern for the tty family. That
is useful, but weak without direct user demand.

## Recommendation

No-go for publishing a bare `term` shard now.

The prototype proves the technical shape works and that the current seven
installable shards resolve together, but two factors argue against publication:

- The name `term` already exists in the broader Crystal ecosystem as
  `bmmcginty/term`.
- Demand is inferred from convenience and upstream precedent, not observed from
  users.

Flip criteria:

- First user request for an umbrella install path.
- A second version-skew report across crystal-term family members.
- A maintainer decision to publish under a non-colliding name such as
  `term-all`, with release docs updated to add the fourth layer.
