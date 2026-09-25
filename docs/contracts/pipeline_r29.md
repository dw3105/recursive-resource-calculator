# Contract: one straight pipeline (round 29, 2026-09-24)

The player's order (2026-09-24): build ONE layout in seven steps, no candidate search.

1. groups: one group per machine name + recipe (+ module/beacon signature);
2. pack: groups placed inside their buffer zones, near the groups they trade with, raw side near the input edge,
   product near the output edge; every allowed direction tried per group;
3. route: belts and pipes;
4. hands: inserters (plain, or long-handed for a far belt);
5. power: poles; when no free spot covers a consumer, a belt/pipe tile may be buried or a hand shifted;
6. tidy: today's improve pass (re-route keep-if-cheaper, hand slide, bury, merge feed) then unbury;
7. validate: ok -> serialize. Not ok -> start again at step 1 with every ring 1 wider. At most 2 retries.

Every lane codes against the clauses below. A clause names its owner file; nobody else edits that file.

## C1 ring bump (groups.lua, validate.lua)

`input.ring_bump` (integer 0, 1 or 2; nil means 0) on the input of `Groups.begin` and `Validate.begin`.
Ring width = `Buffer.ring(catalog, recipe) + ring_bump`. The bump may push a ring above `Buffer.MAX_RING`.
`Buffer.ring` keeps its signature. Block zones (`block.buffer_zones[i].ring`) carry the bumped width, so pack needs
no change for C1.

## C2 roboports stay out of buffer zones (pack.lua, validate.lua, buffer.lua comment)

- `Pack.begin{..., zone_blockers = {TileRect, ...}}`: an origin whose rotated machine zones (`rotate_buffer_zones`)
  intersect any blocker is skipped, exactly like a zone conflict in `buffer_zones_fit`. nil -> no blockers.
- Validate: a machine zone (ring per C1) that intersects a roboport footprint is error `BP_V_BUFFER_ROBOPORT`
  with `{machine_id, roboport_id, zone = {x,y,w,h}, rect = {x,y,w,h}}`. Registered in `reason_codes.lua`.
- `buffer.lua` header: roboports are NOT allowed in a ring; belts, undergrounds, splitters, inserters, poles, pipes
  and beacons still are.

## C3 pack links (pack.lua)

`Pack.begin{..., links = {{a = {block_id =, port_id =}, b = {block_id =, port_id =} | {edge = "left"|"right"|"top"|"bottom"}}, ...}}`.

- A port's tile for a candidate placement = the port's attach cell after rotation (the same cell `choose_port_slots`
  / `copy_port` already compute: `attach_dx, attach_dy` rotated and offset by the origin). A block with no port
  named `port_id` uses its placement centre.
- Link distance = Manhattan distance between the two tiles; to an edge = distance from the tile to that grid edge
  line (`left`: x, `top`: y, `right`: area.w - 1 - x, `bottom`: area.h - 1 - y).
- Candidate cost = sum of link distances over links of this block whose other end is already placed or is an edge
  + growth in tiles of the bounding box of all placed blocks. Lower wins; tie -> `Pack.bssf_score` -> y -> x ->
  direction. Only placed partners count (blocks go in the given order).
- `links` nil or empty -> today's BSSF order exactly (old tests stay green).
- Budget: one op stays around 8 µs (`PORT_ORIGIN_OPS`); the region prune `region_can_beat` must stay correct (a
  region may only be skipped when no origin in it can beat the best cost; when links are present and that bound is
  not cheap, do not prune).

## C4 one group per kind (groups.lua)

- `Groups.step` result: exactly ONE candidate, id `"one"`. `partition_specs` and the rows/legacy double
  enumeration are gone.
- Group key = today's `step_can_join` (same recipe, same machine, same beacon signature, never `_force_block`).
- Form: a row (`docs/contracts/row_block.md`) when the group has 2+ machines, item outputs <= 1 and item inputs <= 6.
  Otherwise today's block; a non-row multi-machine step with more than 2 distinct item flows keeps today's
  one-block-per-machine split (the fragment split), because interior machines cannot reach a block perimeter.
- Row inputs by distinct item input count:
  - 1-2: one near belt on the input face (today);
  - 3-4: + a far belt one tile further out on the input face, `belt_runs` entry `role = "in", far = true`; each
    machine gets a second input hand, `long = true`, `name = catalog.long_inserter.name` (fallback
    `"long-handed-inserter"`), at a different column of the same face, pickup on the far belt, drop in the machine;
  - 5-6: + a far belt on the output face, beyond the output belt, read by a long hand on the output face;
  - 7+: `block.failure = {code = "BP_P_NO_FIT", name = "row-inputs"}`.
