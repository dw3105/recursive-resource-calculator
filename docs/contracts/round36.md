# Round 36 contract — red science 10/s builds; golden case #4

Host `legalcopilot-dev`, 2026-09-25. Base tag `round-36-base` (from `main` 2b4b8b8). Merge target `int/r36`.
Case `tests/golden/cases/player-red-science-10s` (player export 1.1.81): 10 assembling-machine-3 × 3 beacons,
4 foundries × 1 beacon. `lua5.2 tools/stage_fail.lua <prepared_input.json>` prints every stage verdict per attempt.

## Blockers (measured on base, each proven by an in-memory fix + rerun)

| # | where | fault | lane |
|---|---|---|---|
| 1 | `logic/bp/groups.lua` beacon rows (`count > 2` adds a bottom row) and the `beacon-face` refusal | bottom beacon row sits on the hand face → every candidate `BP_P_NO_FIT` | 209 |
| 2 | `groups.lua` `machine_y = beacon_rows_h + 1` for a row | top hands pick from a beacon tile → route `BP_R_PORT_BLOCKED`; the input side of a row needs near belt, far belt, feed row and hand, beyond beacon supply 3 | 209 |
| 3 | `logic/bp/validate.lua` `check_port_approaches` | a belt behind a fluid port is refused (`BP_V_PORT_EDGE_WRONG`) | 210 |
| 4 | `validate.lua` `BP_V_TRANSPORT_UNUSED` | two output hands of one foundry feed one row head (one path from behind, one side-load); only one path is witnessed → 7 belts reported unused; lane_sim shows items flow | 210 |

With 3 and 4 fixed in memory, inserter-10s passes its layered attempt 1: 373 entities, 29 s CPU, lane_sim 0/0/0.

## Clauses

- B1 (209) A row with beacons gets ONE shared beacon row on the OUTPUT side, after the output hand and output belt
  (2 tiles: inside supply 3). Inputs (near belt, far belt, feeds, hands) stay on the top side.
- B2 (209) The row runs past the row ends until every machine is reached by ≥ `count_per_machine` beacons (supply
  box test, `Geometry.supply_box`); no beacon that reaches no machine.
- B3 (209) A second beacon row only when one row cannot reach the count, and never on a hand or belt tile.
- F1 (210) Approach rule by kind: a fluid port refuses only a foreign pipe or pipe-to-ground on its approach tile;
  an item port ignores pipes.
- F2 (210) `BP_V_FLUID_MIX` (new code in `reason_codes.lua`): pipes of two different fluids touch (pipe-to-ground
  connects only to its pair).
- F3 (210) The transfer witness follows every belt path into a used belt — straight from behind and side-load — so
  a second producer hand's path is used.
- A1 (212) `items_per_second = stack × 60 × rotation_speed(quality) × K`, `K` so a fast inserter at stack 1 gives
  2.31; `stack = 1 + force.inserter_stack_size_bonus` (bulk: `bulk_inserter_capacity_bonus`); belt pickup factor is
  one named constant. Facts absent → 4.62 + diagnostic `CATALOG_INSERTER_SPEED_DEFAULT`. The debug export writes
  `rotation_speed`, `extension_speed`, `bulk` per inserter and the force bonuses; the converter passes them on.
- L1 (211) `candidate_links`: a list per `step|flow|role`; one link per producer/consumer block pair; the
  `pack_layered(state)` guard in links goes.
- N1 (213) Notes carry a kind tag (`calc` / `blueprint`); a calc job start clears only calc notes; a blueprint job
  start or a Generate click clears blueprint notes.

## Caps (all from bytes)

red 1/s ≤ 148, green ≤ 305, inserter-10s ≤ 373 (after 210), red-10s ≤ 300 entities and ≤ 150 belts (after all),
every sheet `ok=true mixed=0 starved=0 bleed=0` and `NAMES-OK`.
