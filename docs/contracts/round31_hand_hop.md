# Contract: hand hop (round 31, 2026-09-24)

Player's hand fix of green v1 (`~/share/RRC/player-green-science-1s-20260924-v1-player-fix.txt`): 352 -> 330
entities, no machine moved, lanes clean. Every saving = a hand moved to ANOTHER face of its machine, nearest the belt
it serves (cable plant input under the plant at (10,5); gear output on the gear assembler's bottom face; belt
foundry iron input on its west face). Today a hand may only slide one tile along its own face.

Two halves, one owner each. Each half alone changes no blueprint byte (the other half is missing).

## H1 offer (logic/bp/hands.lua, `Hands.offer_slides`)

For every port whose hand serves exactly one port (same test as today's slides) and whose machine is a single
machine (not a row member: the port has no `row_port`), add `port.hop_options` (on every copy of the port, like
`slide_options`): a list of at most 16 options, nearest to the current hand first (Manhattan, then y, then x):

`{hand_x =, hand_y =, port_x =, port_y =, turns =}`

- the new hand tile touches the machine face (not a corner of the machine's bounding box), is free (no entity), in
  the grid, and is not the current hand tile nor a tile today's `slide_options` already offers;
- `port_x/port_y` = new hand tile + outward normal of that face (the belt tile the hand reads or drops on); free, in
  the grid;
- `turns` (0..3) = quarter turns clockwise that map the current face's outward normal onto the new face's;
- also set `port.hand_x, port.hand_y` (current hand tile) as for slides.

## H2 apply (logic/bp/hands.lua, `Hands.place`)

`route_result.port_slides` entries may carry `hop = {hand_x, hand_y, port_x, port_y, turns}` instead of `dx, dy`.
For such an entry: the port moves to `port_x/port_y` (`attach_dx/dy` shift by the same delta; `travel_dir`,
`normal_dir` rotate by `turns`), the hand moves to `hand_x/hand_y`, `position` = tile centre, its `dir` rotates by
`turns`, and its `pickup_position`/`drop_position` are recomputed: an input hand picks up at the port tile centre and
drops at the machine tile on the other side of the hand; an output hand the reverse. `_occupied` rects follow the hand.

## R5 try (logic/bp/route.lua, improve pass)

`normalize_endpoint` passes `port.hop_options` to the endpoint (like `slide_options`). The improve pass tries each
hop exactly like a slide (snapshot, re-route that binding, keep only if `route_weight` gets smaller, else restore):
`hop_endpoint(work, endpoint, option)` moves the endpoint to `port_x/port_y`, the hand obstacle to
`hand_x/hand_y`, rotates `endpoint.travel_dir` by `turns`, re-reserves port cells, and returns a plain-data undo
(`unhop_endpoint`) that restores all of it. Same free-tile checks as `slide_endpoint`. A kept hop is published in
`result.port_slides` as `{port_id =, hop = {hand_x, hand_y, port_x, port_y, turns}}`. Only endpoints with
`bindings_on_port == 1`, not perimeter. Charge each hop trial like a slide trial (IMPROVE_TRIAL_OPS + expansions).

## Measure (integration)

`sh tools/measure_sheet.sh player-green-science-1s`: target entities <= 340 (player 330), `mixed=0 starved=0`;
red stays <= 183, `mixed=0 starved=0`; draftsman (`~/.venvs/draftsman`) 0 errors.
