# 222b_junk_tidy route: tidy leaves no dead trunk and no splitter chain

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-222b_junk_tidy`, branch `lane/222b_junk_tidy`,
base tag `round-37-222b-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file.** **Never make a validate code non-fatal or skip a check to pass.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green): every rule holds for any flow.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> route <call>`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Base commit already has two FATAL validate codes: `BP_V_SPLITTER_CHAIN` and `BP_V_BELT_NO_SOURCE`
(`logic/bp/validate.lua`). They fire on two real layouts. Route must stop making those layouts. Both causes measured
(legalcopilot-dev, 2026-09-25) by replaying route + tidy on frozen route inputs:

1. **Dead trunk after tidy** -- `tests/golden/cases/player-inserter-10s-bulk`, route call 4. Flow iron plate, one
   source port, two sinks. First routing: trunk segments `r:s:835..839` = belts (26,6) (25,6) (24,6) (24,7) and a
   splitter at (24,8) branching to both sinks. Tidy re-routes both sinks from the source through a NEW splitter at
   (26,8) (`r:s:909`) -- and keeps `r:s:835..839`. Cause: `lift_binding` refuses to lift a segment that carries
   another sink's allocation (`carries_other`, round 36). Each sink's lift sees the other sink's allocation on the
   shared trunk, so neither lift removes it. Result: belts nothing feeds, plus a second splitter.
2. **Splitter chain in first routing** -- `tests/golden/cases/player-inserter-10s`, route call 1. Segments
   `r:s:951`, `r:s:952`, `r:s:953` = three splitters at (31.5,17) (32.5,17) (33.5,17), all east, one per branch
   sink. Each takes both outputs of the one before; all branches end on the same two outputs (north column 34, east
   row 17). One splitter does the job.

## What to build

1. After tidy (and after any lift), sweep each flow: keep only segments on a live path from its source to a bound
   sink (walk from each sink back to the source through what feeds it); delete the rest. A splitter left with one
   live input or one live output becomes a straight belt (or goes). Allocations stay consistent (round 36 test T1
   in `tests/test_red10s_edge_rules.lua` must stay green).
2. Tidy pass (keep-if-valid, like the other tidy passes): a splitter whose two inputs are exactly the two outputs of
   one upstream splitter of the same flow becomes two straight belts. Better still, route never places it: a
   branch whose side cell already carries the same flow from an upstream splitter starts from that belt instead.
3. `tests/test_validate_parallel_ports.lua` asserts the copper-cable witness (0 `BP_V_TRANSPORT_UNUSED`); its
   frozen fixture also holds the splitter chain, so change only its `state.ok` line to "no error but
   `BP_V_SPLITTER_CHAIN`" with a comment -- the chain is caught and fixed upstream now.
4. Tests (red on base): `tests/test_route_tidy_junk.lua` -- replay route + tidy on route inputs frozen with
   `tools/capture_stage_input.lua` (save as `tests/fixtures/route_ins10s_bulk_call4.json`,
   `tests/fixtures/route_ins10s_call1.json`); assert no source-less belt and no chained splitter in the result.

## Files this lane owns

logic/bp/route.lua, tests/test_route_tidy_junk.lua, tests/test_route_tidy.lua, tests/test_route_tidy_shapes.lua, tests/test_validate_parallel_ports.lua, tests/fixtures/route_ins10s_bulk_call4.json, tests/fixtures/route_ins10s_call1.json, docs/tasks/222b_junk_tidy.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/222b_junk_tidy`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane222b-tests", "command": "git diff --name-only round-37-222b-base HEAD | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_tidy_junk\\\\.lua|tests/test_route_tidy\\\\.lua|tests/test_route_tidy_shapes\\\\.lua|tests/test_validate_parallel_ports\\\\.lua|tests/fixtures/route_ins10s_bulk_call4\\\\.json|tests/fixtures/route_ins10s_call1\\\\.json|docs/tasks/222b_junk_tidy\\\\.md)$' | ( ! grep . ) && git diff --quiet round-37-222b-base HEAD -- logic/bp/validate.lua docs/tasks/222b_junk_tidy.md && ! git diff round-37-222b-base HEAD -- logic | grep -q '^+.*coroutine' && python3 -m unittest tests.test_lane_sim 2>&1 | tail -1 | grep -q OK && for t in test_route_tidy_junk test_route_tidy test_route_tidy_shapes test_validate_splitter_chain test_validate_belt_no_source test_validate_parallel_ports test_validate test_route test_route_feed_curve_retry test_red10s_edge_rules test_validate_side_feed_witness test_no_item_names; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane222b-tests-ok", "expect_exit": 0, "expect_regex": "lane222b-tests-ok", "timeout_s": 2400}
{"name": "lane222b-measure", "command": "sh tools/gate_sheet.sh player-inserter-10s-bulk 273 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 371 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 298 | tail -1 | grep -q GATE-OK && echo lane222b-ok", "expect_exit": 0, "expect_regex": "lane222b-ok", "timeout_s": 3000}
```

# bound: 3600s
