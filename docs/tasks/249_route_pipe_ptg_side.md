# 249_route_pipe_ptg_side a pipe joins a pipe-to-ground only on its exposed side

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-249`, branch `lane/249`,
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

A pipe-to-ground has two sides: its exposed side joins a normal pipe; its buried side joins only its partner. On the
player's gray + magenta sheet (frozen route, 154x154, legalcopilot-dev, 2026-09-27) fluid paths END by stepping onto
an existing same-fluid pipe-to-ground from its BURIED side: light oil (35,49) -> exit (36,49) of pair (26,49)->(36,49)
heading east; molten iron (66,39) -> exit (66,40) of pair (66,30)->(66,40) heading south. In the game those pipes do
not connect. `route_chain_walk` correctly refuses (`route-discontinuous`), the demand fails and all 92 demands restart.
The search (`path_cell_free`) must refuse that step: a pipe demand may enter a pipe-to-ground endpoint tile only from
its exposed tile (behind the entry, ahead of the exit, both along `segment.direction`) or from its partner.

Measured in memory (reference `docs/tasks/ref/249_patch_reference.lua`): 4 of 9 tail failures placed in ~0.5 s each;
all 31 `tests/test_route*.lua` + `test_pipe_runs` + `test_pipe_prune` stay green. Put the same logic into the
source (in `path_cell_free`, before `if segment then`), readable, with a short comment citing tiles + date.

## What to build

1. `tests/test_route_pipe_ptg_side.lua` (commit red first):
   - PS1: replay `tests/fixtures/route_snaps/gray_magenta_154_fail2.lua.gz` via
     `io.popen("lua5.2 tools/route_replay_one.lua tests/fixtures/route_snaps/gray_magenta_154_fail2.lua.gz 2>&1")`
     -> output has `REPLAY placed` (base: `REPLAY failed ... reason=route-discontinuous`).
   - PS2 synthetic (`Route.begin`, shapes of `tests/test_route_pipe_join.lua`): one fluid with an existing pair laid
     by a first demand; a second demand whose only short way reaches the pair's buried side must not end there:
     result `ok == true` and `route_chain_walk`-style check — every binding of the fluid reaches its sink (use the
     route result: no shortfalls, no errors). If you cannot build a geometry that is red on base within 15 minutes,
     drop PS2 and write why in the test header; PS1 alone is enough.
2. `logic/bp/route.lua`: the F4 rule as in the reference patch.

## Files this lane owns

logic/bp/route.lua, tests/test_route_pipe_ptg_side.lua, docs/tasks/249_route_pipe_ptg_side.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/249`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane249-tests", "command": "git diff --name-only round-44-wave4 HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_pipe_ptg_side\\.lua|docs/tasks/249_[a-z_]+\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave4 HEAD -- docs/tasks && ! git diff round-44-wave4 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_pipe_ptg_side test_route test_route_budget test_route_chain test_route_collision test_route_tidy_junk test_route_footprints test_route_splitter_physics test_route_splitter_straight test_route_merge_feed test_route_output_join test_route_crowded_fluids test_route_fluid_port_ptg test_route_network test_pipe_runs test_pipe_prune test_route_belt_chain test_route_pipe_join test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane249-tests-ok", "expect_exit": 0, "expect_regex": "lane249-tests-ok", "timeout_s": 3000}
{"name": "lane249-fast", "command": "out=$(lua5.2 tests/test_route_pipe_ptg_side.lua 2>&1); for n in PS1; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane249-ok", "expect_exit": 0, "expect_regex": "lane249-ok", "timeout_s": 600}
```

# bound: 3000s
