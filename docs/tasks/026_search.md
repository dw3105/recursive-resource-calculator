# 026 — a bounded search that keeps the best valid layout

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-026`, branch `lane/026`, base = `feat/round-8-blueprints`, tag `wave-3-complete` (resolve it with `git rev-parse wave-3-complete`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/search.lua` and `tests/test_search.lua` only.
- You never score a layout yourself: `Validate.compare` is the only place the objective order lives.
- A partially routed candidate is never published, and running out of budget is never reported as "no layout exists".
- Everything the job holds is plain data, because it lives in `storage` across saves.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/search.lua` carries the stubs `Search.begin(input)`, `Search.step(job, budget)`, `Search.cancel(job)` and `Search.progress(job)`.
- The stages it drives are merged and green: `logic/bp/plan.lua`, `preflight.lua`, `groups.lua`, `pack.lua`, `route.lua`, `power.lua`, `validate.lua`, `serialize.lua`, each with `begin` and `step` and a budget of `{ops = int}`.
- `logic/bp/grid.lua` gives `robo_grid{cols, rows, tile_w, tile_h, max_connection_distance}` and `edge_slots`.
- `logic/jobs.lua` owns scheduling and revisions; a blueprint job lives at `storage[player_index].blueprint_job` and takes what the calculations leave.
- Objective order (BP-20): fewest physical beacons, then smallest footprint, then fewest poles, then deterministic tie-breakers. Grid size is never an objective of its own; the outer grid is a tie-breaker after those three.
- Grid growth starts at 2 by 2 and grows. A larger grid is still worth trying after a smaller one succeeded, because more room can mean fewer beacons.
- Failure codes: `BP_FAIL_SEARCH_BUDGET`, `BP_FAIL_NO_LAYOUT_GRID_LIMIT`, `BP_FAIL_ENTITY_BUDGET`, `BP_FAIL_CANCELLED`, `BP_FAIL_REVISION_CHANGED`.

## What attempt 1 left undone

Attempt 1 wrote `logic/bp/search.lua` and sixteen cases, and three of its four checks passed: the search tests, the
whole suite and the ownership audit. The red proof timed out at 600 s, exit 124, and that verdict is the whole
failure.

Cause, in your own file: `tests/test_search.lua:149`, `:150` and `:158` drive the search with an unbounded
`while not state.done do ... end`. Against the stub that is restored from the base, `done` never becomes true, so
the run hangs rather than failing, and a hang proves nothing. Lane 016 lost an attempt to the same trap.

Keep everything attempt 1 built. Change only the waits:

1. Bound **every** drive loop, including the two determinism loops and the progress loop, at 600 iterations.
2. When a loop reaches its bound, fail the case with `H.equal(state.done, true, ...)` naming the phase the state
   stopped in, so the stub produces `FAIL <case> [assert]` rather than a hang.
3. Do the same for the two loops already bounded at 10000: 600 is the agreed bound.
4. Run the red proof yourself before the checks: restore the stub in a scratch worktree, run
   `timeout 120 lua5.2 tests/test_search.lua`, and confirm it prints a tagged assertion failure and exits non-zero.

## What to build

1. `Search.begin`/`Search.step` drive the stages in order for each candidate: plan and preflight once, then per grid and per block ordering, group, pack, route, power, validate, and serialize only the winner.
2. The best valid candidate is kept across every grid tried, and exploring a worse or larger one never discards it.
3. Cursors for grid, candidate and ordering are plain data and survive a round trip.
4. Before publishing, the sheet and configuration revisions are checked again; a mismatch is `BP_FAIL_REVISION_CHANGED` and nothing is published.
5. `Search.progress` returns a fraction below 1 until the result is committed, and a phase key.
6. Red-first cases in `tests/test_search.lua`: a small feasible plan produces a validated blueprint; the same input searched twice gives the same layout; a candidate that fails routing is discarded while an earlier valid one is kept; a larger grid that needs fewer beacons wins over a smaller one that needs more; a budget too small ends in `BP_FAIL_SEARCH_BUDGET` and never in a claim that no layout exists; a cancel mid-search publishes nothing; a revision change before publication drops the result; the job holds no function and no LuaObject; progress stays below 1 until the result is committed.
7. Planted breach, pasted red then reverted: drop the incumbent when a larger grid fails, and the "keeps the best valid layout" case must go red.

## What done mean

```checks
{"name": "search-tests", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-complete --manifest docs/tasks/026.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-3-complete -- logic/bp/search.lua; out=$(cd \"$S\" && timeout 120 lua5.2 tests/test_search.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-3-complete HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/search.lua`
- `tests/test_search.lua`

Touch nothing else.

# bound: 8800s

Reviewer ask: does a larger grid needing fewer beacons win, and can exhausting the budget ever be reported as no layout existing?
