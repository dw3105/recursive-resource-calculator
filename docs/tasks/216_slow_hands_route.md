# 216_slow_hands_route route: several hands of one flow side by side on one face all get belts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-216_slow_hands_route`, branch `lane/216_slow_hands_route`,
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

Hands are sized from real inserter speed now (round 36). A force with no stack research moves 2.31 items/s per fast
inserter, so a foundry casting 10/s gears needs 4 output hands side by side on one face.
`tests/golden/cases/player-red-science-10s-stack1` (the player's red science 10/s sheet at 2.31/s) gives no blueprint.
Measured on base (legalcopilot-dev, 2026-09-25) with `tools/stage_fail.lua`: groups, pack, route pass; validate fails.
Route leaves gear hands 2, 3, 4 of `casting-iron-gear-wheel` (drop tiles (21,26)..(21,28), all feeding the science
row's gear feed at (8,4)) `BP_R_NO_PATH` in first routing -- even with the base commit's retry that frees the source
heading (`demand.free_heading` in `fail_demand`, round-36-int3). The natural shape is ONE belt running past all four
drop tiles (an inserter drops onto a belt whatever way it faces). After tidy the validator also reports
`BP_V_UNDERGROUND_UNPAIRED` ×2 ("middle tile carries the underground flow" at (7,8) and (6,8)) and
`BP_V_UNDERGROUND_SIDELOAD_BLOCKED` ×1 (feeder (9,13) into underground input (8,13), lane R): tidy lays shapes the
validator refuses.

## What to build

1. Several output hands of one flow on one face share one belt that passes their drop tiles (or each gets its own
   way out) -- measured, general for any flow and any hand count.
2. Tidy never lays an underground whose middle tile carries its own flow on the surface, nor a side-fed underground
   entrance on a blocked lane (use the validator's rule; a map-edge belt carries both lanes).
3. Prove or drop the base's `demand.free_heading` retry: a test that fails without it, or remove it.
4. Tests (each red on base): frozen-input replays for (1) and (2).

## Files this lane owns

logic/bp/route.lua, tests/test_route_slow_hands.lua, tests/test_route_tidy_shapes.lua, tests/test_route.lua, tests/test_route_tidy.lua, tests/fixtures/route_red10s_stack1_call1.json, tests/fixtures/route_red10s_stack1_call2.json, docs/tasks/216_slow_hands_route.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/216_slow_hands_route`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane216-tests", "command": "git diff --name-only round-36-int3 HEAD | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_slow_hands\\\\.lua|tests/test_route_tidy_shapes\\\\.lua|tests/test_route\\\\.lua|tests/test_route_tidy\\\\.lua|tests/fixtures/route_red10s_stack1_call1\\\\.json|tests/fixtures/route_red10s_stack1_call2\\\\.json|docs/tasks/216_slow_hands_route\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int3 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_slow_hands test_route_tidy_shapes test_route test_route_tidy test_route_budget test_route_rows test_route_network test_no_item_names test_red10s_edge_rules test_route_feed_curve_retry test_validate_side_feed_witness test_validate_parallel_ports; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane216-tests-ok", "expect_exit": 0, "expect_regex": "lane216-tests-ok", "timeout_s": 3000}
{"name": "lane216-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s-stack1 340 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 300 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane216-ok", "expect_exit": 0, "expect_regex": "lane216-ok", "timeout_s": 2400}
```

# bound: 3600s
