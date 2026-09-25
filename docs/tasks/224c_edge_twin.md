# 224c_edge_twin route tidy: two edge belts of one flow side by side become one edge belt and a splitter

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-224c_edge_twin`, branch `lane/224c_edge_twin`,
base tag `round-37-224c-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua` or `logic/bp/search.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Player rule: "1 input item = 1 source!". Base commit adds FATAL validate code `BP_V_SOURCE_DUPLICATE` (> 1 map-edge
input port for one flow). Search still makes two edge terminals for a flow on retry (`edge_split_flows`, round 36) --
that is how red science 10/s builds today, and two earlier attempts to remove it broke the sheet. Keep search as is.
Fix the result after routing, exactly as the player did by hand.

Measured (legalcopilot-dev, 2026-09-25), delivered bytes, x = distance from input edge:
- ours `player-red-science-10s`: calcite edge belts (0,35)→(1,35)→underground in (2,35) and (0,36)→(1,36)→(2,36)→
  underground in (3,36), both heading east (inward).
- player fix `tests/fixtures/player_red10s_fix.txt` (same frame after shifting by (186,1071)): belt (0,35) east;
  splitter at (1.5,36) east (covers tiles (1,35) and (1,36)); (2,35) underground in; (2,36) belt east → (3,36)
  underground in. No belt at (0,36). 3 belts became 1 splitter; ONE edge input.
Frozen route input of the shipped candidate: `tests/fixtures/route_red10s_final.json` (route frame differs: there the
calcite terminals are (0,37) and (0,38)).

## What to build

1. Final route tidy step (after the existing passes): for a flow with two edge terminals on neighbouring edge tiles
   whose paths both go straight inward for at least one tile: keep one edge terminal, turn the two first inside
   tiles into one splitter (same heading), delete the other edge belt, and move the dropped terminal's binding and
   allocations onto the kept one so exactly ONE edge input port remains for the flow in what route hands on
   (ports, bindings, entities). Any flow, belts only.
2. If the shape does not match, leave the layout alone (validate then rejects it and search tries the next).
3. Test `tests/test_route_edge_twin.lua`: replay route + tidy on `route_red10s_final.json`; calcite (by flow id read
   from the fixture, not named in logic) has one edge terminal, one splitter on the first inside column, both sinks
   bound with their full rate.

## Files this lane owns

logic/bp/route.lua, tests/test_route_edge_twin.lua, tests/test_route_tidy.lua, docs/tasks/224c_edge_twin.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/224c_edge_twin`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane224c-tests", "command": "git diff --name-only round-37-224c-base HEAD | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_edge_twin\\\\.lua|tests/test_route_tidy\\\\.lua|docs/tasks/224c_edge_twin\\\\.md)$' | ( ! grep . ) && git diff --quiet round-37-224c-base HEAD -- docs/tasks/224c_edge_twin.md && ! git diff round-37-224c-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_edge_twin test_validate_source_duplicate test_route test_route_tidy test_route_tidy_shapes test_route_feed_curve_retry test_red10s_edge_rules test_validate_parallel_ports test_no_item_names test_no_runtime_require; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane224c-tests-ok", "expect_exit": 0, "expect_regex": "lane224c-tests-ok", "timeout_s": 2400}
{"name": "lane224c-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s 296 174 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 283 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && echo lane224c-ok", "expect_exit": 0, "expect_regex": "lane224c-ok", "timeout_s": 3600}
```

# bound: 3600s
