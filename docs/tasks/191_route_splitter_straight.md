# 191 route: a splitter only on a straight belt; a two-item rear port may be entered as a curve

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-191`, branch `lane/191`,
base tag `round-30-base`, merge target `int/r30`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its tests pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), the
probe `sh tools/first_verdict.sh` (~10 s) and `sh tools/measure_sheet.sh <case>` (red ~15 s, green ~3 min). Never use
`coroutine` (Factorio has none). Plain data state only (the job is resumable across game ticks).

Read `docs/contracts/round30.md` first: it is the contract. Your clauses: R1, R2.

## Explain very simply

Green science: one iron belt must feed four machines, so route splits it with a splitter. Route put the splitter on
a belt CORNER, e.g. iron trunk comes east along y=27 and turns north at (28,27); the splitter sits on (28,27)+(29,27)
facing north. The belt from the west pushes into the splitter's SIDE. In the game a splitter takes items only from
behind. Everything behind that splitter starves. Same for gear at (32,13). Fix: a branch may leave a laid belt only
at a tile fed from behind (a straight tile), never at a corner.

Green science today (`sh tools/measure_sheet.sh player-green-science-1s`, 2026-09-24): route reports ok but leaves
demands unlaid (`BP_R_NO_PATH` shortfalls), so validate rejects all 3 attempts. Shortfalls per attempt:
- attempt 1: gear -> belt foundry (x2), belt foundry product -> science row, iron -> inserter assembler;
- attempt 2: ONLY gear -> belt foundry;
- attempt 3: inserter product -> science row (x6), iron -> gear assembler (x2).
Attempt 2 map (letters: A } V { iron belts, n e s w gear belts, $ splitter, U/u underground, i hand, p pole,
G gear assembler, T belt foundry, N inserter assembler):
```
   0123456789012345678901234567890123456789
