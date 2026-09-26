# 241_game_parity the real engine builds the same blueprint as the offline generator for two golden sheets

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-241`, branch `lane/241`,
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

Every layout number we ship comes from the offline generator (`tests/golden/generate.lua`). The player runs the
mod in the real game. This file proves both give the same blueprint: the in-game blueprint string, decoded, has
exactly the entity lines `tools/game_expect.sh` wrote offline (`tests/game/expected/<case>.txt`). Measured on
round-42-base (legalcopilot-dev, 2026-09-26): red science 1/s matches all 148 lines headless on 2.0.77 and 2.1.20.

## What to build

`tests/game/test_parity.lua` (replace the stub), one `describe("parity", ...)` with these `it` names exactly.
Fixtures (top-level requires): `tests.game.fixtures.player_red_science_1s`, `..._1s_expected`,
`tests.game.fixtures.player_red_science_1s_bulk`, `..._1s_bulk_expected`. Copy the probe's call:
`Generation.start{player_index = 1, sheet_id = S.sheet_id(S.first_sheet()), prepared_input = p, settings =
p.settings, options = p.options, deliver = false}`.
1. `red 1s matches offline via Generation` — 148 lines equal, line by line (report first differing line).
2. `red 1s bulk matches offline via Generation` — 104 lines equal.
3. `red 1s matches offline via rrc-engine-test` — `remote.call("rrc-engine-test", "start_generation", {sheet_id =
   ..., prepared_input = p, settings = p.settings, options = p.options})` returns an id; poll
   `remote.call("rrc-engine-test", "generation_status", id)` until `state ~= "pending"`; `success`;
   `blueprint_string` lines equal expected; `canonical_sha256` is a 64-hex string.
4. `canonical is stable` — `remote.call("rrc-engine-test", "canonical", s)` twice on the same string: equal results
   (compare with `assert.are_same`), not nil.
5. `build id is packaged` — `remote.call("rrc-engine-test", "build_id").packaged == true`; outside `RRC_OFFLINE`
   also `candidate_sha` is 40 hex chars and `factorio_branch` is `"2.0"` or `"2.1"`.

## Files this lane owns

tests/game/test_parity.lua, docs/tasks/241_game_parity.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/241`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane241-owned", "command": "git diff --name-only round-42-base HEAD | grep -Ev '^(tests/game/test_parity\\.lua|docs/tasks/241_game_parity\\.md)$' | ( ! grep . ) && git diff --quiet round-42-base HEAD -- docs/tasks/241_game_parity.md && ! grep -q coroutine tests/game/test_parity.lua && ! grep -nE '^[[:space:]]+.*[^_[:alnum:]]require[[:space:]]*[(\"]' tests/game/test_parity.lua && for t in test_no_item_names test_no_runtime_require test_locale_keys test_game_runner_guard; do timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane241-owned-ok", "expect_exit": 0, "expect_regex": "lane241-owned-ok", "timeout_s": 900}
{"name": "lane241-offline", "command": "out=$(timeout 900 lua5.2 tests/game/offline.lua tests/game/test_parity.lua 2>&1); echo \"$out\" | tail -3; for n in 'red 1s matches offline via Generation' 'red 1s bulk matches offline via Generation' 'red 1s matches offline via rrc-engine-test' 'canonical is stable' 'build id is packaged'; do echo \"$out\" | grep -qF \"PASS parity > $n\" || { echo MISSING $n; exit 1; }; done && echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane241-ok", "expect_exit": 0, "expect_regex": "lane241-ok", "timeout_s": 1200}
```

# bound: 2700s
