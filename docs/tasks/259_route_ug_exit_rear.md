# 259_route_ug_exit_rear a belt never enters an underground exit from its buried rear

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-259`, branch `lane/259`,
base tag `round-45-w3`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

An underground belt exit takes items only from its own pair; its rear side (the tile behind it, along its heading) is
buried. On `player-inserter-10s-stack1` (legalcopilot-dev, 2026-09-27, replayed from a saved validate checkpoint) a
second electronic-circuit branch came north at x=25, turned west at (25,32) and ran into the rear of the circuit pair
exit (24,32) of pair (31,32)->(24,32). The validator refused `BP_V_UNDERGROUND_UNPAIRED` ("middle tile carries the
underground flow"). Route's `path_cell_free` already refuses entering an underground INPUT from the side; nothing
refuses entering an OUTPUT from behind.

Fix: in `path_cell_free` (`logic/bp/route.lua`, just before the comment "An underground input consumes its feed into
the pair"), a belt demand stepping onto a belt underground segment's exit tile while moving in the segment's own
direction is refused (`search.saw_blocked = true; return false`). Riding a pair is not affected (the ride enqueues the
exit directly, never through `path_cell_free`). Reference (measured in memory): `docs/tasks/ref/259_patch_reference.lua`;
with it both `BP_V_UNDERGROUND_UNPAIRED` records vanish on stack1 and all route test files stay green.

## What to build

1. `tests/test_route_ug_exit_rear.lua` (commit red first), synthetic (`Route.begin` shapes of `tests/test_route.lua`):
   - UR1: demand 1 of flow F must cross a wall with an underground pair heading west; demand 2 of the same flow F has
     a sink whose shortest way reaches the pair's exit from its rear. Assert `ok == true`, and no path cell of
     demand 2 steps onto the exit tile moving in the exit's direction (walk `state.result` entities: no plain belt of
     F on a tile strictly between the pair's entry and exit, and no belt of F pointing into the exit's rear). Red on
     base. If you cannot make it red on base in 15 minutes, build the geometry so that the ONLY path for demand 2
     is through the exit's rear and assert demand 2 is reported `BP_R_NO_PATH` shortfall on the fixed code instead.
   - UR2: riding a same-flow pair (entry from behind, out of exit) still works (`allow_ride` case from
     `tests/test_route_underground_feed.lua`): stays green.
2. `logic/bp/route.lua`: the rule, short comment citing tiles + date.

## Files this lane owns

logic/bp/route.lua, tests/test_route_ug_exit_rear.lua, docs/tasks/259_route_ug_exit_rear.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/259`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane259-tests", "command": "git diff --name-only round-45-w3 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_ug_exit_rear\\.lua|docs/tasks/259_route_ug_exit_rear\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w3 HEAD -- docs/tasks && ! git diff round-45-w3 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_ug_exit_rear test_route test_route_budget test_route_chain test_route_collision test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_underground_feed test_route_belt_chain test_route_no_self_cross test_route_self_cross_occupied test_route_shared_hand test_route_dead_ends test_route_pipe_ptg_side test_pipe_runs test_pipe_prune test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane259-tests-ok", "expect_exit": 0, "expect_regex": "lane259-tests-ok", "timeout_s": 3000}
{"name": "lane259-fast", "command": "out=$(lua5.2 tests/test_route_ug_exit_rear.lua 2>&1); for c in UR1 UR2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane259-ok", "expect_exit": 0, "expect_regex": "lane259-ok", "timeout_s": 600}
```

# bound: 3000s
