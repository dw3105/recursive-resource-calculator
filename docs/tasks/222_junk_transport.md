# 222_junk_transport route + validate: no splitter chains, no belts without a source

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-222_junk_transport`, branch `lane/222_junk_transport`,
base tag `round-37-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY),
`python3 -m unittest tests.test_lane_sim`, and the tools named below. Never use `coroutine`. Plain data only.
**No game item or fluid name in code** (`tests/test_no_item_names.lua` must stay green).

Tools: `lua5.2 tools/verdict_codes.lua <prepared_input.json>`; `lua5.2 tools/capture_stage_input.lua ...`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Player's screenshot (inserter 10/s v3 bytes, 2026-09-25, "WTF???"): three splitters in a row at (31.5,17),
(32.5,17), (33.5,17), all facing east. Each takes both lanes out of the one before, so two of them do nothing.
Frozen validate input with that layout: `tests/fixtures/validate_ins10s_v3_chain.json` (validator accepts it).

Second junk, same family, frozen in `tests/fixtures/validate_ins10s_bulk_stub.json` (inserter 10/s with bulk hands,
accepted candidate, legalcopilot-dev 2026-09-25): belts (26.5,6.5) west → (25.5,6.5) → (24.5,6.5) south →
(24.5,7.5) → splitter (24,8.5). Nothing puts items on (26.5,6.5): no hand drops there, no belt feeds it, no edge.
A dead stub that makes a second splitter. Validator accepts it.

`tools/lane_sim.py` misreads that layout too: the foundry hand at (27.5,8.5) drops onto the splitter tile
(26,8.5); lane_sim calls the splitter's other input an unknown source `ext@25,8` and reports `mixed=5`.

## What to build

1. Validate: `BP_V_SPLITTER_CHAIN` -- a splitter whose two inputs are both fed only by the two outputs of one
   upstream splitter of the same flow. `BP_V_BELT_NO_SOURCE` -- a belt run whose first tile gets items from no
   hand drop, no belt/underground/splitter, and is not a map-edge input. Both codes in `logic/bp/reason_codes.lua`.
2. Route tidy (keep-if-valid, like the other tidy passes): replace a chained splitter with two belts; delete a
   source-less belt run; a splitter left with one live input becomes a belt. Both fixtures come out clean.
3. `tools/lane_sim.py`: a hand dropping onto a splitter tile feeds that splitter (both halves as the engine does:
   the dropped-on half). Python unit test `tests/test_lane_sim.py` with a tiny blueprint.
4. Tests (each red on base): `tests/test_validate_splitter_chain.lua`, `tests/test_validate_belt_no_source.lua`
   (codes fire on the frozen fixtures), `tests/test_route_tidy_junk.lua` (tidy on a small built layout removes the
   chain and the stub).

## Files this lane owns

logic/bp/route.lua, logic/bp/validate.lua, logic/bp/reason_codes.lua, tools/lane_sim.py, tests/test_lane_sim.py, tests/test_validate_splitter_chain.lua, tests/test_validate_belt_no_source.lua, tests/test_route_tidy_junk.lua, tests/test_route_tidy.lua, tests/test_route_tidy_shapes.lua, tests/test_validate.lua, docs/tasks/222_junk_transport.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/222_junk_transport`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane222-tests", "command": "git diff --name-only round-37-base HEAD | grep -Ev '^(logic/bp/route\\\\.lua|logic/bp/validate\\\\.lua|logic/bp/reason_codes\\\\.lua|tools/lane_sim\\\\.py|tests/test_lane_sim\\\\.py|tests/test_validate_splitter_chain\\\\.lua|tests/test_validate_belt_no_source\\\\.lua|tests/test_route_tidy_junk\\\\.lua|tests/test_route_tidy\\\\.lua|tests/test_route_tidy_shapes\\\\.lua|tests/test_validate\\\\.lua|docs/tasks/222_junk_transport\\\\.md)$' | ( ! grep . ) && ! git diff round-37-base HEAD -- logic | grep -q '^+.*coroutine' && python3 -m unittest tests.test_lane_sim 2>&1 | tail -1 | grep -q OK && for t in test_validate_splitter_chain test_validate_belt_no_source test_route_tidy_junk test_route_tidy test_route_tidy_shapes test_validate test_validate_parallel_ports test_validate_side_feed_witness test_validate_witness_underground test_route_feed_curve_retry test_red10s_edge_rules test_no_item_names; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane222-tests-ok", "expect_exit": 0, "expect_regex": "lane222-tests-ok", "timeout_s": 2400}
{"name": "lane222-measure", "command": "sh tools/gate_sheet.sh player-inserter-10s 371 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 298 | tail -1 | grep -q GATE-OK && echo lane222-ok", "expect_exit": 0, "expect_regex": "lane222-ok", "timeout_s": 2400}
```

# bound: 3600s
