# 010 — power and report rows in batches, published once

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-010`, branch `lane/010`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/report_steps.lua`, `gui/report.lua`, `logic/compute_power_and_pollution.lua` and `tests/test_report_steps.lua`.
- Every existing report test stays green unmodified: `tests/test_quality_report.lua`, `tests/test_report_wrap.lua`, `tests/test_stale_report.lua`, `tests/test_beacons.lua`, `tests/test_modules.lua`, `tests/test_round_up.lua`. A report shows exactly what it shows today.
- Bounded batches of work, never a bounded number of rows. Every row a sheet produces today still gets drawn; dropping rows or refusing a sheet that used to work is not an acceptable way to be responsive.
- `LuaGuiElement.parent` is read-only: rows cannot be moved between parents. Build into a second container and swap which one is shown.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/report_steps.lua` carries the stubs `begin`, `step` and `publish(state)`, where `publish` returns false when the revisions moved.
- `gui/sheet.lua:Sheet.publish_result(sheet_flow, result, inputs)` is the single publish path today: it stores quality-loop configs, clears `output_flow`, shows a flying text when unsolvable, calls `Report.new_diagnostic` when there are no rates, otherwise computes power and pollution and calls `Report.new`.
- `gui/report.lua:657` `Report.new(parent, result, energy_consumption, pollution, round_up_machines)` and `:697` `Report.new_diagnostic(parent, result)` walk the solver's columns and build rows, including nested quality-loop rows.
- `logic/compute_power_and_pollution.lua` is one function over every column, with per-tier quality-loop work at `:47-90`; its beacon estimate is at `:6` (`group.count * machine_amount / group.sharing`).
- A budget is `{ops = int}` (`docs/feature-contracts.md` §6). Yield inside the column walk and inside the row building.
- `H.parse_report(output_flow)` (`tests/harness.lua:1188`) reads a built report back as a plain table; the existing tests use it, so the finished report must stay readable by it.
- `H.run_ticks(world, n)` fires the mod's own on_tick.
- Destroying a container is one engine call that cannot be split. Measure it against row count rather than claiming everything is preemptible.

## What to build

1. Resumable power aggregation: the same totals the current function returns, computed across ticks with a cursor, to the same numbers.
2. Resumable report construction: rows built in bounded batches into a hidden sibling container under the same parent, never into the visible one.
3. `publish(state)` checks the revisions, swaps the staged container in, destroys the previous one, and returns true. On a mismatch it returns false, destroys the staged container and leaves the visible report untouched.
4. A cancelled build leaves the previous report on screen and marked stale, never a half-drawn one.
5. Measure the destruction: a case that builds a large report and records the row count with the time of the single destroy call, so the residual spike is a documented number rather than a claim. Record it in the commit message.
6. Red-first cases in `tests/test_report_steps.lua`: a large report needs several ticks at a small budget and is identical to the one built in one go, compared through `H.parse_report`; the visible report never shows a partial build; a revision change during building publishes nothing and leaves the old report; a cancel leaves the old report marked stale; power and pollution totals equal today's numbers for an ordinary sheet, a quality-loop sheet and a burner sheet; a diagnostic report builds the same way; a sheet with many rows draws every row.
7. Planted breach, pasted red then reverted: publish the staged container without checking revisions, and the revision case must go red.

## What done mean

```checks
{"name": "report_steps-tests", "command": "lua5.2 tests/test_report_steps.lua && lua5.4 tests/test_report_steps.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/010.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/report_steps.lua; git -C \"$S\" checkout wave-1-green -- gui/report.lua; git -C \"$S\" checkout wave-1-green -- logic/compute_power_and_pollution.lua; out=$(cd \"$S\" && lua5.2 tests/test_report_steps.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree
the proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green
every check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/report_steps.lua`
- `gui/report.lua`
- `logic/compute_power_and_pollution.lua`
- `tests/test_report_steps.lua`

Touch nothing else.

# bound: 8800s

Reviewer ask: does a report built across many ticks equal the one built in a single tick, and can a stale revision ever publish?
