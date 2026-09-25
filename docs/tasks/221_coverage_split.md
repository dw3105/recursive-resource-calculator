# 221_coverage_split groups: shared block that cannot reach its beacon count splits into one-machine blocks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-221_coverage_split`, branch `lane/221_coverage_split`,
base tag `round-37-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item, fluid, recipe or machine name in
code** (`tests/test_no_item_names.lua` must stay green): every rule holds for any step.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> <stage> <call>`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`);
`sh tools/bytes_hash.sh` (compare against `tests/fixtures/bytes_round36.txt`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Player's inserter 10/s sheet with player's research: `tests/golden/cases/player-inserter-10s-bulk` (bulk hands
36.96/s). In game `BP_FAIL_NO_LAYOUT`. Measured (legalcopilot-dev, 2026-09-25): `tools/stage_fail.lua` → 98 of 98
groups runs `BP_P_NO_FIT: configured beacon coverage cannot be split` (`logic/bp/groups.lua` ~2306). Cause: fast
hands mean `needs_individual_blocks` (~2257) stays false for step `casting-iron` (2 foundries, beacon group
`count 1`, `sharing 1`), so both machines join one non-row block (w=7, h=15). That block places 1 beacon; one
machine gets 0 of required 1 → `block.invalid_coverage`. The comment at ~2075 already says "the caller can try a
split" -- nobody does. Proof: patching in memory so that step is split into one-machine fragments
(`_force_block`) → `STAGE-END ok=true`, 278 entities, 72 s CPU.

## What to build

1. When a bucket's shared block comes back `invalid_coverage` (and has > 1 machine), rebuild that bucket as
   one-machine fragments (same fields the existing fragment code sets: `machine_count = 1`, `_physical_ordinal`,
   `_rate_machine_count`, `_force_block`) and build those blocks instead. Only report `BP_P_NO_FIT` when a
   one-machine block still fails. General: no step, recipe or machine name.
2. Test `tests/test_groups_coverage_split.lua` on frozen fixture `tests/fixtures/groups_ins10s_bulk.json` (groups
   input of call 1, already in the tree): groups finishes with 0 failures; every machine reaches its
   `count_per_machine` per beacon signature (use `block.beacon_coverage`).
3. Sheets that build today must not change: bytes hash for the five sheets in `tests/fixtures/bytes_round36.txt`
   unchanged.

## Implementation note

The grouping builder now retries a shared block with invalid beacon coverage as one-machine fragments. Each
fragment keeps aggregate rate accounting and a physical ordinal; a single-machine failure remains a
`BP_P_NO_FIT`. The frozen groups-input regression checks every machine's coverage by beacon signature.

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_coverage_split.lua, tests/test_groups.lua, docs/tasks/221_coverage_split.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/221_coverage_split`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane221-tests", "command": "git diff --name-only round-37-base HEAD | grep -Ev '^(logic/bp/groups\\\\.lua|tests/test_groups_coverage_split\\\\.lua|tests/test_groups\\\\.lua|docs/tasks/221_coverage_split\\\\.md)$' | ( ! grep . ) && ! git diff round-37-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_coverage_split test_groups test_groups_beacon_row test_groups_hands_overflow test_pack_slow_hands test_no_item_names; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane221-tests-ok", "expect_exit": 0, "expect_regex": "lane221-tests-ok", "timeout_s": 1800}
{"name": "lane221-measure", "command": "timeout 1500 lua5.2 tools/stage_fail.lua tests/golden/cases/player-inserter-10s-bulk/prepared_input.json | tail -1 | grep -q 'STAGE-END ok=true' && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 298 | tail -1 | grep -q GATE-OK && echo lane221-ok", "expect_exit": 0, "expect_regex": "lane221-ok", "timeout_s": 3000}
```

# bound: 3000s
