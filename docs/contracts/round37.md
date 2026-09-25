# Round 37 contract (legalcopilot-dev, 2026-09-25)

Base `round-37-base` from `round-36-delivered` (efd1ad4). Measured on player's 1.1.83 exports.

| # | where | fault | fix | lane |
|---|---|---|---|---|
| 4a | `logic/bp/generation.lua` `encode_blueprint` | copy string: no `0`, no `blueprint` wrapper, internal keys | Lua port of `tools/blueprint_string.py` | 220 |
| 4b | `gui/blueprint_delivery.lua` `publish` | cursor write failed, error text lost, nil cursor counted empty, staging inventory leak | keep error text, clipboard fallback, destroy inventory | 220 |
| 3a | `logic/bp/groups.lua` | bulk hands: 2 foundries share block with 1 beacon → `BP_P_NO_FIT` | failing shared block → one-machine blocks | 221 |
| 3b | route tidy / validate | dead belt stub + second splitter accepted | `BP_V_BELT_NO_SOURCE`, tidy removes | 222 |
| 2 | route tidy / validate | 3 splitters in series accepted | `BP_V_SPLITTER_CHAIN`, tidy removes | 222 |
| 3c | `tools/lane_sim.py` | hand drop on splitter read as unknown source | model it | 222 |
| 1a | route demand build | 1 belt per output hand; red-10s 176 belts vs player fix 139 | 1 collector belt per machine output flow | 223 |
| 1b | search edge split / route | 2 edge sources for one flow | 1 edge source per flow, branch inside; `BP_V_SOURCE_DUPLICATE` | 224 |

Player fix reference bytes: `tests/fixtures/player_red10s_fix.txt` (261 entities, 139 belts).
