# 225_beacon_prune search: drop a beacon another block's beacon already covers for, after route, before power

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-225`, branch `lane/225`,
base tag `round-38-base`, merge target `int/r38`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Never touch
`logic/bp/validate.lua`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. `require` only at file top level
(`tests/test_no_runtime_require.lua`). **No game item or fluid name in code** (`tests/test_no_item_names.lua`): the
rule holds for any beacon, any machine, any module.

Tools: `lua5.2 tools/verdict_codes.lua <prepared_input.json>`; `sh tools/gate_sheet.sh <case> <max_entities>
[max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`). Every new test must FAIL on the base code (write that in
the test's header comment).

## Explain very simply

Player's red science 10/s with bulk hands (golden case `player-red-science-10s-bulk`) gives no blueprint today.
Bulk hands are fast, so blocks are small and pack puts them close. The gear foundry's beacon then reaches the
copper-plate foundry too. That foundry needs 1 beacon and now has 2, so its own beacon does nothing. The validator
refuses it with `BP_V_BEACON_REDUNDANT` — correctly. The fix removes such a beacon before the validator looks.

Measured (legalcopilot-dev, 2026-09-26, base = main ce3082b), code patched in memory only:
- frozen validate input of the first candidate, `tests/fixtures/validate_red10s_bulk_c1.json`: validator gives
  exactly one code, `BP_V_BEACON_REDUNDANT` on
  `m:beacon:block:casting-copper|beacon|normal|speed-module-3@normalx2|same_type:1`. With that one entity deleted:
  0 codes.
- whole sheet with the prune run at the START of the `hands` phase in `logic/bp/search.lua` (the branch
  `elseif state.phase == "hands" then`, before `local all = list_copy(state.work.materialized.entities)`):
  `ok=true`, 266 entities, 157 belts, lane_sim 0/0/0, NAMES-OK.
- prune placed earlier (right after `materialize_candidate`) is WRONG: freed beacon tiles change hand slides and
  routes. Keep it in `hands`.
- every other golden sheet unchanged except `player-inserter-10s-bulk`: 274 entities, 102 belts, 6 beacons (was
  273/100/7; search ranks beacon count first — accepted by the player).

## What to build

1. New module `logic/bp/beacon_prune.lua`, `BeaconPrune.run(entities, catalog)`:
   - machines = entities with `kind == "machine"`; beacons = entities with `kind == "beacon"`;
   - need[machine id][signature] = number of beacons with that `signature` whose `required_for` lists the machine;
   - a beacon reaches a machine when the machine box `{x, y, w, h}` overlaps the beacon box grown by its supply
     distance on every side: supply = `entity.supply_w` (and `supply_h`), else catalog `beacon[name].supply_w/h`
     (same numbers `logic/bp/validate.lua` `beacon_projection` reads; distance counts from the beacon EDGE);
   - visit beacons sorted by `id`; remove a beacon only when every machine it reaches that has a need for its
     signature still has ≥ need matching (same `signature`), not-removed, reaching beacons without it;
   - a beacon with no `signature` or no `required_for` is never removed;
   - removes in place from `entities`; returns the list of removed ids.
2. `logic/bp/search.lua`: at the start of the `hands` phase branch, call
   `BeaconPrune.run(state.work.materialized.entities, state.work.input.catalog)`. Nothing else in search changes.
   `require "logic.bp.beacon_prune"` at top level.
3. Test `tests/test_beacon_prune.lua`:
   - fixture `tests/fixtures/validate_red10s_bulk_c1.json`: run on `candidate.entities` with the fixture catalog →
     removes exactly the one id above (read it from the fixture's `BP_V_BEACON_REDUNDANT` check, or compare to the
     literal id string in the TEST only); then `Validate.begin{candidate=…, plan=…, catalog=…, ring_bump=…}` stepped
     to done → 0 errors;
   - hand-built: one machine, one beacon that is its only reaching beacon → kept;
   - hand-built: two machines side by side, each with own beacon, each beacon reaches only its own machine → both
     kept;
   - hand-built: foreign beacon of a DIFFERENT signature reaches the machine → own beacon kept.

## Files this lane owns

logic/bp/beacon_prune.lua, logic/bp/search.lua, tests/test_beacon_prune.lua, docs/tasks/225_beacon_prune.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/225`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane225-tests", "command": "git diff --name-only round-38-base HEAD | grep -Ev '^(logic/bp/beacon_prune\\\\.lua|logic/bp/search\\\\.lua|tests/test_beacon_prune\\\\.lua|docs/tasks/225_beacon_prune\\\\.md)$' | ( ! grep . ) && git diff --quiet round-38-base HEAD -- docs/tasks/225_beacon_prune.md && ! git diff round-38-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_beacon_prune test_red10s_bulk_delivers test_search test_search_retry test_beacons test_beacon_coverage test_beacon_placement_incident test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane225-tests-ok", "expect_exit": 0, "expect_regex": "lane225-tests-ok", "timeout_s": 3000}
{"name": "lane225-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s-bulk 266 157 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s-bulk 274 102 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s 273 150 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 281 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s-bulk 142 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 375 | tail -1 | grep -q GATE-OK && echo lane225-ok", "expect_exit": 0, "expect_regex": "lane225-ok", "timeout_s": 3000}
```

# bound: 2400s
