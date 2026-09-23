# 174 power: pole placement in far fewer ops, same poles

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-174`, branch
`lane/174`, base tag `round-24-base`, merge target `int/r23b`. Host `legalcopilot-dev`.

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

`logic/bp/power.lua`, `Power.step` phase machine. Round 23 indexed supply-relevant positions
(`advance_candidate_index`, `work.positions_by_spec`). A shortcut that kept ONE representative position per
coverage set cut the fixture from 413277 to 8951 ops but broke `tests/test_search.lua` (48 -> 28 of 54): it
changes which poles are chosen. With every supply-relevant position kept, the fixture needs 208630 ops
(`tests/test_power_ops.lua` PO1). Round 23's baseline on the player's sheet: 830451 ops per layout, of which
`candidate_occupied` 688176 and `candidate_coverage` 96254.

## What to build

1. **Profile** ops per phase on the player's first layout at `round-24-base` (temporary counters); put the
   table in your commit message.
2. **Cut ops without changing the chosen poles and wires**: `candidate_occupied` from a cell set instead of
   rect walks; coverage from a consumer-rect index; skip positions dominated by an equal-coverage position
   ONLY where the choice is provably the same (same covers AND same wire neighbours). Target at most
   100 `power.step` calls of 2000 ops per layout on the player's sheet, and one op 5-10 microseconds.
3. `tests/test_power_ops.lua`: **PO3** (red at `round-24-base`) the fixture needs at most a named number of
   ops you measure, at least 4x below 208630; **PO4** on three fixtures the poles and wires are identical to
   `round-24-base`'s output (store the expected poles in the test). PO1/PO2 stay green.
   `tests/test_search.lua` must stay at 48 passed or more.

## Traps

- **Determinism.** Same input, same layout (`tests/test_route_budget.lua`, `coord_key`). Any budget size
  (1 op or 10^9 ops per call) gives the same answer.
- **Measure with the probe** (`CAP=60 sh tools/speed_probe.sh`, about 60 s). Never run two long commands
  at the same time — the host wedged on 2026-09-23 when two ran together.
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/power.lua`, `tests/test_power_ops.lua`

## Commit, THEN check

Commit on `lane/174` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "power-regress", "command": "git diff --name-only round-24-base HEAD | grep -v '^docs/tasks/174' | grep -Ev '^(logic/bp/power\\.lua|tests/test_power_ops\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_power_ops.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo power-regress-ok", "expect_exit": 0, "expect_regex": "power-regress-ok", "timeout_s": 1800}
{"name": "power-speed", "command": "CAP=120 sh tools/speed_probe.sh > /tmp/rrc174-speed.txt; cat /tmp/rrc174-speed.txt; sh tools/speed_gate.sh ratio power.step power.begin 100 < /tmp/rrc174-speed.txt && sh tools/speed_gate.sh worst power.step 0.03 < /tmp/rrc174-speed.txt && echo power-speed-ok", "expect_exit": 0, "expect_regex": "power-speed-ok", "timeout_s": 900}
```

# bound: 2400s
