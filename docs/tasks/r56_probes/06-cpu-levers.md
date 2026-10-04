# 06 CPU levers: in-memory probe gain + bytes (ticket 06 fact-finding)

Host legalcopilot-dev (4 cores, shared), 2026-10-04 07:53-08:30 UTC, lua5.2. Code = origin/main 994dc9f (logic/
same as f3d2268) in own worktree `~/wt-rrc-speed06` + ticket 01 ckpt RRC_GAME_TICK diff + local PROF %.3f and
`vmi=` columns in tools/ckpt.lua (never committed). Load 4.7-21 (other sessions). Wave r56-speed21 then
r56-speed06t, one reason "round 56 ticket 06 cpu levers in-memory probe" (ckpt-save slot).
All patches are in memory only (RC-17): `06-probe/p06.lua` = ckpt `--patch` / `P06_LEVERS` source rewrite.

## Method

- Bytes: whole-sheet game-rate run (`ckpt.lua uninterrupted`, RRC_GAME_TICK=1, 2000 ops/tick), sha8 of
  canonical result + ticks, base vs patched. `06-probe/run2.sh`, `chunk.sh` (blue, chunked under 120 s).
- Work, deterministic: `vmi` = Lua VM instructions (thousands) per phase, count hook (`06-probe/vmi.lua`).
  Load-independent; misses C-side cost (allocation, GC, `next`), so it under-reads allocation levers.
- CPU: in-process A/B (`06-probe/ab_stage.lua`): load the checkpoint, step one phase span at game rate,
  alternate A (base modules) and B (patched modules) N times in one process, min and median. Load 6-17 gives
  +-15% per run; whole-run CPU single shots are noisy (see red-green row: tidy -32% CPU with only -7% vmi).
- Levers in p06.lua:
  - `heap` heap_before without `priority or cost` fallback, push/pop hole sift (same order; serial unique)
  - `dirv` route-local dir vector / opposite tables in place of 58 `Grid.dir_vector` + 15 `Grid.dir_opposite` calls
  - `cempty` crossing_targets early exits return one shared read-only empty list (the one caller only iterates)
  - `pcov` power consumer_covered + rect_intersects without temp table or rect_valid calls
  - `pfast` power finite/integer fast path for plain finite numbers (`v - v == 0`), index builder tests coverage
    on one scratch candidate instead of a fresh 3-table candidate per lattice position
  - `psel` power greedy selected_check remembers permanent rejections (measured ~0: dropped)
  - `sishare` search stage_input shares `catalog` + `snapshot` by reference; `SIGUARD=1` signs both before
    every stage_input call and logs any change

## Lever 1: route A* core (heap, dirv, cempty)

| sheet | base | patched | % | sha same? |
|---|---|---|---|---|
| red-1s route+tidy vmi k | 15702 | 14790 | -5.8 | yes 80095966, 180 ticks |
| green-1s route+tidy vmi k | 84758 | 78623 | -7.2 | yes 6b65a1d1, 535 ticks |
| red-green route+tidy vmi k (all levers run) | 301187 | 277847 | -7.7 | yes c01afb5a, 1602 ticks |
| green route span CPU s, A/B 9 reps (min / med) | 0.184 / 0.242 | 0.200 / 0.232 | +9 / -4 | same end state |
| green tidy span CPU s, A/B 5 reps | 1.615 / 1.945 | 1.804 / 1.852 | +12 / -5 | same end state |
| red-green route span CPU s, A/B 5 reps (+cempty) | 1.200 / 1.316 | 1.204 / 1.336 | 0 / +2 | same end state |
| red-green tidy span CPU s, A/B 3 reps (+cempty) | 5.967 / 6.217 | 5.781 / 5.845 | -3 / -6 | same end state |
| blue | see blue table | | | |

Verdict: **not worth it alone**. Byte-safe, but 6-8% of route work = ~4-5% of magenta (route 69%). CPU gain lies
inside load noise. Ship only as a free rider on another route lane.
Integer `coordinate_key`: not tried. It cannot be byte-safe as a micro-opt. Cell keys are shared with
pipe_runs.lua (own `key(x,y)`), fluid_touch.lua, side_feed.lua and a groups.lua:2832 parse. Six
`pairs(work.segments_by_cell...)` loops in route.lua and three in pipe_runs.lua iterate them, so the key type
changes iteration order. coordinate_key already caches its strings. Self cost 2.8% (ticket 02) is the ceiling.
**needs more** (multi-module, order audit) and is not worth it at 2.8%.

## Lever 2: power (pcov + pfast)

Where the power span goes (vmi sampler, red-green first power span, `06-probe/power_prof.lua`): per-op scheduler
overhead ~38% (`integer` 10%, `finite` 8%, `operation_cost` 8%, Power.step loop head 11%, `consume` 2%),
`advance_candidate_index` 14%, `consumer_covered` 13%, `rect_valid`+`rect_intersects` 15%, greedy 10%.

| sheet | base | patched | % | sha same? |
|---|---|---|---|---|
| red-1s power vmi k (pcov+pfast) | 12651 | 9744 | -23 | yes 80095966 |
| green-1s power vmi k | 37958 | 28303 | -25 | yes 6b65a1d1 |
| red-green power vmi k (all levers run) | 177732 | 122710 | -31 | yes c01afb5a |
| green power span CPU s, A/B 7 reps (min / med) | 0.329 / 0.343 | 0.265 / 0.323 | -19 / -6 | same end state |
| red-green power span CPU s, A/B 5 reps | 2.108 / 2.301 | 1.108 / 1.398 | -47 / -39 | same end state |
| red-green power phase CPU, whole run (1 shot) | 4.79 | 2.16 | -55 | yes |
| pcov alone, red-green span A/B | 1.649 / 1.755 | 1.316 / 1.458 | -20 / -17 | same |
| psel alone, red-green span A/B | 2.118 / 2.376 | 2.087 / 2.365 | -1 / 0 | same |

