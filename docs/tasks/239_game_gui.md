# 239_game_gui the calculator GUI opens, edits and closes on the real engine without an error

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-239`, branch `lane/239`,
base tag `round-42-base`, merge target `int/r42`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run headless Factorio of any kind**: never `tools/game_test.sh`, `tools/game_load_check.sh`, `factorio`,
`factorio-test`, `npx`. They refuse inside a lane anyway. **NEVER run `tests/run.sh`, `suite_parallel.sh`,
`tools/measure_sheet.sh`, `tools/game_expect.sh`, `tests/golden/generate.lua` or any full suite of any kind.**
Your only runner: `lua5.2 tests/game/offline.lua tests/game/<your file>.lua ["<describe> > <it>"]` (the mock,
seconds), plus single guard files `lua5.2 tests/<guard>.lua`. lua5.2 ONLY. Never use `coroutine`.

Game test rules (FactorioTest; the integrator runs your file headless on Factorio 2.0.77 and 2.1.20 after merge):
- `require` ONLY at file top level; never inside `describe`, `it`, `before_each` or any function (the game refuses).
- Use `tests/game/support.lua` helpers (`S.first_sheet`, `S.fill_row`, `S.bind`, `S.calculate`, `S.report_rows`,
  `S.wait_until`, `S.generation_state`, `S.entity_lines`, `S.find`); read `tests/game/test_probe.lua` first — it is
  green headless on both versions and shows every pattern. Never change `support.lua`, `offline.lua`, `index.lua`.
- Waits: `S.wait_until(pred, max_ticks, then_fn, what)` (on_tick based). Assertions: `assert.are_equal(want, got,
  msg)`, `assert.is_true`, `assert.is_nil`, `assert.is_not_nil`, `assert.are_same`, `assert.has_error`.
- Tests share one game: leave the player's cursor empty and the calculator closed at the end of each test
  (`after_each`).
- Engine-only calls the mock lacks: guard with `if not RRC_OFFLINE then ... end` (the shim sets it; the game never
  does). Keep the assertion itself outside the guard whenever the mock supports it.
- Real item names ARE allowed in tests/game (only logic/, gui/, control.lua forbid them).
- You may NOT change RRC code. A real RRC bug you find: keep the test, rename it `it.skip("rrc bug: <what>", ...)`,
  and write the bug in your last commit message. The integrator fixes it.

## Explain very simply

Until now every GUI test ran on a fake Factorio. The fake missed real engine rules before (duplicate element names
crashed 1.1.15; a userdata check broke paste in 1.1.27). This file drives the real calculator GUI in the real game.
The integrator runs it headless after merge; you prove it on the mock.

## What to build

`tests/game/test_gui.lua` (replace the stub), one `describe("gui", ...)` with these `it` names exactly:
1. `toggle opens and closes twice` — `Calculator.toggle(game.players[1])` x4, `storage[1].calculator.visible`
   flips each time; ends closed.
2. `new sheet tab and delete` — click `hxrrc_new_sheet_button` through `event_handlers.on_gui_click[...]` with the
   real element (find it with `S.find(storage[1].calculator, "hxrrc_new_sheet_button")`); tab count +1; select it;
   click `hxrrc_delete_sheet_button`; tab count back.
3. `every sheet cell button responds` — on the first sheet, for export (`Sheet.export_button_of`), blueprint
   (`Sheet.blueprint_button_of`) and cancel (`Sheet.cancel_button_of`): element valid and `name` set; clicking the
   blueprint button opens the blueprint dialog (`require "gui.blueprint_dialog"` at top, `.is_open(1)` true), its
   close button (`hxrrc_blueprint_close_button`) closes it.
4. `no duplicate sibling names` — walk `storage[1].calculator` recursively; in every element, non-empty child names
   are unique.
5. `module picker opens and closes` — after `S.bind` + `S.fill_row` + `S.calculate` of automation-science-pack 1/s
   and waiting for report rows, find a `hxrrc_choose_module_button` in the report, fire
   `event_handlers.on_gui_elem_changed["hxrrc_choose_module_button"]` with `elem_value = "speed-module"`; no error;
   then close the calculator.
6. `removed player data is dropped` — only if the mock supports `on_player_removed` offline; otherwise assert
   `storage[1]` survives a toggle cycle (`it.skip` is NOT allowed here).

## Files this lane owns

tests/game/test_gui.lua, docs/tasks/239_game_gui.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/239`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane239-owned", "command": "git diff --name-only round-42-base HEAD | grep -Ev '^(tests/game/test_gui\\.lua|docs/tasks/239_game_gui\\.md)$' | ( ! grep . ) && git diff --quiet round-42-base HEAD -- docs/tasks/239_game_gui.md && ! grep -q coroutine tests/game/test_gui.lua && ! grep -nE '^[[:space:]]+.*[^_[:alnum:]]require[[:space:]]*[(\"]' tests/game/test_gui.lua && for t in test_no_item_names test_no_runtime_require test_locale_keys test_game_runner_guard; do timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane239-owned-ok", "expect_exit": 0, "expect_regex": "lane239-owned-ok", "timeout_s": 900}
{"name": "lane239-offline", "command": "out=$(timeout 600 lua5.2 tests/game/offline.lua tests/game/test_gui.lua 2>&1); echo \"$out\" | tail -3; for n in 'toggle opens and closes twice' 'new sheet tab and delete' 'every sheet cell button responds' 'no duplicate sibling names' 'module picker opens and closes' 'removed player data is dropped'; do echo \"$out\" | grep -qF \"PASS gui > $n\" || { echo MISSING $n; exit 1; }; done && echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane239-ok", "expect_exit": 0, "expect_regex": "lane239-ok", "timeout_s": 900}
```

# bound: 2700s