12 ...KKKKKK.^......v..{{{{{{{{A...........
13 ...KKKKKK.^p.....v..i...su.$$Uwwwww.....
14 ....ip.i..^......viNNNiww...AiGGGin.....
15 ....>>>>>>^........NNN.....UA.GGGU......
16 ...................NNN.....^A.GGG^......
17 ....................i......^A....^......
18 ....................>>>>>>>^A....^......
19 ............................A....^......
20 ......................p.....A....^.p....
21 .......p........p...........A}}}U^...u}V
22 >>>>>>>>>>>>>>>>>>>>>>>>>>..$$...i.....V
23 ....i..i..i..i..i..i..i..i..A...iTTTTTiV
```
Gear hand (33,14) drops on (34,14) (trunk heads north, then west along y=13 to the inserter assembler). Belt
foundry gear hand (32,23) reads (31,23). A path exists on the map (e.g. splitter at the source tile (34,14)+(35,14)
facing north, then east/south, one underground across the foundry product column x=33, one across iron row y=21).
Suspects, MEASURE which one refuses before you change anything (trace the search for this demand):
(a) `splitter_cell_allowed` (~1004-1043) refuses a splitter when ANY of the 8 neighbours is an underground end:
    (33,15) `U` is diagonal to (34,14) — a splitter covers exactly its 2 tiles, only those must be free of
    underground ends; (b) a source port tile is never offered as a splitter anchor; (c) the branch must jog one tile
    after the splitter and the tile after is reserved. Fix what you measure. Green is DONE only when
    `sh tools/measure_sheet.sh player-green-science-1s` prints `ok=true ... mixed=0 starved=0`.

Red science: the first science row's rear input port (v10 tile (7,2), belt must face south) is entered from behind
by a 3-belt detour (6,2)^ (6,1)> (7,1)v. Entering from the side at (7,2) makes the belt a curve, which keeps both
lanes (the player's hand fix proves it: `mixed=0 starved=0`). Today `rear_curve` (route.lua ~486) allows the curve
only for a 1-flow port; this port carries iron + copper. Allow 2 flows.

## Where the code is (`logic/bp/route.lua`)

- `rear_curve` ~486 (port.rear and at most 1 flow); commit forces last belt to `sink.travel_dir` ~1568-1569.
- `splitter_can_absorb` ~985, `splitter_cell_allowed` ~1004, `splitter_branch_allowed` ~1045,
  `terminal_splitter_refused` ~1066, `merge_splitter_footprint` ~1089.
- commit `append_normal_path` ~1560-1660: splitter conversion ~1603-1660 (`rode_the_trunk` ~1605, rejections
  ~1608, ~1614-1626, ~1639).
- `route_chain_tiles` ~1310-1369 (chain walk; gives you each tile's feeder), seeds in `begin_search` ~1904-1934.
- search expansion: body jump ~2152-2180, side merges ~2167-2187 + `path_cell_free` ~1777-1797, plain sideways
  step after a refused body jump ~2188-2191, crossing retry ~3428-3438.

## What to build

1. R1: "straight-fed" test for a laid tile: the chain tile one step back against the tile's heading is a same-flow
   belt / underground exit / splitter with the same heading, or the tile has no belt feeder at all (a source tile fed
   by hands). Use it in the body jump AND in commit (a corner tile is never converted). Refuse side merges into a
   splitter tile. Remove the plain sideways step queued after a refused body jump. Set `last_route_rejection.x/.y`
   at both commit rejections that lack it.
2. R2: `rear_curve` for at most 2 flows, when the approach tile is not a same-flow belt pointing into the port.
3. Tests, red at `round-30-base` first:
   - new `tests/test_route_splitter_straight.lua`: a trunk that turns (corner) and a second sink beside the corner:
     the splitter is never on the corner tile, its anchor's back neighbour faces the anchor's heading; for all 4
     headings; a side merge into a splitter tile is refused; route still serves both sinks.
   - `tests/test_route_rear_curve.lua` new case RC2: a 2-flow rear port with free side approach is entered from the
     side (last belt faces the port's travel dir, fed from its side), fewer belts than the behind approach.
   - update `tests/test_route_splitter_physics.lua` / `tests/test_route_footprints.lua` /
     `tests/test_route_collision.lua` / `tests/test_route_chain.lua` ONLY where a fixture asserted a corner splitter
     (say which in the commit message).
4. R3 (from the suspects above): whatever makes green route every demand, e.g. a splitter footprint check on its
   own 2 tiles only; a source tile fed only by hands is a legal anchor (R1 already says so).
5. Measure both sheets (`sh tools/measure_sheet.sh player-green-science-1s`, `... player-red-science-1s`). Green must
   print `ok=true ... mixed=0 starved=0`. Red must print `ok=true`, `entities` <= 184 (base 186), `mixed=0
   starved=0`. If green still fails, the MEASURE block prints rejection codes; `tools/lane_sim.py` lines marked
   STARVED name the starving hand; fix route, never the tools.

## Checks (lua5.2 only, one file at a time)

`test_route_splitter_straight test_route_rear_curve test_route_splitter_physics test_route_footprints
test_route_collision test_route_chain test_route test_route_rows test_route_merge_feed test_route_tidy
test_route_free_cell test_route_improve test_route_bury`, then `sh tools/first_verdict.sh`, then both measures.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route_splitter_straight.lua`, `tests/test_route_rear_curve.lua`,
`tests/test_route_splitter_physics.lua`, `tests/test_route_footprints.lua`, `tests/test_route_collision.lua`,
`tests/test_route_chain.lua`.

Never touch anything else: not `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/contracts/**`,
nor any test file not listed here.

## Commit, THEN check

Commit on `lane/191` with both MEASURE lines in the message. **Run the checks below as the very LAST action.**

## What done mean

```checks
{"name": "lane191-tests", "command": "git diff --name-only round-30-base HEAD | grep -v '^docs/tasks/191' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_splitter_straight\\.lua|tests/test_route_rear_curve\\.lua|tests/test_route_splitter_physics\\.lua|tests/test_route_footprints\\.lua|tests/test_route_collision\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && ! git diff round-30-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_splitter_straight test_route_rear_curve test_route_splitter_physics test_route_footprints test_route_collision test_route_chain test_route test_route_rows test_route_merge_feed test_route_tidy test_route_free_cell test_route_improve test_route_bury; do lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane191-tests-ok", "expect_exit": 0, "expect_regex": "lane191-tests-ok", "timeout_s": 1500}
{"name": "lane191-measure", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/measure_sheet.sh player-red-science-1s | tail -1 | tee /tmp/rrc191-red.txt && sh tools/measure_sheet.sh player-green-science-1s | tail -1 | tee /tmp/rrc191-green.txt && grep -q 'ok=true .*mixed=0 starved=0' /tmp/rrc191-red.txt && grep -q 'ok=true .*mixed=0 starved=0' /tmp/rrc191-green.txt && sed -n 's/.* entities=\\([0-9]*\\) .*/\\1/p' /tmp/rrc191-red.txt | awk '{exit !($1 <= 184)}' && echo lane191-measure-ok", "expect_exit": 0, "expect_regex": "lane191-measure-ok", "timeout_s": 900}
```

# bound: 3600s
