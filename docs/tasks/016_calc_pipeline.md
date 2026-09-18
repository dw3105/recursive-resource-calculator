# 016 — a sheet calculation that runs across ticks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-016`, branch `lane/016`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/calc_pipeline.lua` and `tests/test_calc_pipeline.lua` only.
- `gui/sheet.lua` is frozen. It already gives you `Sheet.read_inputs(sheet_flow)`, `Sheet.publish_result(sheet_flow, result, inputs)` and `Sheet.id_of(sheet_flow)`; drive those rather than editing the file.
- Numbers do not move: the same sheet must produce the same rates, statuses and recipe choices it produces today.
- Every existing calculator test stays green unmodified.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/calc_pipeline.lua` carries the stubs `CalcPipeline.start(sheet_flow)`, `CalcPipeline.step(job, budget)` and `CalcPipeline.cancel(player_index, sheet_id)`.
- `logic/jobs.lua` (wave 1) owns the scheduler: `Jobs.request_sheet(player_index, sheet_id, context)`, `Jobs.on_tick(event)`, `Jobs.cancel`, `Jobs.progress_of`, and a job's shape with its revisions, phase, cursor and progress.
- `logic/solver_steps.lua` (wave 2) owns the sliced solve: `SolverSteps.begin(input)` and `SolverSteps.step(state, budget)`.
- `logic/report_steps.lua` (wave 2) owns the sliced power totals and report rows: `ReportSteps.begin(input)`, `ReportSteps.step(state, budget)` and `ReportSteps.publish(state)`, where publish returns false when the revisions moved.
- `logic/snapshot.lua` (wave 1) gives the immutable input and its fingerprint.
- `control.lua` already calls `Jobs.on_tick`; `H.run_ticks(world, n)` drives it in a test.
- The old synchronous path is still what `Sheet.begin_calculation` does. Your pipeline replaces what runs inside it; the entry point keeps its name.

## What to build

1. `CalcPipeline.start(sheet_flow)` takes a snapshot, registers a job through `Jobs`, and returns without solving anything in that callback.
2. `CalcPipeline.step` walks the phases in order: snapshot, solve, power, report, publish. Each phase spends the budget it is handed and keeps its own cursor.
3. Publication happens once, through `ReportSteps.publish`, and only when the sheet and configuration revisions still match. A mismatch drops the result and leaves the previous report.
4. Cancellation stops within two ticks, publishes nothing, and leaves the previous report marked stale.
5. `Sheet.begin_calculation` keeps working for every existing caller: either the pipeline finishes synchronously when nothing yields, or the existing tests keep passing because the queue drains in the ticks they already run.
6. Red-first cases in `tests/test_calc_pipeline.lua`: a sheet calculated through the pipeline gives the same report as the synchronous path, compared through `H.parse_report`; a tiny budget spreads one calculation over many ticks and still commits the same report; an edit during the run stops the old result from publishing; a cancel mid-run leaves the old report and no partial rows; two sheets of one player both finish; a quality-loop sheet and an infeasible sheet both come through unchanged; no partial report is ever visible between ticks.
7. Planted breach, pasted red then reverted: publish without comparing revisions, and the edit case must go red.

## What done mean

```checks
{"name": "calc_pipeline-tests", "command": "lua5.2 tests/test_calc_pipeline.lua && lua5.4 tests/test_calc_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/016.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/calc_pipeline.lua; out=$(cd \"$S\" && lua5.2 tests/test_calc_pipeline.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/calc_pipeline.lua`
- `tests/test_calc_pipeline.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does a sheet calculated across many ticks produce exactly the report the synchronous path produces?
