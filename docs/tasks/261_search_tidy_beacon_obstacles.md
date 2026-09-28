# 261_search_tidy_beacon_obstacles tidy re-route treats every beacon's current footprint as an obstacle

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-261`, branch `lane/261`,
base tag `round-45-w4`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind, except the ONE blue delivers test named below.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

Search order after route: `hands` phase runs `BeaconPrune.run` (`logic/bp/search.lua` ~1770), which may SLIDE a beacon
up to 2 tiles so one beacon covers two machines (beacon sharing). It checks the route entities of that moment. Then
the `tidy` phase re-routes (`Route.tidy_begin`, ~1764), and route's obstacle map still has the beacon at its OLD
tiles: only power poles are passed as new obstacles. On `player-blue-science-10s` (legalcopilot-dev, 2026-09-28) the
refinery beacon slid from (6,17) to (6,16); tidy then laid a petroleum-gas pipe-to-ground at (7,16) under it ->
`BP_V_COLLISION`, the first candidate is refused, and blue's first-candidate test
`tests/test_blue_10s_delivers.lua` BL1 is red.

Fix: where search builds the `poles` list for `Route.tidy_begin`, also pass every live beacon of
`state.work.materialized.entities` (kind or type `beacon`, not `_gone`, rect `x, y, w, h`) as an obstacle. Keep
`pole_cells` (slide filter) as it is. Reference (measured in memory): `docs/tasks/ref/261_patch_reference.lua`; with
it `DETAIL=1 lua5.2 tools/first_stage.lua player-blue-science-10s validate 15` ends `FIRST-VALIDATE ok=true`.

## What to build

1. `logic/bp/search.lua`: the change, short comment citing the tile and date.
2. `tests/test_search_tidy_beacons.lua` (commit red first): TB1 synthetic, fast: build a minimal state the way the
   tidy branch reads it is NOT required; instead unit-test through source: load `logic/bp/search.lua` source and
   assert the `Route.tidy_begin` call site receives obstacles that include beacons (wrap `Route.tidy_begin` in the
   test, run `tools/first_stage.lua`-style is too slow). Simplest honest form: run
   `lua5.2 tools/first_stage.lua player-red-science-1s validate` (about 5 s) with `Route.tidy_begin` wrapped via
   `package.preload` so the test records the obstacles list, and assert it contains an entry with owner starting
   `beacon:` whenever the materialized entities hold a beacon; if red-1s has no beacon use
   `player-red-science-1s-foundry` (it has beacons). Red on base.
3. Run `tests/test_blue_10s_delivers.lua` ONCE at the end (about 6 min; allowed); report its last line.

## Files this lane owns

logic/bp/search.lua, tests/test_search_tidy_beacons.lua, docs/tasks/261_search_tidy_beacon_obstacles.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/261`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane261-tests", "command": "git diff --name-only round-45-w4 HEAD | grep -Ev '^(logic/bp/search\\.lua|tests/test_search_tidy_beacons\\.lua|docs/tasks/261_search_tidy_beacon_obstacles\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w4 HEAD -- docs/tasks && for t in test_search_tidy_beacons test_search test_route test_route_tidy test_blue_10s_delivers test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 1500 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane261-tests-ok", "expect_exit": 0, "expect_regex": "lane261-tests-ok", "timeout_s": 3000}
{"name": "lane261-fast", "command": "out=$(lua5.2 tests/test_search_tidy_beacons.lua 2>&1); echo \"$out\" | grep -q TB1 || { echo MISSING TB1; exit 1; }; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane261-ok", "expect_exit": 0, "expect_regex": "lane261-ok", "timeout_s": 600}
```

# bound: 3000s
