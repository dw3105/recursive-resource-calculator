# 260_groups_port_heading an item port whose along-face heading runs into another item's port points away from its machine

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-260`, branch `lane/260`,
base tag `round-45-w3`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

On `player-inserter-10s-stack1` (legalcopilot-dev, 2026-09-27) block `block:electronic-circuit` (one 4x4 plant at
(4,4)) has output hand 5 of circuit on the top face at (7,3); its port (7,2) is declared with `travel_dir = 12`
(west). The next tile west, (6,2), is the pickup port of copper-cable input hand 7. Route laid circuit north (legal);
the validator checks the tile ahead of an output port along `travel_dir` and refused `BP_V_PORT_EDGE_WRONG`
("port-owned tile carries another flow" at the cable tile). The declaration itself is wrong: an output belt cannot
leave along the face into another item's pickup.

Fix, at the end of `block_ports` in `logic/bp/groups.lua` (after the last `place_side` calls): for every item
(non-fluid, not `fluid_pinned`) port with `inserter_id` and `travel_dir`, if the tile ahead (out) or behind (in) along
`travel_dir` is the `attach_dx/attach_dy` of a port of a DIFFERENT flow in the same block, set `travel_dir` to point
straight away from the machine: `dir_from_vector(attach - hand tile)` for out, its opposite for in. Reference
(measured in memory): `docs/tasks/ref/260_patch_reference.lua`. Measured: stack1 circuit hand 5 -> `travel_dir 0`,
PORT_EDGE_WRONG gone; port headings of all 11 gated golden sheets + am2-repaired unchanged (hash of block|port|travel
per sheet identical with and without the patch).

## What to build

1. `tests/test_groups_port_heading.lua` (commit red first):
   - PH1: replay `tests/fixtures/groups_ins_stack1.json` (pattern of `tests/test_groups_pad_faces.lua`) -> port
     `out:item/electronic-circuit:hand:5:inserter:electronic-circuit:1:output:15` has `travel_dir == 0`; and in every
     block no item port's ahead (out) / behind (in) tile is another flow's port tile. Red on base.
   - PH2: replay `tests/fixtures/groups_red1s_foundry.json` -> every port's `travel_dir` equals base (paste a sorted
     `block|port|travel` hash computed on `round-45-w3`).
2. `logic/bp/groups.lua`: the rule, short comment citing block, tiles, date.

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_port_heading.lua, docs/tasks/260_groups_port_heading.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/260`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane260-tests", "command": "git diff --name-only round-45-w3 HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_port_heading\\.lua|docs/tasks/260_groups_port_heading\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w3 HEAD -- docs/tasks && ! git diff round-45-w3 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_port_heading test_groups test_groups_pad_faces test_groups_hand_off_pipe test_groups_lone_slots test_groups_hands_overflow test_groups_beacon_pad test_groups_faces_beacon_rows test_groups_interior_port test_inserter_geometry test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane260-tests-ok", "expect_exit": 0, "expect_regex": "lane260-tests-ok", "timeout_s": 3000}
{"name": "lane260-fast", "command": "out=$(lua5.2 tests/test_groups_port_heading.lua 2>&1); for c in PH1 PH2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane260-ok", "expect_exit": 0, "expect_regex": "lane260-ok", "timeout_s": 600}
```

# bound: 3000s
