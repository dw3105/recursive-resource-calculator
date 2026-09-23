# 173 deliver: the first layout reaches the player fast, better ones are offered

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-173`, branch
`lane/173`, base tag `round-24-base`, merge target `int/r23b`. Host `legalcopilot-dev`.

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

- `logic/bp/generation.lua`: `Generation.start` queues a job; the job's `step(job, budget)` drives
  `Search.step` on `job.state`; `publish(job)` runs once when the search is done: it encodes the result,
  sets `handle.state = "success"` and, if `handle.deliver`, calls `BlueprintDelivery.deliver(player_index,
  blueprint)` which puts the blueprint in the player's empty cursor (`gui/blueprint_delivery.lua`).
- `gui/progress_panel.lua` shows generation progress.

## The interim contract (the search side fills it; you read it)

The search state carries `state.interim = {sequence = n, result = <blueprint table, same shape as the final
result>, entities = <count>}`, replaced by a new table with `sequence = n + 1` each time the search finds a
better layout. It may be absent (no valid layout yet). Read it from the search state inside the job; build
your tests with a fake search state that sets it, so you do not depend on search timing.

## What to build

1. **First layout, fast.** When the job's search state first shows `state.interim`, the handle gets
   `handle.phase = "improving"`, `handle.interim = {sequence, entities, blueprint_string}` (encode it like
   `publish` does) and, if `handle.deliver`, the blueprint is delivered to the cursor right away with the
   existing `BlueprintDelivery.deliver`. The handle stays `pending`; the search keeps running.
2. **Better ones, offered.** A later interim with a higher sequence updates `handle.interim` and the
   progress panel shows "Better layout found: N entities" with a button that delivers it (never replace
   what is in the player's cursor without a click). New locale keys in `locale/en/locale.cfg`.
3. **Final.** `publish` at the end: if the final result has the same entity count and sequence as the
   interim already delivered, do not deliver again; otherwise offer it the same way as step 2. The final
   `handle.state = "success"` behaviour, `Generation.status` fields and the capture/export path stay as
   today.
4. `tests/test_generation_interim.lua` (new), each row **red at `round-24-base`**, using the repo's test
   harness and factorio mocks as the other `tests/test_generation_*.lua` files do:
   - **GI1** a fake search that exposes interim 1 while not done: the player's cursor receives the
     blueprint and the handle is still `pending` with `phase = "improving"`.
   - **GI2** interim 2 arrives: the cursor is NOT touched, the panel offer exists, clicking it delivers.
   - **GI3** the final result equal to the delivered interim delivers nothing more.

## Traps

- **Determinism.** Same input, same layout (`tests/test_route_budget.lua`, `coord_key`). Any budget size
  (1 op or 10^9 ops per call) gives the same answer.
- **Measure with the probe** (`CAP=60 sh tools/speed_probe.sh`, about 60 s). Never run two long commands
  at the same time — the host wedged on 2026-09-23 when two ran together.
- **Never touch** `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except
  this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/generation.lua`, `gui/blueprint_delivery.lua`, `gui/progress_panel.lua`, `locale/en/locale.cfg`, `tests/test_generation_interim.lua`

## Commit, THEN check

Commit on `lane/173` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "deliver-regress", "command": "git diff --name-only round-24-base HEAD | grep -v '^docs/tasks/173' | grep -Ev '^(logic/bp/generation\\\\.lua|gui/blueprint_delivery\\\\.lua|gui/progress_panel\\\\.lua|locale/en/locale\\\\.cfg|tests/test_generation_interim\\\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in tests/test_generation_*.lua tests/test_blueprint_pipeline.lua tests/test_jobs.lua; do $l $t 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done; done && echo deliver-regress-ok", "expect_exit": 0, "expect_regex": "deliver-regress-ok", "timeout_s": 1800}
{"name": "deliver-suite", "command": "sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo deliver-suite-ok", "expect_exit": 0, "expect_regex": "deliver-suite-ok", "timeout_s": 1200}
```

# bound: 2400s
