# 207_delivery delivery: the finished blueprint reaches the hand, or the player is told why

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-207_delivery`, branch `lane/207_delivery`,
base tag `round-35-base`, merge target `int/r35`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures, no metatables). Every unit test you write must finish in under 20 s (a real red job test may take up to
60 s) and loop over `H.shapes()` (Factorio 2.0 and 2.1). Tests move time ONLY with `H.run_ticks(world, n)` (it fires
on_tick and then nth-tick handlers, like the engine); never call `Registry.progress_refresh()` directly.

Read `docs/contracts/round35.md` first: it is the contract. Your clauses: D1, D2, D3, D4, D5.

## Explain very simply

Player (1.1.79, 2026-09-25): generation finished, no blueprint in the hand, no message. Measured on base with
`lua5.2 docs/tasks/deliver_probe.lua stale` (real red science job, `Generation.start{deliver=true}`, a stale
`storage[1].blueprint_delivery` record): `state=success`, hand empty. Three holes (contract C1-C3):
`logic/bp/generation.lua` publish skips the final when an interim existed; the interim path drops failures;
`gui/blueprint_delivery.lua` returns `blueprint_pending` forever because `BlueprintDelivery.retry` has no caller.
`control.lua` already registers `on_player_cursor_stack_changed` for `Pipette.on_cursor_changed`: chain yours after it
in one handler (Factorio keeps one handler per event).

## What to build

1. D1 final-only automatic delivery (interim stays an offer; `Generation.deliver_interim` keeps working).
2. D2 newest result replaces a stale pending record.
3. D3 busy hand → pending + note `blueprint_waiting_hand`; delivered on the cursor-changed event when the hand is empty.
4. D4 failure → note `blueprint_not_delivered` + button `hxrrc_copy_blueprint_string` opening a string box with the
   blueprint string (reuse the export dialog or the blueprint dialog text box; no new window style).
5. D5 export fields.
6. Locale keys (en/cs/ro) from the contract, appended at the end of the `[hxrrc]` section.
7. Tests (red at base first): new `tests/test_delivery_final.lua`, both shapes, real red job
   (pattern: `docs/tasks/deliver_probe.lua`): (a) interim came first → at success the hand holds the FINAL
   (`#get_blueprint_entities() == #status.result.entities`); (b) stale pending record before start → hand holds the
   final; (c) hand busy at success → note `blueprint_waiting_hand`, then `player.clear_cursor()` + the cursor event
   → hand holds the final; (d) `set_blueprint_entities` made to throw → note `blueprint_not_delivered`, copy button
   present, `status.state == "success"`. Extend `tests/test_export_payload.lua` for D5.

## Files this lane owns

gui/blueprint_delivery.lua, logic/bp/generation.lua, control.lua, gui/blueprint_dialog.lua, gui/export_dialog.lua, logic/export_payload.lua, locale/en/locale.cfg, locale/cs/locale.cfg, locale/ro/locale.cfg, tests/test_delivery_final.lua, tests/test_blueprint_delivery.lua, tests/test_export_payload.lua, tests/test_generation_interim.lua, tests/test_generation_controls.lua, docs/tasks/207_delivery.md, docs/tasks/deliver_probe.lua.
Never touch anything else.

## Commit, THEN check

Commit on `lane/207_delivery`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane207-tests", "command": "git diff --name-only round-35-base HEAD | grep -Ev '^(gui/blueprint_delivery\\.lua|logic/bp/generation\\.lua|control\\.lua|gui/blueprint_dialog\\.lua|gui/export_dialog\\.lua|logic/export_payload\\.lua|locale/en/locale\\.cfg|locale/cs/locale\\.cfg|locale/ro/locale\\.cfg|tests/test_delivery_final\\.lua|tests/test_blueprint_delivery\\.lua|tests/test_export_payload\\.lua|tests/test_generation_interim\\.lua|tests/test_generation_controls\\.lua|docs/tasks/207_delivery\\.md|docs/tasks/deliver_probe\\.lua)$' | ( ! grep . ) && ! git diff round-35-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_delivery_final test_blueprint_delivery test_generation_interim test_generation_controls test_job_flow test_control test_pipette test_export_payload test_export_dialog test_locale_keys test_update_stops_jobs; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && for c in player-red-science-1s player-green-science-1s player-inserter-10s; do sh tools/bytes_hash.sh $c | tail -1; done > /tmp/b$$ && grep -f /tmp/b$$ tests/fixtures/bytes_round35.txt | wc -l | grep -q 3 && echo lane207-tests-ok", "expect_exit": 0, "expect_regex": "lane207-tests-ok", "timeout_s": 2700}
```

# bound: 3000s
