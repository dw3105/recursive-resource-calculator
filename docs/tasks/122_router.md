# 122 router: route what the product can actually travel

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-122`, branch `lane/122`, base tag `round-14-base` (resolve with `git rev-parse round-14-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 26, rules 26.1, 26.2, 26.4, 26.5.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-14-baseline.md`.

`logic/bp/route.lua:791-803` `append_crossing` computes ONE `direction` and writes it to both endpoints.
`route.lua:907-912` `append_underground` does the same with `candidate.direction`. Both branch on
`kind == "pipe"` for the entity NAME only (`route.lua:793`, `:905`), never for direction and never for the
fact that a pipe-to-ground carries no `type` field.

`route.lua:744-770` `underground_candidate` already demands that the two connections face each other
(`route.lua:760`), are axis aligned (`:754`) and are within the smaller of each connection's
`max_underground_distance` and the family maximum (`:763-767`). The emission contradicts the check.

Measured from the delivered bytes by `tools/blueprint_audit.py`, artifact sha256
`9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`: all twelve pipe-to-ground endpoints face
east or south. A pair needs opposite directions, so zero pairs exist and every fluid route is cut. Four
underground belt endpoints have no partner either. 224 of 224 belt entities serve no obligation.

`route.lua:980-981` seeds a FIFO queue with `visited` keyed by `coordinate_key` (`route.lua:112`), which is
`x,y` alone. `route.lua:1063-1067` closes a cell the first time it is reached, from whatever heading. Arrival
direction, turn cost and attachment state are invisible to the frontier. The only compensation is re-running
the whole search under four fixed direction orders (`route.lua:19-24`, retried at `:1376-1378`).

`route.lua:596-608` `build_demands` pairs producers with consumers in list order, taking
`math.min(producer.remaining, consumer.remaining)`, with Manhattan distance as the endpoint tiebreak
(`route.lua:509-527`). No routing cost feeds back into the pairing.

Same-flow reuse exists but is only tolerated, never sought: the gate at `route.lua:637-643`, the allocation
merge at `:772-781`, and the path laydown at `:836-887`. The search has no preference for a cell already
carrying the same flow.

`route.lua:375-397` `mirrored_port` flips a block-edge port to the opposite face, fired only when a placed
port falls outside the grid (`route.lua:405-420`). It moves the logical attachment without materializing the
connecting geometry.

`max_expansions` is one cumulative budget scaled by grid cells times four directions times four orders times
demand count (`route.lua:965-976`).

Recovery machinery already present and worth keeping: per-demand endpoint alternatives
(`next_endpoint_candidate`, `route.lua:1230`), the four direction orders, and rip-up with one demand promoted
to the front, each demand once (`restart_with_priority`, `route.lua:1193-1221`).

PRESERVE: `logic/bp/validate.lua`, `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `logic/bp/pack.lua`,
`logic/bp/search.lua`, `logic/bp/geometry.lua`, `logic/bp/power.lua`, `logic/bp/grid.lua`, `logic/bp/plan.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`,
`tests/test_route_footprints.lua`, `tests/test_route_layout_contract.lua`, `tests/test_underground_pairs.lua`,
`tests/test_route_network.lua` (new).

## What to build

Emit underground endpoints that can pair. Belts: both ends carry the travel direction, `type` `input` at the
entrance and `output` at the exit. Pipes: the two ends carry OPPOSITE directions and no `type` field at all.
Compute the exit end's direction into a local named `exit_direction`; the name is mandated, because the red
proof `ptg-same-direction` binds to it. The emission must agree with `underground_candidate`.

Replace the coordinate-only FIFO with a deterministic Dijkstra whose state is the cell, the arrival direction,
the transport kind and the underground mode. Cost counts newly materialized surface tiles, both underground
endpoints and the span, bends, splitters and crossings; a cell already carrying the same flow within capacity
costs less, so sharing is SOUGHT rather than tolerated. Costs are nonnegative and ties are deterministic.
Re-derive `max_expansions` for the larger state space and record the figure.

Reserve entrance, exit and continuation space as ONE transaction. If any part is impossible, try a different
COMPLETE route or fail with the blocked obligation named. Never commit a successful prefix.

Choose producer-consumer pairing with routing cost feedback rather than list order, trunk first where capacity
permits. Count combined downstream demand exactly once on each shared segment.

Keep bounded rip-up and reroute. Replacing a route removes its obsolete allocations and entities without
deleting shared portions still required elsewhere.

After routing, and again after any rip-up, audit the materialized entities against the committed obligations
and DISCARD abandoned geometry before returning. Rule 26.2's budget is zero.

`mirrored_port` never moves a logical attachment away from its real inserter or fluid connector without also
materializing and validating the connecting geometry.

## What done means

```
red-proof   sh tools/lane_mutate.sh <scratch> ptg-same-direction, then
            sh tools/lane_rows.sh <scratch>/tests/test_route_network.lua --min-cases 12 --fail <case>
            The named case reports fail, zero CASE error, harness summary present.
focused     sh tools/verify_round9_lane.sh "$PWD" 122_router exits 0 on lua5.2 and lua5.4
audit       for a candidate this lane routes, tools/blueprint_audit.py reports 0 unpairable underground
            endpoints of either family and 0 unused belt tiles
budget      the re-derived max_expansions is stated in the lane report with the measurement behind it
oracle      no row of tests/test_blueprint_physical_contract.lua that was green turns red
positive    tests/test_route_network.lua asserts a correct facing pair is ACCEPTED before any rejection case
```
