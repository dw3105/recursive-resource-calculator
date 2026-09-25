# 204_update_stops_jobs control + jobs + generation: a mod update stops every job and closes its record

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-204_update_stops_jobs`, branch `lane/204_update_stops_jobs`,
base tag `round-34-base`, merge target `int/r34`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures, no metatables). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio
2.0 and 2.1) when it touches the GUI or control.

Read `docs/contracts/round34.md` first: it is the contract. Your clauses: U1, U2, U3.

## Explain very simply

The player updated the mod and reloaded: the old blueprint job looked "still going" and nothing stopped it.
Measured on base (legalcopilot-dev, 2026-09-25): start a red science generation (pattern: `tests/test_progress_view.lua`
PV-00), `H.run_ticks(world, 30)`, call `world.handlers.on_configuration_changed({mod_changes = {["RRC-Fork"] =
{old_version = "1.1.77", new_version = "1.1.79"}}})`, run 30 more ticks: `storage[1].blueprint_job` is nil but
`Generation.lookup(1, sheet_id).state` is still `"pending"` forever. The generation record lives in its own table
(`storage[PERSISTENCE_KEY]`, `logic/bp/generation.lua` `persistence`) and nothing closes it on update.
`control.lua` `on_configuration_changed` is where the update lands.

## What to build

1. U1: `Generation.stop_all(reason)` and the `on_configuration_changed` order from the contract. `Registry.progress_sweep`
   may not exist on your base: guard it with `type(Registry.progress_sweep) == "function"` (another change supplies it).
   `Registry.progress_note` exists on base.
2. U2: `Generation.status` / `Generation.lookup` close a `pending` record with no live job of that id (`cancelled`).
3. U3: plain reload keeps a running job; `Generation.cancel` works with module `handles` emptied (simulate by
   clearing the module's handle table through a test hook you add, e.g. `Generation._forget_handles_for_test()`).
4. Tests (red at base first): new `tests/test_update_stops_jobs.lua`, both shapes: U1 via real
   `on_configuration_changed` + `H.run_ticks` (lookup is not pending, `storage[1].blueprint_job` nil, a note
   `hxrrc.blueprint_stopped_update` is set on the sheet through `Registry.progress_note`); U2; U3.

## Files this lane owns

control.lua, logic/jobs.lua, logic/bp/generation.lua, tests/test_update_stops_jobs.lua, tests/test_jobs.lua, tests/test_control.lua, tests/test_generation_interim.lua, tests/test_job_flow.lua, docs/tasks/204_update_stops_jobs.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/204_update_stops_jobs`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane204-tests", "command": "git diff --name-only round-34-base HEAD | grep -Ev '^(control\\.lua|logic/jobs\\.lua|logic/bp/generation\\.lua|tests/test_update_stops_jobs\\.lua|tests/test_jobs\\.lua|tests/test_control\\.lua|tests/test_generation_interim\\.lua|tests/test_job_flow\\.lua|docs/tasks/204_update_stops_jobs\\.md)$' | ( ! grep . ) && ! git diff round-34-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_update_stops_jobs test_jobs test_generation_interim test_control test_job_flow test_blueprint_pipeline test_progress_view; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane204-tests-ok", "expect_exit": 0, "expect_regex": "lane204-tests-ok", "timeout_s": 2400}
```

# bound: 3000s
