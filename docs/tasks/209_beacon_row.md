# 209_beacon_row groups: a beaconed machine row keeps both hand faces

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-209_beacon_row`, branch `lane/209_beacon_row`,
base tag `round-36-base`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data in `storage` only (no closures, no metatables). Unit tests
finish in under 20 s; GUI/control tests loop over `H.shapes()` and move time only with `H.run_ticks(world, n)`.

Read `docs/contracts/round36.md` first: it is the contract. Your clauses: B1, B2, B3.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK` or `GATE-FAIL`).

## Explain very simply

`lua5.2 tools/stage_fail.lua tests/golden/cases/player-red-science-10s/prepared_input.json` on base: every attempt
`STAGE groups ok=false BP_P_NO_FIT:bottom beacon row claims the port-bound inserter face`. The sheet has 10
assembling-machine-3 in one row, 3 beacons each. `logic/bp/groups.lua` adds a bottom beacon row when a machine wants
more than 2 beacons (`if count > 2`), and that row takes the bottom hand face. Measured further with that rule off:
route `BP_R_PORT_BLOCKED` — the row puts machines one tile under the top beacon row (`machine_y = beacon_rows_h + 1`),
so the top hands pick from a beacon tile. The row's input side needs near belt, far belt, feed row and hand; beacon
supply reaches 3 tiles. The output side needs output hand + output belt = 2 tiles: that is where the beacon row goes.

## What to build

1. B1 beacon row on the output side of a beaconed row (after output hand and output belt); inputs stay on top.
2. B2 the row extends past the row ends until every machine is reached ≥ `count_per_machine` (use
   `Geometry.supply_box` against each machine's world box); drop beacons that reach no machine.
3. B3 a second row only when one row cannot reach the count; never on a hand or belt tile.
4. Test (red at base first): new `tests/test_groups_beacon_row.lua`: 10 machines, 3 beacons each, 2 input flows →
   exactly one beacon row, on the output side; every machine reached ≥ 3 by supply box; no beacon on a hand or
   belt tile; the block has both hand faces.
5. Run `tools/stage_fail.lua` on red-10s: groups, pack and route must pass on at least one attempt (validate may
   still fail: other rules are another change's work).

## Files this lane owns

logic/bp/groups.lua, logic/bp/pack.lua, tests/test_groups_beacon_row.lua, tests/test_groups.lua, tests/test_groups_long_hands.lua, tests/test_pack.lua, tests/test_pack_layered.lua, docs/tasks/209_beacon_row.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/209_beacon_row`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane209-tests", "command": "git diff --name-only round-36-base HEAD | grep -Ev '^(logic/bp/groups\\\\.lua|logic/bp/pack\\\\.lua|tests/test_groups_beacon_row\\\\.lua|tests/test_groups\\\\.lua|tests/test_groups_long_hands\\\\.lua|tests/test_pack\\\\.lua|tests/test_pack_layered\\\\.lua|docs/tasks/209_beacon_row\\\\.md)$' | ( ! grep . ) && ! git diff round-36-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_groups_beacon_row test_groups test_groups_long_hands test_groups_hand_count test_groups_fluid_row test_groups_row_inserter_name test_pack test_pack_layered; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane209-tests-ok", "expect_exit": 0, "expect_regex": "lane209-tests-ok", "timeout_s": 2400}
{"name": "lane209-measure", "command": "lua5.2 tools/stage_fail.lua tests/golden/cases/player-red-science-10s/prepared_input.json | grep -q 'STAGE route ok=true' && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 413 | tail -1 | grep -q GATE-OK && echo lane209-ok", "expect_exit": 0, "expect_regex": "lane209-ok", "timeout_s": 1800}
```

# bound: 3600s
