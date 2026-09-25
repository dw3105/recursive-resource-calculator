# 222c_junk_fix route tidy: collapsing a splitter removes it; a dead splitter goes; inserter sheets back to size

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-222c_junk_fix`, branch `lane/222c_junk_fix`,
base tag `round-37-222c-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green).

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`);
`python3 tools/lane_sim.py <bp.txt> --input <prepared_input.json>`.
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Base commit's tidy (`logic/bp/route.lua`: dead-segment sweep and splitter-chain collapse, previous lane) makes
red 1/s, green 1/s, red 10/s, red 10/s stack-1 pass. Two faults remain, measured (legalcopilot-dev, 2026-09-25):

1. `player-inserter-10s` attempt 1 (`tools/verdict_codes.lua`): `BP_V_COLLISION r:1198,r:973`,
   `r:1199,r:973`, `r:1200,r:974`, `r:1201,r:974`, `BP_V_SPLITTER_CHAIN r:974,r:973`. The collapse lays new straight
   belts (r:1198..1201) on the tiles of splitters r:973 / r:974 but never deletes those splitter entities (nor their
   `segments_by_cell` / `entity_by_segment` entries), and it stops after one collapse, so a chain of three keeps two.
   Attempt 1 is rejected; the sheet ships attempt 3 at 406 entities (was 373).
2. `player-inserter-10s-bulk`: 274 entities (cap 273); `lane_sim` still `mixed=1`: hand (20,9) sees
   `ext@23,8`, `ext@24,8` -- a splitter at (24,8.5) whose two input tiles are fed by nothing stays in the layout after
   the sweep removes its dead feed belts. A splitter with no live input goes; one with one live input and one live
   output becomes a straight belt.

## What to build

1. Collapse replaces the splitter: delete its entity, both cells, index entries; lay the straight belts; repeat until
   no chain is left (keep-if-valid).
2. After the dead sweep, apply the splitter rule of fault 2 (repeat to a fixed point).
3. Extend `tests/test_route_tidy_junk.lua`: on `tests/fixtures/route_ins10s_call1.json` no two transport entities
   share a tile and no chain is left; on `tests/fixtures/route_ins10s_bulk_call4.json` no splitter has an unfed input.

## Files this lane owns

logic/bp/route.lua, tests/test_route_tidy_junk.lua, docs/tasks/222c_junk_fix.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/222c_junk_fix`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane222c-tests", "command": "git diff --name-only round-37-222c-base HEAD | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_tidy_junk\\\\.lua|docs/tasks/222c_junk_fix\\\\.md)$' | ( ! grep . ) && git diff --quiet round-37-222c-base HEAD -- docs/tasks/222c_junk_fix.md logic/bp/validate.lua && ! git diff round-37-222c-base HEAD -- logic | grep -q '^+.*coroutine' && python3 -m unittest tests.test_lane_sim 2>&1 | tail -1 | grep -q OK && for t in test_route_tidy_junk test_route_tidy test_route_tidy_shapes test_validate_splitter_chain test_validate_belt_no_source test_validate_parallel_ports test_route test_route_feed_curve_retry test_red10s_edge_rules test_no_item_names test_no_runtime_require; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane222c-tests-ok", "expect_exit": 0, "expect_regex": "lane222c-tests-ok", "timeout_s": 2400}
{"name": "lane222c-measure", "command": "sh tools/gate_sheet.sh player-inserter-10s 371 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s-bulk 273 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 298 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 283 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && echo lane222c-ok", "expect_exit": 0, "expect_regex": "lane222c-ok", "timeout_s": 3600}
```

# bound: 3000s
