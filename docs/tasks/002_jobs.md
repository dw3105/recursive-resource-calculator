# 002 — work that survives a tick, a save and a cancel

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-002`, branch `lane/002`, base = `feat/round-8-blueprints` `4569c48ca39995d321f26ec11403fb273e7a194a` (tag `wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/jobs.lua` and `tests/test_jobs.lua` only.
- `control.lua` already calls `Jobs.on_tick(event)`, `Jobs.forget_player(index)` and `Jobs.invalidate_all(reason)`, and `async_calls[3]` is `Jobs.step`. Keep those names and signatures.
- The legacy queue in `control.lua` (`storage.computation_stack`) stays exactly as it is. You add beside it; you do not replace it.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/jobs.lua` carries the storage layout and the job shape at the top, plus stubs `request_sheet`, `request_all_sheets`, `on_tick`, `step`, `cancel`, `forget_player`, `invalidate_all`, `progress_of`, and `Jobs.OPS_PER_TICK`.
- `control.lua:127` is the existing on_tick: it drains one legacy entry per tick, then calls `ModulePicker.run_restores()`, then `Jobs.on_tick(event)`.
- `control.lua` also resets `storage.computation_stack` and calls `Jobs.invalidate_all("configuration_changed")` on a configuration change, and `Jobs.forget_player` when a player is removed.
- Factorio has no coroutines: a job is an explicit phase plus a cursor, held in `storage`, advanced a slice at a time.
- `H.run_ticks(world, n)` (`tests/harness.lua`) advances the tick and fires the mod's own registered on_tick n times. Drive every job through it; calling `Jobs.step` directly in a test proves nothing about the scheduler.
- There is no real work to run yet: lane W3-calc supplies the calculation pipeline and W4-search the blueprint search. Test with an injected fake job kind, and expose exactly the seam you need for that (a registry of kind to step function is fine, as long as nothing of it is stored in `storage`).

## What to build

1. A job store under `storage[player_index].calc_jobs[sheet_id]` and `storage[player_index].blueprint_job`, created lazily and read defensively, so a save from before this round does not crash.
2. `Jobs.request_sheet(player_index, sheet_id, context)` queues work for one sheet and replaces any pending job for that same sheet rather than stacking: rapid edits must coalesce, never pile up. `Jobs.request_all_sheets` queues every sheet of one player, the visible one first.
3. `Jobs.on_tick(event)` spends one deterministic budget per tick across every player. Calculations are served before blueprint work; service between players is fair and follows a stored cursor, so one player cannot starve another and a disconnected player cannot hold the queue. The budget is a fixed number of operations, never a wall-clock measurement: two machines in a multiplayer game must do the same work in the same tick.
4. `Jobs.cancel(player_index, sheet_id)` stops a job within two ticks of the handler that asked, publishes nothing, and cannot be undone by a duplicate request of the same revision arriving in the same tick.
5. `Jobs.forget_player` drops everything of one player; `Jobs.invalidate_all(reason)` drops every job everywhere and records the reason on the sheets involved.
6. `Jobs.progress_of(player_index, sheet_id)` returns the phase and the fraction, or nil when nothing runs. The fraction never reaches 1 before the job is done.
7. Red-first cases in `tests/test_jobs.lua`: a job advances only when ticks run; the same fixture finished with a budget of one operation per tick and with a huge budget commits the same result; a second request for one sheet replaces the first rather than queueing two; cancel stops within two ticks and publishes nothing; a cancelled job is not restarted by a duplicate request at the same revision; two players both make progress, and neither can be starved; a removed player's jobs vanish; a configuration change invalidates everything; nothing reachable from `storage` is a function or a LuaObject (walk it); progress stays below 1 until done.
8. Planted breach, pasted red then reverted: make the budget per player instead of shared, and the fairness case must go red.

## What done mean

```checks
{"name": "jobs-tests", "command": "lua5.2 tests/test_jobs.lua && lua5.4 tests/test_jobs.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base 4569c48ca39995d321f26ec11403fb273e7a194a --manifest docs/tasks/002.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- logic/jobs.lua; out=$(cd \"$S\" && lua5.2 tests/test_jobs.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat 4569c48ca39995d321f26ec11403fb273e7a194a HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/jobs.lua`
- `tests/test_jobs.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: with a budget of one operation per tick, does the same fixture commit exactly what a huge budget commits, and does cancel stop inside two ticks without publishing?
