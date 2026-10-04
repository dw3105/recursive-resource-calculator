# 06 tail ticks: deterministic tick cost + spike map (2026-10-04)

Host legalcopilot-dev (4 cores, shared). Runs 2026-10-04 07:59-08:33 UTC, load 7.3-17.3 (other sessions). Code f3d2268
(the same code as the engine logs) in own worktree `~/wt-rrc-speed06b`, with local probe patches only: ticket 01
ckpt game-tick patch + `__tt` calls (`06-tail-probe/ckpt_game_tick_tt.diff`). Game rate 2000 ops/tick, layered.
Engine side: ticket 01 logs `01-probe/eng-2.0-{red1,am2green,rg,blue}.log` (2.0.77, 2026-10-03 18:01-18:09 UTC, load
0.7-2.6). Blue offline uses the bound input `20-probe/in/player-blue-science-10s.json`: 6065 ticks, sha c7d1994f
(= ticket 20). Every offline run kept its golden sha (red-1s 80095966, green 6b65a1d1, red-green c01afb5a).
Scope (coordinator, 2026-10-04): a spike is a tick over 50 ms engine-equivalent; ticks over 100 ms are counted too.
Wave r56-speed06t, one reason "round 56 ticket 06 spike map + tick calibration".
Disclosure: 4 early red-1s runs (07:59, about 1-4 s each) got past the slow hook without a slot (command started with `if`).

Probe `06-tail-probe/`:
- `tt.lua` (LUA_INIT): count hook gives instructions per tick. It also wraps `tostring` / `string.format` (calls per
  tick; 7.0 instr per wrapped call, measured, subtracted), gives KB allocated per tick (GC stopped inside the tick),
  samples the stack (TT_WALK) and records units (`p_units.lua` patch).
- `drive.sh`: 20-40 s CPU chunks under timeout 120.
- `fit4.py`: alignment + fits. `classify2.py`: spike classes. `units.py`: worst single call. `agree.py`: engine vs
  model spikes.

## Table 1: tick-cost measure (Q1)

| item | value |
|---|---|
| hook overhead (red-1s step CPU) | none 1.3 s; count only 1.0-1.4 s (noise); walk every 5th fire 1.7 s; walk every fire 4.2 s; C-call hook 15.8 s (11x) |
| hook inflation of counted instr | count only about +0.8% (8 instr per 1000, estimate); walk/5 +7-9%; unit run (count every 100) about +8%. Counts come from count-only runs. |
| alignment, engine tick = offline + | red-1s 17 (corr 0.87), green 13 (0.93), red-green 14 (0.93), blue bound 15 (0.85) |
| fit Minstr only, pooled 4 sheets, n=8373 | 22.9 ms/Minstr + 1.8; r^2 0.76; median abs err 3.0 ms; median rel err on engine >50 ms ticks 51% |
| **fit Minstr + Ktostring, pooled** | **ms = 20.28*Minstr + 1.58*Ktostring + 0.51; r^2 0.86; median abs err 1.3 ms; rel err on >50 ms ticks 18%** |
| same fit per sheet (a, b, r^2) | red-1s 42.1/1.69/0.91 (tick 1 skews a); green 22.0/1.57/0.94; red-green 21.5/1.45/0.91; blue 19.8/1.60/0.85 |
| + MB allocated | no gain (pooled coefficient 0.05 ms/MB, r^2 0.861 the same) |
| budget in "eq-instr" = instr + 78 x tostring calls | 50 ms = 2.44 M; 100 ms = 4.90 M; 16 ms = 0.76 M |
| engine spikes the model catches (>50 / >100 ms) | red-1s 2/2, 1/1; green 4/8, 1/1; red-green 13/26, 5/11; blue 112/128, 63/67 |
| engine-only spikes (model < 50) | green 4 (model median 43 ms), red-green 13 (median 11 ms), blue 16 (median 15 ms): engine/GC/host jitter, no Lua work to slice |

**Surprise 1: one `tostring` costs about 78 VM instructions in the engine (1.6 us).** Instructions alone mis-rank
string-key code. Example red-1s pack: about 100 ms per Minstr, against 15 for route/power. The hot users are
`cell_key` pack.lua:210 and `point_key` validate.lua:541 (`tostring(x)..":"..tostring(y)`). A charge model must count
them (or the keys must change to integers). Number-to-string done implicitly by `..` cannot be seen. The C-call hook
showed no added value beyond tostring.

