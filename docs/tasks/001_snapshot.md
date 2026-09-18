# 001 — a sheet as plain data

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-001`, branch `lane/001`, base = `feat/round-8-blueprints` `4569c48ca39995d321f26ec11403fb273e7a194a` (tag `wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/snapshot.lua` and `tests/test_snapshot.lua` only.
- Never write to the sheet, never solve, never repair. This module reads.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/snapshot.lua` carries the exact shape at the top of the file, plus stubs `Snapshot.of_sheet(sheet_flow)`, `Snapshot.fingerprint(snapshot)`, `Snapshot.state_of(snapshot, result_fingerprint, job_running)`.
- `gui/sheet.lua:Sheet.read_inputs(sheet_flow)` already returns `{sheet_id, player_index, rates, product_parts, options = {start_leftovers, round_up}, empty}` without solving. Use it rather than reading the GUI elements again.
- `gui/sheet.lua:Sheet.id_of(sheet_flow)` reads the sheet's stable id from its tags.
- `gui/input_container.lua:118` `target_of` and `:143` `get_desired_production_rates_by_full_item_name` show how a row becomes a full name and a rate. A full name is `item/x`, `fluid/x`, or `QualityId.encode(name, quality)` (`logic/quality_id.lua:6`) above normal quality.
- Per-player setup lives in `storage[player_index]`: `identifiers_of_chosen_crafting_machines_by_recipe_name`, `module_setups_by_recipe_name`, `recipes_by_product_full_name`, `product_full_names_by_recipe_name`, `consumer_product_full_names`, `burners_by_product_full_name`, `quality_loops_by_key` (`logic/player_data.lua:6-41`). A stored recipe is a LuaRecipePrototype; carry its `.name`, never the object.
- `logic/module_setup.lua:241` `ModuleSetup.signature(setup, machine_identifier)` is a length-prefixed staleness token already used in GUI tags. Reuse it; plain name concatenation lets two different setups collide.
- `storage[player_index].config_revision` and `.sheet_revision[sheet_id]` may be absent in an older save. Treat absent as 0 and never create them here.
- `H.fill_sheet(targets)` returns `sheet_pane, sheet_flow`. The harness reports mocked LuaObjects as `type(x) == "userdata"`.

## What to build

1. `Snapshot.of_sheet` returns the documented shape. `targets` in UI order with `index`, `full_name`, `type`, `name`, `quality` (always a string, `"normal"` when none), `raw_text` as typed, `time_unit`, `rate_per_second` at full precision or nil, `valid`, `reason`. `options` carries `round_up` and `start_leftovers` (nil on 2.1, where the control is not built). `selection` carries, per bound recipe, the recipe name, machine identity and quality, ordered module slots, and beacon groups with type, quality, count, sharing and modules. An explicitly unselected binding is recorded as unselected rather than omitted: "nothing chosen" and "never looked at" are different facts. An empty sheet gives `targets = {}`, never nil.
2. `Snapshot.fingerprint` is stable over everything that decides what would be solved. Build it from length-prefixed parts, so two different structures cannot produce one string.
3. `Snapshot.state_of` returns `not_computed`, `pending`, `failed`, `current` or `stale`, and never repairs anything.
4. Red-first cases in `tests/test_snapshot.lua`: two targets keep order, text, unit and full precision; a quality target carries its parts; an unusable rate gives `valid = false` with a reason and no rate; an empty sheet gives an empty list; the selection carries machine, quality, ordered modules and a beacon group with count and sharing; an unselected binding is present and marked; a walk over the whole snapshot finds no value whose `type` is `"userdata"`; the same unchanged sheet fingerprints equal twice while changing a rate, a unit, a module, a beacon count or the round-up option changes it; all five states, including stale versus current.
5. Planted breach, pasted red then reverted: drop the module list from the fingerprint, and the module case must go red.

## What done mean

```checks
{"name": "snapshot-tests", "command": "lua5.2 tests/test_snapshot.lua && lua5.4 tests/test_snapshot.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base 4569c48ca39995d321f26ec11403fb273e7a194a --manifest docs/tasks/001.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- logic/snapshot.lua; out=$(cd \"$S\" && lua5.2 tests/test_snapshot.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat 4569c48ca39995d321f26ec11403fb273e7a194a HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/snapshot.lua`
- `tests/test_snapshot.lua`

Touch nothing else.

# bound: 5400s

Reviewer ask: does an unchanged sheet fingerprint the same twice while a changed module, beacon count or unit changes it, and can a stale result never be labelled current?
