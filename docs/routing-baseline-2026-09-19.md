# Routing baseline, host legalcopilot-dev, 2026-09-19

Measured on `30a7540` (before the lane 055 merge), with `docs/tasks/058_reproducer.lua`. Every figure here is a
measurement, never a target. Nothing in this file is a verdict on whether the sheet is supported: the expected
outcome of that fixture is **success**, and it has not been reached.

## Fixture shape, as the first routing input actually contains it

```text
grid 54x54  blocks 2  flows 5  ports 9  perimeter_ports 3
block:cable+circuit  w=10 h=11  ports 5
block:machine        w=7  h=3   ports 4
flows: item/cable, item/circuit, item/gear, item/machine, item/plate
```

`item/plate` and `item/gear` are supplied externally; `item/machine` leaves externally. The three production
steps present are `cable`, `circuit` and `machine`. The fixture's recipe set also defines `casting-iron` and
`molten-iron`, but **no fluid flow reaches routing**, so this case does not prove a foundry or fluid chain. A
correctly selected fluid case is separate work and must assert its step names and flows before layout.

The first routing input is frozen at `tests/fixtures/routing/player_chain_first_candidate.lua`
(`source_kind = "harness"`, `source_sha = 30a7540d9bbfe7431d279f1043f2832f336714e9`).

## Work counters

| Figure | Value |
|---|---|
| Path search | breadth-first over grid cells, four direction orders per demand |
| `max_expansions` | `max(4096, w * h * 16)` = 46656 on this grid |
| Demands in the first candidate | 7 |
| Demand orders that route successfully | 5 of 5040, measured by brute force on the frozen input |
| Route ops spent in 1200 ticks at `OPS_PER_TICK = 2000` | 2398671, the whole budget |
| 2000 ticks at `OPS_PER_TICK = 2000` | 270.4 s CPU, still `phase=route`, no terminal result |
| Pole stage, before the repair | `max_poles = 2916`, `max_search_seeds = 256`, candidates 2916 |
| Pole stage, after the repair | `max_poles = 39`, seeds 8, candidates 233, consumers 15 |

## One op that never yields

A watchdog that dumps a traceback after 25 CPU seconds inside a single tick caught:

```text
WATCHDOG fired
	./logic/bp/power.lua:430: in function 'connect_selection'
	./logic/bp/search.lua:526: in function 'run_stage'
	./logic/jobs.lua:481: in function 'on_tick'
```

The pole limits above were the cause and are repaired in `30a7540`. A second watchdog fire at tick 2009 is still
open and belongs to the routing owner: total work across direction-order and demand-order retries is not yet
bounded per op.

## How to reproduce a baseline without paying for the whole pipeline

```sh
lua5.2 -e 'local input = dofile("tests/fixtures/routing/player_chain_first_candidate.lua")
local Route = require "logic.bp.route"
local state = Route.begin(input)
local ops = 0
while not state.done and ops < 4000000 do local budget = {ops = 20000}; Route.step(state, budget); ops = ops + (20000 - budget.ops) end
print(state.done, state.ok, ops, state.errors and state.errors[1] and state.errors[1].code)'
```
