# 027 — a finished blueprint reaches the player, or nothing changes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-027`, branch `lane/027`, base = `feat/round-8-blueprints`, tag `wave-3-green` (resolve it with `git rev-parse wave-3-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `gui/blueprint_delivery.lua` and `tests/test_blueprint_delivery.lua` only.
- The player's held item, inventory and world are untouched on every failure path. Build off cursor, never on it.
- Only a validated complete result is published. A failure or a cancel changes nothing at all.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `gui/blueprint_delivery.lua` carries the stubs `deliver(player_index, blueprint, metadata)`, `retry(player_index)` and `discard(player_index)`.
- The harness serves blueprint stacks: `world.add_blueprint_item()` creates the item, `game.create_inventory(n)` gives staging slots, and a stack carries `set_stack`, `clear`, `is_blueprint`, `is_blueprint_setup()` (a method), `set_blueprint_entities`, `get_blueprint_entities`, `label`, `preview_icons` and `blueprint_description`.
- `player.cursor_stack`, `player.cursor_ghost`, `player.cursor_record` and `player.clear_cursor()` are the cursor surface; `world.hold_item(index, name, quality, count)` and `world.hold_record` set one up in a test. `player.is_cursor_empty` is deliberately not modelled, so check what the cursor holds instead.
- `logic/bp/serialize.lua` produces the blueprint table and its metadata; `logic/bp/search.lua` produces the result that carries it.
- `player.opened` accepts an item stack, which is the basis for opening the blueprint in the game's own editor. Prove what you can offline and say plainly in the commit what only the game can confirm.

## What to build

1. `deliver` stages the blueprint in an inventory the player does not hold, fills its entities, label, icons and description, and only then hands it over.
2. When the cursor cannot take it, the finished result is kept and the player is told; nothing is dropped and no other blueprint is overwritten.
3. `retry` hands over a kept result; `discard` releases it.
4. Every failure path leaves the cursor exactly as it was.
5. Red-first cases in `tests/test_blueprint_delivery.lua`: delivery to an empty cursor gives a set-up blueprint with its entities, label and description; delivery while the player holds an item keeps that item and reports the cursor busy; a kept result is handed over by `retry` once the hand is empty; a failure mid-delivery leaves the cursor and the staging inventory clean; discard releases the result and a later retry reports nothing to deliver; a blueprint is never delivered twice; the staged stack is a blueprint and is set up before it is handed over.
6. Planted breach, pasted red then reverted: clear the cursor before staging, and the busy-cursor case must go red.

## What done mean

```checks
{"name": "blueprint_delivery-tests", "command": "lua5.2 tests/test_blueprint_delivery.lua && lua5.4 tests/test_blueprint_delivery.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-green --manifest docs/tasks/027.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-3-green -- gui/blueprint_delivery.lua; out=$(cd \"$S\" && lua5.2 tests/test_blueprint_delivery.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-3-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `gui/blueprint_delivery.lua`
- `tests/test_blueprint_delivery.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does a full hand ever lose its item, and is a result ever published twice?
