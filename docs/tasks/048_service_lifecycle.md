# 048 — The generation service finishes its own lifecycle, and its capture survives a failed layout

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-048`, branch `lane/048`, base = `feat/round-8-blueprints`, tag `unblock-base` (resolve it with `git rev-parse unblock-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Successor of lane 039. Its implementation is already in your branch as the first commit; you continue it, never rewrite it.

## What is true

**PRESERVE:**
- You own `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, new `tests/test_blueprint_pipeline.lua`, new `tests/test_engine_test_api.lua` and `tests/test_bp_settings.lua`. Everything else is frozen.
- Lane 047 owns `logic/bp/groups.lua`, `logic/bp/route.lua`, `tests/test_groups.lua` and `tests/test_route.lua`. Lane 049 owns `logic/calc_pipeline.lua` and new `logic/calculation_result.lua`. Lane 050 owns `tests/golden/engine/mod/`. Lane 052 owns `logic/export_payload.lua` and `tests/golden/add_case`. Never touch any of them.
- Every existing case stays. You add; you never weaken, skip or delete one. An asynchronous path gains bounded ticks, never fewer assertions.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `docs/engine-evidence/examples/`, task files, the corpus matrix and every merge. Need one of them changed? Send the exact small request and carry on with your other work.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so in your report at once. Never edit an unowned file and never weaken the positive
assertion. Continue every owned implementation and focused test that does not need that fix. Checkpoint your work
before you end. Report component completion and integration blockage as two separate things: a blocked
integration gate is never an overall PASS.

Current facts:
- Your branch's first commit, `3698214`, is lane 039 attempt 3's preserved work: a 645-line `logic/bp/generation.lua`, plus edits to `gui/blueprint_dialog.lua` and `logic/engine_test_api.lua`. It carries **no test file**. It is a checkpoint, never a finished feature.
- That service queues a real job from a real calculated sheet and reaches routing. The physical defect it stops at — a block port labelled `block:gear` while the plan flow names `gear` — belongs to lane 047, which is running now.
- `logic/bp/generation.lua:310` calls `Solver.solve_for` when it cannot find the sliced calculation's result. That is a synchronous solve inside a job step, charged one operation; `docs/feature-contracts.md` §19 forbids it.
- `docs/feature-contracts.md` §19 freezes `CalculationResult` and its `Calculation.get/publish/forget`. Lane 049 publishes that module as `Registry.calculation`. Read it through `Registry` and let your own tests supply a stub publisher, so your lane is green before 049 merges.
- `docs/feature-contracts.md` §20 freezes `Generation.capture(player_index, generation_id)`, `source_kind` and `provenance`. A capture is kept once preparation finished, whatever search does afterwards.
- `logic/engine_test_api.lua` must stop registering the `blueprint` job kind itself (`logic/jobs.lua:564` replaces a kind's entry on every call) and call the service with `deliver = false`.

## What to build

1. Write the two missing test files first, then make them pass.
2. `tests/test_blueprint_pipeline.lua` unit cases, each named a unit case: a Generate click queues a job and returns at once; registration never replaces another caller's publication; job identity; cancel; supersession by a second start on one sheet; a deleted sheet; a revision change; a preparation failure told apart from a search failure; a busy cursor retried; a prepared capture still readable after a terminal search failure. A controlled Search boundary is allowed **only** in these unit cases, and each says so in its name.
3. One separately named mandatory real-sheet case: a small supported chain with a nonzero flow runs from a real calculated sheet through the real modules to a delivered blueprint, with no stubbed Search and no precomputed plan. While lane 047's fix is unmerged this case fails at routing; keep it, report it as an integration blockage, and never invert or weaken it.
4. Preparation reads the published calculation result through `Registry` per §19 and never calls `Solver.solve_for`.
5. Preparation respects the shared budget: catalog projection, snapshot copying and export projection are bounded work with a cursor, never one step charged one operation.
6. `Generation.capture` per §20, with `source_kind` and `provenance`, retained after a failed or cancelled search.
7. `tests/test_engine_test_api.lua`: the interface refuses when `packaged == false`, returns one terminal result, cancels, never publishes into another job on the same sheet, and registers no job kind of its own.

## What done mean

```checks
{"name": "service-tests", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.4 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_engine_test_api.lua && lua5.2 tests/test_bp_settings.lua", "expect_exit": 0, "expect_regex": "failed", "timeout_s": 900}
{"name": "no-runtime-require", "command": "lua5.2 tests/test_no_runtime_require.lua && lua5.2 tests/test_blueprint_delivery.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "no-synchronous-solve", "command": "grep -n 'solve_for' logic/bp/generation.lua; test $? -ne 0 && echo no-synchronous-solve", "expect_exit": 0, "expect_regex": "no-synchronous-solve", "timeout_s": 60}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base unblock-base --manifest docs/tasks/048.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Report the unit cases and the real-sheet case separately, with the real-sheet case's current stage.
- `git diff --stat unblock-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `gui/blueprint_dialog.lua`
- `logic/bp/generation.lua`
- `logic/engine_test_api.lua`
- `tests/test_blueprint_pipeline.lua`
- `tests/test_engine_test_api.lua`
- `tests/test_bp_settings.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the service own its whole lifecycle, and does a capture survive a failed layout?
