# 219_red10s_compact pack: producers sit next to the consumer they feed (red-10s at most 150 belts)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-219_red10s_compact`, branch `lane/219_red10s_compact`,
base tag `round-36-int4`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST. **Do not edit this task file** except to add a "## Built" section at its end.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> <stage> <call>` (freeze one stage's input,
see `tests/test_route_feed_curve_retry.lua`); `sh tools/gate_sheet.sh <case> <max_entities> [max_belts]`.
Every new test must FAIL on the code before your fix (say so in the test's header comment).

## Explain very simply

`player-red-science-10s` builds with 298 entities and 176 belts (legalcopilot-dev, 2026-09-25); cap 150 belts. ASCII
of the blueprint: the science row (10 assembling-machine-3, beacon row below) sits at the top; the four foundries sit
~20 tiles below. Copper plate from the casting-copper foundry climbs 24 tiles up column x=4 and runs 7 east to reach
the row head; iron gears climb column x=15 then run west along y=14/15; the row output runs 10 tiles north to the top
edge. Placing the casting foundries next to the row's input head (and the molten foundries next to them) removes most
of those belts. The pack is `logic/bp/pack.lua` (layered placement by default; `test_pack_adjacent_producers` from the
previous change covers a small case and passes -- it did not move red-10s).

## What to build

1. Measure first: print where pack places each block of red-10s and the manhattan distance from each producer's
   output port to its consumer's input port; write the numbers under "## Built".
2. Place producers next to the consumer port they feed (general rule, any flow): red-10s at most 150 belts.
3. Test (red on base): frozen pack input of red-10s (`tools/capture_stage_input.lua ... pack 1`) -> producer-to-consumer
   port distance of each link at most a bound you measure and justify.

## Files this lane owns

logic/bp/pack.lua, tests/test_pack_red10s_compact.lua, tests/fixtures/pack_red10s_call1.json, tests/test_pack.lua, tests/test_pack_layered.lua, docs/tasks/219_red10s_compact.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/219_red10s_compact`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane219-tests", "command": "git diff --name-only round-36-int4 HEAD | grep -Ev '^(logic/bp/pack\\\\.lua|tests/test_pack_red10s_compact\\\\.lua|tests/fixtures/pack_red10s_call1\\\\.json|tests/test_pack\\\\.lua|tests/test_pack_layered\\\\.lua|docs/tasks/219_red10s_compact\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int4 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_red10s_compact test_pack test_pack_layered test_no_item_names test_red10s_edge_rules test_route_feed_curve_retry test_validate_side_feed_witness test_validate_parallel_ports test_pack_slow_hands test_pack_adjacent_producers test_corpus_setups; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane219-tests-ok", "expect_exit": 0, "expect_regex": "lane219-tests-ok", "timeout_s": 3000}
{"name": "lane219-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s 300 150 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 340 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane219-ok", "expect_exit": 0, "expect_regex": "lane219-ok", "timeout_s": 3000}
```

# bound: 3600s
