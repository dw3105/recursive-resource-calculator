# 224_one_source search + route + validate: one edge source per input flow, second sink branches inside

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-224_one_source`, branch `lane/224_one_source`,
base tag `round-37-wave2`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow, item or fluid.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`lua5.2 tools/capture_stage_input.lua ...`; `sh tools/gate_sheet.sh <case> <max_entities> [max_belts]`.
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Player rule (2026-09-25): **"1 input item = 1 source!"** One flow enters the layout from the map edge ONCE. A second
machine that needs it gets a branch (splitter) from that one line, inside the layout.

Measured (legalcopilot-dev, 2026-09-25):
- red science 10/s, shipped candidate (`tests/fixtures/route_red10s_final.json`, `tests/fixtures/validate_red10s_v1.json`):
  calcite enters twice, edge terminals (0,37) and (0,38), for sinks (1,37) and (13,37). The second terminal comes from
  round 36's `edge_split_flows` (`logic/bp/search.lua` `note_edge_shortfalls` ~1540, `perimeter_cell_free` ~634,
  terminal branch limit ~706): after a shortfall, every edge flow with > 1 sink gets one terminal per sink.
- inserter 10/s with bulk hands (`tests/golden/cases/player-inserter-10s-bulk`): molten fluid enters twice
  (lane_sim `ext@0,21`, `ext@0,23`).
Player's fix (`tests/fixtures/player_red10s_fix.txt`, bytes): ONE calcite edge belt; a splitter on the first tile
inside the edge (bytes (1.5,36), facing east); its two outputs run to the two foundries.

## What to build

1. Search/route: every flow gets exactly ONE edge terminal. Several sinks = branches from that one path (splitter
   for belts, pipe tee for fluids). Allow a splitter whose input is the edge terminal belt itself (first tile inside).
   Remove `edge_split_flows` terminal duplication; keep whatever other part of round 36 is still needed for the
   sheet to build (prove each kept part by a test).
2. Validate: `BP_V_SOURCE_DUPLICATE` -- more than one map-edge terminal for one flow (items and fluids). Code in
   `logic/bp/reason_codes.lua`.
3. Tests (red on base): `tests/test_validate_source_duplicate.lua` (fires on `validate_red10s_v1.json`),
   `tests/test_route_edge_branch.lua` (an edge flow with two sinks next to the edge: one terminal, a splitter,
   both sinks reached). Rewrite `tests/test_red10s_edge_rules.lua` to the new rule (T1 "every bound sink keeps an
   allocation after tidy" stays).

## Files this lane owns

logic/bp/search.lua, logic/bp/route.lua, logic/bp/validate.lua, logic/bp/reason_codes.lua, tests/test_validate_source_duplicate.lua, tests/test_route_edge_branch.lua, tests/test_red10s_edge_rules.lua, tests/test_search.lua, docs/tasks/224_one_source.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/224_one_source`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane224-tests", "command": "git diff --name-only round-37-wave2 HEAD | grep -Ev '^(logic/bp/search\\\\.lua|logic/bp/route\\\\.lua|logic/bp/validate\\\\.lua|logic/bp/reason_codes\\\\.lua|tests/test_validate_source_duplicate\\\\.lua|tests/test_route_edge_branch\\\\.lua|tests/test_red10s_edge_rules\\\\.lua|tests/test_search\\\\.lua|docs/tasks/224_one_source\\\\.md)$' | ( ! grep . ) && ! git diff round-37-wave2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_validate_source_duplicate test_route_edge_branch test_red10s_edge_rules test_search test_candidate_links test_route_feed_curve_retry test_validate_splitter_chain test_validate_belt_no_source test_validate_parallel_ports test_no_item_names; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane224-tests-ok", "expect_exit": 0, "expect_regex": "lane224-tests-ok", "timeout_s": 2400}
{"name": "lane224-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s 298 176 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s-bulk 273 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 371 | tail -1 | grep -q GATE-OK && echo lane224-ok", "expect_exit": 0, "expect_regex": "lane224-ok", "timeout_s": 3000}
```

# bound: 3600s
