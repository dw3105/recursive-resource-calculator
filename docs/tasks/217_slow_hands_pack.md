# 217_slow_hands_pack groups + pack: slow-hand sheets pack, red-10s stays compact

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-217_slow_hands_pack`, branch `lane/217_slow_hands_pack`,
base tag `round-36-int3`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`lua5.2 tools/verdict_codes.lua <prepared_input.json>` (first validate verdict, one line per error);
`lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> <stage> <call>` (freeze one stage's exact
input for a test that replays it in seconds; see `tests/test_route_feed_curve_retry.lua`);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Three measured faults (legalcopilot-dev, 2026-09-25), all in grouping/packing:
(1) `tests/golden/cases/player-inserter-10s-stack1` (inserter 10/s at 2.31/s hands): `tools/stage_fail.lua` shows
100 × `STAGE pack ok=false BP_P_NO_FIT` -- groups builds blocks, pack fits none of them (more hands per machine).
(2) `tests/test_corpus_setups.lua` fails 2 cases: "capture stopped in phase pack after 3000 ticks" for
`assembler-chain-example`. Bisected: passes before real inserter speed (commit ba41cb8^), fails after; the harness
force has no stack bonus, so hands are 0.81/s (yellow) and pack runs out of ticks.
(3) `player-red-science-10s` builds with 298 entities but 176 belts against a cap of 150: pack puts the four foundries
~20 tiles below the science row, so copper plate climbs 24 tiles up column x=4 and gears climb column x=15 to reach
the row head (ASCII map in the round 36 report). Producers must sit next to the consumer they feed.

## What to build

1. Find why every inserter-10s-stack1 candidate is `BP_P_NO_FIT` (print the refused block and grid) and fix it
   generally: blocks with more hands still pack.
2. Pack of the corpus sheet finishes inside its tick bound (`tests/test_corpus_setups.lua` green) -- no bound raised.
3. Red-10s: producers placed next to their consumers; `sh tools/gate_sheet.sh player-red-science-10s 300 150`.
4. Tests (each red on base) for (1) and (3), smallest input that shows each.

## Files this lane owns

logic/bp/groups.lua, logic/bp/pack.lua, tests/test_pack_slow_hands.lua, tests/test_pack_adjacent_producers.lua, tests/test_pack.lua, tests/test_pack_layered.lua, tests/test_groups.lua, docs/tasks/217_slow_hands_pack.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/217_slow_hands_pack`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane217-tests", "command": "git diff --name-only round-36-int3 HEAD | grep -Ev '^(logic/bp/groups\\\\.lua|logic/bp/pack\\\\.lua|tests/test_pack_slow_hands\\\\.lua|tests/test_pack_adjacent_producers\\\\.lua|tests/test_pack\\\\.lua|tests/test_pack_layered\\\\.lua|tests/test_groups\\\\.lua|docs/tasks/217_slow_hands_pack\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int3 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_slow_hands test_pack_adjacent_producers test_pack test_pack_layered test_groups test_groups_beacon_row test_groups_hand_count test_corpus_setups test_inserter_geometry test_no_item_names test_red10s_edge_rules test_route_feed_curve_retry test_validate_side_feed_witness test_validate_parallel_ports; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane217-tests-ok", "expect_exit": 0, "expect_regex": "lane217-tests-ok", "timeout_s": 3000}
{"name": "lane217-measure", "command": "lua5.2 tools/stage_fail.lua tests/golden/cases/player-inserter-10s-stack1/prepared_input.json 2>/dev/null | grep -q 'STAGE pack ok=true' && sh tools/gate_sheet.sh player-red-science-10s 300 150 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane217-ok", "expect_exit": 0, "expect_regex": "lane217-ok", "timeout_s": 2400}
```

# bound: 3600s