- Long hand offsets come from `catalog.long_inserter.pickup_offset / drop_offset` (internal frame, same convention as
  `catalog.inserter`, where the plain inserter is pickup `{x=0,y=1}`, drop `{x=0,y=-1}`); fallback pickup
  `{x=0,y=2}`, drop `{x=0,y=-2}`.
- A far belt is a row belt run: same shape as the near in-run (tiles, dir, head, feeds, hand_ids).

## C5 long inserter facts (catalog.lua, settings.lua, GUI, validate.lua)

`catalog.long_inserter = {name, quality, items_per_second, pickup_offset, drop_offset, drop_position}`, same shape
and capture path as `catalog.inserter` (`logic/catalog.lua` `build_inserter`). Settings key `long_inserter`
(catalog key `long_inserter`), default `long-handed-inserter`, type `inserter`, a picker button in the blueprint
dialog beside the inserter one. Validate resolves pickup/drop offsets per entity NAME: an entity named like
`catalog.long_inserter.name` uses its offsets, else `catalog.inserter`.

## C6 route split (route.lua)

- `Route.begin{..., tidy = false}`: `Route.step` finishes right after first routing: no improve pass, no
  `unbury_empty_pairs`. `tidy` nil -> today's behaviour exactly.
- `Route.tidy_begin(done_state, {obstacles = {TileRect, ...}})` -> new state; `Route.tidy_step(state, budget)` runs
  today's improve pass (reroute, hand slide, bury, merge feed) then `unbury_empty_pairs`; no path may use an
  obstacle cell; result has the same shape as today's `result_for`.
- `Route.free_cell(state, x, y) -> boolean`: frees the belt or pipe tile at (x, y) by burying the straight
  same-flow run through it (reuse `bury_candidate` / `apply_bury`); updates `state.result` in place; false when the
  tile cannot be freed (not transport, near a port, run too short, underground too long).

## C7 power makes room (power.lua)

- `Power.begin{..., make_room = function(x, y) return boolean end}` optional. `occupied[i].kind` is a string
  (`"belt"`, `"underground"`, `"splitter"`, `"pipe"`, `"inserter"`, `"machine"`, `"roboport"`, ...; nil = hard).
- After the greedy cover, for each consumer still uncovered: candidate pole spots that cover it and are blocked only
  by cells of kind belt / underground / pipe / inserter, best first (most uncovered consumers covered). Call
  `make_room(x, y)` for each blocked cell of the spot; all true -> treat the spot as free and select it. At most
  8 spots tried per uncovered consumer. No callback -> today's behaviour exactly.

## C8 hands step (hands.lua, new)

- `Hands.place(materialized, route_result) -> entities`: applies route `port_slides` (today's `apply_hand_slides`,
  `search.lua`) and returns the final inserter entities (plain or long) of the layout.
- `Hands.offer_slides(materialized, grid)`: today's `offer_hand_slides`.
- `Hands.free_cell(materialized, x, y) -> boolean`: moves the hand at (x, y) one tile along its machine face when the
  new tile is free and its pickup and drop still land on the same belt run and the same machine.

## C9 pipeline (search.lua)

- Stages: plan -> preflight -> groups -> pack -> route -> hands -> power -> tidy -> validate -> serialize.
- Attempt `a` = 0, 1, 2 with `ring_bump = a` passed to Groups and Validate.
- Pack `BP_P_NO_FIT` -> next grid, same attempt. Route, hands, power, tidy or validate failure -> attempt + 1, back
  to groups. Attempt 2 fails -> `BP_FAIL_NO_LAYOUT` with every rejection in `errors[1].reason_details`.
- Layered pack (round 35, default; `RRC_PACK=maxrects` turns it off) goes first. Its first rejected candidate, or
  no grid fitting it, restarts the search with MaxRects at grid 1, attempt 0; the rules above then apply unchanged.
  So a sheet that never validates is tried 4 times: layered at bump 0, then MaxRects at bump 0, 1, 2.
- Pack input: `zone_blockers` = roboport footprints; `links` = one link per flow between a producer block's output
  port and a consumer block's input port, plus a link from each raw-input port to `input_edge` and each product
  port to `output_edge`.
- Route input `tidy = false`; after power, tidy with pole footprints as obstacles; if a hand slid out of pole
  cover, run Power once more.
- Power input `make_room` = `Route.free_cell` then `Hands.free_cell`; `occupied[i].kind` set from entity kind.
- Block order: today's greedy connectivity order. No interim publish, no comparator loop, no flip queue, no
  orderings, no `Groups.reverse_run`.
