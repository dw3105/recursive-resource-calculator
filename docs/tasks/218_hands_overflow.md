# 218_hands_overflow groups: more hands than a face holds use another face, never a machine tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-218_hands_overflow`, branch `lane/218_hands_overflow`,
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

Hands are sized from real inserter speed (round 36). `tests/golden/cases/player-inserter-10s-stack1` (the player's
inserter 10/s sheet at 2.31/s hands) now packs, then every attempt fails route `BP_R_PORT_BLOCKED` (measured
legalcopilot-dev, 2026-09-25): src (4,7) owner `machine:block:casting-copper-cable` -> sink (4,24) owner
`machine:block:electronic-circuit`. Copper cable is 15/s from one foundry to one electromagnetic plant; at 2.31/s that
is 7 output hands and 7 input hands. Both ports lie ON a machine tile: groups (`logic/bp/groups.lua`, hand placement
in `append_inserters` / face columns) placed hands past the end of the face when the face ran out of columns.

## What to build

1. When one face cannot hold a flow's hands, use the machine's other free faces; a hand or port never lands on a
   machine tile. If no face can hold them, fail the block by name (`BP_P_NO_FIT`, "inserter-face"), never overlap.
2. Test (red on base): a machine whose one flow needs more hands than its face has columns -> every hand and port on a
   free tile outside the machine, hands on more than one face.
3. `player-inserter-10s-stack1` gets past route on at least one attempt (`tools/stage_fail.lua` shows
   `STAGE route ok=true`).

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_hands_overflow.lua, tests/test_groups.lua, tests/test_groups_hand_count.lua, docs/tasks/218_hands_overflow.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/218_hands_overflow`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane218-tests", "command": "git diff --name-only round-36-int4 HEAD | grep -Ev '^(logic/bp/groups\\\\.lua|tests/test_groups_hands_overflow\\\\.lua|tests/test_groups\\\\.lua|tests/test_groups_hand_count\\\\.lua|docs/tasks/218_hands_overflow\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int4 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_hands_overflow test_groups test_groups_hand_count test_groups_beacon_row test_groups_fluid_row test_inserter_geometry test_no_item_names test_red10s_edge_rules test_route_feed_curve_retry test_validate_side_feed_witness test_validate_parallel_ports test_pack_slow_hands test_pack_adjacent_producers test_corpus_setups; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane218-tests-ok", "expect_exit": 0, "expect_regex": "lane218-tests-ok", "timeout_s": 3000}
{"name": "lane218-measure", "command": "lua5.2 tools/stage_fail.lua tests/golden/cases/player-inserter-10s-stack1/prepared_input.json 2>/dev/null | grep -q 'STAGE route ok=true' && sh tools/gate_sheet.sh player-red-science-10s 300 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 340 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane218-ok", "expect_exit": 0, "expect_regex": "lane218-ok", "timeout_s": 3000}
```

# bound: 3600s
