# 038 — the export window works like the game's own blueprint-string window

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-038`, branch `lane/038`, base = `feat/round-8-blueprints`, tag `wave-5-export-base` (resolve it with `git rev-parse wave-5-export-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

The player compared the two windows side by side and asked for ours to behave like the game's. Two screenshots are
the specification: `~/share/RRC/Screenshot 2026-09-19 094341.png` is ours, `~/share/RRC/Screenshot 2026-09-19 094437.png`
is the game's.

## What is true

**PRESERVE:**
- You own `gui/export_dialog.lua` and `tests/test_export_dialog.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report. The locale keys you need already exist.
- Every existing case in `tests/test_export_dialog.lua` stays. You add; you never weaken or delete.
- `require` runs only while `control.lua` is parsed. Never call it inside a function.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game; ask `rawget(_G, "prototypes")`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

What the two windows do differently, read from the screenshots and from the file:
- The game's window opens with the whole string already **selected**, so CTRL + C works with no click. Ours opens with nothing selected: selecting happens only when the player presses the Select all button, `gui/export_dialog.lua:231-236`.
- The game's text wraps at the right edge and scrolls **vertically**. Ours scrolls **horizontally**: the box carries `word_wrap = true` (`gui/export_dialog.lua:163`), but the payload is Base64 and holds no space, and a wrap point is a space, so one line runs off the edge.
- The game's footer holds one button, Copy, at the left. Ours holds Select all and Close at the right.
- `H.decode_export(text)` reads an encoded string back. Whitespace inside Base64 is discarded by every decoder used here, offline and in the tests, so a string broken across lines still decodes.

## What to build

1. The window opens with the text selected and focused, the way the game's does: call `select_all()` and `focus()` on the text box as the window is built, not only from a button.
2. Make the text wrap at the right edge instead of running off it. Try the engine first: a `maximal_width` on the box, or `word_wrap` with no fixed width. If the engine will not break a token with no space in it, insert a line break every 120 characters into the **displayed** text, keep the payload itself unbroken, and prove in a case that the displayed text decodes through `H.decode_export` once whitespace is dropped.
3. Rename the first button to Copy, key `hxrrc.export_copy`, keep it doing select-and-focus, and show the hint `hxrrc.export_copy_hint` when it is pressed. Both keys exist in `en`, `cs` and `ro`.
4. Keep a way to close the window: keep the Close button, or add the title-bar close the game's window uses. State which you chose in a comment.
5. Keep the state line ("this sheet has not been calculated" and its siblings) and the one-line explanation. Ours is not a blueprint string and the player must not paste it into the game.
6. Add cases: the box is selected when the window opens; the displayed text decodes; the Copy button shows the hint; the state line and explanation are still present; the failure path still shows the failure label and no box.

## What done mean

```checks
{"name": "export-dialog-tests", "command": "lua5.2 tests/test_export_dialog.lua && lua5.4 tests/test_export_dialog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "locale", "command": "lua5.2 tests/test_locale_keys.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 300}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-5-export-base --manifest docs/tasks/038.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case red against the current window, then green.
- `git diff --stat wave-5-export-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `gui/export_dialog.lua`
- `tests/test_export_dialog.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the window open with the whole string selected, and does the text wrap rather than run off the edge?
