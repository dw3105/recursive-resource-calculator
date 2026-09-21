# 121 hands: put the inserters where they can actually reach

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-121`, branch `lane/121`, base tag `round-14-base` (resolve with `git rev-parse round-14-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 26, rules 26.1, 26.3, 26.6.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-14-baseline.md`.

`logic/bp/groups.lua:299` `append_inserters` places every item inserter at a fixed convention:
`groups.lua:316-320` puts inputs one tile left of the machine facing EAST and outputs one row below it facing
SOUTH, indexed by list position. It reads only `dimensions` (`groups.lua:288`). It emits `pickup_target` and
`drop_target` as id strings and `dir`, and **no** `pickup_position` or `drop_position`.

Because nothing publishes a position, `logic/bp/validate.lua:1100-1106` guesses the cells from the direction
vector. The captured facts exist and are unused: `logic/catalog.lua:402-412` copies
`entity.inserter_pickup_position` and `entity.inserter_drop_position`, and `catalog.lua:750-757` publishes
them as `pickup_offset`, `drop_offset` and `drop_position`. `logic/export_payload.lua:178-180` already
requires them.

Measured from the delivered bytes by `tools/blueprint_audit.py`, artifact sha256
`9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`: 11 of 18 inserters move nothing. Five
drop onto empty ground, two pick up from empty ground, one drops into another inserter, one into a
pipe-to-ground, one onto a medium electric pole, one into a beacon. The seven that work are six
belt-to-machine and one machine-to-machine.

Beacons, same artifact: the casting-iron foundry is configured for 3 and is reached by 6. Two of those six
also serve the copper-plate furnace. Three of nine beacons are removable, so the candidate is waste under
rule 26.6. `groups.lua:693-698` strips `covered_members` instead of moving a beacon.

Configured counts, unchanged: casting-iron 3, copper-plate 3, casting-steel 1, copper-cable 1,
electronic-circuit 1.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/route.lua`, `logic/bp/pack.lua`, `logic/bp/search.lua`,
`logic/bp/geometry.lua`, `logic/bp/power.lua`, `logic/bp/grid.lua`, `logic/bp/plan.lua`, `logic/catalog.lua`,
`tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`, `docs/feature-contracts.md`, `tools/**`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `tests/test_groups.lua`,
`tests/test_serialize.lua`, `tests/test_beacon_coverage.lua`, `tests/test_beacons.lua`,
`tests/test_inserter_geometry.lua` (new).

## What to build

Place each inserter from the catalog's `pickup_offset` and `drop_offset`, rotated into the entity frame, so
that the pickup cell intersects the real source entity and the drop cell intersects the target machine.
Delete the fixed left-input, bottom-output convention at `groups.lua:316-320`.

Publish `pickup_position` and `drop_position` on the emitted inserter member, in world coordinates, so
`validate.lua:1089` reads them instead of guessing. The field name `pickup_position` is mandated: the red
proof `inserter-offset-nil` binds to it.

Support belt to machine, machine to belt, belt to belt and machine to machine, at every cardinal rotation.
An unsupported reach reports a named failure and never substitutes a faster inserter.

A fluid connection emits a pipe endpoint at the catalog's rotated connection position and never an item
inserter.

Split blocks until no beacon is redundant under rule 26.6. When splitting cannot succeed, return a named
failure; never strip `covered_members` to hide it. Extra influence from a load-bearing beacon stays legal.

Configured counts stay exactly as listed above.

## What done means

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_rows.sh tests/test_inserter_geometry.lua --min-cases 10 --pass IG1 >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S inserter-offset-nil >/dev/null 2>&1 || rc=1; (cd $S && sh tools/lane_rows.sh tests/test_inserter_geometry.lua --min-cases 10 --fail IG1) >/dev/null 2>&1 || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "rows", "command": "sh tools/lane_rows.sh tests/test_inserter_geometry.lua --min-cases 10 --pass IG1", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "publishes-cells", "command": "grep -q pickup_position logic/bp/groups.lua || { echo 'groups.lua publishes no pickup_position'; exit 1; }; grep -q drop_position logic/bp/groups.lua || { echo 'groups.lua publishes no drop_position'; exit 1; }; echo publishes-cells", "expect_exit": 0, "expect_regex": "publishes-cells", "timeout_s": 120}
{"name": "no-fixed-convention", "command": "grep -q 'machine.x - iw' logic/bp/groups.lua && { echo 'the fixed left-input convention survives'; exit 1; }; echo convention-gone", "expect_exit": 0, "expect_regex": "convention-gone", "timeout_s": 120}
{"name": "oracle-holds", "command": "sh tools/lane_rows.sh tests/test_blueprint_physical_contract.lua --min-cases 88 --pass PC1,ID1,ID2,ID3,ID4,ID5,ID6,TR1,TR2,TR3,TR4,TR5,TR6,TR7,TR8,TR9,TR10,BE1,BE2,BE3,MT1,MT2,MT3,FL1,FL2,FL3,FL4,FL5,FL6,FL7,SR1,SR2,SR3,SR4,EP1,EP2,EP3,WA3", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 121_hands", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-14-base --manifest docs/tasks/121.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 3600s
