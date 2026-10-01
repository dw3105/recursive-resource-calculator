# 303_turn_flip_fluid_route: fluid inputs reach turned machines: edge slots with room, router goes around

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-303`, branch `lane/303`,
base tag `round-54-wave2b-base` (the commit that holds this task file), merge target `int/r54`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every row listed under "Rows that must turn valid" is valid on BOTH versions and BOTH checks pass.
Commit early, commit again, run the checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tools/turn_flip_census.sh`, `tools/ckpt.lua`, `factorio`, `tests/test_drawn_e2e.lua`, `tests/test_turn_flip_census.lua`,
or any full suite, full census, whole golden sheet or headless run of any kind.** The census tool runs ONLY filtered
to one case + one Turn (+ one Flip): `timeout 110 lua5.2 tools/turn_flip_census.lua tests/fixtures/turn_flip_cases_2.1.json
--case <id> --turn <t> --flip <f>` (and the same with `_2.0.json`), ~2-8 s each. Single test files only:
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4). The census writes the generator input and result to
`/tmp/turn_flip_<case>_<t>_<f>.json` / `.r.json`; read `result.errors[1].reason_details` there. Never use `coroutine`
or `math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Deterministic: fixed
scan order, ties broken by id string. Every new test must FAIL on the base code (say so in its header comment, with
date 2026-10-01); commit it red first, then the code.

Read `CONTEXT.md` first: **Block**, **Row**, **Turn**, **Flip**, **Box binding**, **Engine rule**, **Fallback**. Say
"Turn" and "Flip"; never "orient"/"orientation" in new names, comments or messages.

## Why (explain very simply)

A Block can Turn (0, 4, 8, 12 = north, east, south, west) and Flip (mirror). The census forces tiny one-machine-type
sheets (inputs from the left, outputs to the top) into every Turn and Flip. Rows below fail today. The switch
`settings.force_turn_flip` (already in the code) forces them; no Fallback runs while it is set, so a failure is real.
Fix the cause in the code this lane owns, so every listed row builds valid. Rows that are valid today must stay valid.

## What is wrong (measured by the integrator, legalcopilot-dev 2026-10-01; maps from `tools/route_replay_one.lua`)

A first attempt changed only `logic/bp/route.lua` and fixed no row: two separate causes sit in two files.

1. **Edge input slots of two fluids too close (search.lua).** oil-refinery-advanced-oil-processing-1 Turn 0 Flip 0:
   refinery Block at x 1..5, y 16..20 (one tile off the left edge). Its water pipe tile (2,21), crude pipe tile (4,21)
   (bottom side). `generated_perimeter_ports` (`logic/bp/search.lua` ~910, `perimeter_slots(grid, edge, pitch)`) put
   `in:fluid/water` at (0,20) and `in:fluid/crude-oil` at (0,22). Every water path to (2,21) must use (0,21) or
   (1,22), both pipe-neighbours of the crude source (0,22), and (3,21) touches the crude pipe tile (4,21): no legal
   path (`BP_R_NO_PATH`), so validate reports `BP_V_ROUTE_MISSING` / `BP_V_FLUID_DISCONNECTED`. Edge slots of
   DIFFERENT fluids must leave room for each fluid to reach its port without touching the other (at least 2 empty
   tiles between two fluid edge ports, or slots chosen by the side/order their ports need).
   Repro: `tools/capture_stage_input.lua /tmp/turn_flip_<row>.json <out.json> route` then `tools/route_fail_snapshot.lua
   <out.json> 0 <snap>` then `MAP=1 tools/route_replay_one.lua <snap>.2` (all under `timeout 110`, seconds).
2. **Router gives up on a path that exists (route.lua).** chemical-plant-plastic-bar-1 Turn 4 Flip 0: the turned
   chemical plant's gas pipe tile is on the RIGHT side; source `in:fluid/petroleum-gas` at (0,18) on the left.
   Cells reserved for item ports (`work.port_cells`, `p` on the map) ring the top and bottom of the machine, but a
   path around them exists on the map; the router returns `BP_R_NO_PATH`. Find which rule or bound stops it (search
   box / expansion limit / a reserved-cell rule that blocks a cell it need not block) and fix it so a fluid can go
   around a turned machine. electromagnetic-plant-electrolyte-1 Turn 4 (holmium solution from one Block to another)
   fails the same way: check it after your fix.
3. Then go down the row list; every remaining failing row: replay it the same way, find its cause, fix it.

## What to build

- Fixes in the files this lane owns. Switch absent must keep today's bytes for the fast goldens: TF5 in
  `tests/test_force_turn_flip.lua` (red-1s) stays green.
- `tests/test_turn_flip_fluid_route.lua` (new, red on base), markers:
  - TFR1: two fluid inputs whose ports sit on the bottom of one machine next to the left edge get edge slots from
    which both can be routed (build the case by hand: one 5x5 machine at x=1, two fluid ports on its bottom side).
  - TFR2: a fluid input on the far side of a turned 3x3 machine whose top and bottom neighbours are reserved port
    cells is routed around them (path found, no fluid mix).
  - TFR3: no pipe tile of one fluid is a pipe neighbour of a tile of another fluid in TFR1 and TFR2 results.
  - Print each marker on pass.

## Rows that must turn valid (both versions where the case exists)

- `oil-refinery-advanced-oil-processing-1` Turn 0 Flip 0
- `chemical-plant-plastic-bar-1` Turn 4 Flip 0
- `electromagnetic-plant-electrolyte-1` Turn 4 Flip 0
- `chemical-plant-sulfuric-acid-1` Turn 8 Flip 0
- `oil-refinery-advanced-oil-processing-1` Turn 12 Flip 1
- `oil-refinery-advanced-oil-processing-4` Turn 0 Flip 0
- `cryogenic-plant-fluoroketone-1` Turn 4 Flip 0
- `electromagnetic-plant-electrolyte-1` Turn 12 Flip 0
- `assembling-machine-2-concrete-1` Turn 12 Flip 0
- `chemical-plant-plastic-bar-4` Turn 0 Flip 0
- `foundry-casting-iron-4` Turn 4 Flip 0
- `cryogenic-plant-fluoroketone-4` Turn 0 Flip 0
- `electromagnetic-plant-electrolyte-4` Turn 4 Flip 0
- `oil-refinery-advanced-oil-processing-4` Turn 8 Flip 0
- `chemical-plant-sulfuric-acid-4` Turn 8 Flip 0

## Rows valid today that must stay valid (spot check)

- `chemical-plant-plastic-bar-1` Turn 0 Flip 0
- `chemical-plant-sulfuric-acid-1` Turn 0 Flip 0
- `foundry-casting-iron-1` Turn 0 Flip 0
- `assembling-machine-2-concrete-1` Turn 0 Flip 0
- `assembling-machine-1-electronic-circuit-4` Turn 0 Flip 0

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/search.lua`, `tests/test_turn_flip_fluid_route.lua`.

