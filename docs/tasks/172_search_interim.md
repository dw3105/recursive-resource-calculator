# 172 search: stop by layouts, publish each better layout as state.interim, groups.step yields

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-172`, branch
`lane/172`, base tag `round-24-base`, merge target `int/r23b`. Host `legalcopilot-dev`.

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

`logic/bp/search.lua`. Round 23 added a stop rule: after the first incumbent, stop after K=2 validated
non-improving layouts OR after a 2,000,000-op ceiling. The ceiling is counted in ops, and op size changes
per module, so how many layouts it validates depends on op size (1 layout at 256 ops per pack origin, 3 at 16);
the player's sheet reached 242 (the player's accepted v5, `tests/fixtures/blueprints/round22_v5.txt`).
`logic/bp/groups.lua`: `Groups.step` does 0.649 s in one call.

## What to build

1. **Stop by layouts, not ops.** Remove the op ceiling after the first incumbent; stop after `K`
   consecutive validated non-improving layouts (named constant) and after `MAX_LAYOUTS` validated layouts
   in total (named constant). Choose both from measurement so the player's sheet reaches 242 entities or
   fewer. Record `stop` in the result's `search` block.
2. **Interim contract (exact field names — another part of the mod reads them).** Every time the incumbent
   improves, set
   `state.interim = {sequence = <1, 2, 3...>, result = <the serializer's output table for that incumbent,
   the same shape as state.result>, entities = <#result.entities>}`. Build it from the incumbent exactly as
   the final serialization does; do not change `state.result` or the final `done/ok` behaviour.
3. **`Groups.step` yields**: its expensive loop spends ops and resumes from a cursor; worst call <= 30 ms;
   identical candidates.
4. `tests/test_search_stop.lua`: **SS3** (red at `round-24-base`) the stop rule never uses an op ceiling
   after the first incumbent; **SS4** `state.interim.sequence` rises by one per improvement and
   `state.interim.result` equals the serialized incumbent; **SS5** `Groups` worst call bounded.

## Traps

- **Determinism.** Same input, same layout (`tests/test_route_budget.lua`, `coord_key`). Any budget size
  (1 op or 10^9 ops per call) gives the same answer.
- **Measure with the probe** (`CAP=60 sh tools/speed_probe.sh`, about 60 s). Never run two long commands
  at the same time — the host wedged on 2026-09-23 when two ran together.
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/search.lua`, `logic/bp/groups.lua`, `tests/test_search_stop.lua`

## Commit, THEN check

Commit on `lane/172` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "search-regress", "command": "git diff --name-only round-24-base HEAD | grep -v '^docs/tasks/172' | grep -Ev '^(logic/bp/search\\\\.lua|logic/bp/groups\\\\.lua|tests/test_search_stop\\\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_search_stop.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo search-regress-ok", "expect_exit": 0, "expect_regex": "search-regress-ok", "timeout_s": 1800}
{"name": "search-speed", "command": "CAP=600 sh tools/speed_probe.sh > /tmp/rrc172-speed.txt; cat /tmp/rrc172-speed.txt; sh tools/speed_gate.sh end 600 242 < /tmp/rrc172-speed.txt && sh tools/speed_gate.sh first 7000 < /tmp/rrc172-speed.txt && sh tools/speed_gate.sh worst groups.step 0.03 < /tmp/rrc172-speed.txt && echo search-speed-ok", "expect_exit": 0, "expect_regex": "search-speed-ok", "timeout_s": 1200}
```

# bound: 2400s