## Table 2: spikes per sheet and class (Q2; model ms on every offline tick, class = stack-sample share)

"led" = spike ticks where the class holds the largest share (in brackets: of those, ticks over 100 ms). "excess" =
share of the summed (ms - 50) over all spikes.

| sheet | ticks | engine >50 / >100 | model >50 / >100 | median / p99 ms | worst non-spike tick (model / engine) | groups | pack legal | validate | power | stage copy + glue | other |
|---|---|---|---|---|---|---|---|---|---|---|---|
| red-1s | 180 | 2 / 1 | 3 / 1 | 5.1 / 53 | 49.0 / 49.8 | led 1 (1), 55% | led 2, 11% | - | - | 0 led, 29% | pack other 3% |
| green-1s | 535 | 8 / 1 | 5 / 1 | 6.5 / 50 | 49.7 / 49.5 | led 1 (1), 72% | led 4, 21% | - | - | 5% | - |
| red-green | 1602 | 26 / 11 | 23 / 6 | 7.0 / 63 | 49.0 / 48.4 | led 2 (2), 67% | led 8 (4), 20% | led 1, 0.2% | led 8, 4% | led 4, 5% | pack other 2% |
| blue (bound) | 6065 | 129 / 68 | 133 / 77 | 9.0 / 117 | 49.7 / 49.8 | led 6 (6), 32% | led 29 (17), 21% | **led 47 (40), 31%** | led 46 (9), 10% | led 3 (3), 5% | tidy publish 1 (1), serialize 1 (1) |

Route A* expansion and tidy trial search lead no spike on any of the 4 sheets: route expand is under 1% of spike
excess, and no single `search_step` call reached 1 ms. Their ticks stay under 50 ms with today's charge
(EXPANSION_OPS=7).

## Per class: loop, slice point, worst single unit (unit run, model ms; unit instr include about +8% hook)

| class | loop / charge site | worst single call that cannot be sliced today | finer slice seen |
|---|---|---|---|
| Groups regroup | groups.lua:2717-2738, 1 op per bucket (:2729) and per candidate (:2736); all buckets in one tick (tickets 17, 18) | `build_block` groups.lua:1360: blue 204 ms (9.8 M instr), green/red-green 102 ms, red-1s 50 ms | `append_inserters` :1068 82 ms blue, 101 ms green; `place_row` :2018 80 ms blue; one hand `candidate_inserter` :456 (call :1030) 30 ms blue, 46 ms red-green (base, before ticket 18 hoists) |
| Pack legal reject | pack.lua:771-777 layered_scan charges `cost` from layered_legal pack.lua:718 (reject = 1 op) | one origin `layered_legal`: blue 10.8 ms (4927 tostring), red-green 5.2 ms. Spikes are about 2000 rejects, not one unit | per origin is enough: charge by w*h cells + zones (pack.lua:722-724, :101) |
| Validate physical | validate.lua:3314-3320 phase `physical`: one machine per tick (spent = 2000 at :3326-3327) | **one machine `check_physical_transfers` validate.lua:2331: blue 205 ms (6.7 M instr, 43k tostring), 44 ticks with a call over 50 ms**; red-green 40 ms | per input/output entry inside the machine loop :2600-2762 (each scans all inserters :2641/:2693 + `connection_path` + `point_key` :541) |
| Validate one-shot passes | validate.lua:3299-3313 + spent=2000 at :3326-3327 | blue `check_beacons` :1071 115 ms, `check_transport_shapes` :1590 91 ms, `check_fluid_mix` :2979 51 ms | none today; each pass is one loop over all entities |
| Power candidate scan | power.lua:976-1030, `candidate_position` charged 4 ops (power.lua:340), then on a blocked spot it loops over all consumers (power.lua:1016-1018 `consumer_covered` :367 -> `rect_intersects` :57) | one spot is cheap; red-green ticks 568-574 are 51-81 ms from 2000 ops of such spots | charge `#work.consumers` per blocked spot |
| Power publish | power.lua:988 `publish_finish` one tick (cost = min(available, 2000)) | blue 154 ms (3.7 M instr, 50k tostring), red-green 59 ms | not sliced; split publish into parts |
| Stage-input copy | search.lua:343-347 `stage_input` -> search.lua:60 `copy(state.work.input)`, no op charged (run_stage search.lua:1405 charges 1 op only if the stage spent none) | blue 30.7 ms, red-1s 24 ms (1.2-1.5 M instr) per stage begin | do not slice it; stop copying the read-only input |
| Incumbent copy | search.lua:2441-2450 copy(candidate) + copy(validate.result) when a candidate is kept | blue tick 6063: 8.5 M instr glue, about 170 ms | share instead of copy |
| Tidy publish | route.lua:4136-4155 (own ticks); `result_for` route.lua:3471 -> pipe_runs.lua:135 | blue 132 ms (6.5 M instr) | - |
| Route expand / tidy trial | route.lua:5340-5343 and :4772-4773, 7 ops per `search_step` route.lua:3127 | under 1 ms per expansion; `trial_finish` :4797 12.5 ms blue; `append_normal_path` :2277 4 ms | no spike, no change needed |
| Plan | plan.lua:685-693 | inside tick 1 with Groups; red-1s plan share is small (Groups 2.46 of 3.98 M) | - |

