# 223_collector_belt route: one belt per machine output flow, passing every hand drop tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-223_collector_belt`, branch `lane/223_collector_belt`,
base tag `round-37-wave2`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow and any hand count.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/capture_stage_input.lua ...`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Player hand-fixed our red science 10/s blueprint (2026-09-25): `tests/fixtures/player_red10s_fix.txt`, 261 entities,
139 belts. Ours: 298 entities, 176 belts. Every machine, beacon, hand, pole and pipe sits in the same tile. Only belts
and one splitter differ.

Frozen route input of the shipped candidate: `tests/fixtures/route_red10s_final.json` (route call 3). Replay it
(see `tests/test_route_feed_curve_retry.lua` for the pattern). Measured (legalcopilot-dev, 2026-09-25):
- gear foundry has 2 output hands, drop tiles (20,25) and (20,26); two demands, two parallel belts (rows 25, 26),
  both climb column 16 as two belts and take BOTH underground slots under the beacon row (row 13, x=7 and x=8);
- copper-plate foundry has 2 output hands, drop tiles (8,25) and (8,26); two demands, two belts; no underground
  slot is left, so it detours west to column 5, up to row 1 and over the top (~37 extra belts).
Player's fix: each foundry's two hands drop onto ONE belt running past both drop tiles; gear takes one underground
slot, copper takes the other; no detour. An inserter drops onto a belt tile whatever way the belt faces.

## What to build

1. Demand build: output hands of one flow on one machine whose drop tiles are collinear and adjacent (any count)
   become ONE collector: a belt laid through every drop tile, heading the way that leads toward the sink, and ONE
   demand from the collector's downstream end. Pick heading by trial if both work (keep the one that routes).
2. Hands that cannot form a collector keep today's behavior.
3. Test `tests/test_route_collector.lua` on `route_red10s_final.json`: each of the two foundries' output flows is one
   connected belt run touching both its drop tiles; no belt of any flow with y < 3 outside the feed row at y = 3
   (no detour over the top); total belt cells lower than base (print both).

Implementation note: demand construction joins collinear adjacent output ports belonging to the same machine and
flow into one source demand. Its route begins on the lower drop tile, so a northbound route lays belt under every
adjacent hand drop. Other ports retain the per-port demand behavior.

## Files this lane owns

logic/bp/route.lua, tests/test_route_collector.lua, tests/test_route.lua, tests/test_route_tidy.lua, docs/tasks/223_collector_belt.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/223_collector_belt`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane223-tests", "command": "git diff --name-only round-37-wave2 HEAD | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_collector\\\\.lua|tests/test_route\\\\.lua|tests/test_route_tidy\\\\.lua|docs/tasks/223_collector_belt\\\\.md)$' | ( ! grep . ) && ! git diff round-37-wave2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_collector test_route test_route_tidy test_route_tidy_shapes test_route_rows test_route_feed_curve_retry test_red10s_edge_rules test_validate_parallel_ports test_no_item_names; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane223-tests-ok", "expect_exit": 0, "expect_regex": "lane223-tests-ok", "timeout_s": 2400}
{"name": "lane223-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s 275 150 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 371 | tail -1 | grep -q GATE-OK && echo lane223-ok", "expect_exit": 0, "expect_regex": "lane223-ok", "timeout_s": 2400}
```

# bound: 3600s
