# Contract: green science works, red loses its jogs, pack gets fast (round 30, 2026-09-24)

Measured on legalcopilot-dev, 2026-09-24, `round-29-delivered` (ffd321e):

- Green science (`tests/golden/cases/player-green-science-1s`) never delivers. Route puts a splitter on a belt
  CORNER tile: iron at (28,27), gear at (32,13). A corner is fed from its side; a splitter takes items only from
  behind, so every iron and gear consumer starves (game-rule walk: 0 of 4 iron, 0 of 2 gear consumers reached).
- Validate did not see it: the player's catalog has no `splitter` entity spec, so a splitter counted 1 tile wide
  (fixed in base, `entity_tile_rect`), and validate lets a belt push into a splitter's side (clause V1).
- Green's converted input carried wrong live facts (roboport logistic_radius 50, pole supply 7, no infrastructure
  specs): grid 101x101, pack 55 s per run. Base aligns them to the red live capture (same save): grid 54x54,
  generation 29.17 s CPU, pack 16.17 s (4.27 s, 32556 origins per run), worst tick 0.665 s (power), 0.468 s (pack).
- Corrected green still fails: route leaves demands unlaid (`BP_R_NO_PATH`), e.g. attempt 2 only gear -> belt
  foundry (clause R3).
- Red v10: the player removed two jogs by hand (186 -> 183 entities): a detour into the first row's rear port
  (clause R2) and a product exit one column off its belt (clause E1).

Oracle for every lane and for integration: `sh tools/measure_sheet.sh <case>` (game-rule belt walk
`tools/lane_sim.py`, last line `MEASURE case=... ok=... entities=... mixed=... starved=...`).

Each clause names its owner file; nobody else edits that file.

## R1 splitter only on a straight belt (route.lua)

A splitter anchor (the laid belt tile a branch leaves from) is allowed only when that tile is fed from BEHIND:
the chain tile one step back against its heading is a same-flow belt, underground exit or splitter facing the same
heading, or the tile is a source port tile fed only by hands (no belt feeds it). A curve tile (fed from a side) is
never an anchor.

- Enforced in the search body jump (`route.lua` ~2152-2180: `splitter_can_absorb` / `splitter_branch_allowed`) AND in
  commit (`append_normal_path` ~1603-1660). The search must never plan what commit refuses.
- A side merge into a splitter tile is refused (`path_cell_free` ~1777-1797).
- The plain sideways step queued when the body jump is refused (~2188-2191) is removed: it can never commit.
- Both commit rejections (~1608 and ~1639) set `last_route_rejection.x/.y`.

## R3 every green demand laid (route.lua)

Green must route every demand. Measure first which rule refuses gear -> belt foundry on attempt 2 (see task 191).
Named suspects: `splitter_cell_allowed` refuses a splitter beside ANY underground end in its 8 neighbours (a
splitter covers exactly 2 tiles; only those 2 must be free of underground ends); a source tile fed only by hands is a
legal anchor (R1).

## R2 rear curve with two items (route.lua)

`rear_curve` (~486) holds for a rear port carrying at most 2 flows (today: 1), when the port's approach tile is not
a same-flow belt pointing into the port. A curve keeps both lanes (oracle: player's hand fix of v10 prints
`mixed=0 starved=0`). Commit keeps the last belt facing `sink.travel_dir` (~1568-1569) as today.

## V1 splitter game rules (validate.lua)

`transport_neighbors` (~579-624): a splitter tile is entered only from a transport entity behind it facing the
same way; a belt never enters a belt that faces it head-on. A side-fed splitter breaks the walk and is reported by
today's codes (`BP_V_ROUTE_DISCONTINUOUS` / `BP_V_TRANSPORT_UNUSED`); no new reason code.

## E1 exit priced from the first belt tile (search.lua)

`slot_cost` (~800-828) measures from each port's FIRST BELT tile: an out port's tile plus one step along its
`travel_dir`; an in port's tile minus one step; the port tile when no `travel_dir` is known. The
`nearest_distance == 1 -> +2` patch (~820-823) is removed. Red v10: product port (19,9) travelling east -> exit
at x=20, straight up.

## P1 pack speed, same answer (pack.lua)

For every input, `Pack` returns the SAME placements (`block_id, x, y, dir, w, h, port_slots`) as `round-30-base`.
Base answers are recorded in `tests/fixtures/pack_base_red.txt` and `tests/fixtures/pack_base_green.txt`
(`lua5.2 tools/pack_placements.lua <prepared_input.json>`). Allowed means, all exact:

- each (block, dir, x, y) is evaluated once, keeping the best BSSF over the regions holding it (same tie order);
- admissible cut: link lower bound = sum, over links whose partner is placed or an edge, of the Manhattan distance
  from the partner tile / edge line to the candidate rect grown by 1, plus a bbox-growth lower bound; a region or
  origin is skipped only when bound > best (strict: ties still scanned);
- cheap checks first (bound, then buffer zones, then `choose_port_slots`);
- work in `place()` / `prune_regions` is charged to `budget.ops` so one tick stays bounded.

Targets: green `PACK-CPU <= 2` s, origins `<= 50%` of base (32556), red not slower than base (3.96 s).

## P2 power tick bounded, same poles (power.lua)

The 0.665 s single tick in power (green) is unbudgeted work; charge it to `budget.ops` or split it. Pole output
unchanged on both sheets. Worst tick in pack and power `<= 0.15` s.