Worst tick left if every spike class were sliced = worst non-spike tick = 48-50 ms on all 4 sheets, both model and
engine (Table 2). That is the 50 ms line by definition. Below 50 ms the tick costs fall off smoothly: median 5-9 ms,
p90 14-17 ms. To reach "worst tick ~= normal tick" you must also slice the single units in the table above that run
over 50 ms. On blue those are: physical transfers per machine 205, build_block 204, power publish 154, incumbent copy
about 170, result_for 132, check_beacons 115, check_transport_shapes 91, place_row 80 ms. Engine-only jitter is
about 4-16 spikes per sheet over 50 ms with no Lua work behind them (Table 1). Slicing cannot remove it.

## Surprises

1. Instruction count alone is not a tick-cost measure. tostring costs about 78 instr each in the engine.
   With tostring counted, r^2 = 0.86 and the error on 50 ms spikes is 18%.
2. Validate, not pack, leads blue's spikes: 47 ticks (40 over 100 ms). Each one is a single machine's
   `check_physical_transfers` (up to 205 ms). One machine per tick is already the slice; the unit itself is too big.
3. Deep copies are a hidden class with no op charge: `stage_input` (24-31 ms per stage begin, on every sheet) and the
   incumbent copy (about 170 ms on blue).
4. Route A* and tidy trials, the expected hot loops, cause no spikes on these 4 sheets at today's 7 ops per expansion.

## Ops-per-tick scan (2026-10-04 08:37-08:52 UTC, load 6.5-13.9, reason "round 56 ticket 06 ops per tick scan")

Same worktree and loop (`ckpt.lua --ops N`, RRC_GAME_TICK). Tracer `tt.lua` count every 1000 instr + tostring wrap +
`p_units.lua` units. Logs `06-tail-probe/logs/ops<N>-<sheet>.{tt,log}` (blue 2000 = `ops2000b-blue`, the rerun). Table
`scan.py`. Model ms = 20.28*Minstr + 1.58*Ktostring + 0.51. The unit wrappers add instructions: blue median +1.8%,
p90 +12.6% against the count-only run. "After slicing" drops every tick in which the spike-class units (Groups
make_candidates_once, validate checks, power publish_finish + candidate_position, stage_input, route result_for, pack
layered_legal) add up to >= 25 ms.

