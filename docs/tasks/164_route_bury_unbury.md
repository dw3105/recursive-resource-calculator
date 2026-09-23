# 164 route: bury a straight laid run instead of diving the new path, and unbury any pair that covers nothing

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-164`, branch
`lane/164`, base tag `round-21-integrated`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-21-integrated`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything
else, then say which item and why.

## Explain very simply

When two belts must cross, one of them goes **underground** under the other. Today the router can only
send the belt it is **building now** underground. The belt that is **already laid** never moves.

The player placed our blueprint on 2026-09-23 and showed the cost: at `(9,20)` copper-plate dived east
under a long straight **gear** column at `x=10`, and the copper inlet had to be fed from the side by a
splitter. The player: "it is much more reasonable to put gears belt underground instead of copper plates
one!" A straight laid run is the easiest thing to bury: swap the belt just before the crossing for an
underground input and the belt just after for an output, and the new path walks straight across on top.

The player also named the opposite tool: "BURY and UNBURY existing lane is a useful instrument! underground
belts are more expensive than normal one and unused ones must be 'unburied'". An underground pair whose
covered tiles are all free buys nothing and costs more than plain belts. Turn it back into belts.

## Where the code is

`logic/bp/route.lua`:

- `search_step` — the step loop. When the next tile holds a laid belt the search cannot enter, it falls to
  the crossing branch (`crossing_targets`) and dives the NEW path. Side-fed dives cost
  `SIDELOAD_UNDERGROUND_COST` (8) on top.
- `path_cell_free` — decides whether a step may enter a tile.
- `append_normal_path` — commits a path; `append_crossing` lays an underground pair and marks both
  endpoint tiles in `work.underground_cells` AND `work.splitter_blocked_cells`.
- Every transport tile is its own segment in `work.segments_by_cell`, with `allocations` per flow; an
  underground pair is ONE segment with `underground = true`, `underground_entry_key`/`_exit_key` and
  `_x`/`_y` fields; entities carry `ug_role`, `ug_pair_id`, `type = "input"/"output"`.
- `route_chain_walk` walks a directed chain, following underground pairs; the validator and
  `tools/transport_shape_probe.py` judge the result.
- `Route.step` sets `state.result = result_for(work)` when the last demand is done — the place for a
  post-pass.

## BURY — what is true

A path stepping from `P` into tile `C` that holds a laid belt run `R` travelling perpendicular to the step
may **bury R under C** instead of diving itself, when ALL of these hold (call `B = C - R.dir`,
`A = C + R.dir`, `BB = B - R.dir`, `AA = A + R.dir`):

1. `B`, `C`, `A` are plain surface belts (not underground, not splitter) of one direction `R.dir`, each
   carrying the same flow set, none a sink or source port tile of any demand (`work.port_cells` owners),
   none the drop or pickup tile of an inserter.
2. `BB` feeds `B` **straight from behind** (a same-direction belt, an underground output or a splitter
   facing `R.dir`) — so the new input at `B` is never side-fed.
3. `AA` holds a transport tile of that flow that `A` feeds (so the new output delivers somewhere).
4. Neither `B` nor `A` is within the reach of another underground of the same family lined up on `R.dir`
   (a pair may not pass another pair of its own family).
5. The new path's own step onto `C` is legal in every other way.

Price it in `transition_cost` terms: a bury converts two belts into two undergrounds and frees one tile, so
it costs `BURY_COST` (suggested 3, measure it) — cheaper than a new dive (`2 + distance + 2`, plus 8 when
side-fed) but dearer than any plain walk. The search records the bury on the state; at commit
(`append_normal_path`) the bury is applied FIRST: `B` becomes an underground input, `A` its output, `C`'s
belt is removed, the three per-tile segments merge into one underground segment with the same allocations,
and every map is updated (`segments_by_cell`, `entity_by_segment`, `underground_cells`,
`splitter_blocked_cells`, any binding whose `segment_id` pointed at a removed segment). Then the new path's
belt is laid on `C`.

