# 252_route_dead_ends no pipe leaves a pipe-to-ground sideways; blocked straight feeds curve or turn at once

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-252`, branch `lane/252`,
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

Three more moves the router plans but cannot build, or retries far too late, traced on the frozen 154x154 route of
the player's gray + magenta sheet (legalcopilot-dev, 2026-09-27):

- F4b pipe LEAVES a pipe-to-ground on its buried side. Molten iron path (45,43) -> (45,42) -> (44,42): (45,42) is the
  exit of pair (45,35)->(45,42) heading south, exposed side (45,43). Stepping west to (44,42) leaves through a side
  that connects to nothing; `route_chain_walk` refuses `route-discontinuous`. `path_cell_free` already checks ENTERING
  an endpoint (lane 249). Add the mirror: when the tile we come FROM holds a pipe-to-ground endpoint, the step is
  allowed only to its exposed tile or its partner.
- F7 row feed port whose straight-in tile is a machine: piercing rounds sink (85,54) wants arrival heading east, but
  (84,54) is a machine. Only the curve works, and `curve_allowed` is granted only after a failed search + a full
  restart (two 28 s searches). In `begin_search`: `feed_curve` sink whose tile behind (`sink - travel_dir`) has a
  `static_owner` -> `demand.curve_allowed = true` at once.
- F9 machine output heading into a machine: plastic bar source (146,70) heading west into (145,70), a machine.
  `free_heading` is granted only after failure + restart. In `begin_search`: non-perimeter, non-row source whose tile
  ahead (`source + travel_dir`) has a `static_owner` -> `demand.free_heading = true` at once.

Reference patches (measured in memory): `docs/tasks/ref/252_patch_reference_f4b.lua` (applies on top of the
current source, it anchors on lane 249's comment) and `docs/tasks/ref/252_patch_reference_f79.lua`. With them the
three demands place in 0.05-0.35 s, and all 31 `tests/test_route*.lua` + `test_pipe_runs` + `test_pipe_prune` stay
green. Put the same logic into the source, readable, with a short comment at each spot citing tiles and date.

## What to build

1. `tests/test_route_dead_ends.lua` (commit red first), each via `io.popen("lua5.2 tools/route_replay_one.lua <f> 2>&1")`:
   - DE1: `tests/fixtures/route_snaps/gray_magenta_154_molten_iron.lua.gz` -> `REPLAY placed` (base: failed).
   - DE2: `tests/fixtures/route_snaps/gray_magenta_154_piercing.lua.gz` -> `REPLAY placed` (base: failed after ~30 s).
   - DE3: `tests/fixtures/route_snaps/gray_magenta_154_plastic.lua.gz` -> `REPLAY placed` (base: failed).
2. `logic/bp/route.lua`: F4b, F7, F9 as above.

## Files this lane owns

logic/bp/route.lua, tests/test_route_dead_ends.lua, docs/tasks/252_route_dead_ends.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/252`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane252-tests", "command": "git diff --name-only round-44-wave5 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_dead_ends\\.lua|docs/tasks/252_[a-z_]+\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave5 HEAD -- docs/tasks && ! git diff round-44-wave5 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_dead_ends test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_crowded_fluids test_route_fluid_port_ptg test_route_network test_pipe_runs test_pipe_prune test_route_belt_chain test_route_pipe_join test_route_pipe_ptg_side test_route_no_self_cross test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane252-tests-ok", "expect_exit": 0, "expect_regex": "lane252-tests-ok", "timeout_s": 3000}
{"name": "lane252-fast", "command": "out=$(lua5.2 tests/test_route_dead_ends.lua 2>&1); for n in DE1 DE2 DE3; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane252-ok", "expect_exit": 0, "expect_regex": "lane252-ok", "timeout_s": 600}
```

# bound: 3000s
