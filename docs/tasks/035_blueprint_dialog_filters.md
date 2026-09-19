# 035 — aligned rows, and a picker that offers one category

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-035`, branch `lane/035`, base = `feat/round-8-blueprints`, tag `wave-4-gui-base` (resolve it with `git rev-parse wave-4-gui-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. The dialog shipped in 1.1.41. The player reports two defects, both visible in the screenshots: the six rows do not align, and every picker offers every entity in the game, so choosing a belt means hunting through hundreds of icons.

## What is true

**PRESERVE:**
- You own `gui/blueprint_dialog.lua` and `tests/test_bp_settings.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report. `logic/bp/settings.lua` is **not** yours this time: the validation rules are already right, only the window is wrong.
- Every existing case in `tests/test_bp_settings.lua` stays. You add; you never weaken or delete.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c).
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- `gui/blueprint_dialog.lua:110-121` builds each infrastructure row as its own `flow`, so every label sets its own width and the six icons land at six different x positions. The two edge rows below already use a `table` with `column_count = 2` (`:137`) and do line up.
- `gui/blueprint_dialog.lua:113-119` adds each `choose-elem-button` with `elem_type = "entity-with-quality"` and **no `elem_filters`**, so the picker opens on every entity prototype in the game. The player's screenshot shows hundreds of unrelated entities under one category.
- `elem_filters` is a real member of `LuaGuiElement` on 2.0.77 and 2.1.19 (`docs/api/2.0.77.members.json`), and `type` is a real `EntityPrototypeFilter`. The harness now accepts every filter name that page lists (`tests/harness.lua`, `FILTER_NAMES_BY_ELEM_TYPE`).
- The categories and their entity types: `roboport` -> `roboport`, `pole` -> `electric-pole`, `belt` -> `transport-belt`, `inserter` -> `inserter`, `pipe` -> `pipe`, `underground_pipe` -> `pipe-to-ground`. The same six keys are listed in `logic/bp/settings.lua:17-24`.
- A belt choice carries its family, and an orphan belt is refused with `BP_REJ_BELT_FAMILY_MISSING`. Filtering the picker never replaces that check: a modded belt with no splitter still has to be refused.
- `LuaStyle.column_alignments` exists on a `table` element only, and its entries are writable by index (`tests/harness.lua:570-586`).

## What to build

1. Put the six infrastructure rows in one `table` with `column_count = 2`, so every label shares one column and every picker shares the next. Keep each element's existing name, because the handlers and the tests find them by name.
2. Put the two edge rows in that same table, so all eight rows align on one grid.
3. Give every picker its `elem_filters`, one `{filter = "type", type = "<entity type>"}` per category, using the mapping above.
4. Keep the error label and the footer where they are; the footer buttons stay right-aligned.
5. Add cases: each picker carries exactly the filter its category needs; the rows live in one table whose `column_count` is 2; every element keeps the name it had, proved by opening the dialog and reading the same names the existing cases use.
6. Add a case that a filtered picker still refuses an invalid choice: a belt without a splitter yields `BP_REJ_BELT_FAMILY_MISSING` and the dialog stays open, as `tests/test_bp_settings.lua:104` already proves.
7. Name new cases in the existing `BP<n>` sequence, continuing after the highest one in the file.

## What done mean

```checks
{"name": "settings-tests", "command": "lua5.2 tests/test_bp_settings.lua && lua5.4 tests/test_bp_settings.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-gui-base --manifest docs/tasks/035.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case red against the current window, then green.
- `git diff --stat wave-4-gui-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `gui/blueprint_dialog.lua`
- `tests/test_bp_settings.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does the belt picker offer belts alone, and do all eight rows share one grid?
