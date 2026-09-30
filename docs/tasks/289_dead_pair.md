# 289_dead_pair: an unfed underground pair is pruned by the router and refused by the validator

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-289`, branch `lane/289`,
base tag `round-52-base` (`f13b7496e3df8592499363ee4c50bf28df08c0d2`), merge target `int/r52`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 90 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/sheet_verdict.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`,
`tests/golden/generate.lua`, `tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet
or headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY, never lua5.4) or `timeout 90 python3 -m unittest tests/<file>.py`;
headless test files only offline: `timeout 90 lua5.2 tests/game/offline.lua tests/game/<file>.lua`. Never use
`coroutine` or `math.random`. `require` only at file top level. **No game item or entity name in `logic/`.** Every
new test must FAIL on the base code where this task says "red on base" (say so in its header comment, with date
2026-09-30); commit it red first, then the code.

## Explain very simply

Read `CONTEXT.md` terms **Dead pair**, **Fallback**, **Waste rule**. Player ruling 2026-09-30: a Dead pair (an
underground belt pair that carries no items) makes a layout INVALID, in every pack mode.

Seen: drawn inserter-10s bytes `tests/fixtures/dead_pair_inserter10s.bp.txt` (sha c3d630e6..., round 51): pair
entrance (27,16) -> exit (32,16), nothing feeds (27,16). lane_sim printed `mixed=4` because it seeds an unfed
entrance as an external supply `ext@27,16`. Scan of all 14 layered player sheets (legalcopilot-dev 2026-09-30):
zero Dead pairs, so layered bytes must not change.

Why it survives today (code read at base):
- Router `prune_dead_route_segments` (`route.lua:4159-4262`): building the fed set (4186-4209) marks every
  segment's outputs fed whether or not that segment is fed; an underground always marks its exit + the tile after
  (4187-4192). Removal (4242-4244) skips `segment.underground` and splitters. `audit_route_work` (3216-3266) drops
  only zero-allocation segments; a dead pair keeps the allocation `append_crossing` gave it (1669).
  `unbury_empty_pairs` (3424-3501) checks only that the span is empty, never feed.
- Likely origin: demand B lays its own pair P2 beside A's pair P1 (ride offered only as last resort,
  `route.lua:2680-2683,5157-5162`); the improve pass re-routes B riding P1 (`allow_bury`, 4471,4485), lifts B's
  feeder belts (`lift_binding` 4043-4099) but P2 keeps its allocation.
- Validator: `feeds` (`validate.lua:2238-2251`) counts an entrance as feeding its exit by direction alone;
  `mark_path` (2252-2356) then marks the unfed pair used -> no `BP_V_TRANSPORT_UNUSED`.
  `tests/test_validate_witness_underground.lua:56-61` asserts exactly that (entrance at (10,8) with nothing behind
  is "not unused"); this test changes ON PURPOSE (cite the ruling in its comment).
  `BP_V_BELT_NO_SOURCE` (1667-1682) checks only `tile.kind == "belt"`. Lane witnesses per tile live in
  `check_transport_shapes` (`witnesses[key][lane][flow_id]`, 1613-1762).
- lane_sim (`tools/lane_sim.py:146-151`): every unfed tile except exits/splitters is seeded `ext@x,y`.

## What to build

1. Router: in `prune_dead_route_segments` an underground entrance counts fed only when its entrance tile is fed
   (a fed segment behind it that outputs into it, a hand drop, or a source port tile). An unfed pair is removed
   (both tiles), its downstream plain belts pruned by the existing walk, its allocations dropped. Fed pairs stay
   byte-identical.
2. Validator: new code `BP_V_UNDERGROUND_DEAD` (detail `{x=, y=, flow_id=}`) for an underground entrance with no
   physical feeder (no transport predecessor that outputs into it by game rules, no hand drop, not a source port
   tile). Put it in `check_transport_shapes` next to `BP_V_BELT_NO_SOURCE`. `mark_used`/`feeds` must no longer
   mark an unfed pair used. Register the code wherever other `BP_V_*` codes are registered (grep
   `BP_V_BELT_NO_SOURCE` across the repo). If a locale file needs a key, that file is NOT yours: say so in your
   final message instead.
3. `tests/test_validate_witness_underground.lua:56-61`: the unfed entrance now gets `BP_V_UNDERGROUND_DEAD`; fix
   the assertion + comment "player ruling 2026-09-30: Dead pair is invalid".
4. lane_sim: count Dead pairs (underground input in a pair, no predecessor in `pred`, no hand drop onto it) and
   print them in the LANE-SIM line as `dead=N`; never seed `ext@` on such an entrance. `mixed`/`starved`/`bleed`
   meaning unchanged.
5. `tools/sheet_verdict.sh`: `lanes=` field carries `dead` (it reads the LANE-SIM line; check the format) and a new
   field `fell_back=0|1` read from the r.json (see 6).
6. `search.lua` `layered_fallback` (1487-1500): when it sets `state.work.drawn_off`, also record
   `state.work.fell_back = true`; export it on the search result the same way other result flags reach the r.json
   (grep how the result is built in search.lua and what `tests/golden/generate.lua` writes). Touch nothing else in
   search.lua.
7. Tests (headers: DP1-DP5 red on round-52-base):
   - `tests/test_route_dead_pair.lua` DP1: hand-built work (template `tests/test_route_prune_splitter.lua`): belt
     row feeds pair P1; parallel pair P2 with nothing behind -> after `Route._test.prune_dead_route_segments`
     P2 gone, P1 + its belts kept. DP2: fed pair only -> nothing removed.
   - `tests/test_validate_dead_pair.lua` DP3: unfed pair -> `BP_V_UNDERGROUND_DEAD`; DP4: same pair fed by a belt
     behind -> no code.
   - `tests/test_lane_sim.py` DP5: run lane_sim on `tests/fixtures/dead_pair_inserter10s.bp.txt` with input
     `tests/golden/cases/player-inserter-10s/prepared_input.json` -> `dead=1` and `mixed=0`.
   Print "DP1".."DP4" in the lua tests when each passes; DP5 is a unittest method named `test_DP5_dead_pair`.
8. Keep green (one at a time): list in the first check below, and `python3 -m unittest tests/test_lane_sim.py`.

## Files this lane owns

logic/bp/route.lua, logic/bp/validate.lua, logic/bp/search.lua, tools/lane_sim.py, tools/sheet_verdict.sh, tests/test_route_dead_pair.lua, tests/test_validate_dead_pair.lua, tests/test_validate_witness_underground.lua, tests/test_lane_sim.py, docs/tasks/289_dead_pair.md. In `route.lua` touch only `prune_dead_route_segments` and helpers it alone uses; in `validate.lua` only `check_transport_shapes`, `feeds`/`mark_used`/`mark_path` and the code registry; in `search.lua` only `layered_fallback` + result export.

## Commit, THEN check

Commit on `lane/289`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane289-tests", "command": "git diff --name-only round-52-base HEAD | grep -Ev '^(logic/bp/route\\.lua|logic/bp/validate\\.lua|logic/bp/search\\.lua|tools/lane_sim\\.py|tools/sheet_verdict\\.sh|tests/test_route_dead_pair\\.lua|tests/test_validate_dead_pair\\.lua|tests/test_validate_witness_underground\\.lua|tests/test_lane_sim\\.py|docs/tasks/289_dead_pair\\.md)$' | ( ! grep . ) && for t in test_route_dead_pair test_validate_dead_pair test_validate_witness_underground test_route_prune_splitter test_route_tidy test_route_tidy_junk test_route_tidy_shapes test_route_bury test_route_bury_row_flow test_route test_validate_belt_no_source test_validate_transport_shapes test_twins test_search_draw_phase test_drawn_e2e test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane289-tests-ok", "expect_exit": 0, "expect_regex": "lane289-tests-ok", "timeout_s": 3000}
{"name": "lane289-fast", "command": "out=$( (timeout 120 lua5.2 tests/test_route_dead_pair.lua; timeout 120 lua5.2 tests/test_validate_dead_pair.lua; timeout 120 python3 -m unittest -v tests/test_lane_sim.py) 2>&1); for c in DP1 DP2 DP3 DP4 test_DP5_dead_pair; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -Eq 'FAILED|[1-9][0-9]* failed' && { echo RED; exit 1; }; echo lane289-ok", "expect_exit": 0, "expect_regex": "lane289-ok", "timeout_s": 300}
```

# bound: 5400s
