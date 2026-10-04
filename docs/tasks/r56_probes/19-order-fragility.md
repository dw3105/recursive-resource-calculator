# 19 Why does magenta layered grid 6 route only on the plain restart order (2026-10-03/04, legalcopilot-dev, main f3d2268)

Code = origin/main f3d2268 in `~/wt-rrc-speed02` + ticket 01 `RRC_GAME_TICK=1` ckpt patch, game-rate loop (2000 ops/tick),
lever B (strict_ends from start) under every row. Ticks and sha op-based. Load 11-20 (other sessions). Wave file
`~/.cache/rrc/r56-speed19` (r56-speed02 ckpt-save budget used by ticket 14).

Probe files `19-probe/` (all in-memory, chained):
- `p_detail.lua` (local-retry sites P19-LR + every validate error with detail), `p_commits.lua` (P19-C per committed path in
  box `P19_BOX` or flow `P19_FLOW`; `P19_QUIET=1` off), `dump.lua` / `sink.lua` / `deadend.lua` (snapshot readers).
- `p_fix.lua` FIX1, `p_fix2.lua` FIX1+FIX2, `p_fix3.lua` FIX3 (dropped), `p_fix3b.lua` FIX1+FIX2+FIX3b,
  `p_watch.lua` / `p_watch2.lua` (tidy dead-end watch per step / per cleanup sub-step), `p_fluidwhy.lua`.
- `drive.sh` = ticket 14 driver, wave r56-speed19, default patch p_fix2. Logs `logs_*`, `ins_*.log`, `am2_*.log`.

## Answer

**"Order fragility" is not one cause. A changed demand order walks route + tidy into latent validity defects that the
plain order happens to miss.** c's rejected drawn candidates each hit a different defect. Three found, file:line, each
proven by an in-memory fix:

| # | defect | site | seen | fix probe |
|---|---|---|---|---|
| D1 | splitter branch ENDS on a row-port sink whose travel_dir is not the trunk heading: north splitter at (32-33,23) feeds row head (33,23) that runs south; row unfed | search body_jump route.lua:3287 (no row-port check); commit guard `row_head_reuse_guard` :1871-1876 exempts `segment.splitter` | drawn ins-10s c: 1 NO_SOURCE + 4 ROUTE_DISCONTINUOUS + 19 TRANSPORT_UNUSED, iron-plate demand 5 (sink row_port travel 8 rear_curve) | FIX1: no body_jump when target is a row-port sink and `leaving.direction ~= sink.travel_dir` |
| D2 | pipe dive STARTS on another machine's fluid port tile: pipe-to-ground at (4,35) faces away from foundry casting-iron:2 (7.5,36.5) | guard exists at route.lua:3388-3397 but only under `work.strict_ptg` (last-resort phase; comment: "on first routing it moved player-magenta-science-10s") | drawn ins-10s c: BP_V_FLUID_DISCONNECTED molten-iron | FIX2: guard on in every phase |
| D3 | tidy keeps a trial whose old splitter keeps an output into an empty tile; cleanup `untangle_splitter_chains` (route.lua:4334, called :4391) turns chained splitters into belts, leaving belt (34,3) ending on nothing; `prune_dead_route_segments` removes only UNFED segments | keep test route.lua:5185 (and :4800/:4803) = all_bindings_reach_sinks + fewer entities; prune :4390 | drawn am2 c: BP_V_TRANSPORT_UNUSED electronic-circuit (34,3); watch: dead-end appears at untangle step, tick 717 | FIX3 (keep-check) too strict, dropped; FIX3b: after untangle, trim plain flow belts ending on no segment and no endpoint |

## Tables

Drawn (sugiyama):

| sheet | drawn B (t14) | drawn c (t14) | c + FIX1+2 | c + FIX1+2+3b | B + FIX1+2+3 | B + FIX1+2+3b |
|---|---|---|---|---|---|---|
| inserter-10s | 550 / 3415714b | 1645 drawn_off | **536 / b3091145** valid | - | 550 same | 550 same |
| am2-chain-repaired | 865 / ccce425b | 1506 drawn_off | 1506 (D3 left) | **836 / a7a72f32** valid (replay from tidy snap) | 865 same | 865 same |
| inserter-10s-bulk | 785 / cd09d6b3 | same | - | - | 788 / 7e621e09 | 784 / cd09d6b3 (same sha) |
| red-green-science-10s | 2162 / 079b9b90 | same | - | - | 2175 / 926a6edb | 2162 same |
| inserter-10s-stack1 | 3773 / 1616d34c | 2385 / 748fca6a | - | - | 3078 / 124f1c16 | 3773 same |

