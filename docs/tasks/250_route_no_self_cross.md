# 250_route_no_self_cross a path never steps on its own tile twice, and dives only from a free tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-250`, branch `lane/250`,
base tag `round-44-wave4`, merge target `int/r44`. Host `legalcopilot-dev`.

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

A search state is (tile, heading, mode), so one path may pass the SAME tile twice with different headings. The
commit cannot build that (one tile, one entity) and refuses. Traced on the player's gray + magenta sheet (frozen
route 154x154, legalcopilot-dev, 2026-09-27):
- iron stick: path surfaces at its own exit (123,18), goes (124,18) (124,17) (123,17) and back onto (123,18), then to
  the sink (123,19) -> `route-discontinuous`.
- steel plate: surfaces at (65,25), loops (65,26) (64,26) (64,25) back onto (65,25) and dives east from it ->
  `crossing-occupied` five times (crossing retries), demand dies.
- molten iron: dives from (86,20), a tile already holding its own pipe -> `crossing-occupied` five times.

GENTLE rule (same pattern as `no_chain_dive` already in the source): old sheets survive these refusals by restarting in
a new order, and banning always moves frozen test geometry. So a demand gets the ban only when needed:
- F5: route step, commit refused `route-discontinuous`: path visits a tile twice and demand has no `no_self_cross` ->
  `restart_with_priority`; if refused, `demand.no_self_cross = true` and search again. Extend the existing
  `two_crossings` branch (it must still set `no_chain_dive` only for chain dives).
  `enqueue_state`: with `search.demand.no_self_cross`, refuse a state whose tile already lies on its parent chain.
- F6: crossing-occupied branch: when `crossing_retries` passes 4 and demand has no `strict_dive` ->
  `demand.strict_dive, demand.no_self_cross = true, true`, `crossing_retries = 0`, search again (else fail as today).
  Dive guard: with `strict_dive`, no dive from mode 1 and no dive from a tile that already holds a segment.

Reference patches (in memory, measured): `docs/tasks/ref/250_patch_reference_f5.lua`,
`docs/tasks/ref/250_patch_reference_f6.lua` (F6 applies after F5). With them 3 tail failures place in 2.7-4.0 s and
all 31 `tests/test_route*.lua` + `test_pipe_runs` + `test_pipe_prune` stay green. Put the same logic into the source,
readable, a short comment at each spot citing tiles + date.

## What to build

1. `tests/test_route_no_self_cross.lua` (commit red first), replays via
   `io.popen("lua5.2 tools/route_replay_one.lua <fixture> 2>&1")`:
   - NS1: `tests/fixtures/route_snaps/gray_magenta_154_fail4.lua.gz` -> `REPLAY placed` (base: failed,
     route-discontinuous).
   - NS2: `tests/fixtures/route_snaps/gray_magenta_154_fail3.lua.gz` -> `REPLAY placed` (base: failed,
     crossing-occupied).
   - NS3: for NS1's placed output, the printed path has no tile twice.
2. `logic/bp/route.lua`: F5 + F6 as above.

## Files this lane owns

logic/bp/route.lua, tests/test_route_no_self_cross.lua, docs/tasks/250_route_no_self_cross.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/250`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane250-tests", "command": "git diff --name-only round-44-wave4 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_no_self_cross\\.lua|docs/tasks/250_[a-z_]+\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave4 HEAD -- docs/tasks && ! git diff round-44-wave4 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_no_self_cross test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_crowded_fluids test_route_fluid_port_ptg test_route_network test_pipe_runs test_pipe_prune test_route_belt_chain test_route_pipe_join test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane250-tests-ok", "expect_exit": 0, "expect_regex": "lane250-tests-ok", "timeout_s": 3000}
{"name": "lane250-fast", "command": "out=$(lua5.2 tests/test_route_no_self_cross.lua 2>&1); for n in NS1 NS2 NS3; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane250-ok", "expect_exit": 0, "expect_regex": "lane250-ok", "timeout_s": 600}
```

# bound: 3000s
