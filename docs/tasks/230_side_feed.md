# 230_side_feed never bury a belt run under a side feed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-230`, branch `lane/230`,
base tag `round-40-base`, merge target `int/r40`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua`, `logic/bp/route.lua` or `logic/bp/search.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY),
`tools/stage_fail.lua` and `tools/bytes_hash.sh`. Never use `coroutine`. Plain data only. `require` only at file
top level (`tests/test_no_runtime_require.lua`). **No game item or fluid name in code**
(`tests/test_no_item_names.lua`; tests use made-up flow ids like `item/a`). Every new test must FAIL on the base
code (write that in the test's header comment).

## Explain very simply

When a new flow must cross a belt run already laid, the router may bury three tiles of that run: the first becomes an
underground entrance, the middle is free for the crossing flow, the last becomes the exit (`bury_candidate` in
`logic/bp/route.lua`). It checks the belt behind and the belt ahead, never a belt that feeds the run FROM THE SIDE.
A side feed onto an underground entrance blocks one lane (`BP_V_UNDERGROUND_SIDELOAD_BLOCKED`); onto the middle tile
it feeds nothing. The player's red + green science 10/s sheet (`tests/golden/cases/player-red-green-science-10s`)
fails on exactly this: gear branch belt (13,39) heading south feeds gear run tile (13,40), then the run is buried
there so copper cable can cross at (14,40).

Base already calls `SideFeed.into(work.segments_by_cell, coordinate_key, {{bx,by},{x,y},{ax,ay}}, b.direction)` in
`bury_candidate` and gives up the bury when it returns `true`. It is a stub returning `false` in
`logic/bp/side_feed.lua`. Fill it.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = round-39 main + `PROBE_B` part of
`docs/tasks/r40_probe_reference.diff`: first `STAGE validate` line of `tools/stage_fail.lua` on the new case is
`STAGE validate ok=false BP_V_FLUID_MIX=1` (the side-load fault is gone; the fluid mix is another task's). All 8 older
sheets stay byte-identical to `tests/fixtures/bytes_round39.txt`.

## What to build

`cells` maps `key(x, y)` to a route segment (`key` is route.lua's `coordinate_key`, pass-through). A segment has
`kind` ("belt" / "pipe"), `direction` (Grid.NORTH/EAST/SOUTH/WEST from `logic/bp/grid.lua`), `splitter`,
`underground` and, for an underground, `underground_entry_key` (key of its entrance tile). `tiles` is `{{x, y}, ...}`.

1. `SideFeed.into(cells, key, tiles, direction)`: for every tile `{px, py}` in `tiles` and every heading `d` that is
   neither `direction` nor its opposite: let `(dx, dy) = Grid.dir_vector(d)`, side = `cells[key(px - dx, py - dy)]`.
   Return `true` when side exists, `side.kind == "belt"`, not `side.splitter`, `side.direction == d`, and NOT
   (`side.underground` and `side.underground_entry_key == key(px - dx, py - dy)`) -- an entrance tile outputs
   nothing. Else `false`.
2. Exactly as the `PROBE_B` block in the reference diff; no env flag.
3. `tests/test_side_feed.lua`: SF1/SF2/SF3 a belt from the side pointing into the first / middle / last tile of an
   east run → true (both sides, north and south); SF4 a belt behind or ahead, or a side belt pointing AWAY → false;
   SF5 side neighbour is an underground entrance tile → false, an underground exit pointing in → true; SF6
   `Route.begin` on the `tests/test_route_bury.lua` crossing shape plus one extra flow-`item/a` source whose belt joins
   run `item/a` from the side on a tile the crossing would bury: route ok and no underground entrance is side-fed
   (no belt of any flow points into an underground entrance tile from a side).

## Files this lane owns

logic/bp/side_feed.lua, tests/test_side_feed.lua, docs/tasks/230_side_feed.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/230`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane230-tests", "command": "git diff --name-only round-40-base HEAD | grep -Ev '^(logic/bp/side_feed\\.lua|tests/test_side_feed\\.lua|docs/tasks/230_side_feed\\.md)$' | ( ! grep . ) && git diff --quiet round-40-base HEAD -- docs/tasks/230_side_feed.md && ! git diff round-40-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_side_feed test_route_bury test_validate_transport_shapes test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane230-tests-ok", "expect_exit": 0, "expect_regex": "lane230-tests-ok", "timeout_s": 3000}
{"name": "lane230-measure", "command": "f=$(mktemp); timeout 1500 lua5.2 tools/stage_fail.lua tests/golden/cases/player-red-green-science-10s/prepared_input.json > $f 2>&1; grep -m1 \"^STAGE validate\" $f | grep -qxF 'STAGE validate ok=false BP_V_FLUID_MIX=1' || { echo STAGE-WRONG; exit 1; }; for c in player-red-science-10s-bulk player-red-science-10s player-red-science-10s-stack1 player-red-science-1s player-red-science-1s-bulk player-green-science-1s player-inserter-10s player-inserter-10s-bulk; do l=$(sh tools/bytes_hash.sh $c); grep -qxF \"$l\" tests/fixtures/bytes_round39.txt || { echo BYTES-DIFF $c; exit 1; }; done; echo lane230-ok", "expect_exit": 0, "expect_regex": "lane230-ok", "timeout_s": 3000}
```

# bound: 2400s
