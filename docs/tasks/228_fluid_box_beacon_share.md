# 228_fluid_box_beacon_share output fluid box picked from the other end; a beacon slides to serve two blocks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-228`, branch `lane/228`,
base tag `round-39-base`, merge target `int/r39`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua` or `logic/bp/search.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`sh tools/gate_sheet.sh`. Never use `coroutine`. Plain data only. `require` only at file top level
(`tests/test_no_runtime_require.lua`). **No game item or fluid name in code** (`tests/test_no_item_names.lua`).
Every new test must FAIL on the base code (write that in the test's header comment).

## Explain very simply

Two small fixes, both from the player's hand edit of red science 10/s bulk.

1. **Fluid output box.** A foundry has two equal output fluid boxes (catalog `fluid_boxes` index 3 at (-1,-2) and
   index 4 at (1,-2)). `fluid_connection` in `logic/bp/groups.lua:110-140` takes the FIRST matching box, the one
   on the left, away from the casting foundry that eats the fluid. The player used the right one. Rule: for
   role `"output"` walk the boxes in REVERSE catalog order; inputs keep forward order.
2. **Beacon share.** Beacons are placed per block, and two blocks never share (`groups.lua:272`). The molten-copper
   and molten-iron foundries each got their own beacon. One beacon one tile lower serves both (engine: machine
   collision box overlaps the beacon's supply area). `logic/bp/beacon_prune.lua` only deletes beacons, never moves
   one. Add a share pass before the prune: slide a beacon up to 2 tiles so it also serves another same-signature
   beacon's machines, then delete that other beacon.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = round-39-base + the `PROBE_FBOX` (outputs only; NOT
`PROBE_FBOX_IN`) and `PROBE_BEAC` parts of `docs/tasks/r39_probe_reference.diff`: `player-red-science-10s-bulk` →
ok, **261 entities, 157 belts**, lane_sim 0/0/0; the molten-iron beacon moves (3,17)→(2,16) and the molten-copper
beacon is deleted.

## What to build

Base already calls `BeaconPrune.run(entities, catalog, route_entities)` at the start of the `hands` phase (third
argument = `state.work.route.result.entities`, ignored today).

1. `logic/bp/groups.lua` `fluid_connection`: when `role ~= "input"`, visit boxes from last to first. Nothing else
   in groups.lua changes.
2. `logic/bp/beacon_prune.lua`: new `BeaconPrune.share(entities, route_entities, catalog)` exactly as in the
   reference diff, with these three parts that the probe needed:
   - occupancy: every entity in `entities` by `x,y,w,h` (or `x,y`), every route entity by
     `math.floor(position.x), math.floor(position.y)`;
   - for each beacon `b` (sorted by id) with `signature` and `required_for`, for each other not-gone beacon `o` of
     the same signature that `b` does not already reach for all of `o.required_for`: first free spot in the order
     `dy = -2..2`, then `dx = -2..2`, where the moved box reaches every machine in `b.required_for` AND in
     `o.required_for` (use the existing strict `reaches`). Move `b`: `x, y`, and shift `cx, cy` and `position` by the
     same delta when present; append `o`'s `required_for`, `covered_members`, `member_ids`, `members` to `b`'s;
     mark `o` gone; stop looking for `b`.
   - delete gone beacons from `entities` in place. Return the number moved.
   `BeaconPrune.run(entities, catalog, route_entities)` calls `share` first, then the existing prune unchanged.
3. `tests/test_fluid_box.lua`: FB1 foundry-like catalog with two output boxes → output port connection is the LAST
   box (position x = +1); FB2 input port still the FIRST box.
4. `tests/test_beacon_share.lua`, hand-built: BS1 two 5x5 machines 12 tiles apart vertically, each with its own
   3x3 beacon that reaches only it → after `run`, one beacon left, reaching both, with both machine ids in
   `members`; BS2 same but a route belt on the only shared spot → both beacons kept; BS3 beacons of different
   signatures → both kept; BS4 moved beacon's `cx, cy` shift with `x, y`.

## Files this lane owns

logic/bp/groups.lua, logic/bp/beacon_prune.lua, tests/test_fluid_box.lua, tests/test_beacon_share.lua,
docs/tasks/228_fluid_box_beacon_share.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/228`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane228-tests", "command": "git diff --name-only round-39-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|logic/bp/beacon_prune\\.lua|tests/test_fluid_box\\.lua|tests/test_beacon_share\\.lua|docs/tasks/228_fluid_box_beacon_share\\.md)$' | ( ! grep . ) && git diff --quiet round-39-base HEAD -- docs/tasks/228_fluid_box_beacon_share.md && ! git diff round-39-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_fluid_box test_beacon_share test_beacon_prune test_beacons test_beacon_coverage test_inserter_geometry test_groups_fluid_row test_validate_fluid_port test_route test_red10s_bulk_delivers test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane228-tests-ok", "expect_exit": 0, "expect_regex": "lane228-tests-ok", "timeout_s": 3000}
{"name": "lane228-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s-bulk 261 157 | tail -1 | grep -q GATE-OK && echo lane228-ok", "expect_exit": 0, "expect_regex": "lane228-ok", "timeout_s": 900}
```

# bound: 2400s
