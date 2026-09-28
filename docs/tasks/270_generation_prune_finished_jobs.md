# 270_generation_prune_finished_jobs saved blueprint jobs keep only the newest record per sheet

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-270`, branch `lane/270`,
base tag `round-46-base-270`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`, `factorio`,
or any full suite, whole sheet or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

A player save (`SA_D0.zip`, 2026-09-28) holds 30.03 MB of RRC saved data; 26.03 MB (87 %) is
`storage.blueprint_generations.jobs`: 21 records (job ids 1..21: 10 success, 9 failure, 2 cancelled), 1.1-2.0 MB
each. Every Generate press makes a new job id (`logic/bp/generation.lua:1331`) and `persist_handle` (`:99-125`)
stores a full deep copy (capture snapshot + catalog, result, interim, canonical, ~205 KB fingerprint strings).
The only delete is `forget_persisted` (`:127-129`), called only when a job is refused at start (`:1347`). No cap,
no prune. `rebind_handles` (`:901-911`) also deep-copies EVERY record into process-local `handles` on each load.
Result: save and RAM grow 1-2 MB per Generate press, forever.

Fix:
1. When `persist_handle` writes a record whose `state` is `success`, `failure` or `cancelled`, delete every OTHER
   record in `state.jobs` with the same `player_index` + `sheet_id`, a LOWER `job_id`, and state not `pending`;
   also `handles[id] = nil` for each deleted id. The newest record keeps everything it has today (debug export
   reads its `capture`: `logic/export_payload.lua:1067`). `state.lookup` keeps pointing at the newest id.
2. `Generation.prune_all()`: same rule over all saved records (keep, per player + sheet, the highest job id plus
   any `pending`). Called from `control.lua` `on_configuration_changed` right after
   `local stopped = Generation.stop_all("mod_updated")` (~:62) — this shrinks existing saves on mod update.
   Never call it from `on_load` (storage is read-only there).
3. `Generation.status(player_index, old_id)` for a pruned id returns nil; check `gui/blueprint_dialog.lua:360-400`
   still copes with nil (it already guards `terminal.job_id and Generation.status(...)`; if a path indexes the
   result without a nil check, report it in the lane report — do NOT edit gui files).
Do NOT change fingerprints, snapshot format, `blueprint_attempts`, `calc_results` or the job scheduler.

## What to build

1. `tests/test_generation_prune.lua` (reuse the setup of `tests/test_generation_record_handoff.lua` /
   `tests/test_generation_attempt_lookup.lua`; small inputs, seconds):
   - GP1 start and finish (success or failure, whichever is fastest with a tiny input) 10 generations on ONE sheet:
     `storage.blueprint_generations.jobs` holds exactly 1 record, the newest id; `Generation.lookup` returns it;
     `Generation.capture` for it is non-nil. Red on base (10 records).
   - GP2 two sheets, 3 generations each: 2 records, one per sheet.
   - GP3 a pending job on sheet A is never pruned by a finished job on sheet A with a lower id, nor by `prune_all`.
   - GP4 `prune_all` on a storage seeded with 21 finished records over 3 sheets leaves 3; `handles` for pruned ids
     are gone (`Generation.status` returns nil for them).
   - GP5 cancelled-by-supersede (start twice quickly on one sheet) leaves only the newer record once it ends.
2. `logic/bp/generation.lua` prune rule + `Generation.prune_all`; `control.lua` one call line.
3. Keep green: all `tests/test_generation_*.lua`, `test_export_payload`, `test_progress_view`, `test_jobs` (if present).

## Files this lane owns

logic/bp/generation.lua, control.lua (ONLY the one `Generation.prune_all()` line), tests/test_generation_prune.lua,
docs/tasks/270_generation_prune_finished_jobs.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/270`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane270-tests", "command": "git diff --name-only round-46-base-270 HEAD | grep -Ev '^(logic/bp/generation\\.lua|control\\.lua|tests/test_generation_prune\\.lua|docs/tasks/270_generation_prune_finished_jobs\\.md)$' | ( ! grep . ) && git diff --quiet round-46-base-270 HEAD -- docs/tasks && for t in test_generation_prune test_generation_attempt_lookup test_generation_boundary_rules test_generation_controls test_generation_interim test_generation_recipe_facts test_generation_record_handoff test_generation_reload test_export_payload test_progress_view test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane270-tests-ok", "expect_exit": 0, "expect_regex": "lane270-tests-ok", "timeout_s": 3000}
{"name": "lane270-fast", "command": "out=$(lua5.2 tests/test_generation_prune.lua 2>&1); for c in GP1 GP2 GP3 GP4 GP5; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane270-ok", "expect_exit": 0, "expect_regex": "lane270-ok", "timeout_s": 600}
```

# bound: 3000s
