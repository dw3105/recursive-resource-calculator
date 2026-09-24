# Contract: no belt bleeding, free hand placement (round 32, 2026-09-24)

Player placed green v2 (331 entities) on 2026-09-24, boxed two "belt bleeding" spots and pasted a fix (320,
`~/share/RRC/player-green-science-1s-20260924-v2-player-fix.txt`): "inserter placement must not be restricted
artificially!"

## Explain very simply

A flow's belt ends at the machine that eats it. If that last belt points into another flow's belt, the game keeps
pushing items on: circuits ran onto the science belt (green science eats no circuits, so they block the inserter
lane) and gears ran onto the foundry's iron stub. Our checks missed it: lane_sim never asked "does this machine eat
this item", validate never asked "does this belt carry a flow it does not declare".

Hands: the player moved hands to other faces (inserter product to the assembler's east face, foundry gear input to
its top face). We could not, because (measured, legalcopilot-dev 2026-09-24, green, attempt 2):
- hop options are built ONCE before routing, from the first hand layout: east-face tile (22,14) was held by the gear
  input hand then, so it was never offered, even after that hand moved away;
- east-face tiles (22,15), (22,16) were offered but REFUSED live (gear hand/belt there at trial time), never retried;
- the gear output port serves 2 bindings (`bindings_on_port == 2`): no slide or hop at all.

## Base (done, commit on `int/r32`, tag `round-32-base`)

- validate `BP_V_BELT_BLEED`: a tile that declares flows is witnessed carrying another flow (check_transport_shapes).
  Green v2 layout: 43 records (circuits on science belt, gears at (31,24)); red v12: 0. Green now fails
  `BP_FAIL_NO_LAYOUT` until a lane fixes it.
- `tools/lane_sim.py`: BLEED = an item on an input hand's pickup tile that its recipe does not eat; last line
  `LANE-SIM mixed=M starved=S bleed=B`; `tools/measure_sheet.sh` prints `bleed=`.
  v2 -> bleed=5; player fix -> 0; red v12 -> 0.
- `tests/test_validate_bleed.lua` (VB1-VB3); `test_validate_splitter` VS5 now expects a bleed (a splitter sends both
  items to both outputs).

## E1 turn the last belt (new `logic/bp/ends.lua`, hook in `logic/bp/search.lua`)

`Ends.turn_heads(route_result)` runs once after tidy is done (search.lua, right before `Hands.place`). Plain data, no
closures, one call (cost O(belts), charged nothing extra).

For every plain belt entity E (`transport-belt` family, not underground, not splitter) in `route_result.entities`
whose front tile holds a transport entity F that ACCEPTS E by game rules (belt not facing E head-on; splitter only
when facing E's direction from behind; underground entrance from behind or side; never an underground exit) and F's
declared flows (`flow_ids` or `flow_id`) do NOT include every flow E declares: try E's heading turned one quarter
left, then one quarter right. Take the first heading H where:
- the tile in front of E (heading H) holds no transport that accepts E and lacks E's flows;
- every transport that fed E before (a belt/underground exit/splitter whose front tile is E) still feeds E and is not
  head-on to H (no feeder at E's front tile after the turn);
- no transport of another flow now feeds E from behind (its front is E, same heading H).
Set E's `dir` (and `direction` if present) to H. No heading fits: leave E as is (validate will reject; retry ring).
Plain belts only: never move, add or delete an entity.

## F1 hop options from the machine, not the first layout (`logic/bp/hands.lua`)

`Hands.offer_slides` offers a hop on EVERY face tile of the machine (not a bounding-box corner) that is inside the
grid and holds no machine/robo/beacon/pole entity. Tiles held by other HANDS today are offered too (route checks
freedom live when it tries). Port tile likewise (only non-hand entities exclude it). No 16 cap. Order: nearest to the
current hand first (Manhattan, then y, then x). `served[hand] == 1` and `not port.row_port` stay.

## F2 multi-binding ports (`logic/bp/route.lua`, improve pass)

A slide or hop is tried also when the endpoint's port has more than 1 binding: the trial lifts EVERY binding on that
port, moves the endpoint, re-routes each lifted binding (binding order), and keeps the move only when every binding
reaches its sink and `route_weight` gets smaller. Undo restores all. Charge per trial as today (IMPROVE_TRIAL_OPS +
expansions per re-routed binding).

## F3 retry refused moves (`logic/bp/route.lua`, improve pass)

A hop/slide refused because its tile was taken (`hop_endpoint`/`slide_endpoint` returned nil) is remembered
(port_id + option). After the pass over all bindings, if at least one move was kept in that pass, the remembered
refused options are tried once more (same trial + keep-if-smaller rules). At most one retry round.

## Measure (integration, legalcopilot-dev)

`sh tools/measure_sheet.sh player-green-science-1s`: ok=true, `mixed=0 starved=0 bleed=0`, entities <= 331
(target <= 320, player's fix); validate reports no `BP_V_BELT_BLEED`.
`sh tools/measure_sheet.sh player-red-science-1s`: ok=true, entities <= 169, `mixed=0 starved=0 bleed=0`.
Speed (tools/profile.lua): green CPU <= 35 s, worst call <= 0.12 s (tools/tick_parts.lua).
Draftsman (`~/.venvs/draftsman`) 0 errors on both.
