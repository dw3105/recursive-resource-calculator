# 251_route_shared_hand a second flow of a shared input hand side-joins the belt at its hand tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-251`, branch `lane/251`,
base tag `round-44-wave5`, merge target `int/r44`. Host `legalcopilot-dev`.

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

On the player's gray + magenta sheet a `rail` machine takes stone AND iron stick with ONE inserter (groups pair two
input flows on one cell when `multi_flow_hands` is on: 17.9 + 17.9 of a 60/s belt). Both flows must arrive on the one
belt tile the inserter picks from, (85,39) on the frozen 154x154 route (legalcopilot-dev, 2026-09-27). Iron stick
arrives first and lays its belt heading south through (85,39). Stone must side-join that belt at (85,39). In
`path_cell_free`, the side-entry branch refuses any foreign-flow side entry under `multi_flow_hands` unless the
improve pass's `search.merge_target` is set, so in first routing stone can NEVER reach its hand: in a 30 min CPU run
stone failed 11 of 23 times and restarted all 92 demands each time.

Fix F8: the side entry is allowed when it is the demand's own target tile AND that tile is a shared hand: its port
cell lists this demand's sink port AND `flow:<the flow already on that belt>`. Nothing else changes.
Reference (measured in memory): `docs/tasks/ref/251_patch_reference.lua`. With it the stone demand places in 0.35 s,
and all 31 `tests/test_route*.lua` + `test_pipe_runs` + `test_pipe_prune` stay green. Put the same logic into the
source, readable, with a short comment citing the tile and date.

## What to build

1. `tests/test_route_shared_hand.lua` (commit red first):
   - SH1: `lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_stone.lua.gz` (via
     `io.popen(... .. " 2>&1")`) -> `REPLAY placed` (base: `REPLAY failed`).
   - SH2: the placed path's last cell is `85,39` (the shared hand tile).
2. `logic/bp/route.lua`: F8 as above.

## Files this lane owns

logic/bp/route.lua, tests/test_route_shared_hand.lua, docs/tasks/251_route_shared_hand.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/251`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane251-tests", "command": "git diff --name-only round-44-wave5 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_shared_hand\\.lua|docs/tasks/251_[a-z_]+\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave5 HEAD -- docs/tasks && ! git diff round-44-wave5 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_shared_hand test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_crowded_fluids test_route_fluid_port_ptg test_route_network test_pipe_runs test_pipe_prune test_route_belt_chain test_route_pipe_join test_route_pipe_ptg_side test_route_no_self_cross test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane251-tests-ok", "expect_exit": 0, "expect_regex": "lane251-tests-ok", "timeout_s": 3000}
{"name": "lane251-fast", "command": "out=$(lua5.2 tests/test_route_shared_hand.lua 2>&1); for n in SH1 SH2; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane251-ok", "expect_exit": 0, "expect_regex": "lane251-ok", "timeout_s": 600}
```

# bound: 3000s
