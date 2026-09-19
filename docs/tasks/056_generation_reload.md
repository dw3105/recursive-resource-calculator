# 056 — A generation job survives a reload, or it cancels cleanly

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-056`, branch `lane/056`, base = `feat/round-8-blueprints`, tag `queue-base` (resolve it with `git rev-parse queue-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/generation.lua`, `logic/engine_test_api.lua`, `tests/test_engine_test_api.lua`, new `tests/test_generation_reload.lua` and new `tests/test_generation_record_handoff.lua`. Everything else is frozen.
- `tests/test_blueprint_pipeline.lua` is **not** yours. Its cases stay exactly as they are, including the mandatory real-sheet case that is red while lane 053 works. Lane 053 owns `logic/bp/search.lua` and `tests/test_search.lua`. Lane 055 owns `docs/api/*.json`.
- Every existing case stays. You add; you never weaken, skip or delete one.
- The branch carries one **known red** case: `tests/test_blueprint_pipeline.lua` holds the mandatory real-sheet case, which fails with `BP_FAIL_NO_LAYOUT_GRID_LIMIT` while lane 053 repairs the defect under it. Never edit that file, never change its expected outcome, and never treat its failure as yours. Report `component checks: PASS; feature integration: BLOCKED by tests/test_blueprint_pipeline.lua (lane 053)` when your own work is done.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `tests/golden/required-matrix.json`, the board and every merge. Need one changed? Send the exact small patch and carry on with your other work.
- `info.json` carries the user's own uncommitted edit and `mod-description.md` is the user's untracked file. Never touch either.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so at once. Never edit an unowned file and never weaken an assertion. Continue every owned
piece that does not need that fix. Checkpoint before you end.

Current facts:
- `logic/bp/generation.lua:20-21` keeps `next_job_id` and `handles` as module locals. A reload rebuilds the module, so every pending handle is gone while the saved job stays in `storage`. An offline probe that reloaded only `logic.bp.generation` observed `Before module reload: pending, saved job: true` and `After module reload: nil, saved job: true`. That probe is not a Factorio save and load; your case must exercise the supported reload path.
- `BP-19` allows either clean resumption or clean cancellation after a reload. It allows no orphaned job, no duplicate delivery and no calculator left unusable.
- `docs/feature-contracts.md` §17 fixes `Generation.register/start/status/cancel` and the terminal result; §19 fixes the calculation record and `Registry.calculation`; §20 fixes the capture.
- `tests/test_blueprint_pipeline.lua:258` replaces `Registry.calculation` with a test getter after computing a real result, so nothing yet proves the **real** `logic/calculation_result.lua` record reaches preparation.
- Writing to `storage` during the engine's load event is forbidden; rebuilding a process-local callback is not.

## What to build

1. `tests/test_generation_reload.lua` first: a job pending across a reload of the supported path, then the behaviour you chose, stated in the file. Resume plain saved state, or cancel cleanly. Never both, never neither.
2. After a reload: a job id is never reused for different work; `status`, `cancel` and `capture` stay defined for every id the save carries; a saved job never runs with no owner to publish to; a stale capture is never served as current; two players and two sheets never receive each other's result.
3. The occupied-cursor retry contract of `gui/blueprint_delivery.lua` keeps working across the reload.
4. `tests/test_generation_record_handoff.lua`: a real sliced calculation publishes through `logic/calculation_result.lua`, and preparation reads **that** record through the registered path, with the revision and fingerprint checks doing their work. This proves preparation before routing succeeds; it never asserts a finished layout.
5. A controlled Search boundary is allowed only in a case whose name says it is a lifecycle unit case.
6. If `control.lua` needs a load hook, write the exact small patch in your report and keep going; never edit it.

## What done mean

```checks
{"name": "lifecycle-tests", "command": "lua5.2 tests/test_generation_reload.lua && lua5.4 tests/test_generation_reload.lua && lua5.2 tests/test_generation_record_handoff.lua && lua5.4 tests/test_generation_record_handoff.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "neighbours", "command": "lua5.2 tests/test_engine_test_api.lua && lua5.2 tests/test_blueprint_delivery.lua && lua5.2 tests/test_calculation_result.lua && lua5.2 tests/test_no_runtime_require.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base queue-base --manifest docs/tasks/056.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the reload case failing before your change, with the lost handle, and passing after.
- Name the behaviour you chose and the contract line that allows it.
- `git diff --stat queue-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/bp/generation.lua`
- `logic/engine_test_api.lua`
- `tests/test_engine_test_api.lua`
- `tests/test_generation_reload.lua`
- `tests/test_generation_record_handoff.lua`

Touch nothing else.

# bound: 1800s

Reviewer ask: after a reload, is every saved job either running or cleanly cancelled?
