# 123 layout: size the network from demand, and stop lying about optimality

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-123`, branch `lane/123`, base tag `round-14-base` (resolve with `git rev-parse round-14-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 26, rules 26.1, 26.2, 26.8.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-14-baseline.md`.

`logic/bp/search.lua:582-587` `external_port_count` counts the non-external entries on the opposite side of a
flow and returns `math.max(1, count)`. It never reads a rate or a capacity. `search.lua:642-663`
`generated_perimeter_ports` then makes one independent perimeter slot per copy, each of which becomes its own
demand and its own belt run. `search.lua:729` `reconcile_generated_ports` rewrites rates and drops unbound
copies AFTER routing, so the geometry cost is already paid.

`search.lua:602-613` returns true whenever the beacon count is zero, or generated ports outnumber planned
ports, with explicit grids and explicit perimeter ports guarded off. `search.lua:1262-1266` then sets
`grid_index`, `candidate_index` and `order_index` to the end, so the first validated candidate wins and
`Validate.compare` at `:1258` never sees the rest.

Spine changed `search.lua:788` to publish the `ports` argument the function has always received. Before that
every production candidate published `ports = {}`, which together with the always-non-nil `route` at
`search.lua:1236` set `legacy_route_only` at `validate.lua:654` and skipped every physical check at
`validate.lua:1217`.

Timing on the player's sheet, lua5.2, default configuration, host legalcopilot-dev, before round 14:

```
TOTAL 29.41s ok=true
  plan     0.00s   0.0%  calls=2
  groups   0.47s   1.6%  calls=2
  pack     1.72s   5.8%  calls=28
  route   25.07s  85.2%  calls=884
  power    1.31s   4.5%  calls=509
  validate 0.18s   0.6%  calls=2
```

Fourteen candidates were tried; candidate 14 succeeded in 1.07s and the first thirteen burned about 26s.

Already measured and refuted, do not retry: ordering the route frontier by remaining distance never finished
one candidate in 110s against 6.8s; disabling the four direction-order retries saved 13% and removed a real
fallback; granting a restart only while it bought progress gave 66.72s over 60 candidates; ordering candidates
by block count descending gave 74.10s over 59 candidates against 27.60s over 14.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `logic/bp/route.lua`,
`logic/bp/pack.lua`, `logic/bp/geometry.lua`, `logic/bp/power.lua`, `logic/bp/grid.lua`, `logic/bp/plan.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/search.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`,
`tests/test_search_allowance.lua`, `tests/test_external_ports.lua`, `tests/test_port_tile_flow.lua`,
`tests/test_demand_terminals.lua` (new).

## What to build

Size external terminals from aggregate demand, capacity and legal branching, never from consumer or producer
headcount. Start at one terminal per compatible supply network; every extra terminal carries a recorded
capacity or feasibility reason. Put the sizing in a function named `terminals_for_demand`; the name is
mandated, because the red proof `terminals-headcount` binds to it.

Delete the first-feasible shortcut at `search.lua:602-613` and the cursor fast-forward at `:1262-1266`. Per
rule 26.8 the search proves its bound, compares its documented alternatives, or reports a bounded heuristic
result NAMING what it discarded. Record the chosen score and the discarded alternatives on the result.

Place strongly connected producers and consumers near each other and orient their real interfaces toward
feasible corridors, respecting beacon and collision constraints.

Measure and report wall time per phase and per candidate on lua5.2. This lane carries NO time gate; the five
second ceiling is an integration gate. Report the numbers, not a verdict.

## What done means

```
red-proof   sh tools/lane_mutate.sh <scratch> terminals-headcount, then
            sh tools/lane_rows.sh <scratch>/tests/test_demand_terminals.lua --min-cases 8 --fail <case>
            The named case reports fail, zero CASE error, harness summary present.
            Repeat for ports-empty against the case that proves the candidate carries its placed ports.
focused     sh tools/verify_round9_lane.sh "$PWD" 123_layout exits 0 on lua5.2 and lua5.4
terminals   one supply feeding two nearby consumers below capacity produces ONE terminal, not two runs, and
            the case asserts the count
honesty     a case proves the search reports what it discarded when it returns a bounded heuristic result
timing      the lane report carries per-phase and per-candidate wall time on lua5.2, measured, with the
            command that produced it
oracle      no row of tests/test_blueprint_physical_contract.lua that was green turns red
```
