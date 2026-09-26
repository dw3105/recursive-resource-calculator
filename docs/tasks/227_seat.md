# 227_seat seat each item input hand on the machine face nearest where its flow enters

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-227`, branch `lane/227`,
base tag `round-39-base`, merge target `int/r39`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua`, `logic/bp/search.lua` or `logic/bp/hands.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
`sh tools/gate_sheet.sh`. Never use `coroutine`. Plain data only. `require` only at file top level
(`tests/test_no_runtime_require.lua`). **No game item or fluid name in code** (`tests/test_no_item_names.lua`).
Every new test must FAIL on the base code (write that in the test's header comment).

## Explain very simply

Two ore foundries sit right next to the sheet's left edge, where ore and calcite enter. Hand faces are picked
before anything is placed, by flow NAME (`logic/bp/groups.lua:1444-1506`): calcite sorts first and gets the west
face, ore gets the east face. So each ore belt dives underground under the foundry and turns back (6 undergrounds),
and the shared calcite belt starts at the top row. The player put every hand on the west face: calcite on the two
rows that face each other, ore on the outer rows. No undergrounds.

Two parts:
- **Seat**: after pack, before route, move each item input hand of an edge-fed flow to the best tile on its
  machine's faces, using the existing hop machinery (`Hands.offer_slides` hop_options + `Hands.place` hops).
- **Approach tile**: the edge terminal of a flow may stand on the tile in front of that same flow's port on the
  FIRST attempt (today only after `edge_split_flows`). Without it the seated ore port at (1,9) cannot be fed: route
  says `BP_R_NO_PATH`.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = round-39-base + the `PROBE_SEAT` + `PROBE_APPR` parts
of `docs/tasks/r39_probe_reference.diff`: `player-red-science-10s-bulk` → ok, **250 entities, 149 belts**, lane_sim
0/0/0. Seated hands: copper foundry calcite (2,9)→(2,13), copper ore (8,9)→(2,9); iron foundry iron ore
(8,21)→(2,25) (the log line for each move is in the reference diff). `player-inserter-10s` stays ok only with the same-flow skip (rule 5):
without it the second iron-ore hand of that foundry loses its belt.

## What to build

Base already calls `Seat.run(materialized, grid, flows, input_edge)` right after `Hands.offer_slides` in
`logic/bp/search.lua` (and calls `Hands.offer_slides` again when it returns > 0), and
`perimeter_cell_free` asks `Seat.approach_open(state)`. Fill `logic/bp/seat.lua` exactly as `logic/bp/seat.lua`
in the reference diff (minus the `io.stderr` line):

1. Candidates: every port in `materialized.ports` with `role == "in"`, `kind ~= "fluid"`, not `row_port`, with
   `hop_options`, whose hand (`by_id["m:"..inserter_id]` or `by_id[inserter_id]`) and machine (`hand.machine_id`)
   exist, and whose flow has a producer with `step_id == "$external"` in `flows`.
2. Shared flow = its candidates sit on ≥ 2 different machines.
3. Order: shared first; then machine id; then flow id (string compare).
4. Options = stay (current hand/port tile, turns 0) + `port.hop_options`. Skip an option whose hand tile or port
   tile is already used by a seated hand. Key, lowest wins, compared left to right:
   `{edge distance of port tile, k2, stay and 0 or 1, hand_y, hand_x}`; edge distance = `port_x` for left edge,
   `port_y` top, `grid.w-1-port_x` right, `grid.h-1-port_y` bottom; k2 for a shared flow = min box distance from the
   port tile to any OTHER machine of that flow; k2 for an unshared flow = minus the sum of Manhattan distances to
   this machine's already seated shared-flow port tiles.
5. A machine with 2+ candidates of the same flow: none of those is seated (they stay).
6. Apply all moves with one `Hands.place(materialized, {port_slides = {{port_id=…, hop=option}, …}})`. Return the
   count moved.
7. `Seat.approach_open(state)` returns `true`.
8. `tests/test_seat.lua`, hand-built (no sheet run): SE1 two 5x5 machines on the left edge each with a calcite
   (shared) and an ore (own) hand on the east face → calcite seats on the two facing rows of the west face, ore on
   the outer west rows; SE2 two same-flow hands on one machine → not moved; SE3 a row port is never moved; SE4
   `approach_open` is true. Build ports with `Hands.offer_slides` so hop_options are real.

## Files this lane owns

logic/bp/seat.lua, tests/test_seat.lua, docs/tasks/227_seat.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/227`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane227-tests", "command": "git diff --name-only round-39-base HEAD | grep -Ev '^(logic/bp/seat\\.lua|tests/test_seat\\.lua|docs/tasks/227_seat\\.md)$' | ( ! grep . ) && git diff --quiet round-39-base HEAD -- docs/tasks/227_seat.md && ! git diff round-39-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_seat test_hands test_hands_hop test_route_hop test_route_hop_multi test_route_hand_slide test_red10s_bulk_delivers test_red10s_edge_rules test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane227-tests-ok", "expect_exit": 0, "expect_regex": "lane227-tests-ok", "timeout_s": 3000}
{"name": "lane227-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s-bulk 250 149 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 375 | tail -1 | grep -q GATE-OK && echo lane227-ok", "expect_exit": 0, "expect_regex": "lane227-ok", "timeout_s": 1800}
```

# bound: 2400s
