# 272_layout_seat_rundir_beacon seat never lands on a hand, a flipped row never exits onto a roboport, beacon prune keeps coverage

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-272`, branch `lane/272`,
base tag `round-47-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua save|list|uninterrupted`, `factorio`, or any full suite, whole sheet or
headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Sheet `player-gray-magenta-science-10s` (grid 104x154) is refused by validate. Three causes sit between pack and
route (measured legalcopilot-dev 2026-09-28, lua5.2, base `06ba0a7`):

- **B2 Seat hops a hand onto another hand.** `Seat.run` (`logic/bp/seat.lua`, called at search.lua ~:1690) hops
  hands whose input flow is `$external`. Its `used` set (~:73, check ~:84-86) holds only tiles picked by earlier
  seated ports; `Hands.offer_slides` builds `taken` from non-hand entities only (hands.lua ~:25-30). So the stone
  hand of machine rail:3 hopped onto (30,96), the tile of the (unseated) iron-stick hand, both picking from (29,96)
  → BP_V_COLLISION, BP_V_PORT_EDGE_WRONG, BP_V_SOURCE_DUPLICATE, 39 BP_V_BELT_BLEED. Fix (reference
  `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_hand.lua`, proven by Seat replay: shared hand tiles 1 → 0, only 1 of 181 hands moves;
  bytes of 13 golden sheets unchanged): before the loop, mark every hand NOT in Seat's list, and the port tile of
  such a hand, as used. Do not touch hands.lua (would change hop options on every sheet).
- **B6 row flip onto a roboport.** `RunDir.choose` (`logic/bp/run_dir.lua`) mirrors a row after pack. Its
  validity check (~:140-150) tests the flipped port tile and one tile along `q.dir` against grid edge and other
  blocks only: no roboports, and `q.dir` is the port NORMAL (for a row out port it points back into the row), so
  the exit tile is never tested. Production row @0 flipped, out port (54,102) exits west onto roboport k:8
  (50..53 x 100..103) → BP_R_NO_PATH, 7 discontinuous + 16 unused. Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_rundir.lua` +
  `p_rundir2.lua`, proven by `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/fast_rundir.lua` in 0.3 s: exits on roboport 1 → 0): new
  last parameter `obstacles` (list of `{rect={x,y,w,h}}` or rects); flip invalid when port tile or exit tile is inside
  one; for role `out` the exit tile is along `Grid.rotate_dir(p.travel_dir, placement.dir)`. Caller in
  `logic/bp/search.lua` (the single `RunDir.choose(...)` call, ~:394) passes `state.work.robo_obstacles`.
- **B8 beacon prune drops coverage.** `BeaconPrune.share` (`logic/bp/beacon_prune.lua`, merge test ~:70-72,
  append ~:122, `_gone` ~:125) merges two beacons of one signature even when both serve the same machine; that
  machine then loses a beacon (rail:3 got 2 of 3 → BP_V_BEACON_COVERAGE_SHORT). Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_beacon.lua`):
  refuse a merge when `beacon.required_for` and `other.required_for` share a machine id. Synthetic proof:
  X{M1} Y{M1,M2} Z{M1} → base leaves M1 with 2, fixed keeps 3.

Probe patch format: file returns `function(module_name, src) return new_src end`; reference files are what ran.

## What to build

1. `tests/test_seat_hand_taken.lua` SH1 (red on base): machine with an unseated input hand at tile T and an
   `$external` hand whose best hop option lands on T (or on T's port tile) → after `Seat.run`, no two hands share
   a tile and no two ports share a tile. SH2: with no conflict the chosen hop is unchanged.
2. `tests/test_run_dir_obstacle.lua` RD1 (red on base): row block whose flip is preferred and whose flipped out
   port exit tile lies in an obstacle rect → `RunDir.choose` returns the unflipped block. RD2: same without the
   obstacle → flipped. RD3: out exit tile uses travel_dir (normal pointing into the row is not the exit).
3. `tests/test_beacon_prune_shared.lua` BP1 (red on base): X{M1} Y{M1,M2} Z{M1} → M1 still covered by 3 beacons.
   BP2: two beacons serving disjoint machines still merge as before.
4. `logic/bp/seat.lua`, `logic/bp/run_dir.lua`, `logic/bp/beacon_prune.lua`, the one call line in
   `logic/bp/search.lua`; short comments with measured numbers + date.
5. Also keep green (one at a time, `timeout 90`): `test_seat`, `test_run_dir`, `test_beacon_prune`,
   `test_beacon_share`, `test_beacons`, `test_beacon_coverage`, `test_hands`, `test_hands_hop`, `test_search`,
   `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/seat.lua, logic/bp/run_dir.lua, logic/bp/beacon_prune.lua, logic/bp/search.lua (ONLY the
`RunDir.choose(...)` call), tests/test_seat_hand_taken.lua, tests/test_run_dir_obstacle.lua,
tests/test_beacon_prune_shared.lua, docs/tasks/272_layout_seat_rundir_beacon.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/272`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane272-tests", "command": "git diff --name-only round-47-base HEAD | grep -Ev '^(logic/bp/seat\\.lua|logic/bp/run_dir\\.lua|logic/bp/beacon_prune\\.lua|logic/bp/search\\.lua|tests/test_seat_hand_taken\\.lua|tests/test_run_dir_obstacle\\.lua|tests/test_beacon_prune_shared\\.lua|docs/tasks/272_layout_seat_rundir_beacon\\.md)$' | ( ! grep . ) && git diff --quiet round-47-base HEAD -- docs/tasks && [ $(git diff round-47-base HEAD -- logic/bp/search.lua | grep -c '^[-+][^-+]') -le 4 ] && for t in test_seat_hand_taken test_run_dir_obstacle test_beacon_prune_shared test_seat test_run_dir test_beacon_prune test_beacon_share test_beacons test_beacon_coverage test_hands test_hands_hop test_search test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane272-tests-ok", "expect_exit": 0, "expect_regex": "lane272-tests-ok", "timeout_s": 3000}
{"name": "lane272-fast", "command": "out=$(for t in test_seat_hand_taken test_run_dir_obstacle test_beacon_prune_shared; do lua5.2 tests/$t.lua 2>&1; done); for c in SH1 SH2 RD1 RD2 RD3 BP1 BP2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^3$' && echo lane272-ok", "expect_exit": 0, "expect_regex": "lane272-ok", "timeout_s": 900}
```
