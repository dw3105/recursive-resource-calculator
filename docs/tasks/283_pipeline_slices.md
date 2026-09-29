# 283_pipeline_slices: a sheet calculation takes its snapshot in slices, never in the Compute tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-283`, branch `lane/283`,
base tag `round-50-base`, merge target `int/r50`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet or headless run of any
kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Player save (legalcopilot-dev 2026-09-29, Factorio 2.0.77, 55 mods): `CalcPipeline.start`
(`logic/calc_pipeline.lua:226`) calls `Snapshot.of_sheet`, which builds and fingerprints all 529 recipe setups of
the player (86-95 ms + 10-35 ms), then `Jobs.request_sheet` deep-copies that snapshot five times (31-52 ms). All in
ONE tick: 130-142 ms per sheet. Game stutters on load, on productivity research, on module change.

Fix: start takes only a cheap snapshot head; the job's `snapshot` phase finishes it in slices, a few dozen
products per tick, before the solve. The snapshot module gives this API (frozen contract; it may not exist in your
tree yet):

- `Snapshot.begin_sheet(sheet_flow)` -> snapshot: same fields as `of_sheet` except `selection = nil`,
  `fingerprint = {input = nil, result = nil}`, plus `build` (plain data).
- `Snapshot.step(snapshot, budget)` -> true when done. Takes `Snapshot.ENTRY_OPS` (40) per product from
  `budget.ops`; >= 1 product per call when `budget.ops > 0`. Done: `snapshot.selection` and
  `snapshot.fingerprint.input` set (bytes equal to `of_sheet`), `snapshot.build = nil`. Done snapshot: returns true,
  takes no ops.
- `Snapshot.progress(snapshot)` -> `done_units, total_units`.

## What to build

1. `logic/calc_pipeline.lua`:
   - `CalcPipeline.start`: `Snapshot.begin_sheet(sheet_flow)` in place of `Snapshot.of_sheet`; initial progress
     `{phase = "snapshot", done_units = 0, total_units = <second value of Snapshot.progress>}`. Nothing else of
     start changes.
   - `CalcPipeline.step`, `job.phase == "snapshot"`: when `state.snapshot.build ~= nil`, call
     `Snapshot.step(state.snapshot, budget)`, set `progress(job, "snapshot", Snapshot.progress(state.snapshot))`
     and `cursor(job, "snapshot", {done = <done units>})`; if not done, leave the phase (the while loop ends when
     `budget.ops <= 0`). When done, or when `build == nil` (a job saved before this change, or one given a
     finished snapshot): set `state.snapshot.selection = nil` (the fingerprint stays: `calculation_record` reads
     `snapshot.fingerprint.input`) and run today's code (solver begin, phase `solve`, `consume(budget)`).
   - A job whose snapshot has neither `build` nor `fingerprint.input` still runs (fingerprint nil, as today).
   - Short comment with the numbers above + date 2026-09-29.
2. New `tests/test_calc_pipeline_slices.lua` (header: CP1 CP2 CP3 red on round-50-base). If
   `Snapshot.begin_sheet` is nil in the loaded module, the test installs a stub on the `Snapshot` table that keeps
   the contract: `begin_sheet` = `of_sheet` result with `selection` removed, `fingerprint.input = nil`, and
   `build = {left = <number of selection entries>, full = <of_sheet fingerprint>, selection = <of_sheet selection>}`;
   `step` takes 40 ops per entry, at least 1 per call, and on the last entry sets `selection`, `fingerprint.input`,
   `build = nil`; `progress` counts. When the real functions exist, the test uses them unchanged. Use the harness
   world of `tests/test_calc_pipeline.lua` with at least 4 recipes bound so the selection has >= 4 entries.
   - CP1: `CalcPipeline.start(sheet_flow)` never calls `Snapshot.of_sheet` (wrap it with a counter for the call).
   - CP2: job stepped with `Jobs.step(job, {ops = 40})` stays in phase `snapshot` for >= 2 calls, progress
     `done_units` grows; then finishes normally (drive to done with `{ops = 2000}` calls, pattern from
     `tests/test_calc_pipeline.lua`); published record `input_fingerprint` == `Snapshot.of_sheet(sheet_flow)
     .fingerprint.input`.
   - CP3: once past `snapshot`, `job.state.snapshot.selection == nil` and `job.state.snapshot.fingerprint.input`
     is a string.
   - CP4: a job whose state snapshot is a full `of_sheet` result (no `build`) goes straight to `solve` and
     publishes the same record as base.
3. Keep green (one at a time, `timeout 90`): `test_calc_pipeline`, `test_job_flow`, `test_jobs`,
   `test_calculation_result`, `test_progress_panel`, `test_progress_view`, `test_snapshot`, `test_report_steps`,
   `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/calc_pipeline.lua, tests/test_calc_pipeline_slices.lua, docs/tasks/283_pipeline_slices.md. Never touch
anything else.

## Commit, THEN check

Commit on `lane/283`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane283-tests", "command": "git diff --name-only round-50-base HEAD | grep -Ev '^(logic/calc_pipeline\\.lua|tests/test_calc_pipeline_slices\\.lua|docs/tasks/283_pipeline_slices\\.md)$' | ( ! grep . ) && for t in test_calc_pipeline_slices test_calc_pipeline test_job_flow test_jobs test_calculation_result test_progress_panel test_progress_view test_snapshot test_report_steps test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane283-tests-ok", "expect_exit": 0, "expect_regex": "lane283-tests-ok", "timeout_s": 2400}
{"name": "lane283-fast", "command": "out=$(timeout 120 lua5.2 tests/test_calc_pipeline_slices.lua 2>&1); for c in CP1 CP2 CP3 CP4; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane283-ok", "expect_exit": 0, "expect_regex": "lane283-ok", "timeout_s": 300}
```

# bound: 3600s