Verdict: **ready** (pcov + pfast, drop psel). Byte-safe: same decisions and the same op charges, so the same ticks.
Power is 19-28% of red-1s / green / red-green / blue (ticket 02), so the lever is worth ~8-12% of those sheets.
A spatial index was not needed for this result. The cost was per-op overhead and allocation, not the scan.
A real index would change op charges and therefore ticks, so it is a separate, non-byte-neutral step.

## Lever 3: stage_input deep copy (sishare catalog + snapshot)

`sitime` = per-key copy time inside stage_input (one run per sheet):

| sheet | stage_input calls | copy ms total | of which catalog + snapshot | share of step CPU | sha same with sishare? | SIGUARD changes |
|---|---|---|---|---|---|---|
| red-1s | 4 | 113 | 64 + 44 | ~10% (1.1 s) | yes 80095966 | 0 |
| green-1s | 4 | 94 | 61 + 23 | ~2.5% | yes 6b65a1d1 | 0 |
| red-green | 5 | 169 | 89 + 46 | ~1% | yes c01afb5a | 0 |

vmi with sishare: red-1s -4.9% total, green -1.5%. Each call costs 20-35 ms of CPU, and that cost lands on the
stage-begin tick. That tick is the part that matters for worst-tick: one catalog copy alone is about two 16 ms
tick budgets.
Verdict: **ready** offline, byte-safe on 3 sheets with a mutation guard. Before shipping, check one thing in game:
whether storage persistence of a job state keeps the shared catalog reference safe. Jobs copies state at the
storage boundary. Small total gain on big sheets.

## Lever 4: publish tick (sha256 on demand, persist_handle copies once)

Code read (logic/bp/generation.lua at 994dc9f):
- `canonical_digest` (:1059) runs the pure-Lua `sha256` (:1004) over `helpers.table_to_json(canonical)` on every
  publish (:1292). Only engine tests and offline tools read `canonical_sha256` (ticket 09).
- `persist_handle` (:115) builds `record` from fresh `copy_plain`s: capture, result, canonical, interim (whose
  `.result` is the same blueprint again). It then copies the whole record again (:139
  `state.jobs[id] = copy_plain(record)`). The outer copy is redundant: every field is already a fresh copy or a
  scalar. Publish calls it 3 times (:1256 search done, :1293 update_capture -> :806, :1330 final).

lua5.2 timing (`06-probe/t_publish.lua`, functions loaded from generation.lua source). Red-green result scaled by
entity count. Capture = magenta prepared input (961 KB). Min of 3-5. Load ~7:

| size | sha256 ms | persist today (x2 copy) ms | persist copy once ms | publish est. today: sha + 3 persist | est. after | saved |
|---|---|---|---|---|---|---|
| red-green 609 ent | 163 | 76 | 32 | 389 | 96 | 293 |
| blue-size 1437 ent | 404 | 94 | 63 | 685 | 189 | 495 |
| magenta-size 2155 ent | 543 | 129 | 71 | 929 | 212 | **717** |

In-game measurements from ticket 09 agree: sha256 magenta 710 ms, persist x3 417 ms, publish 1529 ms. Expected
in-game saving: ~0.7-1.0 s of a ~1.5 s magenta publish tick, with no byte change (the blueprint is not touched).
Verdict: **ready**. sha256 runs only when an engine test asks for it (a flag on the job, or test API computes it
lazily), and the redundant outer copy is dropped. The engine test owes parity: canonical_sha256 must still be
present wherever engine_test_api.lua:307 reads it.

## Blue (bound input 20-probe/in/player-blue-science-10s.json)

| run | when (UTC), load | total step CPU s | power s | route+tidy s | pack s | validate s | ticks | sha8 |
|---|---|---|---|---|---|---|---|---|
| base, one call (`run2.sh`) | 08:12, 5.5 | 65.0 | 12.5 | 32.5 | 10.7 | 8.3 | 6065 | c7d1994f |
| all levers (heap,dirv,cempty,pcov,pfast,sishare), 35 s chunks | 08:21-08:24, 14-16 | 64.2 | 7.7 | 31.1 | 13.7 | 10.6 | 6065 | c7d1994f |

- Bytes: **same** (sha c7d1994f…, 6065 ticks, 1475 entities). Blue base vmi: power 493 M, route+tidy 1299 M.
- CPU: the two runs ran at load 5.5 and 14-16, so only the phase split compares. Power fell 12.5 -> 7.7 s (-38%)
  while every lever-free phase rose 20-30% (pack +28%, validate +28%). That matches the red-green A/B. Route+tidy
  -4% under 3x the load is consistent with the 6-8% vmi gain, but it does not prove it.
- Not done: a base chunked rerun. Its first 35 s chunk save hit the 120 s cap at load 16 (DRIVER-FAIL chunk 0).
  Not retried, so the slot was not spent again. A blue power-span A/B was also not run.

## Surprises

- Power cost is ~38% scheduler overhead per op (finite/integer/operation_cost/loop) and allocation in the
  index builder, not the "linear scans". A no-index fix gives -39..-47% of the red-green power span with the
  same ticks.
- psel (greedy rejection memo) gains nothing: selected_check is not hot on these sheets.
- Route micro-opts are real in vmi (-6..-8%) but small. The A* expand body (search_step's per-neighbour rules)
  is the cost, not the heap or the vectors.
- stage_input looks small in share, but each call puts 20-35 ms on a single tick.
- Load on the host reached 21 (other sessions); 80 s CPU chunks timed out at 120 s wall, so blue ran in 35 s chunks.
