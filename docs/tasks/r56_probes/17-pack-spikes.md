# Ticket 17: which call makes 1-4 s ticks in "pack" phase

Host legalcopilot-dev, 2026-10-03 22:13-22:19 UTC, load 9.5-17.4, lua5.2, worktree ~/wt-rrc-speed02 at origin/main
f3d2268 (+ local ckpt.lua RRC_GAME_TICK patch = exact jobs.lua loop, 2000 ops/tick). Offline tick N = game tick N+15
(blue spikes 1/68/248/389/663/894 here = engine 15/83/263/404/678/909 in ticket 16).

Probes (research/17-probe/): `spike.lua` (per-tick line sampler, ~3x overhead), `split.lua` (per-tick CPU in
Groups.step / Pack.step / rest; `BUCKETS=1` prints each bucket build). Logs: `logs/blue.log`, `logs/*-split.log`,
`logs/blue-buckets.log`.

## Fact 1: big spikes are Groups, not Pack

Every 0.8-4.4 s "pack" tick is the first tick of a grid: search.lua:1427 `start_grid` -> `Groups.begin`, then
search.lua:2119 `run_stage(..., Groups)` -> groups.lua:2721 `make_candidates_once` builds ONE bucket per call
(groups.lua:2638 `build_block`) and charges `ops = ops - 1` (groups.lua:2724); emit charges 1 op per candidate.
The search.lua:2121 comment says "one resumable transition per game tick", but jobs.lua:441 re-calls the job until
2000 ops are spent, so all buckets + emit run in the one tick (blue 17 Groups.step calls in one tick). Phase label
already reads "pack" after the tick, so ticket 16 filed them under pack.

| sheet | Groups ticks (offline tick) | ms per regroup, lua5.2 | Groups.step calls/tick | regroups = grids |
|---|---|---|---|---|
| blue-science-10s | 1, 68, 248, 389, 663, 894 | 874-954 | 17 | 6 |
| magenta-science-10s | 1, 53, 238, 403, 730, 1040 | 2089-2193 | 26 | 6 |
| inserter-10s-stack1 | 1, 51 | 3052-3073 | 13 | 2 |
| red-green-science-10s | 1, 85 | 1017-1031 | 16 | 2 |

Tick 1 also carries plan (ticket 01). One bucket alone breaks 16 ms: blue chemical-science-pack (23 machines)
258 ms, electronic-circuit 134 ms, plastic-bar 91 ms (blue-buckets.log). So build_block itself is unsliced; charging
more ops per bucket would spread buckets over ticks but leave a 258 ms tick.

Whether Groups output differs between grids (input carries `grid` + `ring_bump`, search.lua:1427) is not measured.

## Fact 2: Pack's own spikes are smaller, from origins charged 1 op

Pack-only ticks over 30 ms, offline: blue 23 (36-282 ms, worst 282 @1096), magenta 52 (worst 161 @898), red-green 9
(worst 79), stack1 5 (worst 43). All inside pack.lua:776 `layered_scan` -> pack.lua:718 `layered_legal`. A rejected
origin costs 1 op (pack.lua:721-727), but reaching the reject runs w*h `cell_key` string lookups (pack.lua:722-724,
:210), `placement_avoids_port_cells` (pack.lua:306-309) and `buffer_zones_fit` (pack.lua:101-104: zones x every
placed buffer zone via Buffer.conflict, buffer.lua:37). That loop grows with placements, so late ticks of each grid
cost most (blue 1084-1096). 2000 ops of cheap rejects = up to 2000 such scans. A step charged too few ops; no call
ignores `budget.ops`.

## Ruled out

- Pack.begin (Grid.free_regions + rebuild_indexes): 4-29 ms on grid-start ticks (pack column).
- The ~0.7-1.1 s route-start tick in each split log is the ckpt `graph_dump` save (blue.log sampler: graph_dump.lua
  lines top SELF), probe artifact. Ticket 16 engine blue had no such tick at the pack->route edge.

## Answer

1. Groups regroup at each grid start, all buckets in one tick (groups.lua:2724 charges 1 op per bucket build,
   build_block groups.lua:1001 unsliced): 0.9 s blue, 2.2 s magenta, 3.1 s stack1, 1.0 s red-green per regroup
   offline; engine 1.4-2.0x at load (blue 1.3-4.4 s). Present on all four sheets.
2. Pack layered_legal reject path charged 1 op, cost grows with placed buffer zones: 36-282 ms ticks; all four sheets.
