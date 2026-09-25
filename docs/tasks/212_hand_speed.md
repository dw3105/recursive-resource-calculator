# 212_hand_speed catalog: inserter items per second from game facts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-212_hand_speed`, branch `lane/212_hand_speed`,
base tag `round-36-base`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data in `storage` only (no closures, no metatables). Unit tests
finish in under 20 s; GUI/control tests loop over `H.shapes()` and move time only with `H.run_ticks(world, n)`.

Read `docs/contracts/round36.md` first: it is the contract. Your clauses: A1.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK` or `GATE-FAIL`).

## Explain very simply

`logic/catalog.lua` (build_inserter) sets `items_per_second = 4.62` for every inserter. The game gives the facts
(`docs/api/2.0.77.members.json`, `2.1.19.members.json`): `LuaEntityPrototype.get_inserter_rotation_speed(quality)`,
`get_inserter_extension_speed(quality)`, prototype `bulk`, `LuaForce.inserter_stack_size_bonus`,
`bulk_inserter_capacity_bonus`. One swing is one full turn: `1 / rotation_speed` ticks. Wiki (chest to chest, no
bonus): inserter 0.83/s, fast inserter 2.31/s, long-handed 1.15/s. A fast inserter at stack 2 gives 4.62 = today's
default. Golden captures carry none of these facts, so their bytes must not change.

## What to build

1. A1 formula, `K`, stack, bulk, belt pickup factor (one named constant with a comment saying why).
2. Force bonuses read from the player's force in game; `tests/harness.lua` mock inserter prototypes gain
   `get_inserter_rotation_speed` / `get_inserter_extension_speed` (vanilla values) and the mock force gains the two
   bonuses.
3. Debug export (`logic/export_payload.lua`) writes the facts; `tools/prepared_from_export.py` passes them to the
   catalog when present.
4. Facts absent → 4.62 + diagnostic `CATALOG_INSERTER_SPEED_DEFAULT`.
5. Tests (red at base first): new `tests/test_catalog_inserter_speed.lua` (yellow 0.83±0.03, fast 2.31±0.05, long
   1.15±0.05 at stack 1; fast at stack 2 = 4.62±0.1; bulk with bonus; higher quality faster; missing facts → 4.62 +
   diagnostic); converter unittest in `tests/test_prepared_from_export.py`.

## Files this lane owns

logic/catalog.lua, logic/export_payload.lua, tools/prepared_from_export.py, tests/harness.lua, tests/test_catalog_inserter_speed.lua, tests/test_catalog.lua, tests/test_bp_settings.lua, tests/test_long_inserter_catalog.lua, tests/test_export_payload.lua, tests/test_prepared_from_export.py, docs/tasks/212_hand_speed.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/212_hand_speed`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane212-tests", "command": "git diff --name-only round-36-base HEAD | grep -Ev '^(logic/catalog\\\\.lua|logic/export_payload\\\\.lua|tools/prepared_from_export\\\\.py|tests/harness\\\\.lua|tests/test_catalog_inserter_speed\\\\.lua|tests/test_catalog\\\\.lua|tests/test_bp_settings\\\\.lua|tests/test_long_inserter_catalog\\\\.lua|tests/test_export_payload\\\\.lua|tests/test_prepared_from_export\\\\.py|docs/tasks/212_hand_speed\\\\.md)$' | ( ! grep . ) && ! git diff round-36-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_catalog_inserter_speed test_catalog test_bp_settings test_long_inserter_catalog test_export_payload test_blueprint_pipeline; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && python3 -m unittest tests/test_prepared_from_export.py 2>&1 | tail -1 | grep -q OK && for c in player-red-science-1s player-green-science-1s player-inserter-10s; do sh tools/bytes_hash.sh $c | tail -1; done > /tmp/b$$ && grep -c -f /tmp/b$$ tests/fixtures/bytes_round35.txt | grep -q 3 && echo lane212-tests-ok", "expect_exit": 0, "expect_regex": "lane212-tests-ok", "timeout_s": 2400}
```

# bound: 3000s
