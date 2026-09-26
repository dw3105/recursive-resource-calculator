# Round 38 contract (legalcopilot-dev, 2026-09-26)

Base `round-38-base` from `round-37-delivered` (ce3082b). Measured on player's 1.1.85 export
`red-science-10s-1.1.85.txt` (bulk hands 36.96/s, turbo belts, legendary substation and roboport).

| # | where | fault (measured) | fix | lane |
|---|---|---|---|---|
| 1 | `logic/bp/search.lua` `hands` phase | bulk hands → small blocks packed close; gear foundry beacon (y 15..17) reaches copper foundry (y 8..12); copper foundry's own beacon redundant → `BP_V_BEACON_REDUNDANT`, only fault of candidate 1; every later candidate fails too → `BP_FAIL_NO_LAYOUT` | new `logic/bp/beacon_prune.lua`: before power, drop each beacon whose removal keeps every machine's configured count. In memory: `ok=true`, 266 entities, 157 belts, 0/0/0 | 225 |

Trigger: same sheet with fast hands delivers (`ok=true`). Prune right after pack changes hand slides — rejected.
Side effect accepted by player: `player-inserter-10s-bulk` 274 entities / 102 belts / 6 beacons (was 273/100/7).

Open, not this round: MaxRects fallback on this sheet still fails (calcite shortfall; `BP_V_SOURCE_DUPLICATE` from
round-36 edge split; `BP_V_PORT_EDGE_WRONG` iron-ore port). Export progress `done_units > total_units` on failure
(cosmetic). `delivery.last_reason` in export is leftover from 1.1.83 save.
