# 120 gate: make the validator able to fail

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-120`, branch `lane/120`, base tag `round-14-base` (resolve with `git rev-parse round-14-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 26, rules 26.1, 26.2, 26.3, 26.4, 26.5, 26.6.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-14-baseline.md`.

The validator has never run on a production candidate. `logic/bp/search.lua:777` took the placed `ports` and
`search.lua:788` published `ports = {}`; `search.lua:1236` always supplies a non-nil `route`. So
`validate.lua:654` set `legacy_route_only` for **every** production candidate and `validate.lua:1217` returned
`true` before any physical check ran. The comment at `validate.lua:1213` asserts the opposite and is false.
Spine has filled `ports`, so that early return now fires on candidates it was never meant for.

The same flag disables recipe identity at `validate.lua:1483` and `validate.lua:1493`.

`validate.lua:1245` exempts any instance of a multi-machine step that carries no port or inserter binding, as
`isolated_probe`. `validate.lua:1121-1137` `external_reachable` returns `not found`, so the **absence** of a
matching external endpoint is scored as successful reachability to it; callers at `:1257`, `:1298`, `:1470`
and `:1506` read that as success.

`validate.lua:1100-1106` guesses an inserter's pickup and drop cells as centre minus and plus the direction
vector. The captured offsets exist: `logic/catalog.lua:402-412` and `catalog.lua:750-757` carry
`pickup_offset`, `drop_offset` and `drop_position`. `validate.lua:1089` already prefers
`entity.pickup_position`, and the oracle now publishes it, so the guess is the fallback that must go.

`validate.lua:1196` reads `connection.position or connection.pos`. The catalog writes `positions`, a
four-entry list, one per rotation (`logic/catalog.lua:377-395`, header contract `catalog.lua:18`). Against
real captured data `fluid_connection_cells` therefore returns `{}` for every machine.

`validate.lua:789-795` checks beacon influence only as `got + tolerance(got) < required`. There is no excess
rule and no counterpart code.

Measured from the delivered bytes by `tools/blueprint_audit.py`, artifact sha256
`9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`: 11 of 18 inserters move nothing, 12 of 12
pipe-to-ground endpoints cannot pair, 4 underground belt endpoints cannot pair, 224 of 224 belt entities serve
no obligation, 35 pipe tiles touch no machine, 3 of 9 beacons are removable, 0 of 10 wires arrived.

`BP_V_TRANSPORT_UNUSED` and `BP_V_BEACON_REDUNDANT` are registered in `logic/bp/reason_codes.lua` and are not
emitted anywhere yet.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `logic/bp/route.lua`, `logic/bp/pack.lua`,
`logic/bp/search.lua`, `logic/bp/geometry.lua`, `logic/bp/power.lua`, `logic/bp/grid.lua`, `logic/bp/plan.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/validate.lua`, `tests/test_validate.lua`, `tests/test_validated_candidate.lua`,
`tests/test_power_semantics.lua`, `tests/test_blueprint_delivery.lua`, `tests/test_physical_witness.lua` (new).

## What to build

Delete `legacy_route_only` entirely: the assignment at `validate.lua:654`, the early return at `:1217`, and
both recipe guards at `:1483` and `:1493`. The historical fixture that needed it becomes an explicit
rejection test, or is upgraded with independently verified geometry. It never weakens the runtime validator.

Delete `isolated_probe` at `:1245`. Every instance of a multi-machine step is fed and drained.

Change `external_reachable` so a missing required external endpoint rejects instead of returning reachable.

Derive inserter pickup and drop cells from the catalog's `pickup_offset` and `drop_offset` rotated into the
entity frame. Delete the direction-vector fallback at `:1100-1106`. Resolve each cell to the entity occupying
it and reject unless it is a real belt or a real machine, per rule 26.3: empty ground, a pipe, a
pipe-to-ground, a pole, a beacon, a roboport, another inserter and a chest are each invalid. Emit
`BP_V_INSERTER_GEOMETRY` naming the inserter and what it found.

Change `fluid_connection_cells` to read `positions` indexed by rotation. Keep accepting the singular
`position` only if a fixture still needs it; the captured shape is the one that must work.

Emit an ordered connection witness per rule 26.4 for every required transfer, and name the **first** illegal
step in the rejection, not only the obligation.

Enforce rule 26.2: any transport entity or inserter that serves no obligation in the final graph rejects as
`BP_V_TRANSPORT_UNUSED`, naming the entity. Membership of a connected component is not the test; product must
reach the entity from a real source and leave it toward a real sink.

Enforce rule 26.6: a beacon whose removal leaves every machine at or above its configured count rejects as
`BP_V_BEACON_REDUNDANT`, naming the beacon. Extra influence from a load-bearing beacon stays legal.

Every negative case starts from an independently valid candidate that passes first.

## What done means

```
red-proof   sh tools/lane_mutate.sh <scratch> witness-code, then
            sh tools/lane_rows.sh <scratch>/tests/test_physical_witness.lua --min-cases 12 --fail <case>
            The named case reports fail, zero CASE error, harness summary present.
            Repeat for waste-code and beacon-redundant-code.
focused     sh tools/verify_round9_lane.sh "$PWD" 120_gate exits 0 on lua5.2 and lua5.4
oracle      lua5.2 tests/test_blueprint_physical_contract.lua and lua5.4 likewise: every row that
            docs/round-14-baseline.md lists as expected-red for lane 120 now passes, and no row that was
            green turns red
positive    tests/test_physical_witness.lua contains at least one case asserting the valid control is
            ACCEPTED, and it runs before every rejection case in the file
```
