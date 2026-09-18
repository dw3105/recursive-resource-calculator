# 017 — what the blueprint is built out of

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-017`, branch `lane/017`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/settings.lua`, `gui/blueprint_dialog.lua` and `tests/test_bp_settings.lua`.
- `gui/sheet.lua` is frozen; it already calls `BlueprintDialog.on_generate_clicked(event)`.
- A belt choice carries its family. A modded belt with no known family is refused, never swapped for a vanilla tier.
- Settings belong to one sheet. Changing one sheet never changes another.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/settings.lua` carries the shape and the stubs `Settings.of_sheet`, `Settings.store`, `Settings.validate`, `Settings.belt_family`, plus `Settings.EDGES` and the two defaults (left in, top out).
- `gui/blueprint_dialog.lua` carries `BlueprintDialog.open`, `close`, `is_open`, `on_generate_clicked` and `FRAME_NAME = "hxrrc_blueprint_dialog"`.
- `logic/catalog.lua` (wave 1) resolves a prototype and its quality-dependent numbers. Ask it rather than reading prototypes here where you can.
- Storage key: `storage[player_index].blueprint_settings[sheet_id]` (`docs/feature-contracts.md` §4). Seed a new sheet from the player's last choices, never from another sheet's current ones.
- Locale keys exist: `blueprint_dialog_title`, `blueprint_generate`, the six `blueprint_infra_*`, `blueprint_edge_input`, `blueprint_edge_output`, and the four `blueprint_edge_*` names.
- Reason codes for a refused choice: `BP_REJ_OPTION_PROTOTYPE_MISSING`, `BP_REJ_BELT_FAMILY_MISSING`, `BP_REJ_EDGES_EQUAL`, `BP_REJ_QUALITY_UNAVAILABLE` (`logic/bp/reason_codes.lua`).
- `gui/module_picker.lua:201-257` is the modal pattern; `control.lua:85-96` handles closing, and it is frozen, so report anything it needs rather than editing it.

## What to build

1. `Settings.of_sheet` returns the sheet's stored choices or the defaults; `Settings.store` keeps them per sheet.
2. `Settings.validate` refuses a choice the game cannot honour and returns its reason code and subject: a missing prototype, a locked quality, equal edges, a belt with no family.
3. `Settings.belt_family` derives the underground belt and splitter at the belt's own quality, and returns nil when none is known.
4. The dialog shows the six infrastructure choices and the two edges, keeps the player's overrides, and refuses to generate while a choice is invalid, naming what is wrong.
5. Red-first cases in `tests/test_bp_settings.lua`: defaults are left in and top out; an override survives a close and reopen; two sheets keep separate settings; a new sheet seeds from the last choices; a belt yields its family at the chosen quality; a belt with no family is refused with `BP_REJ_BELT_FAMILY_MISSING` and nothing is substituted; equal edges are refused; a locked quality is refused; a missing prototype is refused; the dialog opens once, closes cleanly and leaves the sheet untouched.
6. Planted breach, pasted red then reverted: fall back to the vanilla belt family when none is known, and the family case must go red.

## What done mean

```checks
{"name": "bp_settings-tests", "command": "lua5.2 tests/test_bp_settings.lua && lua5.4 tests/test_bp_settings.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/017.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/settings.lua; git -C \"$S\" checkout wave-2-green -- gui/blueprint_dialog.lua; out=$(cd \"$S\" && lua5.2 tests/test_bp_settings.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/settings.lua`
- `gui/blueprint_dialog.lua`
- `tests/test_bp_settings.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: is a modded belt with no known family refused rather than silently replaced by a vanilla tier?
