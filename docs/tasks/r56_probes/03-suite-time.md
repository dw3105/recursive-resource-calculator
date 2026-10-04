# Ticket 03: which tests and shards eat suite wall clock

Measured 2026-10-03 19:26:19Z -> 20:19:22Z, legalcopilot-dev (4 cores, 16 GB), fresh worktree ~/wt-rrc-speed03 at
main f3d2268 (logic/tests/tools == b14786e). Load1 at row start 0.7-3.9 (census row pushes it to ~11 while it runs).
Suite GREEN (status=0), 0 failed rows. One run, wave r56-speed02 slot suite.

Probe: tests/run.sh patched to time each step (same steps and order; python tool tests per module instead of one
discover). Rows: research/03-probe/timing.txt (`TIME kind name wall user sys rc load1 start`), log
research/03-probe/suite.log. Headless test seconds = sum of FactorioTest `PASS ... (N s)` per shard section.
Static facts (whole-sheet builders, duplicates, fixed paths): research/03-static-survey.md.

## Table 1: suite wall by part (53 min 03 s total; row sum 3179 s)

| Part | Rows | Wall s | % suite | User CPU s | Note |
|---|---|---|---|---|---|
| Lua tests/test_turn_flip_census.lua | 1 | 904 | 28% | 2583 | 288 small sheets, `xargs -P 4`, all 4 cores |
| Lua, other 316 files | 316 | 704 | 22% | 682 | single core each |
| Headless 2.0 player mods, 8 shards | 8 | 824 | 26% | 784 | |
| Headless 2.1 vanilla, 8 shards | 8 | 371 | 12% | 324 | |
| Headless 2.0 vanilla, 8 shards | 8 | 316 | 10% | 282 | |
| Python tests/tools (20) + tests/test_*.py (6) | 26 | 42 | 1% | 30 | |
| Gamemock tests/game via offline.lua | 16 | 20 | 1% | 19 | |
| luac data.lua, settings.lua | 2 | 0 | 0% | 0 | |

Lua size buckets (317 files): 227 < 1 s, 61 in 1-5 s, 25 in 5-20 s, 6 >= 20 s.

## Table 2: Lua files >= 10 s wall

| File | Wall s | Kind (survey) |
|---|---|---|
| test_turn_flip_census.lua | 903.9 | 288 whole small sheets, 4 cores |
| test_inserter_stack1_delivers.lua | 61.3 | whole sheet inserter-10s-stack1 layered |
| test_route_search_loop.lua | 58.1 | route unit |
| test_route_journal2.lua | 53.7 | route unit |
| test_blue_10s_delivers.lua | 51.1 | first stage blue (validate 15) |
| test_route_no_replay.lua | 43.4 | route unit |
| test_ckpt.lua | 19.3 | red-1s whole x2 + 4 save + 4 resume |
| test_delivery_final.lua | 18.6 | red-1s mock whole x8 |
| test_fixture_facts.lua | 17.1 | |
| test_route_improve_waste.lua | 16.1 | route unit |
| test_route_fail_snapshot.lua | 15.3 | |
| test_red_green_fluid_ports.lua | 14.2 | red-green first validator input |
| test_red_green_10s_delivers.lua | 14.2 | red-green whole layered |
| test_drawn_e2e.lua | 13.6 | 4 drawn small sheets |
| test_corpus_setups.lua | 13.1 | |
| test_route_pipe_join.lua | 10.4 | |

## Table 3: headless shards (wall = row; tests = FactorioTest sum; overhead = staging + Factorio start/exit)

| Config | Wall s | Tests s | Overhead s | Overhead / shard | Biggest test files (s) |
|---|---|---|---|---|---|
| 2.0 vanilla | 316 | 240 | 75 | 9.4 | turn_flip_sims 93 (shard 8), capture 28, parity 16, twins 8-13/shard |
| 2.0 player | 824 | 712 | 112 | 14.0 | turn_flip_sims 241 (shard 8), sheets 176 (shard 6), twins 25-32/shard, turn_flip_cases 26 |
| 2.1 vanilla | 371 | 288 | 83 | 10.4 | turn_flip_sims 122 (shard 8), capture 34, turn_flip_cases 19, parity 15, sheets 14 |
| all 24 | 1511 | 1240 | 270 | 11.3 | turn_flip_sims 456 total = 30% of headless |

Shard walls: 2.0 26/20/52/33/18/20/31/115; player 61/46/54/54/42/216/65/287; 2.1 28/20/59/32/17/31/38/147.
Shard 8 (feed + turn_flip_sims) is longest in every config; player shards 6 and 8 = 503 s = 61% of player config.
Player mods slow every test: twins 25-32 s per shard vs 8-13 s vanilla.

## Table 4: gate (round 55, ~/.claude/plans/r55_gate/gate.log, 2026-10-03 12:56:00Z -> 13:18:20Z, b14786e == f3d2268 code)

| Rows | Wall s | Note |
|---|---|---|
| head layered 14 | 650 | magenta layered alone 452 (18 chunks) |
| head drawn 14 | 281 | magenta drawn 116 |
| head total 28 | 931 (15.5 min) | the "gate 28 runs" |
| main drawn A/B 14 | 408 | RC-11 same-hour main run |
| all 42 | 1340 (22.3 min) | load not logged per row (gap) |

Gate rows run in ckpt chunks of <= 115 s (chunk_bytes.sh): save cost adds wall; multi-chunk CPU sum misses saves.

## Answers

1. Wall eaters: census 904 s (28%), headless 1511 s (47%; turn_flip_sims 456, player sheets 176, player twins ~230,
   shard overhead 270), other Lua 704 s (22%). r55-suite4 "1357 s unlogged gap" (12:01:29 -> 12:24:06) = census
   window (904 s here at load ~2; longer under r55 load).
2. Whole-sheet builders: see survey Table 1 (11 subprocess/in-process whole builds of goldens, 1 drawn x4, ckpt x10
   runs, census 288 + 2). Only census and stack1/blue/route units exceed 40 s.
3. Repeat work: red-10s-bulk built twice (bulk_delivers redundant with bulk_shape :33); red-1s whole built by TF5,
   ckpt uninterrupted, ckpt list, golden_profile (one r.json + sha could serve); test_probe golden parity duplicates
   test_parity; census CT4 repeats CT1. Saving from these: small (< 30 s); big lumps are census and headless sims.
4. Parallel: other 316 Lua files = 704 s single-core serial -> ~180-200 s on 4 cores if 5 fixed /tmp paths
   (survey Table 3) get unique names and ledger append is safe; census already uses 4 cores (no gain, only fewer
   or faster sheets); headless max 2 at once (ticket 04) after per-shard build tree: 1511 s -> ~760 s floor.
   Even then suite floor ~ 904 + 200 + 760 = ~31 min > 15 min target: census and headless sims/sheets must
   shrink, move to gate, or run concurrently with Lua part.
5. Fixed overhead: 24 stagings + Factorio starts = 270 s (11 s/shard); fewer, larger shards cut it, but longest
   shard (player 8, 287 s) sets parallel floor.

## Gaps

- Gate per-row load not logged (r55 log). Gate figures from 2026-10-03 12:56Z, not re-run.
- Lua user CPU for census 2583 s at -P 4: per-sheet cost not split (288 sheets ~ 9 CPU s each average).
- Python discover replaced by per-module runs: 40 s here vs 74.3 s single discover in r55-suite4 (different load).
