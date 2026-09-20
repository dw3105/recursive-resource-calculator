# 094 beacon geometry: the overlap rule, and beacon rows that actually cover

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rules 24.1, 24.2, 24.3.

A player's sheet asks for 3 speed beacons per machine and the generator never places a layout for it. Replaying
that capture offline names two defects in this file.

**Defect A. Coverage asks whether the machine CENTRE sits in the beacon supply area.** The engine rule is that
an entity is supplied when its COLLISION BOX OVERLAPS the area.

- `logic/bp/groups.lua:251` `covers` compares `machine_center` against `math.min(supply_w, supply_h)`.
- `logic/bp/groups.lua:415-432` `needs_tighter_row` is a SECOND centre test, on the y axis only.
- `logic/bp/groups.lua:229` `machine_size` returns tile dimensions, never a collision box.

Measured on the player's capture: `covered=0` on 3744 of 3744 beacon placements. A 5x5 machine at `y=3` has its
centre at `y=5.5`; a beacon row at `y=0` with reach 3 reaches `y=4.5`. The beacon sits directly over the machine
and covers nothing.

**Defect B. All beacons go in ONE centred horizontal row, and every machine must be covered by all of them.**

- `logic/bp/groups.lua:464` centres the row.
- `logic/bp/groups.lua:477` places `group.count` beacons at pitch `row.w + 1`.
- `logic/bp/groups.lua:573` sets `block.invalid_coverage` when any required machine sees fewer than
  `group.count` of that signature.
- `logic/bp/groups.lua:671` drops the whole candidate when any block is `invalid_coverage`.

Three supply rects 9 tiles wide, spaced 4 apart, intersect in about one tile. Measured after fixing defect A
only: `got` reaches 2 at most and reaches 3 **zero** times in 2280 checks. Candidates stay 0.

**Defect C. `count_per_machine` is reused as a physical count.** `logic/bp/groups.lua:367` sets
`existing.count = math.max(existing.count, group.count_per_machine)`, and from there `group.count` means
"beacons to place". The validator reads `count_per_machine` correctly at `logic/bp/validate.lua:635`.

`logic/bp/geometry.lua` already exists and owns the conversion. `Geometry.world_box`, `Geometry.supply_box`,
`Geometry.box_overlaps_supply` and `Geometry.box_in_supply` are the entry points. `tests/test_geometry.lua`
pins them from explicit coordinates.

**Trap.** `logic/bp/groups.lua:243` has a `rects_overlap` helper that takes TILE rectangles. Swapping the centre
test for it is not this task. A 3x3 machine at `3,4` overlaps a beacon supply area reaching `y 4.5` on its tile
footprint and does NOT overlap it with a `[-0.7, 0.7]` collision box, whose top edge is `4.8`. Grouping would
accept what the validator rejects.

**Trap.** `tests/test_beacon_coverage.lua:48-55` hand-rolls the centre rule in the test itself, and case `B3` at
`:86` asserts a beacon at `x=3,y=0,w=3,h=3,supply=3` covers NEITHER machine at `y=4`. That case encodes the
defect. It is rewritten, pinned to declared collision geometry: the tile-fallback machine is covered, a machine
with box `[-0.7, 0.7]` is not. No claim that every 3x3 machine at that tile position is covered.

PRESERVE: `logic/bp/geometry.lua`, `logic/bp/validate.lua`, `logic/bp/search.lua`, `logic/bp/pack.lua`,
`logic/bp/route.lua`, `logic/bp/power.lua`, `logic/bp/plan.lua`, `logic/bp/grid.lua`, `logic/catalog.lua`,
`tests/harness.lua`, `tests/golden/**`, `tests/fixtures/**`, `info.json`, `mod-description.md`.

Files this lane owns: `logic/bp/groups.lua`, `tests/test_groups.lua`, `tests/test_beacon_coverage.lua`.

Lane 095 changes `logic/bp/validate.lua` in parallel. Planner-and-validator agreement is checked at
integration, on the merged tree, never in this lane. Do not import that check here.

## What to build

1. Both coverage tests call `logic/bp/geometry.lua`. `covers` (`:251`) and the y-axis test inside
   `needs_tighter_row` (`:415-432`) use collision-box overlap against a supply area measured as a distance from
   the beacon centre. Never re-derive a box; never substitute tile-rectangle overlap.
2. Beacon rows go above AND below the machine row, and the block is sized so every machine's world box overlaps
   at least `count_per_machine` beacon supply areas of that signature.
3. `count_per_machine` stays a per-machine requirement. Physical beacon count becomes an output of placement and
   is reported as `block.physical_beacon_count`. `:367` and `:573` stop conflating the two.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-11-base -- logic/bp/groups.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_groups.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -qE '^FAIL .*BG3 a machine configured for three beacons overlaps three supply areas .*\\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -q '\\[error\\]' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^test_groups \\[Lua 5\\.[24]\\]: [1-9][0-9]* cases, ' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 900}
{"name": "no-tile-overlap-shortcut", "command": "grep -q 'Geometry' logic/bp/groups.lua || { echo 'groups.lua does not call the shared geometry'; exit 1; }; echo geometry-shared", "expect_exit": 0, "expect_regex": "geometry-shared", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 094_beacon_geometry", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-11-base --manifest docs/tasks/094.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Every check runs on both interpreters.

```
red-proof   git checkout round-11-base -- logic/bp/groups.lua; lua5.2 tests/test_groups.lua
            emits FAIL <your named case> ... [assert], zero [error], and a summary line matching
            ^test_groups \[Lua 5\.[24]\]: [1-9][0-9]* cases,
boxes       a machine whose collision box is smaller than its tile footprint is NOT covered where the
            footprint would have been; asymmetric boxes; all four directions; a genuine miss; both sides of
            the tolerance boundary. Expectations written as explicit coordinates, never by calling covers().
counts      a machine configured for 1, 2, 3 and 4 beacons of one signature overlaps at least that many
            supply areas of that signature. The count 3 case fails on round-11-base.
block       a block of 5 machines of differing sizes gives every machine its own configured count
semantics   count_per_machine is never assigned to a physical count; a block reports its physical count
candidates  a plan whose machines each request 3 beacons yields candidates > 0
focused     sh tools/verify_round9_lane.sh "$PWD" 094_beacon_geometry
```

Never reduce a configured beacon count to make a check pass.

Your own tests must include, in `tests/test_groups.lua`, by these exact case names. The red proof greps for `BG3 a machine configured for three beacons overlaps three supply areas`, so a different spelling fails the launch rather than the work.

- `BG1 a machine covered by its collision box is covered, and by its tile footprint alone is not`
- `BG2 an asymmetric collision box survives all four placed directions`
- `BG3 a machine configured for three beacons overlaps three supply areas`
- `BG4 a block of five machines of differing sizes each gets its configured count`
- `BG5 count_per_machine is never assigned to a physical beacon count`
