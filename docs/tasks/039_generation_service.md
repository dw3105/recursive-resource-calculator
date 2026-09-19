# 039 — Generate actually generates, and one service owns the job

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-039`, branch `lane/039`, base = `feat/round-8-blueprints`, tag `recovery-base` (resolve it with `git rev-parse recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Stream A of the recovery plan. This is the biggest missing player workflow: the dialog validates and stops.

## What is true

**PRESERVE:**
- You own `gui/blueprint_dialog.lua`, new `logic/bp/generation.lua`, `logic/engine_test_api.lua`, new `tests/test_blueprint_pipeline.lua`, new `tests/test_engine_test_api.lua`, and `tests/test_bp_settings.lua`. Everything else is frozen; if you need a change elsewhere, stop and report.
- Lane 037 owns `control.lua`, `gui/sheet.lua`, `logic/calc_pipeline.lua` and six older test files **right now**. Never touch them. If registration in `control.lua` is needed, say so in your report and expose `Generation.register()` so the integrator can wire it.
- Every existing case stays. You add; you never weaken or delete. An asynchronous path gains bounded ticks, never fewer assertions.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The Generate handler ends at `gui/blueprint_dialog.lua:287-290` with `return true, settings` and a comment that a later lane supplies the job. Nothing downstream runs.
- `logic/engine_test_api.lua:233` calls `Jobs.register("blueprint", {begin = Search.begin, step = Search.step, ...})` from inside its own start path. `logic/jobs.lua:564` replaces a kind's entry on every call, so whichever caller registers last decides how every blueprint job publishes.
- Everything below the dialog exists and is green: `logic/bp/plan.lua`, `preflight.lua`, `groups.lua`, `pack.lua`, `route.lua`, `power.lua`, `validate.lua`, `serialize.lua`, `search.lua`, and `gui/blueprint_delivery.lua` with its occupied-cursor retry.
- `docs/feature-contracts.md` §17 freezes what you build: `Generation.register/start/status/cancel`, `GenerationInput`, `PreparedInput`, `TerminalResult`, and the rules for supersession, revisions, cancellation and a deleted sheet.
- `Jobs` already services jobs from `Jobs.on_tick` under one shared budget, and the progress panel refreshes from `Registry.progress_refresh`.

## What to build

1. `logic/bp/generation.lua` exactly as §17 describes. It registers the `blueprint` kind once, and `Generation.register()` is idempotent.
2. A validated Generate click calls `Generation.start` with `deliver = true` and returns at once. Preparation — snapshot, catalog, plan — happens inside the job, never inside the click.
3. On success, hand the result to `BlueprintDelivery.deliver`, keeping its busy-cursor retry. On failure, show the reason codes and the stage. On cancel or a stale result, the previous report and the cursor stay as they were.
4. `logic/engine_test_api.lua` stops registering the job kind itself and calls the same service with `deliver = false`. One terminal result per job; canonical digest fields come from the canonical result.
5. `tests/test_blueprint_pipeline.lua`: one small supported chain with a nonzero flow runs from a real calculated sheet through the real modules to a delivered blueprint. No stubbed Search, no precomputed plan in the positive case.
6. `tests/test_engine_test_api.lua`: the interface refuses when `packaged == false`, returns one terminal result, cancels, and never publishes into another job on the same sheet.
7. If the positive case fails inside an algorithm, stop and report the first broken stage with a minimal reproducer. Never turn a positive case into an expected rejection to make it pass.

## What done mean

```checks
{"name": "pipeline-tests", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.4 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_engine_test_api.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "delivery-and-settings", "command": "lua5.2 tests/test_blueprint_delivery.lua && lua5.2 tests/test_bp_settings.lua && lua5.2 tests/test_no_runtime_require.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base recovery-base --manifest docs/tasks/039.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the end-to-end case failing before the service exists and passing after.
- `git diff --stat recovery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `gui/blueprint_dialog.lua`
- `logic/bp/generation.lua`
- `logic/engine_test_api.lua`
- `tests/test_blueprint_pipeline.lua`
- `tests/test_engine_test_api.lua`
- `tests/test_bp_settings.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does one Generate click, on a real calculated sheet, end with a blueprint in the player's hand?
