# 095 validator symmetry: beacons get the rule poles already have

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rules 24.1, 24.2, 24.4.

This file already states the engine rule and already applies it to one of two consumers.

- `logic/bp/validate.lua:227` `box_in_area` implements collision-box overlap against a supply area.
- `logic/bp/validate.lua:660` uses it for poles, inside `check_power_coverage`.
- `logic/bp/validate.lua:232` `point_in_area` implements the machine-centre test.
- `logic/bp/validate.lua:625` uses THAT one for beacons, inside `check_beacons` (`:620`).

So the validator supplies a pole by overlap and a beacon by centre, in the same file, 35 lines apart.

`logic/bp/geometry.lua` owns the conversion and this file already calls it: `box_in_area` at `:227` delegates
to `Geometry.box_overlaps_supply` and `Geometry.supply_box`. Two overlap rules exist on purpose - collision is
strict, supply is tolerant by one epsilon - and `tests/test_geometry.lua` pins both.

**`check_robo` has never been tested.** `logic/bp/validate.lua:595` is the roboport connectivity pass. No test
anywhere in `tests/` asserts `BP_V_ROBO_DISCONNECTED`. It is the only failure path in this file with zero
coverage.

`check_robo` also reaches for a field that does not exist. `logic/bp/validate.lua:606-609` resolves a reach from
`entity.connection_distance`, then `spec.connection_distance`, then `work.catalog.robo.connection_distance`,
ending in a literal `0`. `LuaEntityPrototype::connection_distance` is `subclasses: ["RollingStock"]` in the
pinned 2.0.77 and 2.1.19 API, so `catalog.robo` never carries it, and the planner now derives the gap from
`logistic_radius * 2` at `logic/bp/search.lua:198`. A reach of `0` disconnects every roboport pair.

`tests/fixtures/engine/roboport-cell.json` holds a player blueprint of four unmodded roboports at maximum
connection distance: normalised positions `(0,0)`, `(50,0)`, `(0,50)`, `(50,50)`. Its own `proves` and
`does_not_prove` lists are binding. Four roboports bound ONE cell; cell count is never roboport count.

**Trap.** No engine observation of the roboport REJECTION boundary exists. A test that moves roboports apart and
asserts rejection is a geometry statement, not an engine measurement, and is labelled as such in its own name
and comment. Do not present it as an observed engine result, and do not infer a diagonal or corner-touch rule
from the four-roboport square: its horizontal and vertical edges already connect all four, so Euclidean and
area-based connectivity agree on it.

**Trap.** `tests/test_validated_candidate.lua` validates a frozen fixture that encodes current coverage output.
It passes on `round-11-base`. If it moves, explain the change one case at a time; never bulk-update it.

PRESERVE: `logic/bp/geometry.lua`, `logic/bp/groups.lua`, `logic/bp/search.lua`, `logic/catalog.lua`,
`tests/harness.lua`, `tests/fixtures/**`, `tests/golden/**`, `info.json`, `mod-description.md`.

Files this lane owns: `logic/bp/validate.lua`, `tests/test_validate.lua`, `tests/test_power_semantics.lua`,
`tests/test_validated_candidate.lua`.

Lane 094 changes `logic/bp/groups.lua` in parallel. Planner-and-validator agreement is checked at integration,
on the merged tree, never in this lane.

## What to build

1. `check_beacons` (`:620-625`) uses `box_in_area`, the same call `check_power_coverage` makes at `:660`.
2. `check_robo` (`:595`, reach at `:606-609`) resolves its reach the way the planner does: an explicit value
   first, then `logistic_radius * 2`. Never a literal `0`.
3. `check_robo` gets its first tests, using the fixture as a coordinate oracle.

## What done mean

Every check runs on both interpreters.

```
red-proof   git checkout round-11-base -- logic/bp/validate.lua; lua5.2 tests/test_validate.lua
            emits FAIL <your named case> ... [assert], zero [error], and a summary line matching
            ^test_validate \[Lua 5\.[24]\]: [1-9][0-9]* cases,
symmetry    one geometry, asserted twice: a machine whose box overlaps a supply area but whose centre lies
            outside is supplied by a beacon AND by a pole; the fractional-box counterexample from
            tests/test_geometry.lua GE3 is rejected by both
robo        the four positions in tests/fixtures/engine/roboport-cell.json validate as connected, before and
            after an arbitrary translation; a reach of 0 makes this go red
boundary    geometry only, named and commented as such: with a stated spacing, moving the WHOLE right-hand
            column beyond it is rejected and names its roboports via BP_V_ROBO_DISCONNECTED. No alternate
            path may remain. This asserts nothing about the engine's true boundary.
short       BP_V_BEACON_COVERAGE_SHORT still fires when a machine genuinely gets too few
frozen      lua5.2 tests/test_validated_candidate.lua stays 2/2, or each change is explained case by case
focused     sh tools/verify_round9_lane.sh "$PWD" 095_validator_symmetry
```
