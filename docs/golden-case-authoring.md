# Golden case authoring

The corpus setups under `tests/golden/setup/` are executable, offline
descriptions of the world needed by a golden case. They feed the existing
calculation, preparation and search services; they do not replace any of
those production paths.

## The five production-chain cases

The lane owns these case/setup pairs:

- `base-only-crafting-smelting`: smelting followed by crafting;
- `shared-intermediate-multi-target`: two targets sharing one smelted item;
- `fluid-byproduct-chain`: water in, dirty water out, then a smelting step;
- `assembler-chain-example`: a compact all-assembler chain; and
- `repeatability`: the same prepared graph captured twice.

Every setup declares `declared_chain.steps` and `declared_chain.flows`. The
flow declaration uses the production names (`item/foo` and `fluid/bar`), so a
fluid or byproduct cannot disappear behind an otherwise plausible item chain.
The setup also records mocked prototype facts, selected recipes and machines,
module/beacon loadouts, infrastructure, mod/version, Factorio branch,
research, generation bounds, and the engine scenario's supply and drain.

`Setup.assert_calculated_graph` is called after the sliced calculation has
published its solver result and before `Generation.start` is called. It
compares the calculated recipe step names and the union of every non-zero
recipe input/output flow with the declared chain. A mismatch reports the
names/flows found, which makes an accidental external import visible at the
assertion point.

Run the focused checks with:

```sh
lua5.2 tests/test_corpus_setups.lua
lua5.4 tests/test_corpus_setups.lua
```

## Harness captures and provenance

Capture an individual setup through the real path:

```sh
tmp=$(mktemp -d)
lua5.2 tests/golden/capture_case.lua fluid-byproduct-chain \
  --output "$tmp/export.txt" --options "$tmp/options.json"
tests/golden/add_case fluid-byproduct-chain --force \
  --export "$tmp/export.txt" --options "$tmp/options.json"
```

The five checked-in cases are drafts with `source_kind: "harness"`.
Their prepared inputs and exports are useful replay inputs, but they are not
Factorio observations. In the capture provenance, `candidate_sha: "harness"`
is the stable source identity emitted by the offline producer; it is the
harness source-SHA sentinel, not a packaged candidate SHA. A later packaged
Factorio run must write a separate runtime capture with its own candidate SHA.

`add_case` preserves `export.json`, the encoded `export.txt`,
`prepared_input.json`, `options.json`, and `provenance.json`. It records the
observed generation result separately from policy. Thus a bounded search
failure can appear in `observed_outcome` while `supported_outcome` and
`expected_outcome` remain `production`. Do not turn that observation into a
rejection case, and do not create runtime evidence from a harness capture.

The existing `tiny-chain` setup is intentionally different: its zero search
budget is a failure-capture demonstration. It is not one of the five
production-chain cases and must not be copied as their graph template.

## Reviewing or accepting a case

The generated `candidate.json` is a placeholder. A draft does not accept a
golden expectation. Use the normal corpus runner to generate a fresh
candidate, inspect its independent assertions and provenance, and use
`tests/golden/accept` only after review. Never edit a harness provenance to
make it look like a packaged runtime observation.
