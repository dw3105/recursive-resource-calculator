# 301_turn_flip_groups: mirrored Block rebuild keeps ports on the edge; turned Row ports off belt runs

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-301`, branch `lane/301`,
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

1. **Flip rebuild refuses every flippable fluid machine.** `Groups.reorient(groups, block, {dir=0, mirror=true})`
   (`logic/bp/groups.lua` ~2623) returns nil for chemical plant, cryogenic plant, EM plant and foundry: the rebuilt
   Block passes `_reorient_build` but `Groups.ports_on_edge(result)` is false (instrumented on
   chemical-plant-plastic-bar-1, electromagnetic-plant-electrolyte-1, foundry-iron-ore-melting-1, all Turn 0 Flip 1).
   So `build_block(..., {dir=0, mirror=true})` puts at least one port tile off the Block edge: the mirrored machine's
   fluid connection / pipe tile / item port is computed unmirrored somewhere (compare `fluid_pipe_tile` near :767,
   the port position code in `build_block`, and `Grid.fluid_connection(conn, dir, mirror)` in `logic/bp/grid.lua`,
   which mirrors x in the machine frame first, then turns — engine fact, see `tests/fixtures/flip_fluidboxes_*.txt`).
   Fix the mirrored build so every port sits on the Block edge exactly as for an unmirrored machine seen in a mirror.
   Generation error today: `BP_FAIL_FLIP_REBUILD`.
2. **Turned item row puts an output port on an input belt.** assembling-machine-1-electronic-circuit-4 Turn 4 and
   assembling-machine-2-concrete-4 Turn 4: validate `BP_V_PORT_EDGE_WRONG` — the output port
   `out:item/electronic-circuit:hand:...` tile is occupied by the `item/copper-cable` input run (`occupant_flow_id`).
   Row ports and belt runs of a Row turned east must not share tiles (row ports built near `groups.lua` :2130-2150;
   runs turned with `rotate_cell` :2841-2858).

## What to build

- Fix both in `logic/bp/groups.lua`.
- `tests/test_turn_flip_groups.lua` (new, red on base), markers:
  - TG1: mirrored rebuild of a one-machine chemical-plant-like Block (build the Block from a hand-made catalog entity
    with the chemical plant's fluid boxes copied from `tests/fixtures/flip_fluidboxes_2.1.txt`; no item names in
    `logic/`, names in tests are fine) -> `Groups.reorient` non-nil and `Groups.ports_on_edge` true.
  - TG2: mirrored fluid port tile = mirror (x -> w-1-x) of the unmirrored one for that Block.
  - TG3: a two-input Row turned east: no row port tile equals any belt run tile.
  - Print each marker on pass.

## Rows that must turn valid (both versions where the case exists)

- `chemical-plant-plastic-bar-1` Turn 0 Flip 1
- `chemical-plant-plastic-bar-1` Turn 4 Flip 1
- `chemical-plant-plastic-bar-4` Turn 8 Flip 1
- `chemical-plant-sulfuric-acid-1` Turn 12 Flip 1
- `chemical-plant-sulfuric-acid-4` Turn 0 Flip 1
- `cryogenic-plant-fluoroketone-1` Turn 0 Flip 1
- `cryogenic-plant-fluoroketone-4` Turn 4 Flip 1
- `electromagnetic-plant-electrolyte-1` Turn 8 Flip 1
- `electromagnetic-plant-electrolyte-4` Turn 12 Flip 1
- `foundry-iron-ore-melting-1` Turn 0 Flip 1
- `foundry-iron-ore-melting-4` Turn 8 Flip 1
- `foundry-casting-iron-1` Turn 0 Flip 1
- `assembling-machine-1-electronic-circuit-4` Turn 4 Flip 0
- `assembling-machine-1-electronic-circuit-4` Turn 4 Flip 1
- `assembling-machine-2-concrete-4` Turn 4 Flip 0

## Rows valid today that must stay valid (spot check)

- `assembling-machine-1-electronic-circuit-1` Turn 0 Flip 0
- `assembling-machine-1-electronic-circuit-4` Turn 8 Flip 0
- `chemical-plant-plastic-bar-1` Turn 0 Flip 0
- `foundry-casting-iron-1` Turn 0 Flip 0

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_turn_flip_groups.lua`.

## Commit, THEN check

Commit on `lane/301`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane301-tests", "command": "git diff --name-only round-54-wave2-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_turn_flip_groups\\.lua)$' | ( ! grep . ) && for t in test_turn_flip_groups test_force_turn_flip test_turned_block test_orient test_flip_geometry test_port_edges test_groups_rows test_pack_drawn test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane301-tests-ok", "expect_exit": 0, "expect_regex": "lane301-tests-ok", "timeout_s": 3000}
{"name": "lane301-rows", "command": "bad=0; for r in chemical-plant-plastic-bar-1:0:1 chemical-plant-plastic-bar-1:4:1 chemical-plant-plastic-bar-4:8:1 chemical-plant-sulfuric-acid-1:12:1 chemical-plant-sulfuric-acid-4:0:1 cryogenic-plant-fluoroketone-1:0:1 cryogenic-plant-fluoroketone-4:4:1 electromagnetic-plant-electrolyte-1:8:1 electromagnetic-plant-electrolyte-4:12:1 foundry-iron-ore-melting-1:0:1 foundry-iron-ore-melting-4:8:1 foundry-casting-iron-1:0:1 assembling-machine-1-electronic-circuit-4:4:0 assembling-machine-1-electronic-circuit-4:4:1 assembling-machine-2-concrete-4:4:0 assembling-machine-1-electronic-circuit-1:0:0 assembling-machine-1-electronic-circuit-4:8:0 chemical-plant-plastic-bar-1:0:0 foundry-casting-iron-1:0:0; do c=${r%%:*}; rest=${r#*:}; t=${rest%%:*}; f=${rest#*:}; for v in 2.0 2.1; do grep -q \"\\\"$c\\\"\" tests/fixtures/turn_flip_cases_$v.json || continue; out=$(timeout 110 lua5.2 tools/turn_flip_census.lua tests/fixtures/turn_flip_cases_$v.json --case $c --turn $t --flip $f 2>&1 | grep '^CENSUS ver'); echo \"$out\"; echo \"$out\" | grep -Eq 'result=(valid|forbidden)' || bad=1; done; done; [ $bad = 0 ] && echo lane301-rows-ok", "expect_exit": 0, "expect_regex": "lane301-rows-ok", "timeout_s": 3000}
```

# bound: 5400s
