# 049 — A finished calculation leaves a record, and nothing solves twice

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-049`, branch `lane/049`, base = `feat/round-8-blueprints`, tag `unblock-base` (resolve it with `git rev-parse unblock-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/calc_pipeline.lua`, `tests/test_calc_pipeline.lua`, new `logic/calculation_result.lua` and new `tests/test_calculation_result.lua`. Everything else is frozen.
- Lane 048 owns `logic/bp/generation.lua` and reads your module through `logic/registry.lua`. Lane 052 owns `logic/export_payload.lua`. Never touch either.
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
- `logic/calc_pipeline.lua` drives snapshot, solver steps, power steps and report steps, and commits only when the revisions still match. It publishes the solver result nowhere, so a later reader cannot find it.
- Lane 039's service therefore fell back to a synchronous `Solver.solve_for` inside a job step.
- `docs/feature-contracts.md` §19 freezes `CalculationResult`, its storage key `storage[player_index].calc_results[sheet_id]`, the three-way currency test (`sheet_revision`, `config_revision`, `input_fingerprint`), the drop rules for reset, configuration change, sheet deletion and a leaving player, and the calls `Calculation.get`, `Calculation.publish`, `Calculation.forget`.
- `logic/registry.lua` is how a module reaches another without a runtime `require`. Publish yours as `Registry.calculation` inside `logic/calculation_result.lua`; say in your report that `control.lua` must require it, because that file is the coordinator's.

## What to build

1. `logic/calculation_result.lua` exactly as §19 describes, plain data only, publishing itself as `Registry.calculation`.
2. `logic/calc_pipeline.lua` publishes the record in the same step that commits the staged report, never earlier. A failed, cancelled, superseded or stale run leaves the previous record untouched.
3. Reset, configuration change, sheet deletion and a leaving player drop the affected records. Copying is bounded work charged against the job budget.
4. `tests/test_calculation_result.lua`: publish and read back; a record with an older `sheet_revision` reads as stale; one with an older `config_revision` reads as stale; one whose `input_fingerprint` changed reads as stale; a cancelled run never overwrites; deletion and reset drop; nothing reachable in `storage` is a function, a metatable or a LuaObject.
5. `tests/test_calc_pipeline.lua`: one completed sliced calculation makes its solver result readable through `Calculation.get` with no second solve, and the same result appears at budget 1 and at budget 10^6.

## What done mean

```checks
{"name": "calculation-tests", "command": "lua5.2 tests/test_calculation_result.lua && lua5.4 tests/test_calculation_result.lua && lua5.2 tests/test_calc_pipeline.lua && lua5.4 tests/test_calc_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "neighbours", "command": "lua5.2 tests/test_jobs.lua && lua5.2 tests/test_snapshot.lua && lua5.2 tests/test_report_steps.lua && lua5.2 tests/test_no_runtime_require.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base unblock-base --manifest docs/tasks/049.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the stale-record cases failing before the currency test exists and passing after.
- `git diff --stat unblock-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/calc_pipeline.lua`
- `logic/calculation_result.lua`
- `tests/test_calc_pipeline.lua`
- `tests/test_calculation_result.lua`

Touch nothing else.

# bound: 1800s

Reviewer ask: can preparation read a finished calculation without solving again?
