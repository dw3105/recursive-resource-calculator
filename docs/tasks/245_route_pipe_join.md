# 245_route_pipe_join a second pipe of one fluid joins the first from any side, over its own pipe-to-ground

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-245`, branch `lane/245`,
base tag `round-44-wave2`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tests/golden/generate.lua`, `tools/game_test.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item
or entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment).

## Explain very simply

The player's gray + magenta science sheet has oil: one fluid (light oil) comes from two producers into one sink. The
first pipe reaches the sink; the second must JOIN that pipe network. Pipes have no direction: any same-fluid pipe
touching another joins it. The router gets this wrong twice. Traced on the player's frozen route input
`tests/fixtures/route_gray_magenta_154.json` (grid 154x154, legalcopilot-dev, 2026-09-27), demand heavy-oil cracking
→ light-oil cracking, sink T at (104,63):

1. The first light-oil pipe entered T heading west. The second path can only enter T heading east (other sides are
   machine tiles or next to a water port). `path_cell_free` refuses a head-on entry into a same-flow run
   (~`logic/bp/route.lua:2177`, `if move_direction == Grid.dir_opposite(segment.direction) then`). That is a BELT
   rule (a belt never takes items from the tile it faces); for pipes it is wrong. Patched in memory: T accepted.
2. The path is then laid, and `route_chain_reaches_sink` rejects it (`reject("route-discontinuous")`, ~`:2046`). The
   path is 67 tiles with pipe-to-ground pairs (76,63)→(85,63) and (100,63)→(103,63); `route_chain_walk` from the source
   reaches only 59 tiles: it stops at the entry (76,63) and never reaches the exit (85,63). The router throws away a path
   it built itself, fails the demand `BP_R_NO_PATH`, and restarts all 92 demands.

The chain walk's pipe branch is ~`:1616-1646` (a pipe-to-ground joins its partner and the one tile its exposed side
faces). Find why a pair laid by `append_normal_path` for a pipe demand is not walked from entry to exit (keys,
direction, or which segment the entry/exit cells hold) and fix the laying or the walk so they agree. Do not weaken the
check: a path that truly does not reach its sink must still be refused.

## What to build

1. `tests/test_route_pipe_join.lua` (input shapes of `tests/test_route.lua`: `Grid.new`, `catalog.pipe` with
   `throughput_per_second`, `underground = "pipe-to-ground"`, `underground_max_distance`; blocks with fluid ports).
   Commit red first.
   - PJ1 one fluid, 2 producer blocks, 1 consumer block. Obstacles leave the consumer's port tile reachable from the
     first producer from one side and from the second producer ONLY from the opposite side → `ok == true`, both
     demands placed, the second path ends entering the sink tile head-on.
   - PJ2 one fluid path that must cross a wall of another fluid's pipe using a pipe-to-ground pair, with its sink
     already fed by the same fluid → `ok == true`, and no `route-discontinuous` rejection
     (`state.work.counters` or result has no such rejection; a direct check through the route result is fine).
   - PJ3 belts keep the head-on refusal: a belt demand that can only enter an existing same-flow belt run head-on
     still fails (existing behaviour).
   - PJ4 frozen fixture: load `tests/fixtures/route_gray_magenta_154.json`, run `Route.begin` + `Route.step` with
     `{ops = 2000}` until the demand from port `heavy-oil-cracking:out:fluid/light-oil:machine:heavy-oil-cracking:1`
     to `light-oil-cracking:in:fluid/light-oil:machine:light-oil-cracking:1` is placed (bindings contain it) or 90 s
     CPU pass → it is placed. (About 40 s on this host; this is the only slow case.)
2. `logic/bp/route.lua`: (a) the head-on refusal applies only when `demand.kind ~= "pipe"`; (b) the pipe-to-ground
   fix from "Explain". Comment each with why.

## Files this lane owns

logic/bp/route.lua, tests/test_route_pipe_join.lua, docs/tasks/245_route_pipe_join.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/245`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane245-tests", "command": "git diff --name-only round-44-wave2 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_pipe_join\\.lua|docs/tasks/245_route_pipe_join\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave2 HEAD -- docs/tasks/245_route_pipe_join.md && ! git diff round-44-wave2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_pipe_join test_route test_route_budget test_route_bury test_route_chain test_route_collector test_route_collision test_route_crowded_fluids test_route_edge_twin test_route_feed_curve_retry test_route_fluid_port_ptg test_route_footprints test_route_free_cell test_route_hand_slide test_route_hop test_route_hop_multi test_route_improve test_route_layout_contract test_route_merge_feed test_route_network test_route_output_join test_route_rear_curve test_route_rows test_route_splitter_physics test_route_splitter_straight test_route_ticks test_route_tidy test_route_tidy_junk test_route_tidy_shapes test_route_twin_survives_tidy test_route_underground_feed test_route_waste test_pipe_runs test_pipe_prune test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane245-tests-ok", "expect_exit": 0, "expect_regex": "lane245-tests-ok", "timeout_s": 2400}
{"name": "lane245-fast", "command": "out=$(lua5.2 tests/test_route_pipe_join.lua 2>&1); for n in PJ1 PJ2 PJ3 PJ4; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane245-ok", "expect_exit": 0, "expect_regex": "lane245-ok", "timeout_s": 300}
```

# bound: 2400s
