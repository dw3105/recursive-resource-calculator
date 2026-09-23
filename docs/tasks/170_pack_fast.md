# 170 pack: one op costs microseconds and a layout packs in half a second

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-170`, branch
`lane/170`, base tag `round-24-base`, merge target `int/r23b`. Host `legalcopilot-dev`.

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

`logic/bp/pack.lua`. Round 23 made `Pack.step` resumable: one op per origin tried, cells indexed. But
about 4.9 s CPU per layout remains (19.45 s over 4 pack.begin) and the worst call is 0.102 s.

## What to build

1. **Profile** one `Pack.begin` + steps on the player's first candidate (temporary `os.clock` counters,
   not committed): time in `scan_region`, `choose_port_slots`, `cell_is_free`, `better`, region
   splitting. Put the table in your commit message.
2. **Cut the work** to at most 0.5 s CPU per layout: prune origins that cannot beat `state.cursor.best`
   (the BSSF score depends only on region and size, so a region whose best possible score loses needs no
   origin scan), stop the pinned-port origin sweep at the first origin that fits when later origins cannot
   score better, and cache slot options per (block, direction). The chosen placements must be identical.
3. **Calibrate the op**: charge ops in proportion to work (for example one op per ~10 origins or per
   `choose_port_slots` call), so a 2000-op call does 10-20 ms of work — never over 30 ms.
4. Extend `tests/test_pack_budget.lua`: **PB3** (red at `round-24-base`) packing the player-shaped fixture
   needs at most a named number of ops you measure; PB1/PB2 stay green.

## Traps

- **Determinism.** Same input, same layout (`tests/test_route_budget.lua`, `coord_key`). Any budget size
  (1 op or 10^9 ops per call) gives the same answer.
- **Measure with the probe** (`CAP=60 sh tools/speed_probe.sh`, about 60 s). Never run two long commands
  at the same time — the host wedged on 2026-09-23 when two ran together.
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/pack.lua`, `tests/test_pack_budget.lua`

## Commit, THEN check

Commit on `lane/170` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "pack-regress", "command": "git diff --name-only round-24-base HEAD | grep -v '^docs/tasks/170' | grep -Ev '^(logic/bp/pack\\\\.lua|tests/test_pack_budget\\\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_pack_budget.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo pack-regress-ok", "expect_exit": 0, "expect_regex": "pack-regress-ok", "timeout_s": 1800}
{"name": "pack-speed", "command": "CAP=120 sh tools/speed_probe.sh > /tmp/rrc170-speed.txt; cat /tmp/rrc170-speed.txt; sh tools/speed_gate.sh cpu_per pack.step pack.begin 0.5 < /tmp/rrc170-speed.txt && sh tools/speed_gate.sh worst pack.step 0.03 < /tmp/rrc170-speed.txt && sh tools/speed_gate.sh ratio pack.step pack.begin 300 < /tmp/rrc170-speed.txt && echo pack-speed-ok", "expect_exit": 0, "expect_regex": "pack-speed-ok", "timeout_s": 900}
```

# bound: 2400s
