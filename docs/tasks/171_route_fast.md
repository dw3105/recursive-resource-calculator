# 171 route: a layout routes in one second

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-171`, branch
`lane/171`, base tag `round-24-base`, merge target `int/r23b`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-24-base`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Commit early: after your first working change, commit, then keep improving and commit again.
Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything else,
then say which item and why.

## Explain very simply

The player clicked "generate" in Factorio 2.0.77 on 2026-09-23: 10+ minutes, 3 UPS. The game advances a
blueprint search once per tick with 2000 ops (`Jobs.OPS_PER_TICK`, `logic/jobs.lua`). The player chose:
**show the first valid layout fast, then keep improving and offer better ones.**

Round 23 made single ticks short. What is left, measured with `CAP=600 sh tools/speed_probe.sh` at
`round-24-base` on legalcopilot-dev 2026-09-23 (3 layouts validated; pack op already
calibrated to 16 ops per port origin, ~8 microseconds per op):

```
SPEED END ticks=1355 cpu=33.73 worst_tick=1.284 done=true ok=true entities=242
MOD groups.begin calls=2 cpu=0.00 worst=0.000
MOD groups.step calls=2 cpu=1.38 worst=0.723
MOD pack.begin calls=4 cpu=0.04 worst=0.017
MOD pack.step calls=1265 cpu=19.45 worst=0.102
MOD plan.begin calls=1 cpu=0.00 worst=0.000
MOD plan.step calls=2 cpu=0.00 worst=0.000
MOD power.begin calls=3 cpu=0.01 worst=0.003
MOD power.step calls=75 cpu=0.43 worst=0.013
MOD route.begin calls=3 cpu=3.10 worst=1.094
MOD route.step calls=21 cpu=6.88 worst=0.916
MOD serialize.begin calls=1 cpu=0.06 worst=0.058
MOD serialize.step calls=1 cpu=0.00 worst=0.002
MOD validate.begin calls=3 cpu=0.03 worst=0.009
MOD validate.step calls=4 cpu=0.82 worst=0.291
```

Two numbers matter in game: **ticks** (the game waits at least ticks/60 seconds) and **CPU**. A tick that
does only 1 ms of work wastes the frame; a tick over ~20 ms drops UPS. The rule: **one op costs about
5-10 microseconds**, so 2000 ops are 10-20 ms of work.

`tools/speed_probe.sh` replays the player's sheet exactly as the game does and prints `SPEED`, `FIRST`
(ticks until `Search` exposes its first valid layout as `state.interim`) and `MOD` lines.
`tools/speed_gate.sh` turns them into `speed-gate-ok` / `speed-gate-FAIL` (read its header for modes).

## Where the code is

`logic/bp/route.lua`. Round 23 made route resumable (`Route.begin` cheap, improve pass across calls), but
one layout costs about 1-2 s CPU and `route.begin` still does 1.094 s in one call. The demand searches (`begin_search`,
`search_step`) and the post-route re-route pass (`improve_routes`: for every binding, lift, re-search up to
200000 steps, keep only if `route_weight` falls; plus one re-search per hand-slide option) dominate.

## What to build

1. **Profile** one layout (temporary counters): CPU and `search_step` count in first routing vs the
   re-route pass, per binding. Put the table in your commit message.
2. **Cut the work** to at most 1.0 s CPU per layout. Ideas, measure each: skip a re-route whose lifted
   path cannot shrink (a lifted path of length L can only be kept if the new search finds cost < L, so
   bound the re-search by that cost and abandon early); cap re-search expansions per binding by a small
   multiple of the lifted length; skip hand-slide options whose new port tile is farther (Manhattan) from
   the path's other end than the old one; reuse per-demand data instead of rebuilding. A layout may lose a
   little quality but the player's sheet must still end at most 246 entities with the probe's full run.
3. **Calibrate the op**: one op ≈ 5-10 µs, a 2000-op call 10-20 ms, never over 30 ms.
4. Extend `tests/test_route_ticks.lua`: **RT4** (red at `round-24-base`) the improve pass on a fixture
   whose paths are already shortest spends at most a named number of `search_step`s you measure.
   `tests/test_route_hand_slide.lua`, `tests/test_route_improve.lua` stay green.

## Traps

- **Determinism.** Same input, same layout (`tests/test_route_budget.lua`, `coord_key`). Any budget size
  (1 op or 10^9 ops per call) gives the same answer.
- **Measure with the probe** (`CAP=60 sh tools/speed_probe.sh`, about 60 s). Never run two long commands
  at the same time — the host wedged on 2026-09-23 when two ran together.
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route_ticks.lua`

## Commit, THEN check

Commit on `lane/171` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "route-regress", "command": "git diff --name-only round-24-base HEAD | grep -v '^docs/tasks/171' | grep -Ev '^(logic/bp/route\\\\.lua|tests/test_route_ticks\\\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_route_ticks test_route_hand_slide test_route_improve test_route_bury; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo route-regress-ok", "expect_exit": 0, "expect_regex": "route-regress-ok", "timeout_s": 1800}
{"name": "route-speed", "command": "CAP=300 sh tools/speed_probe.sh > /tmp/rrc171-speed.txt; cat /tmp/rrc171-speed.txt; sh tools/speed_gate.sh cpu_per route.step route.begin 1.0 < /tmp/rrc171-speed.txt && sh tools/speed_gate.sh worst route.step 0.03 < /tmp/rrc171-speed.txt && sh tools/speed_gate.sh end 300 246 < /tmp/rrc171-speed.txt && echo route-speed-ok", "expect_exit": 0, "expect_regex": "route-speed-ok", "timeout_s": 900}
```

# bound: 2400s