| sheet | ops | ticks | sha = 2000? | raw p50 / p90 / p99 / max ms | ticks >50 / >100 | after slicing: dropped ticks, p50 / p90 / p99 / max ms |
|---|---|---|---|---|---|---|
| red-1s | 2000 | 180 | 80095966 | 5.2 / 14.7 / 53 / 133 | 3 / 1 | 8; 4.7 / 11.5 / 38 / 39 |
| red-1s | 3000 | 119 | same | 8.2 / 23.4 / 80 / 143 | 7 / 1 | 8; 6.7 / 17.1 / 41 / 41 |
| red-1s | 4000 | 93 | same | 9.4 / 34.3 / 155 / 155 | 5 / 2 | 8; 9.0 / 23.1 / 48 / 48 |
| red-1s | 6000 | 64 | same | 12.9 / 52.2 / 176 / 176 | 8 / 3 | 7; 11.9 / 33.1 / 52 / 52 |
| green-1s | 2000 | 535 | 6b65a1d1 | 6.7 / 13.8 / 50 / 437 | 5 / 1 | 10; 6.5 / 12.0 / 23 / 45 |
| green-1s | 3000 | 356 | same | 9.5 / 20.1 / 91 / 450 | 5 / 3 | 20; 8.9 / 16.5 / 29 / 50 |
| green-1s | 4000 | 273 | same | 12.2 / 27.0 / 131 / 460 | 5 / 3 | 23; 11.3 / 21.0 / 48 / 52 |
| green-1s | 6000 | 184 | same | 18.6 / 42.1 / 211 / 483 | 11 / 4 | 19; 16.5 / 31.8 / 56 / 60 |
| red-green | 2000 | 1602 | c01afb5a | 7.8 / 16.7 / 64 / 867 | 23 / 6 | 97; 7.8 / 13.8 / 24 / 84 |
| red-green | 3000 | 1068 | same | 11.5 / 24.9 / 95 / 877 | 42 / 9 | 78; 11.5 / 19.7 / 29 / 83 |
| red-green | 4000 | 809 | same | 15.2 / 33.3 / 117 / 881 | 50 / 11 | 69; 15.1 / 26.2 / 36 / 92 |
| red-green | 6000 | 542 | same | 22.6 / 51.8 / 186 / 889 | 56 / 16 | 56; 22.4 / 38.1 / 52 / 105 |
| blue bound | 2000 | 6065 | c7d1994f | 9.0 / 15.7 / 117 / 822 | 135 / 77 | 245; 7.9 / 14.4 / 21 / 160 |
| blue bound | 3000 | 4039 | same | 13.3 / 23.4 / 154 / 819 | 114 / 67 | 193; 11.5 / 21.1 / 28 / 160 |
| blue bound | 4000 | 3041 | same | 17.5 / 31.0 / 225 / 817 | 120 / 77 | 182; 15.1 / 27.6 / 37 / 160 |
| blue bound | 6000 | 2032 | same | 26.0 / 47.4 / 353 / 838 | 170 / 65 | 151; 22.4 / 40.5 / 54 / 160 |

- Bytes are the same at every ops value on all 4 sheets (16/16 ok=true). Ticks scale as 1/ops: 2000->6000 = 0.33-0.36x.
  Blue ops_used 12.10-12.14 M at every value.
- p50 and p90 grow about linearly with ops (2000->6000: p50 x2.5-2.9). Under 2000 ops the normal tick is 5-9 ms
  model. At 6000 ops it is 13-26 ms, and p90 is 33-52 ms after slicing.
- The max after slicing at a high ops value: red-1s 52, green 60, red-green 105, blue 160 ms. Blue's 160 ms (tick
  6063) and 108 ms (6064) are the incumbent copy (search.lua:2441-2450) and serialize. Neither is wrapped, and
  neither depends on ops. Leave those 2 out and blue's worst is 33 ms at 2000 and 66 ms at 6000.
  Red-green's 84-105 ms ticks are route-start ticks: stage_input 22 ms + route input/copy glue (search.lua:1197
  make_route_input) that is not wrapped.
- Reading: at 3000 ops the tick count drops a third, and the sliced tail stays under 50 ms (p99 28-41 ms) on all
  4 sheets. That holds only if the unwrapped copies (incumbent copy, serialize, route-input glue) are sliced or cut
  too. At 4000, p99 after slicing is 36-48 ms. At 6000, p99 reaches 52-56 ms and max 52-105 ms (blue 66 ms) beyond
  the unwrapped copies.

## Per phase at 2000 / 4000 / 6000 ops (no new runs; ops-scan logs, `06-tail-probe/phase.py`, 2026-10-04 ~09:00 UTC)

Phase = Search phase at tick start (hands counted with route, serialize = publish). Times are model ms after slicing
(the same rule: ticks with >= 25 ms of spike-class units are dropped). Columns give p50 / p90 / p99 / max.

| sheet | phase share of ticks: tidy / power / validate / pack / route | route @2000 | route @4000 | route @6000 | tidy @4000 | pack @4000 |
|---|---|---|---|---|---|---|
| red-1s | 18 / 29 / 17 / 16 / 19% | 2.6 / 4.5 / 38 / 38 | 4.8 / 10.6 / 48 / 48 | 6.9 / 20.3 / 52 / 52 | 12 / 17 / 45 / 45 | 23 / 44 / 44 / 44 |
| green-1s | 41 / 26 / 14 / 9 / 10% | 2.7 / 4.5 / 45 / 45 | 4.8 / 19.5 / 53 / 53 | 6.9 / 36 / 60 / 60 | 16 / 21 / 23 / 49 | 19 / 29 / 48 / 48 |
| red-green | 31 / 29 / 14 / 12 / 13% | 2.7 / 15.3 / 19 / 84 | 4.9 / 31 / 37 / 92 | 7.0 / 44 / 105 / 105 | 21 / 28 / 31 / 31 | 18 / 32 / 90 / 90 |
| blue bound | 27 / 19 / 19 / 18 / 16% | 2.7 / 15.3 / 21 / 33 | 4.9 / 30 / 40 / 46 | 7.1 / 45 / 56 / 66 | 24 / 31 / 37 / 42 | 18 / 21 / 34 / 34 |

