# 253_route_self_cross_occupied a self-crossing path refused for any reason retries without self-crossing

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-253`, branch `lane/253`,
base tag `round-44-wave6`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tests/golden/generate.lua`,
`tools/game_test.sh`, `factorio`, or any full suite, sheet run or headless run of any kind.** Run only single test
files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file
top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code (say so in its
header comment).

## Seconds-scale tool you must use

`lua5.2 tools/route_replay_one.lua <snapshot.lua.gz>` loads a saved route state at a failed demand and runs ONLY that
demand (~10 s). Env `PATCH=<file.lua>` (file returns `function(src) ... return src end`) applies an in-memory change
to `logic/bp/route.lua` for trials. Prints `REPLAY placed|failed code=... reason=... path=N cells t=...`, then path
cells (`J<n>` = underground jump), and with `MAP=1` a tile map.

## Explain very simply

Lane 250 taught the router: when a path visits one tile twice and the commit refuses it as `route-discontinuous`,
retry that demand with `no_self_cross`. On the player's gray + magenta sheet at grid 54x254 (frozen route,
legalcopilot-dev, 2026-09-27) electric furnace's path loops (18,207) -> (18,208) -> (19,208) -> (19,209) ->
(18,209) -> (18,208) -> (17,208): tile (18,208) twice. This time the commit refuses it as `occupied` (the second
visit lands on the belt the same path just laid), so the retry never fires; the demand dies even when first in order.

Fix F5b: the existing branch in `Route.step` (`elseif not placed and reason == "route-discontinuous" and (not
demand.no_chain_dive or not demand.no_self_cross) then`) also fires when the refused path visits a tile twice and the
reason is not `capacity` and the demand has no `no_self_cross` yet. Everything inside the branch stays as is.
Reference (measured in memory): `docs/tasks/ref/253_patch_reference.lua`. With it the demand places in 0.12 s.

## What to build

1. `tests/test_route_self_cross_occupied.lua` (commit red first):
   - SO1: `io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_54_furnace.lua.gz 2>&1")`
     -> `REPLAY placed` (base: `REPLAY failed ... reason=occupied`).
   - SO2: the placed path (second output line) has no tile twice.
2. `logic/bp/route.lua`: F5b as above, short comment citing tiles and date.

## Files this lane owns

logic/bp/route.lua, tests/test_route_self_cross_occupied.lua, docs/tasks/253_route_self_cross_occupied.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/253`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane253-tests", "command": "git diff --name-only round-44-wave6 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_self_cross_occupied\\.lua|docs/tasks/253_[a-z_]+\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave6 HEAD -- docs/tasks && ! git diff round-44-wave6 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_self_cross_occupied test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_crowded_fluids test_route_fluid_port_ptg test_route_network test_pipe_runs test_pipe_prune test_route_belt_chain test_route_pipe_join test_route_pipe_ptg_side test_route_no_self_cross test_route_shared_hand test_route_dead_ends test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane253-tests-ok", "expect_exit": 0, "expect_regex": "lane253-tests-ok", "timeout_s": 3000}
{"name": "lane253-fast", "command": "out=$(lua5.2 tests/test_route_self_cross_occupied.lua 2>&1); for n in SO1 SO2; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane253-ok", "expect_exit": 0, "expect_regex": "lane253-ok", "timeout_s": 600}
```

# bound: 3000s