FIX3 (keep-check) changes 3 B rows (two +3/+13 ticks): refuses trials that cleanup would make valid. FIX3b: 0 trims, 5/5
drawn B byte-identical.

Layered c + FIX1+2 (`logs_lay_cfix2`): stack1 1654 / 3caa20a2, red-green 1484 / 4f35d4de, inserter-10s 1105 / 00cee697,
ins-bulk 516 / 742baca3, am2 674 / ad3824c5 = ticket 14 c column byte for byte.

Magenta layered (the gate, B = 17426 / 3af0c7f4):

| variant | grid 6 route end | restarts / expansions | grid 6 candidate | total |
|---|---|---|---|---|
| B (t13) | 12087 | 33 / 2.88M | valid | 17426 |
| c (t14) | 12232 | 33 | rejected after power -> MaxRects | 29246 |
| c + FIX1+2 (`logs_mag_cfix2`, done 23:41 UTC) | 14977 | 36 / 3.71M (+29%) | **valid, stays layered** | **19863 / 2e2f8646 / 2263 ent (+14%)** |
| B + FIX1+2+3b (`logs_mag_Bfix3b`, stopped 00:12 UTC at tick ~54k) | 12051 | 33 / 2.87M | **REJ BP_V_TRANSPORT_UNUSED n=3** (0 trims) -> MaxRects, then LANE_MIX, BELT_NO_SOURCE | > 53796, layered lost |

## Verdict

1. c's magenta loss and both drawn losses are validity defects, not order per se. FIX1+FIX2 make c keep magenta layered,
   but c's own route search costs +29% expansions there: **19863 > 17426, c fails the gate even with fixes.**
2. The fixes are not neutral on magenta: under plain B, FIX1/FIX2 move grid 6 paths and land on a 4th invalid layout
   (3 unused belts, not a plain dead end). Same class as D1-D3; next defect not traced (would be whack-a-mole).
3. **No cheap order-independent fix -> restart policy closed for round 56** (ship lever B alone, ticket 14 answer 5).
4. D1-D3 are real latent validity bugs (any order change, layout change or new lever can walk into them). Shipping
   them needs RC-10 gentle form (fire only where build fails today) and the magenta row; own question, not speed.
5. Tests: no test covers `strict_ptg` (grep tests/ 2026-10-04); row-port tests (9 files) have no splitter-branch-onto-
   row-head case; `test_route_prune_splitter` / `test_route_dead_pair` have no chained-splitter dead output.

## Follow-up 2026-10-04 00:14-00:30 UTC (legalcopilot-dev, load 13-20)

- **D4 named** (`logs_mag_Bfix3b_val`, P13_VALEXIT at first validate reject): magenta B + FIX1+2+3b grid 6 rejects
  3 BP_V_TRANSPORT_UNUSED, all `fluid/light-oil`: pipe-to-ground pair (47,44) facing W + (57,44) facing E, pipe (58,44).
  A fed pipe run reaching no machine: pipe twin of D3 (prune :4390 keeps fed segments; FIX3b trims belts only).
- **Layered B + FIX1+2+3b, 13 non-magenta sheets** (`logs_lay_Bfix3b`, 0 trims): 12/13 byte-identical to ticket 13/14 B
  (am2 681 ad3824c5 ... red-science-1s 180 80095966). **blue-science-10s 39515 / 2c82cb7e vs B 5309 / d744abca (7.4x)**:
  grid 6 candidate rejected 18 BP_V_LANE_MIX (advanced-circuit input hands, y=3) + 18 ROUTE_DISCONTINUOUS + 68
  TRANSPORT_UNUSED, then fallback. So FIX1/FIX2 break blue and magenta under plain B: not shippable as-is.
- **Variant g** (from ticket 14 `logs_g`, no rerun): grid 6 route 34 restarts, fatal BP_R_CAPACITY at tick 14253; last
  restarts FLUID_MIX water key 44, FLUID_MIX molten-copper key 36, NO_PATH iron-stick key 49; final demand not logged.
  Not traced further: B spends 5339 ticks after route (12087 -> 17426), so g ends >= ~19600 even if its route succeeded:
  g cannot meet 17426.
- lane_sim / game lab / parity (ticket 05) not run: they gate a byte-changing LANE at integration; this ticket ships none.
