# 009 — recipe setups back to what a new player starts with

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-009`, branch `lane/009`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/reset.lua`, `logic/player_data.lua` and `tests/test_reset.lua`.
- `tests/test_player_data.lua` stays green unmodified; it pins today's initialization.
- Never call `PlayerData.initialize_player_data`: it assigns `storage[player_index] = {}` and would destroy the GUI handles `calculator` and `sheet_section`.
- Targets, tabs, rates, units, qualities, display preferences, solver options and blueprint settings all survive a reset.
- One player only. Another player's data, results and jobs are untouched.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/reset.lua` carries the stubs `Reset.run(player_index)`, `Reset.forget_player(player_index)` and `Reset.on_reset_clicked(event)`. `gui/calculator.lua` already builds `hxrrc_reset_setups_button` and calls the handler; `control.lua` already calls `Reset.forget_player` when a player is removed.
- The initializers are in `logic/player_data.lua`: `initialize_chosen_crafting_machines` (`:6`, local), `initialize_module_setups` (`:14`, local) and `PlayerData.initialize_recipe_bindings` (`:22`, exported). The two locals must be exported for reuse; that is why this lane owns the file.
- What a reset clears, all under `storage[player_index]`: `identifiers_of_chosen_crafting_machines_by_recipe_name`, `module_setups_by_recipe_name`, `recipes_by_product_full_name`, `product_full_names_by_recipe_name`, `consumer_product_full_names`, `burners_by_product_full_name`, `quality_loops_by_key`.
- `logic/player_data_updater.lua:86-96` `PlayerDataUpdater.reinitialize` shows the order that matters: machines, then bindings, then burners, then module setup migration and sanitation, then quality loops.
- `logic/jobs.lua` (wave 1) gives `Jobs.forget_player`, `Jobs.request_all_sheets` and `Jobs.cancel`. `storage[player_index].config_revision` is the revision a job compares against before it commits (`docs/feature-contracts.md` §4).
- `gui/module_picker.lua:187-197` `ModulePicker.forget_player` and `storage[player_index].pipette` and `.pipette_requests` are the copied-setup state a reset must drop, or an old paste could put a cleared setup back.
- Locale keys exist: `reset_setups_button`, `reset_setups_tooltip`, `reset_setups_confirm`, `reset_setups_done`.

## What to build

1. `Reset.run(player_index)` invalidates that player's queued and running work first, advances `config_revision`, closes the module picker, drops pipette state and pending pastes, then re-runs the three initializers, then queues every sheet for recalculation with the visible one first.
2. A result computed before the reset can never commit afterwards: the revision it carries no longer matches.
3. Export both initializers from `logic/player_data.lua` without changing what they do; `PlayerData.initialize_player_data` keeps calling them.
4. `Reset.on_reset_clicked` runs it for the clicking player and reports completion.
5. Red-first cases in `tests/test_reset.lua`: several sheets with customized recipes, machines, modules, beacon groups and quality loops all return to defaults while every target row, tab, rate and unit survives; a recipe that initialization binds automatically is bound again rather than left blank; a second player's setups, sheets and jobs are untouched; a reset during a running calculation prevents that calculation from committing; a pending pipette paste cannot restore a cleared setup; two resets in a row leave the same state; a reset with an empty sheet and with a missing prototype does not crash; `storage[player_index].calculator` and `.sheet_section` survive; blueprint settings and the round-up option survive.
6. Planted breach, pasted red then reverted: skip the revision bump, and the "old work cannot commit" case must go red.

## What done mean

```checks
{"name": "reset-tests", "command": "lua5.2 tests/test_reset.lua && lua5.4 tests/test_reset.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/009.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/reset.lua; git -C \"$S\" checkout wave-1-green -- logic/player_data.lua; out=$(cd \"$S\" && lua5.2 tests/test_reset.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/reset.lua`
- `logic/player_data.lua`
- `tests/test_reset.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: after a reset, can a calculation that started before it still commit, and does every target row survive?
