# 006 — an honest progress bar and a Cancel that works

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-006`, branch `lane/006`, base = `feat/round-8-blueprints` `4569c48ca39995d321f26ec11403fb273e7a194a` (tag `wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `gui/progress_panel.lua` and `tests/test_progress_panel.lua` only.
- `gui/sheet.lua` already builds `hxrrc_calc_progressbar` and `hxrrc_cancel_button`, hidden, each in its own cell, and calls `ProgressPanel.on_cancel_clicked(event)`. Keep those names.
- Never disable the calculator window while work runs: the controls that stop that work live inside it.
- The bar's value is a fraction in [0, 1]; the harness refuses anything else.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `gui/progress_panel.lua` carries the stubs `show`, `hide`, `update(sheet_flow, progress)` and `on_cancel_clicked`.
- `Sheet.progressbar_of(sheet_flow)` and `Sheet.cancel_button_of(sheet_flow)` return the two controls, or nil on a sheet not yet repaired. Handle nil rather than assuming.
- `progress` is `{phase = string, done_units = int, total_units = int | nil}`, the shape every job reports (`docs/feature-contracts.md` §6). `total_units` is nil while the work is still discovering how much there is.
- Phase locale keys exist: `calc_phase_reading`, `_expanding`, `_assembling`, `_solving`, `_feeding`, `_power`, `_report`, plus `calc_cancel`, `calc_canceled` and `calc_progress_tooltip` (which takes three parameters: phase, done, total).
- `logic/jobs.lua` is another lane's file (W1-jobs) and is a stub in your base. Call `Jobs.cancel(player_index, sheet_id)` and `Jobs.progress_of(player_index, sheet_id)`; in your tests inject your own progress values rather than depending on that lane.
- A value of 1 is inside the range the harness allows. That the bar does not read 1 before a result is committed is behaviour this lane owns, not something the range check can prove.
- `H.run_ticks(world, n)` fires the mod's own on_tick.

## What to build

1. `show` and `hide` make the bar and Cancel visible together and hide them together; a sheet whose controls are missing is left alone rather than crashed on.
2. `update(sheet_flow, progress)` sets the caption to the phase's own locale key and the value to completed work over total work. While `total_units` is nil the bar shows a documented phase estimate and never a fabricated countdown, and it stays strictly below 1 until a complete result or a final diagnostic is committed.
3. Refresh at least every 10 game ticks while work runs, and do not add an artificial delay when work finishes sooner than a frame.
4. `on_cancel_clicked` cancels that sheet's job, hides the controls, and leaves the previous report visible and labelled canceled rather than replaced by partial rates.
5. Red-first cases in `tests/test_progress_panel.lua`: the controls stay hidden while nothing runs and appear when work starts; the caption names the phase; the value tracks done over total; with an unknown total the value still rises and stays below 1; the value only reaches 1 after completion is reported; Cancel hides the controls and leaves the old report on screen marked canceled; the calculator frame is never disabled by any of this; a sheet without the round 8 cells is handled without error.
6. Planted breach, pasted red then reverted: set the value to 1 when the last known phase begins, and the "below 1 until committed" case must go red.

## What done mean

```checks
{"name": "progress_panel-tests", "command": "lua5.2 tests/test_progress_panel.lua && lua5.4 tests/test_progress_panel.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base 4569c48ca39995d321f26ec11403fb273e7a194a --manifest docs/tasks/006.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- gui/progress_panel.lua; out=$(cd \"$S\" && lua5.2 tests/test_progress_panel.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat 4569c48ca39995d321f26ec11403fb273e7a194a HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `gui/progress_panel.lua`
- `tests/test_progress_panel.lua`

Touch nothing else.

# bound: 5400s

Reviewer ask: can the bar ever read 1 before a result is committed, and does the calculator stay usable while work runs?
