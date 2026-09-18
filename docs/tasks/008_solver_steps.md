# 008 — the solver in slices, with the same answers

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-008`, branch `lane/008`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/solver_steps.lua`, `logic/solver.lua` and `tests/test_solver_steps.lua`.
- `Solver.solve_for(rates, player_index, product_parts, options)` keeps its name, its arguments and its result shape, and stays synchronous for every existing caller. Everything the existing tests assert about it stays true.
- These files must stay green **unmodified**: `tests/test_solver.lua`, `tests/test_quality_feed.lua`, `tests/test_quality_loop.lua`, `tests/test_quality_recycle_only.lua`, `tests/test_recycling.lua`, `tests/test_round_up.lua`, `tests/test_quality.lua`, `tests/test_quality_integration.lua`. If one of them has to change, stop and report; do not edit it.
- Numbers do not move. No tolerance is loosened, no round is skipped, no ordering is changed to make slicing easier.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/solver_steps.lua` carries the stubs `SolverSteps.begin(input)` and `SolverSteps.step(state, budget)` and the phase list.
- The phases already exist inside `logic/solver.lua`: `collect_columns` (`:402-564`, a queue walk inside a fixpoint), per-column net amounts (`:85-123`), `prepare_matrix` (`:567-588`), `solve_once` (`:622-706`, elimination in place with a noise test and two pivot strategies), back-substitution (`:694-703`), `worst_residual` (`:710-731`), `backwards_reasons` (`:800-823`), `compute_product_rates` (`:766-791`), and the feed search `Solver._solve_with_feed` (`:1015-1193`), which re-mixes, rebuilds and re-solves per probe, up to `Solver.FEED_ROUND_LIMIT = 50`.
- `solve_once` eliminates in place while `gauss_solve` keeps the original through `copy_matrix` (`:594-603`). A resumable run must persist both, and the pivot index is the natural cursor.
- Test seams already exported: `Solver._reverse_visit_order`, `_gauss_solve`, `_solve_once`, `_worst_residual`, `_backwards_reasons`, `_loop_column` (`:1198-1202`).
- A budget is `{ops = int}`, decremented inside the loops, per `docs/feature-contracts.md` §6. Yield inside the elimination and inside the feed probes, not only between phases: one large matrix is already more than a tick of work.
- Nothing in the state may be a LuaObject: columns hold prototype references today, so a persisted cursor carries names and indices and looks the objects up again on resume.

## What to build

1. `SolverSteps.begin` takes the same inputs `Solver.solve_for` takes and returns a plain-data state naming its phase and cursor.
2. `SolverSteps.step(state, budget)` advances within the budget and returns when it is spent. Phases, in order: following ingredients, expanding quality stages, building the matrix, eliminating, substituting back, measuring residuals, the feed search, and assembling the result. Every long loop keeps a cursor and yields inside itself.
3. `Solver.solve_for` becomes a wrapper that drives `SolverSteps` to completion with an unbounded budget and returns exactly what it returns today.
4. Red-first cases in `tests/test_solver_steps.lua`: a fixture solved with a budget of one operation per step and the same fixture solved in one go give identical rates, statuses, reasons and recipe choices, compared field by field; a fixture needing the feed search does the same, including `feed_rounds`; a state carries no LuaObject; the cursor survives being serialized and read back (round-trip it through a plain copy) and finishes with the same answer; an infeasible sheet and an unsolvable sheet both come out of the sliced path unchanged; the number of steps taken is bounded by the work, so a larger budget never changes the result, only the step count.
5. Planted breach, pasted red then reverted: stop the feed search one round early, and the feed equality case must go red.

## What done mean

```checks
{"name": "solver_steps-tests", "command": "lua5.2 tests/test_solver_steps.lua && lua5.4 tests/test_solver_steps.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/008.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/solver_steps.lua; git -C \"$S\" checkout wave-1-green -- logic/solver.lua; out=$(cd \"$S\" && lua5.2 tests/test_solver_steps.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree
the proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green
every check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/solver_steps.lua`
- `logic/solver.lua`
- `tests/test_solver_steps.lua`

Touch nothing else.

# bound: 8800s

Reviewer ask: do a one-operation budget and an unbounded budget produce identical rates, statuses and recipe choices on the quality and feed fixtures?
