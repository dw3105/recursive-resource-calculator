# 229_fluid_touch no pipe is ever laid beside another fluid's pipe

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-229`, branch `lane/229`,
base tag `round-40-base`, merge target `int/r40`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua`, `logic/bp/route.lua` or `logic/bp/search.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY),
`tools/stage_fail.lua` and `tools/bytes_hash.sh`. Never use `coroutine`. Plain data only. `require` only at file
top level (`tests/test_no_runtime_require.lua`). **No game item or fluid name in code**
(`tests/test_no_item_names.lua`; tests use made-up flow ids like `fluid/a`). Every new test must FAIL on the base
code (write that in the test's header comment).

## Explain very simply

A plain pipe joins every pipe next to it. So a pipe of one fluid laid beside a pipe of another fluid mixes both
(`BP_V_FLUID_MIX`). The router refuses to step ONTO another fluid's pipe, but never refuses the tile BESIDE it. And
the pass that lifts an empty pipe-to-ground pair back to the surface (`unbury_empty_pairs`) lays plain pipes without
looking beside them either. The player's red + green science 10/s sheet
(`tests/golden/cases/player-red-green-science-10s`) fails on exactly this: molten iron pipe (8,24) beside molten
copper pipe (9,24).

Base already calls both answers from `logic/bp/route.lua` (first line of `path_cell_free`; and in
`unbury_empty_pairs`, where `true` keeps the pair buried). Both are stubs returning `false` in
`logic/bp/fluid_touch.lua`. Fill them.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = round-39 main + `PROBE_A` + `PROBE_C` parts of
`docs/tasks/r40_probe_reference.diff`: first `STAGE validate` line of `tools/stage_fail.lua` on the new case is
`STAGE validate ok=false BP_V_UNDERGROUND_SIDELOAD_BLOCKED=1` (the fluid mix is gone; the side-load fault is another
task's). All 8 older sheets stay byte-identical to `tests/fixtures/bytes_round39.txt`.

## What to build

`cells` maps `key(x, y)` to a route segment (`key` is route.lua's `coordinate_key`, pass-through). A segment has
`kind` ("pipe" / "belt"), `underground` (true for a pipe-to-ground pair), `flow_id` and maybe `flow_ids` (set:
`flow_ids[id] == true`). "Has flow f" = `segment.flow_id == f or (segment.flow_ids and segment.flow_ids[f] == true)`.
Neighbours = the 4 tiles (x±1, y) and (x, y±1).

1. `FluidTouch.path_blocked(cells, key, demand, x, y)`: `false` unless `demand.kind == "pipe"`. Then `true` when any
   neighbour segment has `kind == "pipe"`, is NOT `underground`, and does not have flow `demand.flow_id`.
2. `FluidTouch.unbury_blocked(cells, key, pair, tiles)`: `false` unless `pair.kind == "pipe"`. Then `true` when any
   tile in `tiles` (`{x=, y=}` list) has a neighbour segment `~= pair` with `kind == "pipe"` (underground or not)
   that does not have flow `pair.flow_id`.
3. Exactly as `PROBE_A` (`foreign_pipe_beside`) and `PROBE_C` in the reference diff; no env flags.
4. `tests/test_fluid_touch.lua`, hand-built cells: FT1 foreign plain pipe beside → path blocked; FT2 same-flow pipe
   beside → free; FT3 foreign pipe-to-ground beside → path free; FT4 belt demand beside foreign pipe → free; FT5
   unbury tile beside foreign pipe → blocked, beside same flow → free, belt pair → free; FT6 `Route.begin` on a small
   grid (see `tests/test_route_bury.lua` for the shape of a hand-built route input) with two fluid flows whose
   straight paths would run side by side: route ok and no two different-flow plain pipes are orthogonal neighbours.

## Files this lane owns

logic/bp/fluid_touch.lua, tests/test_fluid_touch.lua, docs/tasks/229_fluid_touch.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/229`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane229-tests", "command": "git diff --name-only round-40-base HEAD | grep -Ev '^(logic/bp/fluid_touch\\.lua|tests/test_fluid_touch\\.lua|docs/tasks/229_fluid_touch\\.md)$' | ( ! grep . ) && git diff --quiet round-40-base HEAD -- docs/tasks/229_fluid_touch.md && ! git diff round-40-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_fluid_touch test_route_bury test_validate_fluid_mix test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane229-tests-ok", "expect_exit": 0, "expect_regex": "lane229-tests-ok", "timeout_s": 3000}
{"name": "lane229-measure", "command": "f=$(mktemp); timeout 1500 lua5.2 tools/stage_fail.lua tests/golden/cases/player-red-green-science-10s/prepared_input.json > $f 2>&1; grep -m1 \"^STAGE validate\" $f | grep -qxF 'STAGE validate ok=false BP_V_UNDERGROUND_SIDELOAD_BLOCKED=1' || { echo STAGE-WRONG; exit 1; }; for c in player-red-science-10s-bulk player-red-science-10s player-red-science-10s-stack1 player-red-science-1s player-red-science-1s-bulk player-green-science-1s player-inserter-10s player-inserter-10s-bulk; do l=$(sh tools/bytes_hash.sh $c); grep -qxF \"$l\" tests/fixtures/bytes_round39.txt || { echo BYTES-DIFF $c; exit 1; }; done; echo lane229-ok", "expect_exit": 0, "expect_regex": "lane229-ok", "timeout_s": 3000}
```

# bound: 2400s
