# 005 — the window that shows the debug string

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-005`, branch `lane/005`, base = `feat/round-8-blueprints` `4569c48ca39995d321f26ec11403fb273e7a194a` (tag `wave-0-spine`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `gui/export_dialog.lua` and `tests/test_export_dialog.lua` only.
- `gui/sheet.lua` already builds the Export debug button and calls `ExportDialog.on_export_clicked(event)`. Keep that name and signature.
- Opening, reading or closing this dialog changes nothing on the sheet: no recompute, no repair, no stored setting.
- Two children of one parent may never share a name; the engine refuses it and the harness refuses it too.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `gui/export_dialog.lua` carries the stubs `open`, `close`, `is_open`, `on_export_clicked`, and `ExportDialog.FRAME_NAME = "hxrrc_export_dialog"`.
- The payload builder is another lane's file (`logic/export_payload.lua`, W2-payload). It exists as a stub whose `ExportPayload.encode(payload)` returns `nil, "not implemented"`. Call it through `require "logic.export_payload"` and handle both outcomes; your tests inject their own builder rather than depending on that lane.
- `gui/module_picker.lua:201-257` is the modal to copy: a frame on `player.gui.screen`, `auto_center = true`, a scroll pane with a bounded height, a right-aligned footer flow, and `player.opened = frame`.
- `control.lua:85-96` closes a mod frame on `on_gui_closed` and guards the calculator against a child dialog stealing its close. A new modal must be handled there, so if your dialog needs a change in `control.lua`, stop and report it rather than editing it.
- Never open a GUI inside an `on_gui_closed` handler; `storage.opened_restores` and `ModulePicker.run_restores()` exist because the engine refuses it.
- The harness serves `text-box` with `word_wrap`, `read_only`, `selectable`, the methods `select_all` and `focus`, and the readers `H.text_selected(element)` and `H.text_focused(element)`.
- Locale keys already exist: `export_dialog_title`, `export_select_all`, `export_close`, `export_explanation`, `export_encoding_failed`, and `export_state_not_computed`, `_current`, `_pending`, `_stale`, `_failed`.

## What to build

1. `ExportDialog.open(player_index, sheet_flow)` builds a frame holding a scrollable, selectable, read-only text box with the whole string, a label saying which state the sheet is in, an explanation that the string is not a blueprint, and a footer with Select all and Close.
2. Select all selects the whole text so a keyboard copy takes everything; no clipboard write is attempted.
3. When encoding failed, the dialog says so and shows no string at all. A truncated string is never presented as valid.
4. `close` destroys the frame and clears its stored handle; `is_open` answers honestly; opening twice never builds a second frame; a sheet being deleted or a player being removed leaves nothing behind.
5. Red-first cases in `tests/test_export_dialog.lua`: the dialog opens with the string in a read-only selectable box; Select all marks the whole text; Close destroys it; opening twice keeps one frame; an encode failure shows the failure message and no box; the sheet's report and its controls are untouched before and after; the state label follows the snapshot state it was given; the dialog carries no two children of one parent with one name.
6. Planted breach, pasted red then reverted: return the string even when encoding reported failure, and the failure case must go red.

## What done mean

```checks
{"name": "export_dialog-tests", "command": "lua5.2 tests/test_export_dialog.lua && lua5.4 tests/test_export_dialog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base 4569c48ca39995d321f26ec11403fb273e7a194a --manifest docs/tasks/005.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout 4569c48ca39995d321f26ec11403fb273e7a194a -- gui/export_dialog.lua; out=$(cd \"$S\" && lua5.2 tests/test_export_dialog.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat 4569c48ca39995d321f26ec11403fb273e7a194a HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `gui/export_dialog.lua`
- `tests/test_export_dialog.lua`

Touch nothing else.

# bound: 5400s

Reviewer ask: does a failed encode show a failure and no text box, and does opening or closing the dialog leave the sheet exactly as it was?