## Commit, THEN check

Commit on `lane/303`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane303-tests", "command": "git diff --name-only round-54-wave2b-base HEAD | grep -Ev '^(logic/bp/route\\.lua|logic/bp/validate\\.lua|logic/bp/search\\.lua|tests/test_turn_flip_fluid_route\\.lua)$' | ( ! grep . ) && for t in test_turn_flip_fluid_route test_force_turn_flip test_route_crowded_fluids test_route_fluid_port_ptg test_route_pipe_join test_route_pipe_ptg_side test_validate_fluid_mix test_validate_fluid_port test_fluid_touch test_search_draw_phase test_search_pipeline test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane303-tests-ok", "expect_exit": 0, "expect_regex": "lane303-tests-ok", "timeout_s": 3000}
{"name": "lane303-rows", "command": "bad=0; for r in oil-refinery-advanced-oil-processing-1:0:0 chemical-plant-plastic-bar-1:4:0 electromagnetic-plant-electrolyte-1:4:0 chemical-plant-sulfuric-acid-1:8:0 oil-refinery-advanced-oil-processing-1:12:1 oil-refinery-advanced-oil-processing-4:0:0 cryogenic-plant-fluoroketone-1:4:0 electromagnetic-plant-electrolyte-1:12:0 assembling-machine-2-concrete-1:12:0 chemical-plant-plastic-bar-4:0:0 foundry-casting-iron-4:4:0 cryogenic-plant-fluoroketone-4:0:0 electromagnetic-plant-electrolyte-4:4:0 oil-refinery-advanced-oil-processing-4:8:0 chemical-plant-sulfuric-acid-4:8:0 chemical-plant-plastic-bar-1:0:0 chemical-plant-sulfuric-acid-1:0:0 foundry-casting-iron-1:0:0 assembling-machine-2-concrete-1:0:0 assembling-machine-1-electronic-circuit-4:0:0; do c=${r%%:*}; rest=${r#*:}; t=${rest%%:*}; f=${rest#*:}; for v in 2.0 2.1; do grep -q \"\\\"$c\\\"\" tests/fixtures/turn_flip_cases_$v.json || continue; out=$(timeout 110 lua5.2 tools/turn_flip_census.lua tests/fixtures/turn_flip_cases_$v.json --case $c --turn $t --flip $f 2>&1 | grep '^CENSUS ver'); echo \"$out\"; echo \"$out\" | grep -Eq 'result=(valid|forbidden)' || bad=1; done; done; [ $bad = 0 ] && echo lane303-rows-ok", "expect_exit": 0, "expect_regex": "lane303-rows-ok", "timeout_s": 3000}
```

# bound: 5400s
