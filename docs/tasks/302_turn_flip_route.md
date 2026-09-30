# 302_turn_flip_route: fluid input reaches turned ports; fluids never mix

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-302`, branch `lane/302`,
base tag `round-54-wave2-base` (the commit that holds this task file), merge target `int/r54`. Host `legalcopilot-dev`.

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

## What is wrong (measured by the integrator, legalcopilot-dev 2026-09-30)

1. **Fluid input never routed to a turned machine's fluid port.** validate: `BP_V_ROUTE_MISSING` for
   `fluid/<input fluid>` + `BP_V_FLUID_DISCONNECTED` (`first_illegal_step = "fluid connection"`) +
   `BP_V_PORT_UNREACHABLE` ("no binding uses this port as a sink/source") on the edge input `in:fluid/...` and the
   machine port `...:in:fluid/...`. Rows: chemical-plant-plastic-bar-1 Turn 4 Flip 0 (petroleum gas), oil-refinery
   Turn 0 Flip 0 (water, even unturned!), cryogenic Turn 4, EM plant Turn 4, asm-2 concrete Turn 12, ... The route
   either never asks for this demand or cannot reach the port. Start from `tools/route_fail_snapshot.lua` /
   `tools/route_replay_one.lua` (skill rung 3) on the census `/tmp/turn_flip_<row>.json` input if useful, or
   `ckpt`-free direct `Route` calls. Look at fluid endpoint position for turned/rotated ports (`rotate_connection`
   `logic/bp/route.lua` ~247, used ~281 and ~295; `endpoint_position`) and at which side of the Block the pipe must
   leave from.
2. **Two fluids' pipes touch.** route/validate `BP_R_FLUID_MIX` on multi-fluid machines turned: cryogenic x4, EM
   plant x4, oil-refinery Turn 4/8/12, sulfuric-acid x4 Turn 8. Pipes of different fluids must never be adjacent in a
   way the engine joins (pipe-to-pipe neighbour, or a pipe on another box's connection tile).

## What to build

- Fix both in `logic/bp/route.lua` (and `logic/bp/validate.lua` ONLY if the validator is wrong: prove it with the
  engine box facts in `tests/fixtures/flip_fluidboxes_*.txt` / `box_binding_*.txt` and say so in the commit).
- `tests/test_turn_flip_route.lua` (new, red on base), markers:
  - TR1: one refinery-like 5x5 machine at Turn 0, water from the left edge: route has a fluid path edge -> the box the
    Box binding names (build the input by hand; no item names in `logic/`).
  - TR2: same machine turned 4: path reaches the turned connection tile.
  - TR3: two fluid inputs on neighbouring connections of a turned machine: no tile of fluid A is a pipe neighbour of
    a tile of fluid B (no fluid mix).
  - Print each marker on pass.

## Rows that must turn valid (both versions where the case exists)

- `chemical-plant-plastic-bar-1` Turn 4 Flip 0
- `chemical-plant-sulfuric-acid-1` Turn 8 Flip 0
- `oil-refinery-advanced-oil-processing-1` Turn 0 Flip 0
- `oil-refinery-advanced-oil-processing-1` Turn 12 Flip 1
- `oil-refinery-advanced-oil-processing-4` Turn 0 Flip 0
- `cryogenic-plant-fluoroketone-1` Turn 4 Flip 0
- `electromagnetic-plant-electrolyte-1` Turn 4 Flip 0
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

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/validate.lua`, `tests/test_turn_flip_route.lua`.

## Commit, THEN check

Commit on `lane/302`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane302-tests", "command": "git diff --name-only round-54-wave2-base HEAD | grep -Ev '^(logic/bp/route\\.lua|logic/bp/validate\\.lua|tests/test_turn_flip_route\\.lua)$' | ( ! grep . ) && for t in test_turn_flip_route test_force_turn_flip test_route_crowded_fluids test_route_fluid_port_ptg test_route_pipe_join test_route_pipe_ptg_side test_validate_fluid_mix test_validate_fluid_port test_fluid_touch test_fluid_box test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane302-tests-ok", "expect_exit": 0, "expect_regex": "lane302-tests-ok", "timeout_s": 3000}
{"name": "lane302-rows", "command": "bad=0; for r in chemical-plant-plastic-bar-1:4:0 chemical-plant-sulfuric-acid-1:8:0 oil-refinery-advanced-oil-processing-1:0:0 oil-refinery-advanced-oil-processing-1:12:1 oil-refinery-advanced-oil-processing-4:0:0 cryogenic-plant-fluoroketone-1:4:0 electromagnetic-plant-electrolyte-1:4:0 electromagnetic-plant-electrolyte-1:12:0 assembling-machine-2-concrete-1:12:0 chemical-plant-plastic-bar-4:0:0 foundry-casting-iron-4:4:0 cryogenic-plant-fluoroketone-4:0:0 electromagnetic-plant-electrolyte-4:4:0 oil-refinery-advanced-oil-processing-4:8:0 chemical-plant-sulfuric-acid-4:8:0 chemical-plant-plastic-bar-1:0:0 chemical-plant-sulfuric-acid-1:0:0 foundry-casting-iron-1:0:0 assembling-machine-2-concrete-1:0:0; do c=${r%%:*}; rest=${r#*:}; t=${rest%%:*}; f=${rest#*:}; for v in 2.0 2.1; do grep -q \"\\\"$c\\\"\" tests/fixtures/turn_flip_cases_$v.json || continue; out=$(timeout 110 lua5.2 tools/turn_flip_census.lua tests/fixtures/turn_flip_cases_$v.json --case $c --turn $t --flip $f 2>&1 | grep '^CENSUS ver'); echo \"$out\"; echo \"$out\" | grep -Eq 'result=(valid|forbidden)' || bad=1; done; done; [ $bad = 0 ] && echo lane302-rows-ok", "expect_exit": 0, "expect_regex": "lane302-rows-ok", "timeout_s": 3000}
```

# bound: 5400s
