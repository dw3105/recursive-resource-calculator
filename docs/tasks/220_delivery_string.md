# 220_delivery_string delivery: copy string pastes in game, blueprint reaches hand or clipboard

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-220_delivery_string`, branch `lane/220_delivery_string`,
base tag `round-37-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in logic code**
(`tests/test_no_item_names.lua` must stay green). Every new test must FAIL on the code before your fix (write that
in the test's header comment).

## Explain very simply

Player (RRC 1.1.83, Factorio 2.0.77, 2026-09-25) ran Generate on red science 1/s. Layout built (142 entities). Two
faults, measured on player's export `tests/golden/cases/player-red-science-1s-bulk` (legalcopilot-dev, 2026-09-25):

1. Blueprint never reached hand. Export `delivery.last_reason = blueprint_delivery_failed`. In
   `gui/blueprint_delivery.lua` staging (`stage`) passed, then `publish` failed writing the cursor. The `pcall`
   error text is thrown away, so nobody knows why. `cursor_is_empty` returns true when `player.cursor_stack == nil`,
   and `publish` then indexes nil. Staging inventory from `game.create_inventory(1)` is never destroyed (leak).
2. Copy string does not paste. `logic/bp/generation.lua` `encode_blueprint` = `helpers.encode_string(table_to_json(result))`:
   no leading `0` version char, no `{"blueprint": ...}` wrapper, and internal keys (`search`, `chosen_score`,
   `discarded_alternatives`) inside. Game import refuses it. The correct format is in `tools/blueprint_string.py`
   `build()` (KEEP keys, typed underground/loader ends, icons from placed recipe machines, wires with real connector
   ids only -- pole-to-pole placeholder wires omitted, poles auto-connect -- `item`, `version`, `label`).

## What to build

1. New `logic/bp/blueprint_string.lua`: `BlueprintString.build(result, label) -> string` = Lua port of
   `tools/blueprint_string.py build()` with pole autoconnect allowed; `version` packed from
   `script.active_mods.base` (fallback 2.0.77); returns `"0" .. helpers.encode_string(json)`.
   `encode_blueprint` in generation.lua uses it (only that function changes in generation.lua).
2. New `tools/lua_blueprint_string.lua <generate-output.json>`: prints the Lua string (harness helpers) for a
   `tests/golden/generate.lua` output.
3. Delivery: nil `cursor_stack` = not usable. `publish` keeps the pcall error text: `state.blueprint_delivery_last_error`
   (string). Fallback chain when the cursor write fails or no cursor: `player.add_to_clipboard(staged)` then
   `player.activate_paste()` (each in pcall) → reason `blueprint_on_clipboard`, note tells Ctrl+V; else keep
   `blueprint_not_delivered` + Copy string. Staging inventory `destroy()`ed on every path.
4. Export (`logic/export_payload.lua`): `delivery.last_error` carries the text.
5. Harness (`tests/harness.lua`): player with nil cursor; cursor whose `set_blueprint_entities` throws;
   `add_to_clipboard`, `activate_paste`; inventory `destroy`. Locale en/cs/ro: `blueprint_on_clipboard`.
6. Tests: `tests/test_blueprint_string_game.lua` (string starts `0`; decodes to `blueprint` with item, version,
   label, icons, entities; no key outside KEEP+entity_number+type; underground ends typed; placeholder pole wires
   dropped) and `tests/test_delivery_fallback.lua` (nil cursor → clipboard + activate_paste; throwing cursor →
   `last_error` text in export; inventory destroyed every path).

## Files this lane owns

gui/blueprint_delivery.lua, logic/bp/generation.lua, logic/bp/blueprint_string.lua, logic/export_payload.lua, tests/harness.lua, locale/en/locale.cfg, locale/cs/locale.cfg, locale/ro/locale.cfg, tools/lua_blueprint_string.lua, tests/test_blueprint_string_game.lua, tests/test_delivery_fallback.lua, tests/test_blueprint_delivery.lua, tests/test_delivery_final.lua, tests/test_export_payload.lua, docs/tasks/220_delivery_string.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/220_delivery_string`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane220-tests", "command": "git diff --name-only round-37-base HEAD | grep -Ev '^(gui/blueprint_delivery\\\\.lua|logic/bp/generation\\\\.lua|logic/bp/blueprint_string\\\\.lua|logic/export_payload\\\\.lua|tests/harness\\\\.lua|locale/(en|cs|ro)/locale\\\\.cfg|tools/lua_blueprint_string\\\\.lua|tests/test_blueprint_string_game\\\\.lua|tests/test_delivery_fallback\\\\.lua|tests/test_blueprint_delivery\\\\.lua|tests/test_delivery_final\\\\.lua|tests/test_export_payload\\\\.lua|docs/tasks/220_delivery_string\\\\.md)$' | ( ! grep . ) && ! git diff round-37-base HEAD -- logic gui | grep -q '^+.*coroutine' && for t in test_blueprint_string_game test_delivery_fallback test_blueprint_delivery test_delivery_final test_export_payload test_locale_keys test_no_item_names test_progress_status_line test_update_stops_jobs; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane220-tests-ok", "expect_exit": 0, "expect_regex": "lane220-tests-ok", "timeout_s": 1800}
{"name": "lane220-python-equal", "command": "o=$(mktemp) && timeout 600 lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s-bulk/prepared_input.json --output $o >/dev/null 2>&1 && lua5.2 tools/lua_blueprint_string.lua $o > $o.lua.txt && python3 tools/blueprint_string.py $o -o $o.py.txt --allow-pole-autoconnect 2>/dev/null && python3 -c \"import sys,json,zlib,base64\nd=lambda p: json.loads(zlib.decompress(base64.b64decode(open(p).read().strip()[1:])))['blueprint']\na=d(sys.argv[1]); b=d(sys.argv[2]); assert open(sys.argv[1]).read().startswith('0'); assert a['entities']==b['entities'], 'entities differ'; assert a.get('wires')==b.get('wires'), 'wires differ'; print('lane220-equal-ok')\" $o.lua.txt $o.py.txt", "expect_exit": 0, "expect_regex": "lane220-equal-ok", "timeout_s": 900}
```

# bound: 2400s
