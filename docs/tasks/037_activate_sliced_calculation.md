# 037 — Compute runs in slices, and every older case learns to tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-037`, branch `lane/037`, base = `feat/round-8-blueprints`, tag `wave-4-green` (resolve it with `git rev-parse wave-4-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

The pipeline, the progress panel and the cancel path are all built, merged and green. Nothing in the shipped code
loads them, so a player still gets the old blocking solve, and the bar and Cancel never appear. This lane connects
them and repairs every case that assumed the report exists in the same tick.

## What is true

**PRESERVE:**
- You own exactly these files: `control.lua`, `gui/sheet.lua`, `logic/calc_pipeline.lua`, `tests/test_calc_pipeline.lua`, `tests/test_input.lua`, `tests/test_module_picker.lua`, `tests/test_pipette.lua`, `tests/test_player_data.lua`, `tests/test_round_up.lua`. Everything else is frozen; if you need a change elsewhere, stop and report. This is the one lane allowed to edit those three shipped files and those older test files.
- You never weaken a case. A case that pressed Compute and read the report keeps every assertion it had; it gains the ticks that let the work finish.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`, and 1.1.39 shipped that crash.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, measured on this base:
- `gui/sheet.lua:289` calls `Solver.solve_for(...)` and then `Sheet.publish_result(...)` in the same call, so the game freezes for the whole solve and the whole report build.
- `logic/calc_pipeline.lua` is complete: `CalcPipeline.start(sheet_flow)` enqueues a job, `CalcPipeline.step(job, budget)` advances snapshot, solve, power, report, publish, and `CalcPipeline.cancel(player_index, sheet_id)` stops it. Twenty cases cover it, including the budget sweep and the revision checks. **No shipped file requires it.**
- `logic/jobs.lua` services jobs from `Jobs.on_tick`, which `control.lua:158` already calls, and the progress panel refreshes from `Registry.progress_refresh` on every serviced tick plus `script.on_nth_tick(10, ...)` (`gui/progress_panel.lua:184-212`).
- `logic/registry.lua` carries the late edges: a module publishes itself at load, its partner reads the field when it runs. `logic/calc_pipeline.lua` requires `gui.sheet`, so the reverse edge must be a registry entry, never a require.
- A trial wiring on this base turned **308 cases red across six files**: `tests/test_calc_pipeline.lua`, `tests/test_input.lua`, `tests/test_module_picker.lua`, `tests/test_pipette.lua`, `tests/test_player_data.lua`, `tests/test_round_up.lua`. Every one of them presses the real Compute button and reads the report at once. `tests/test_pipette.lua` alone lost 115 cases.
- `H.run_ticks(world, n)` drives ticks in the harness. `Sheet.publish_result` remains the single place a report is committed.

## What to build

1. `control.lua` requires `logic.calc_pipeline` while it is parsed, so the job kind and the registry entry exist before any handler runs.
2. `logic/calc_pipeline.lua` publishes itself: `Registry.calc_pipeline = CalcPipeline`.
3. `gui/sheet.lua` starts the job instead of solving inline when the pipeline is loaded. Keep the inline solve as the path taken when it is absent, so a source checkout and a stripped build still work.
4. Decide, and state in a comment, what the queued recompute path does (`control.lua`'s `async_calls[1]`, reached from `Calculator.recompute_everything`). Either it slices too, or it stays inline; whichever you choose, every existing case must pass and a large sheet must not freeze the game on a player's own click.
5. Repair the six test files: after pressing Compute, drive ticks until the job is gone, bounded at 600 ticks, and fail the case naming the phase it stopped in. Never assert on a report before the job finishes.
6. Add cases proving the feature is live: pressing Compute enqueues a job rather than publishing at once; the bar becomes visible while the job runs and hides when it ends; Cancel during a run leaves the previous report intact and marked stale; the sliced report equals the report the inline path produces for the same sheet.
7. Keep `Sheet.calculate` as the name `async_calls[1]` holds, because a save from an older version can hold queued entries naming it.

## What done mean

```checks
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "pipeline-and-gui", "command": "lua5.2 tests/test_calc_pipeline.lua && lua5.4 tests/test_calc_pipeline.lua && lua5.2 tests/test_progress_panel.lua && lua5.2 tests/test_control.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "no-runtime-require", "command": "lua5.2 tests/test_no_runtime_require.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 300}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-green --manifest docs/tasks/037.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the case that proves Compute enqueues rather than publishes, red against the current inline call and green after.
- Paste the count of cases in each of the six repaired files before and after, so no case was dropped.
- `git diff --stat wave-4-green HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `control.lua`
- `gui/sheet.lua`
- `logic/calc_pipeline.lua`
- `tests/test_calc_pipeline.lua`
- `tests/test_input.lua`
- `tests/test_module_picker.lua`
- `tests/test_pipette.lua`
- `tests/test_player_data.lua`
- `tests/test_round_up.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a player's Compute click leave the game ticking, and does every older case still assert what it asserted before?
