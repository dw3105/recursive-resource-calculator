# Ticket 18: does Groups output change between grids of one search

Host legalcopilot-dev, 2026-10-03 22:26-22:39 UTC, lua5.2, load 9.9-21.6 (last run at 21.6: ms noisy, shape holds).
Worktree ~/wt-rrc-speed02 at origin/main f3d2268 (+ ticket 17's local ckpt.lua RRC_GAME_TICK patch), read only.
Ticket 14's session runs probes in that same worktree at the same time; this ticket edited nothing in it.

Probes (research/18-probe/):
- `fp.lua` (LUA_INIT): for every Groups run, sha256 of its input with `grid` removed and of its result, a diff
  against the first run, and an optional count-hook sampler (SAMPLE=1, TARGET=<linedefined>) that splits CPU by
  direct sub-call.
- `replay.lua <route ckpt>`: runs Groups alone on the checkpoint's own Groups input. Compares the stored result
  with a fresh one, then ring_bump 1/2 and split x2 of the biggest step. Prints the deep-copy cost.
- `p_box.lua` (LUA_INIT, loads fp.lua): in-memory patches of groups.lua (BOX default, ROT=1, NOBOX=1 = base) plus
  timers (TIMEMACH, TIMEHAND, TIMEBUCKET).

Run 1 (game rate, until route start): `RRC_GAME_TICK=1 LUA_INIT=@fp.lua ckpt.lua save <case> phase=route`. Logs are
`logs/<case>.log` and `logs/red-green.log`. Its checkpoints in the scratchpad fed every replay.

## Fact 1: the same bytes on every grid, on all four sheets

| sheet | regroups to route start | input sha (minus grid) | result sha | ms per regroup |
|---|---|---|---|---|
| player-blue-science-10s | 6 (grids 54x54 .. 104x104) | d3330f6025e3 x6 | cda9093627be x6 | 904-971 |
| player-magenta-science-10s | 6 | f2501d7dcfa5 x6 | 44148d44376e x6 | 2006-2133 |
| player-inserter-10s-stack1 | 2 | 592bb4189c6c x2 | 857baf811f3b x2 | 3067-3073 |
| player-red-green-science-10s | 2 | 572dc87dcf28 x2 | 0056e8c86a93 x2 | 949-1063 |

Why: groups.lua never reads `input.grid`. grep finds no `grid` read in groups.lua, buffer.lua, belt.lua or grid.lua.
The only per-search inputs it reads are `ring_bump` (groups.lua:2426) and `split_steps` (groups.lua:2593).

Also measured, all four sheets (logs/*-replay.log):
- Deterministic: the same input twice gives the same sha.
- The stored `state.work.groups.result` at route start (after pack of every grid) equals a fresh run. Pack does not
  change the shared result. This is proven only up to route start; search uses the candidate with no copy
  (search.lua:1872).
- Deep copy of the result costs 5-14 ms (fp.copy).

## Fact 2: what changes Groups input in one search

Every regroup is a `start_grid` call (search.lua:1416). Its Groups input = `copy(state.work.input)` + plan + grid +
`ring_bump = state.work.attempt` (search.lua:1427). The only write to `state.work.input` is split retry
(search.lua:2029). Callers:

| caller | file:line | Groups input changes? |
|---|---|---|
| preflight -> first grid | search.lua:2116 | first run |
| next_grid | search.lua:1444 | no (grid only, unread) |
| layered_fallback | search.lua:1815 | attempt reset to 0 |
| split_retry | search.lua:2032 | yes: split_steps; attempt 0 |
| discard_candidate attempt+1 | search.lua:2050 | yes: ring_bump |
| edge inset retry | search.lua:2060 | no (edge_inset not in Groups input) |
| lane_cap redo | search.lua:2418 | no |
| strict_ends redo | search.lua:2422 | no |

Replay on the route checkpoints (logs/*-fulldiff.log, every diff path):
- ring_bump 1 or 2 changes only `blocks[*].buffer_zones[*].ring` (+1/+2). Diff counts: red-green 33, blue 58,
  magenta 58, stack1 11. Not one other path changes.
- split x2 of the biggest step changes geometry on red-green (875 diff paths) and blue (2642). On magenta and stack1 it
  changes nothing (chunks there are already >= 2).

Cache key: `split_steps` (serialized) + `ring_bump`. `ring` can also be patched on a cached build (+bump on every
buffer zone, then the conflict assert at groups.lua:2439 again). Cache the whole Groups state, not only `.result`:
`Groups.reorient` reads `groups_state` (groups.lua:2749).

Saved per search to route start, lua5.2: blue 5 x 0.9 s, magenta 5 x 2.1 s, stack1 1 x 3.0 s, red-green
1 x 1.0 s. Redo starts that do not change the input (lane_cap, strict_ends, edge inset, next_grid after a redo)
also hit. A full-run count of those is not measured.

## Fact 3: where build_block time goes, and two byte-safe fixes

Sampler (count hook every 1000 VM instructions, ring 0, logs/*-sample*.log). "Base" means no patch:

| level | sub-call | share of Groups CPU |
|---|---|---|
| build_block (groups.lua:1360) -> | append_multi_flow_inserters (:1001, via :1906 -> :1070) | stack1 100%, magenta 96%, red-green 92%, blue 62% |
| | beacon place_row (:2018) + redundant (:2159) | blue 16% + 16%, red-green 3% + 3%, magenta 2% + 1% |
| :1001 -> | candidate_inserter (:456, called at :1030 per hand) | 100% on blue, magenta, stack1 |
| :456 -> | Geometry.world_box (geometry.lua:87) at :536-538 | stack1 64%, blue 60% |
| | transfer_cells (:383) at :508 | 13-14% (after BOX fix: 42-48%) |
| | cell_in_rect (:390) | 5-6% (after BOX fix: 12-16%) |

Cause: `candidate_inserter` scans (w+16)x(h+16) tiles x 4 directions. For each tile it calls world_box on every
machine of the block (:536-538). It also builds 2 point tables and rotates both offsets (:508 -> :383), but the
rotation depends only on direction.

In-memory patches (p_box.lua). Both are pure hoists in the same float order:
- BOX: world_box per machine once per call (`__bx[member]` memo).
- ROT: rotate pickup/drop offsets once per direction; cells = `cell_of(x + iw/2 + dx)`.

The result sha is equal to base on all 20 runs (4 sheets x ring 0, ring 0 again, ring 1, ring 2, split). Groups ms
per regroup, lua5.2 (logs/*-pbox.log, *-rot.log, *-mach-*.log):

| sheet | base | BOX | BOX+ROT |
|---|---|---|---|
| red-green | 1016-1063 | 346-386 | 228-268 |
| blue | 875-971 | 504-532 | 437-494 |
| magenta | 2048-2133 | 509-554 | 360-428 |
| stack1 | 2905-3073 | 1009-1065 | 663-680 |

## Fact 4: slice points against 16 ms (BOX+ROT on)

| unit | file:line | worst, base | worst, BOX+ROT | over 16 ms after fix |
|---|---|---|---|---|
| one hand (candidate_inserter call) | groups.lua:1030 inside the hand loop :1007 | 142 ms magenta casting-steel | 13.8 ms | 0 of 160 calls |
| one machine (append_inserters) | groups.lua:1906 | 553 ms stack1 electronic-circuit | 170 ms stack1 electronic-circuit | stack1 yes |
| one bucket (build_block) | groups.lua:2638, charged 1 op at :2724 | 614 ms magenta casting-steel | 247 ms blue chemical-science-pack | 3 to 11 per sheet |

- One yield per bucket is not enough. Blue chemical-science-pack stays at 247 ms after the fix. That time is beacon
  code (:2018/:2159 = 32% of blue base CPU), which the hand fixes do not touch.
- Stack1 electronic-circuit runs 94-130 ms (many hands per machine).
- The finest unit measured under 16 ms is one hand. The engine runs 1.2-2.2x lua5.2 (ticket 01), so 13.8 ms there
  may be up to ~30 ms.
- Beacon code per row (:2018) and per redundancy check (:2159) is not timed per call.

## Answer

1. Equal. On blue, magenta, stack1 and red-green, the Groups result is byte-equal across every grid of one search
   (6/6/2/2 regroups to route start). Groups never reads `grid`.
2. Cache key: `split_steps` + `ring_bump`. ring_bump changes only `buffer_zones[*].ring`; split changes geometry.
   Cache the Groups state (reorient reads it). The shared result is unchanged through pack to route start; a later
   change is not proven (deep copy 5-14 ms if needed). Saves 1-5 regroups per search: 1.0-10.5 s lua5.2 per sheet.
3. Two byte-safe hoists in candidate_inserter (groups.lua:536-538 world_box, :508 transfer_cells) make Groups
   2.0-5.6x faster: magenta 2.1 -> 0.4 s, stack1 3.0 -> 0.67 s.
4. Slice point: per hand (groups.lua:1007 loop, candidate_inserter call :1030), <= 13.8 ms lua5.2 after the fix.
   Beacon placement (:2018 place_row, :2159 redundant) needs its own slice: blue chemical-science-pack 247 ms. A
   per-bucket yield (:2724) alone leaves 3-11 ticks over 16 ms per sheet.

Correction to ticket 17: `build_block` is groups.lua:1360. groups.lua:1001 is `append_multi_flow_inserters`.
