# Round 18 ledger — a splitter that never turns, and the first delivered blueprint

Host `legalcopilot-dev`, 2026-09-22. Branch `feat/round-8-blueprints`. Base tag `round-18-base` at
`952e092`. Never pushed, `main` untouched at `3670e8e`.

## 1. The product delivers

```
sh tools/deliver.sh player-red-science-1s --target <a note-only target>
deliver: case=player-red-science-1s output=~/share/RRC/player-red-science-1s-20260922.txt bytes=3314
  belts=274 undergrounds=14 splitters=9 inserters=26 machines=11 poles=12 pipes=0 beacons=0
  roboports=6 entities_excluding_roboports=346 entities=352 wires=11
  invalid_inserters=4 unpairable_underground=0 unused_belt_tiles=9
  generation_s=224.814 encode_s=0.061 audit_s=0.059
```

**First blueprint this project has ever generated from the player's own sheet with `ok=true`.**

## 2. The fault, and how the geometry works

**A splitter never turns flow.** Two tiles side by side across its own direction, items in at the back of
both, out at the front of both. **No side output.**

`logic/bp/route.lua:1350` read `local splitter_direction = direction` — the NEW demand's heading. A north
trunk crossed by a west demand became a WEST-facing splitter whose input side then faced east, severing the
trunk feeding it. Measured: the validator's walk reached 23 tiles of a 67-entity copper network,
`12:21 -> 12:19 -> 11:20`, and `12:18` was never reached.

Six changes, `logic/bp/route.lua` only:

| site | change |
|---|---|
| `splitter_branch_cell` | the other tile is one step in the BRANCH direction; the splitter keeps the TRUNK's heading, so the tile is literally the next path cell |
| `splitter_branch_allowed` | asks about that tile; an existing splitter serves a further branch only when `splitter_direction == segment.direction` |
| `search_step`, body jump | leaving a laid run is a step into the splitter's other tile, at the trunk's heading, `mode = 2` |
| `search_step`, body guard | `mode = 2` forbids turning inside the body, the same shape of rule as `surfaced` |
| `path_cell_free` | a side entry into a laid run is a MERGE and builds nothing; only the head-on entry is impossible |
| `append_normal_path` | `incoming` and `outgoing` judged separately; a path may END on a splitter's second tile |

## 3. Records, player's first candidate

| measure | round 17 close | round 18 |
|---|---|---|
| records, candidate 1 | 80 | **0**, `ok=true` |
| `BP_V_ROUTE_DISCONTINUOUS` | 9 | **0** |
| `BP_V_TRANSPORT_UNUSED` | 71 | **0** |
| probe wall seconds | 12.1 | **8.4** |
| `generation_s`, whole sheet | 324.2 | **224.8** |

## 4. Census, `round-16-base` frozen full tier against today

```
baseline  ok=false  entities_delivered=0    validate_attempts=11  records=2862
today     ok=true   entities_delivered=352  validate_attempts=1   records=121
```

| code | frozen | today |
|---|---|---|
| `BP_V_ROUTE_DISCONTINUOUS` | 221 | **0** |
| `BP_V_TRANSPORT_UNUSED` | 2611 | **26** |
| `BP_V_UNDERGROUND_UNPAIRED` | 3 | **0**, carried since round 16, closed |
| `BP_V_PORT_UNREACHABLE` | 5 | 30 |
| `BP_V_INSERTER_GEOMETRY` | 5 | 26 |
| `BP_V_TRANSFER_BROKEN` | 5 | 26 |
| `BP_V_TARGET_SHORTFALL` | 11 | 8 |
| `BP_V_ROUTE_MISSING` | 0 | 4 |
| `BP_PW_DISCONNECTED` | 1 | 1 |

**Every one of today's 121 records belongs to the ONE alternative the search discarded**, because
`tools/real_sheet_census.py:records_of` reads `result.discarded_alternatives` on a succeeding run. The
accepted candidate carries zero. `tools/census_gate.py` divides by that discard count, so success inflates
every rate while the absolute total collapsed. Lane 154 owns the rule.

## 5. Gates

```
RED-LIST    ok 223 identities, none worse than docs/round-16-red-list.txt
            test_route_budget 2 -> 0, test_route_footprints 6 -> 0, test_blueprint_pipeline 2 -> 0
CENSUS-GATE fail, on the denominator described above; lane 154
```

## 6. Frozen counts amended, with their measurement

`tests/test_route_chain.lua` RC2 and RC8, `tests/test_route_collision.lua` RX1: underground endpoints
**6 to 8**, entities **91 to 93**. A run that meets a foreign flow head-on now dives under it, because a
splitter never turns and a foreign flow may never be merged into. Measured as `item/plate` running WEST
along `y=2` crossing `r:244`, a NORTH-facing `item/gear` belt at `(14,2)`, endpoints `(15,2)` input and
`(13,2)` output. Belt count **85** and splitter count **0** are unchanged, so contract 28.8's continuation
still wins.

## 7. Carried, named, never fixed here

**The 127-entity target.** Delivered 346 entities excluding roboports against the player's 127.

| family | player | delivered |
|---|---|---|
| entities excluding roboports | 127 | 346 |
| `transport-belt` | 84 | 274 |
| `splitter` | 0 | 9 |
| underground endpoints | 0 | 14 |
| `inserter` | 22 | 26 |
| machines | 11 | 11 |
| poles | 10 | 12 |

Belts per flow, delivered candidate, measured 2026-09-22:

```
item/iron-gear-wheel          belts=69   underground=2   splitters=3
item/iron-ore                 belts=62   underground=2   splitters=3
item/copper-plate             belts=46   underground=2   splitters=3
item/automation-science-pack  belts=36   underground=6   splitters=0
item/iron-plate               belts=36   underground=0   splitters=0
item/copper-ore               belts=25   underground=2   splitters=0
```

Contract 28.8 already names the answer: one trunk through every port tile in turn, continuation and never
a fork. The player's own factory has **zero** splitters and **zero** undergrounds.

Also carried: `transport_demand_by_entity_id`, written twice and read nowhere.