**Re-check every condition at commit** — never trust the search's view of a tile that another commit may
have changed. A refused bury at commit re-searches, exactly like the existing `crossing-occupied`
recovery in the route loop.

## UNBURY — what is true

After the last demand, before `result_for(work)`: every underground pair whose covered tiles (strictly
between entry and exit) hold no segment, no static obstacle (`work.obstacles`, `indexed_cell(work.grid, ...)`)
and no reserved port cell of another port, becomes plain belts of its direction on entry, every covered
tile, and exit — one segment per tile, allocations copied, maps updated. Deterministic order (sort by entry
key). A pair covering at least one occupied tile stays.

## Traps, each measured on this host

- **Determinism.** `tests/test_route_budget.lua` and `coord_key` need the same input to give the same
  layout. Scan candidates in a fixed order.
- **A bury must never create a side-load, a back-to-back pair or a ring.** `sh tools/round21_product.sh`
  must stay `product-ok` with `sideload=0 back_to_back=0 cycles=0`.
- **Frozen fixture rows move.** `tests/test_route_collision.lua` RX1 and `tests/test_route_chain.lua` RC8
  freeze exact counts. When your change moves them, re-freeze to the NEW measurement with a comment naming
  what moved and why; never loosen a ceiling you did not measure.
- **The product must not grow.** On the player's sheet at `round-21-integrated`, full generation measured
  2026-09-23: `ok=true`, 257 entities, 189 belts, 12 underground endpoints, 4 splitters. Report yours. More
  entities than 257 is a regression you must explain or undo.
- **Never touch** `logic/bp/search.lua`, `logic/bp/validate.lua`, `logic/bp/reason_codes.lua`,
  `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `tools/**`, `docs/**` except this task, `info.json`,
  `mod-description.md`, `.agent-lane.toml`, any `tests/**` file except those listed below.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route_bury.lua` (new), and — only to re-freeze a measured count as
described above — `tests/test_route_collision.lua`, `tests/test_route_chain.lua`.

## What to build

1. BURY and UNBURY in `logic/bp/route.lua`, each with a short comment naming the player's words and the
   `(9,20)` case.
2. `tests/test_route_bury.lua`, driven through `Route.begin` / `Route.step` like
   `tests/test_route_underground_feed.lua`, each row **red at `round-21-integrated`**:
   - **BU1** a long straight laid run of flow A, then flow B that must cross it perpendicular with a
     turn right before the crossing: B walks straight across on the surface and A is buried: A has one
     pair whose entry and exit sit one tile either side of the crossing, and B has no underground.
   - **BU2** the same with the tile BEFORE the crossing on A being a curve (A turns just there): no bury —
     it would side-feed A's new input — so B dives as before.
   - **BU3** unbury: a pair whose covered tiles end up free is published as plain belts, and a pair that
     covers an occupied tile is kept.
3. Report on the player's sheet: entities, belts, undergrounds, splitters, the probe line, and every bury
   and unbury performed (tiles and flows).

## Commit, THEN check

Commit your work on `lane/164` with a message that says what changed and what was measured. **Run the two
checks below as the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "bury-regress", "command": "git diff --name-only round-21-integrated HEAD | grep -v '^docs/tasks/164' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_bury\\.lua|tests/test_route_collision\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_route_bury.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_route_underground_feed.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_validate_transport_shapes.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo bury-regress-ok", "expect_exit": 0, "expect_regex": "bury-regress-ok", "timeout_s": 1800}
{"name": "bury-product", "command": "sh tools/round21_product.sh > /tmp/rrc164-product.txt 2>&1; cat /tmp/rrc164-product.txt; grep -q '^product-ok$' /tmp/rrc164-product.txt && grep -q 'sideload=0 back_to_back=0 cycles=0' /tmp/rrc164-product.txt && echo bury-product-ok", "expect_exit": 0, "expect_regex": "bury-product-ok", "timeout_s": 1200}
```

# bound: 2400s

Reviewer ask: on the player's sheet, did any side-fed dive disappear because a straight run was buried
instead, did the entity count stay at or below 257, and is every pair left covering something?
