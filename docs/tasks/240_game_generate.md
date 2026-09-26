# 240_game_generate a sheet calculates and its blueprint reaches the cursor through the real job system

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-240`, branch `lane/240`,
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

The first headless run found the blueprint never reached the cursor in the real game (empty icon list refused) —
the fake Factorio let it pass. This file drives the whole player path in the real game: type a target, compute,
press Generate, wait for the job, get the blueprint in hand, build it. Measured on round-42-base (legalcopilot-dev,
2026-09-26): red science 1/s generates and delivers headless in 5.6-6.4 s on 2.0.77 and 2.1.20. Green science
generation is NOT a target (it fails `BP_FAIL_NO_LAYOUT` after 315 s; open item) — green is only calculated.

## What to build

`tests/game/test_generate.lua` (replace the stub), one `describe("generate", ...)` with these `it` names exactly.
Bind recipes with `S.bind("item/<name>", "<name>")` for every product in the chain before calculating.
1. `red and green calculate` — two rows: automation-science-pack 1/s, logistic-science-pack 1/s; calculate; wait
   for report rows; rows > 0.
2. `generate button delivers to cursor` — red 1/s only (clear row 2 first or use a new sheet); calculate; open the
   dialog with `BlueprintDialog.open(1, sheet)` (`require "gui.blueprint_dialog"` at top), click
   `hxrrc_blueprint_generate_button` through `event_handlers.on_gui_click`; wait until
   `storage[1].blueprint_job == nil` (max 36000 ticks); cursor holds a set-up blueprint;
   `#cursor_stack.get_blueprint_entities() > 0`.
3. `blueprint builds as ghosts` — same flow; outside `RRC_OFFLINE` call
   `cursor_stack.build_blueprint{surface = game.surfaces[1], force = "player", position = {200, 200},
   build_mode = defines.build_mode.forced}` and assert the returned ghost count equals the blueprint entity count;
   clean the built ghosts after (`surface.find_entities_filtered{area = ..., type = "entity-ghost"}` destroy).
4. `cancel mid-run stops the job` — `Generation.start{player_index = 1, sheet_id = ..., deliver = true}`, after 1
   tick `Generation.cancel(1, id)`; state `cancelled`; `storage[1].blueprint_job == nil`; 600 more ticks with no
   error; cursor empty.
5. `progress caption shows percent only` — while a job runs, `Sheet.progressbar_of(sheet).caption` (read
   `tests/test_progress_view.lua` for its form) contains a percent and no phase words.
6. `busy cursor keeps result pending then retry delivers` — hold `iron-plate` in the cursor
   (`cursor_stack.set_stack{name = "iron-plate", count = 1}`), generate with deliver; after the job,
   `storage[1].blueprint_delivery ~= nil`; clear cursor; `BlueprintDelivery.retry(1)` (`require
   "gui.blueprint_delivery"` at top) returns true; cursor holds the blueprint.

## Files this lane owns

tests/game/test_generate.lua, docs/tasks/240_game_generate.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/240`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane240-owned", "command": "git diff --name-only round-42-base HEAD | grep -Ev '^(tests/game/test_generate\\.lua|docs/tasks/240_game_generate\\.md)$' | ( ! grep . ) && git diff --quiet round-42-base HEAD -- docs/tasks/240_game_generate.md && ! grep -q coroutine tests/game/test_generate.lua && ! grep -nE '^[[:space:]]+.*[^_[:alnum:]]require[[:space:]]*[(\"]' tests/game/test_generate.lua && for t in test_no_item_names test_no_runtime_require test_locale_keys test_game_runner_guard; do timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane240-owned-ok", "expect_exit": 0, "expect_regex": "lane240-owned-ok", "timeout_s": 900}
{"name": "lane240-offline", "command": "out=$(timeout 900 lua5.2 tests/game/offline.lua tests/game/test_generate.lua 2>&1); echo \"$out\" | tail -3; for n in 'red and green calculate' 'generate button delivers to cursor' 'blueprint builds as ghosts' 'cancel mid-run stops the job' 'progress caption shows percent only' 'busy cursor keeps result pending then retry delivers'; do echo \"$out\" | grep -qF \"PASS generate > $n\" || { echo MISSING $n; exit 1; }; done && echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane240-ok", "expect_exit": 0, "expect_regex": "lane240-ok", "timeout_s": 1200}
```

# bound: 2700s
