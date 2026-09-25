# 213_note_kinds progress panel: a blueprint note survives a calc recompute

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-213_note_kinds`, branch `lane/213_note_kinds`,
base tag `round-36-base`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data in `storage` only (no closures, no metatables). Unit tests
finish in under 20 s; GUI/control tests loop over `H.shapes()` and move time only with `H.run_ticks(world, n)`.

Read `docs/contracts/round36.md` first: it is the contract. Your clauses: N1.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK` or `GATE-FAIL`).

## Explain very simply

After a mod update, `control.lua` sets the note "Blueprint generation stopped…" on each stopped sheet and then
`Calculator.recompute_everything` starts calc jobs; `ProgressPanel.show` (gui/progress_panel.lua) clears every note
when a job shows, so the player may never see it.

## What to build

1. N1 kind tag on the note flow `hxrrc_job_note` (tags `{kind = "calc"|"blueprint"}`); blueprint captions
   (`hxrrc.blueprint_canceled`, `hxrrc.blueprint_stopped_update`, `hxrrc.blueprint_not_delivered`,
   `hxrrc.blueprint_waiting_hand`) are `blueprint`, others `calc`.
2. `ProgressPanel.show` for a calc job clears only a calc note; a blueprint job start clears blueprint notes; the
   Generate click clears blueprint notes (hook through `Registry.progress_note(player_index, sheet_id, nil)`; do not
   edit files you do not own).
3. Test (red at base first): new `tests/test_note_kinds.lua`, both shapes: running red blueprint job →
   `on_configuration_changed` → `H.run_ticks(world, 60)` with the calc recompute running → note
   `hxrrc.blueprint_stopped_update` still present; a new blueprint job start clears it.

## Files this lane owns

gui/progress_panel.lua, tests/test_note_kinds.lua, tests/test_progress_panel.lua, tests/test_panel_sweep.lua, docs/tasks/213_note_kinds.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/213_note_kinds`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane213-tests", "command": "git diff --name-only round-36-base HEAD | grep -Ev '^(gui/progress_panel\\\\.lua|tests/test_note_kinds\\\\.lua|tests/test_progress_panel\\\\.lua|tests/test_panel_sweep\\\\.lua|docs/tasks/213_note_kinds\\\\.md)$' | ( ! grep . ) && ! git diff round-36-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_note_kinds test_progress_panel test_panel_sweep test_update_stops_jobs test_delivery_final test_progress_status_line test_job_flow; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane213-tests-ok", "expect_exit": 0, "expect_regex": "lane213-tests-ok", "timeout_s": 2400}
```

# bound: 2400s
