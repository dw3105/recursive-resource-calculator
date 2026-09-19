# 034 — the export box is readable and the whole string is reachable

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-034`, branch `lane/034`, base = `feat/round-8-blueprints`, tag `wave-4-gui-base` (resolve it with `git rev-parse wave-4-gui-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. The dialog shipped in 1.1.41 and the player reports it unusable: the text box is one line tall, narrower than the frame, and the string is clipped.

## What is true

**PRESERVE:**
- You own `gui/export_dialog.lua` and `tests/test_export_dialog.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_export_dialog.lua` stays. You add; you never weaken or delete.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c).
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, from the screenshot the player sent and from the file:
- `gui/export_dialog.lua:156-166` adds a `scroll-pane` with `style.maximal_height = 400` and a `text-box` inside it with no size at all. An element with no width takes its minimal size, so the box renders about one line high and a third of the frame wide, and the string is unreadable.
- The frame has no width either (`:140-147`), so the caption, the state label at `:149`, the explanation at `:174` and the footer at `:180` each set a different width and the dialog looks ragged.
- The state label reads `hxrrc.export_state_<state>`. On the player's sheet it said the sheet has not been calculated, and a string was still offered: that is correct, EX-04 requires an export from an uncalculated sheet. Do not remove it; make the two lines sit together as one explanation block.
- `H.decode_export(text)` in the harness reads the encoded string back, so a case can assert the box holds the whole payload rather than a prefix.
- LuaStyle in the harness is a writable table, so `element.style.width = 600` is assertable (`tests/harness.lua:570`).

## What to build

1. Give the text box a fixed readable size: at least 560 wide and 220 high, `word_wrap = true`, read-only and selectable as now.
2. Give the frame a minimal width so the caption, the state line, the explanation and the footer align on one left edge, and keep `auto_center = true`.
3. Keep the scroll-pane only if the box still needs it; if the box scrolls on its own, drop the pane rather than nesting two scrolls.
4. The explanation stays one readable paragraph under the box, never beside it.
5. Add cases: the text box carries the full encoded string, decodes through `H.decode_export`, and its style holds the width and height; the frame's width is set; the failure path still shows the failure label and no box.
6. Name them in the existing case sequence of that file.

## What done mean

```checks
{"name": "export-dialog-tests", "command": "lua5.2 tests/test_export_dialog.lua && lua5.4 tests/test_export_dialog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-gui-base --manifest docs/tasks/034.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case red against the current layout, then green.
- `git diff --stat wave-4-gui-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `gui/export_dialog.lua`
- `tests/test_export_dialog.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the box hold the whole string at a size a player can read and select?