Plan/groups and publish are 1 tick each (0-1.6%).

- **Route cannot run at 8000-12000 ops and stay <= 50 ms.** Route p90 grows linearly at about 7.5 ms per 1000 ops
  (red-green and blue: 15 / 30 / 45 ms at 2000 / 4000 / 6000). Linear extrapolation (not measured): p90 about 60 ms
  at 8000 and about 90 ms at 12000. Blue p99 slope 4000->6000 is 7.9 ms per 1000 ops, so p99 is about 72 ms at 8000
  and about 103 ms at 12000. 50 ms on the route p90 is reached near 6500 ops (blue, red-green).
- One A* step is under 1 ms, but 7 ops per expansion x 2000 ops = about 285 expansions per tick, at about 0.05 ms
  each. Route leads no spike only because 2000 ops keep it at about 15 ms p90.
- Route p99/max at 2000-4000 on red-1s, green and red-green (38-92 ms) is the route-start tick: stage_input 22 ms
  plus the route-input copy (search.lua:1197). That cost does not depend on ops. Fixing the copies is needed for
  route <= 50 ms at any ops.
- The other phases at 4000 ops: tidy p99 23-45 ms, pack p99 34-48 ms (red-green 90 = route-start glue tick),
  power p99 <= 30 ms, validate p99 <= 52 ms (red-green 52 = validate end), blue validate max 160 (incumbent copy).
- Magenta / stack1: the route share of ticks here is 10-19%, and route is 7-13% of CPU on these sheets. That is far
  from magenta's 69% and stack1's 83% route CPU (ticket 02). The per-tick route cost depends on expansion cost (map
  size, layered grid 6) and cannot be carried over from these 4 sheets. Only the tick count can be estimated:
  ticks ~= ops_used / ops per tick, because bytes and ops_used do not change with ops (blue 12.10-12.14 M at every
  value). The route ms per 1000 ops on magenta needs its own run.

## Magenta route window, ops 2000 vs 4000 (resume only, no slot; 2026-10-04 09:13-09:15 UTC, load 29)

Source: bound snapshot `20-probe/c.b-magenta-science-10s.0.lua.gz` (f3d2268, offline tick 2843, phase route), resumed
with `ckpt.lua resume --ops N --at-tick 4343` and the same tracer, in 2 parallel processes. Logs:
`06-tail-probe/logs/mag-win{2000,4000}.{tt,log}`.
- ops 2000 ran its 1500 ticks.
- ops 4000 hit timeout 120 at 1150 ticks (load 29). That covers about the same work as 2300 ticks at 2000 ops.
- Every window tick was a route tick, and none had spike-class work >= 25 ms, so raw = after slicing.

Stack1: no checkpoint in ckpt form anywhere. `tests/fixtures/route_snaps/stack1_*` are route-stage fixtures and
ckpt.lua cannot resume them. Not measured.

| magenta route ticks | ticks | p50 / p90 / p99 / max model ms | ticks > 50 ms |
|---|---|---|---|
| ops 2000 | 1500 | 13.4 / 17.4 / 22.6 / 30 | 0 |
| ops 4000 | 1150 | 26.5 / 34.4 / 40.8 / 44 | 0 |

- Route ms scale almost exactly with ops (x1.98 p50, x1.80 p99): about 9.1 ms p99 per 1000 ops. Route p99 hits 50 ms
  near 4900-5000 ops (linear, not measured). Per op, magenta route ticks cost about 0.9x blue's 2000-ops p90 and
  1.1x its p99. At 2000 ops magenta route p50 is 13 ms against blue's 2.7: magenta route ticks are full expansion
  ticks; on blue most route ticks are short.
- So 4000 ops keeps magenta route ticks <= 50 ms in this window (max 44). This holds for this window only (ticks
  2844-4343 of 34565): route-start and restart ticks (stage_input + route-input copy) and the later layered grid 6
  route are not in it.
