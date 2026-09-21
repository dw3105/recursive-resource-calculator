# Round 13 baseline ledger

Host legalcopilot-dev, 2026-09-21. Spine tree: the commit that adds
`tests/test_blueprint_physical_contract.lua`. Written before any lane starts, so a lane cannot be credited for
a failure it did not cause, nor blamed for one it inherited.

Aggregate counts are never the allowlist. Every entry names its invocation, its test identity and its
interpreter.

## Pre-spine baseline, at `7c5429e`

| invocation | red |
|---|---|
| `lua5.2 tests/test_search.lua` | BP-20: `a larger grid that needs fewer beacons wins`, `the better candidate found second wins`, `the better first candidate survives a worse follow-up`, `equal beacon counts defer to footprint area`; 2 shapes each |
| `lua5.4 tests/test_search.lua` | the same four, 2 shapes each |
| `lua5.2 tests/test_corpus_setups.lua` | `shared-intermediate-multi-target`, `fluid-byproduct-chain`; 2 shapes each |
| `lua5.4 tests/test_corpus_setups.lua` | the same two, 2 shapes each |
| `python3 -m unittest tests.tools.test_golden_tools` | `test_accept_generated_case_promotes_reviewed_draft`, `test_accept_changes_only_the_named_expectation` — both `only captured cases may be accepted`, `tests/golden/lib/runner.py:1118` |

## Post-spine baseline

Spine goes **known, not green**. The physical contract is written against behaviour that does not exist yet,
so it is red on purpose; a lane closes its rows, and nothing else may change.

### `lua5.2 tests/test_blueprint_physical_contract.lua` — 54 cases, 12 passed, 42 failed
### `lua5.4 tests/test_blueprint_physical_contract.lua` — 54 cases, 12 passed, 42 failed

Identical on both interpreters. Per shape, 2.0 and 2.1 alike:

**Green already (6):**

| case | why it already holds |
|---|---|
| `PC1` the hand-built working factory is accepted | the positive control is genuinely valid under today's rules, so every rejection below is a real catch and not a broken base |
| `ID6` a lost module is rejected | `BP_V_MODULE_MISMATCH` already exists |
| `BE1` influence above the configured count is accepted | today's check is `got < required`, which is the behaviour the user asked to keep |
| `BE2` a speed beacon reaching a quality machine is rejected | `validate.lua:635-638`, already geometry-driven |
| `SR2` a furnace member never receives a recipe field | true today only because **no** member receives one |
| `SR3` serialization preserves the recipe and its quality | `serialize.lua:393` copies the field when it is present; the producer is what never sets it |

**Red on purpose (21 per shape, 42 in total):**

| case | closed by |
|---|---|
| `ID1` recipe deleted | lane 111 |
| `ID2` recipe replaced | lane 111 |
| `ID3` recipe on a furnace | lane 111 |
| `ID4` machine prototype changed | lane 111 |
| `ID5` machine quality changed | lane 111 |
| `TR1` input inserter removed | lane 111 |
| `TR2` output inserter removed | lane 111 |
| `TR3` input inserter moved off target | lane 111 |
| `TR4` output inserter reversed | lane 111 |
| `TR5` middle belt removed | lane 111 |
| `TR6` middle belt reversed | lane 111 |
| `TR7` every belt removed | lane 111 |
| `TR8` every inserter removed | lane 111 |
| `TR9` input belt no longer reaches its supply port | lane 111 |
| `TR10` output branch over capacity | lane 111 |
| `BE3` per-instance influence records | lane 111 |
| `MT1` measured transport cost and production area | lane 111 |
| `MT2` an absent metric rejects | lane 111 |
| `MT3` the published comparator order | lane 111 |
| `SR1` grouping carries the recipe | lane 110 |
| `SR4` a serializer-only mutation is detected | lane 111 produces `Validate.reconcile_artifact`, lane 113 calls it on the production path |

`SR2` is expected to **stay** green and to become meaningful once `SR1` closes: today it passes vacuously,
because no member carries a recipe at all.

## Dispatcher, proven before the tag

`tools/verify_round9_lane.sh`, with traps for `lua`, `lua5.2`, `lua5.4`, `python3` and `gateslot` first on
`PATH`:

| command | result |
|---|---|
| `--dispatch-only "$PWD" 110_producer` … `115_goldens` | bounded selection, right runner, **none** `dispatch=suite` |
| `--dispatch-only "$PWD" 999_missing` | exit 2 |
| `"$PWD" 112_capture --dispatch-only` | exit 2, never executes |
| `--dispatch-only "$PWD" 112_capture extra` | exit 2 |
| traps fired across all of the above | **0** |

## Rule

Any change to a line above, other than a lane closing its own listed rows, blocks the merge that caused it.
