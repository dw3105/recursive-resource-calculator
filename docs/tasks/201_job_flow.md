# 201_job_flow gui: Generate closes the dialog, Cancel stops the blueprint, Cancel never locks the sheet

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-201_job_flow`, branch `lane/201_job_flow`,
base tag `round-33-base`, merge target `int/r33`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio 2.0 and 2.1)
when it touches the GUI or control.

Read `docs/contracts/round33.md` first: it is the contract. Your clauses: G1, G2, G3, G4, G5 (lane 201 part), G6,
and dropping the per-tick `Registry.progress_refresh` call from `Jobs.on_tick` (`logic/jobs.lua:480-484`, P3 note).

## Explain very simply

Player, 2026-09-24: no way to cancel a blueprint calculation; after pressing Generate the dialog should close and the
calculator come back with its progress bar; reopening the calculator mid-job should show the bar; Cancel lets the
blueprint keep going and breaks the layout. The contract names every cause by file:line. GUI tests use the engine
mock in `tests/harness.lua` (`H.new_world`, `require "control"`, `world.handlers.on_init()`, click handlers via
`event_handlers.on_gui_click[name]`, `H.run_ticks`); the mock fires `on_gui_closed` when `player.opened` changes and
refuses opening a GUI inside that event — follow the existing pattern in `tests/test_bp_settings.lua` and
`tests/test_blueprint_pipeline.lua`.

## What to build

1. G1, G2, G3 (incl. `cancel` in the blueprint job spec, `generation.lua:1287`), G4 (tombstone drops only the
   canceled job's own late publish; rewrite test J4 in `tests/test_jobs.lua` to this rule), G5 lane-201 part, G6.
2. Remove the per-tick progress refresh call from `Jobs.on_tick`.
3. New `tests/test_job_flow.lua` (red at base first), both shapes: JF1 Generate click closes dialog, calculator
   visible + opened on job's tab; JF2 dialog footer caption is `gui.close` and closing leaves the job running; JF3 sheet
   Cancel during a blueprint job: handle state `canceled`, no `blueprint_job`, run 600 ticks → no cursor write, no
   offer; JF4 Compute then Generate after a Cancel both start a job; JF5 failure with dialog closed calls
   `Registry.progress_note` (stub); dialog error label `single_line == false`; JF6 close calculator, reopen mid-job →
   job's tab selected.

## Files this lane owns

gui/blueprint_dialog.lua, gui/sheet.lua, gui/calculator.lua, control.lua, logic/jobs.lua, logic/bp/generation.lua,
tests/test_job_flow.lua, tests/test_jobs.lua, tests/test_calc_pipeline.lua, tests/test_blueprint_pipeline.lua,
tests/test_generation_interim.lua, tests/test_bp_settings.lua, tests/test_control.lua. Never touch anything else
(`gui/progress_panel.lua` belongs to someone else: call only its existing functions).

## Commit, THEN check

Commit on `lane/201_job_flow`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane201_job_flow-tests", "command": "git diff --name-only round-33-base HEAD | grep -v '^docs/tasks/201_job_flow' | grep -Ev '^(gui/blueprint_dialog\\.lua|gui/sheet\\.lua|gui/calculator\\.lua|control\\.lua|logic/jobs\\.lua|logic/bp/generation\\.lua|tests/test_job_flow\\.lua|tests/test_jobs\\.lua|tests/test_calc_pipeline\\.lua|tests/test_blueprint_pipeline\\.lua|tests/test_generation_interim\\.lua|tests/test_bp_settings\\.lua|tests/test_control\\.lua)$' | ( ! grep . ) && ! git diff round-33-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_job_flow test_jobs test_calc_pipeline test_blueprint_pipeline test_generation_interim test_bp_settings test_control test_progress_panel test_round8_spine test_generation_attempt_lookup test_export_attempt_integration; do timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane201_job_flow-tests-ok", "expect_exit": 0, "expect_regex": "lane201_job_flow-tests-ok", "timeout_s": 2400}
```

# bound: 3600s
