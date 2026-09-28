# 273_validate_ports_alarms_ends validator keeps every row port, drops two false alarms, splitter footprint fixed, no whole-entity scans

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-273`, branch `lane/273`,
base tag `round-47-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

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

Sheet `player-gray-magenta-science-10s` (grid 104x154): validate refuses; some errors are validator bugs, one is a
belt-end bug, and two passes freeze the game (measured legalcopilot-dev 2026-09-28, lua5.2, base `06ba0a7`):

- **B3 validator loses row ports.** `collect_ports` (`logic/bp/validate.lua` ~:390-397) skips a port whose id was
  seen. Row port ids (`row:in:<flow>`, `row:out:<flow>`, `row:in:rear`) repeat across blocks, so every later block
  loses its ports → 15 false "machine has no own port" BP_V_ROUTE_DISCONTINUOUS + 23 false BP_V_TRANSPORT_UNUSED.
  Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_portkey.lua`, first two replacements only; proven 30 → 13 and 62 → 39, no
  new code): dedup key = id + (step_id or block_id) + member_id. `port_index` (~:116) must not keep only the first
  of equal ids for binding checks: index by id → list, and resolve by step/block where the binding says.
- **B9a false alarm, pipe beside pipe-to-ground.** `middle_segment` (~:1277) flags a same-fluid plain pipe running
  beside a pipe-to-ground span as BP_V_UNDERGROUND_UNPAIRED; in Factorio a surface pipe never interacts with the
  span. Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_valfalse.lua`): return nil when source or sink is a pipe.
- **B9b false alarm, head-on ends.** Loop walk (~:1760) follows a belt into a head-on belt (two dead ends facing each
  other) and reports BP_V_ROUTE_LOOP; other checks (~:601, lane walk ~:1638) already treat head-on as not connected.
  Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_valfalse.lua`): do not follow into a tile whose direction is opposite (unless underground
  input). Proven: 135 → 133 errors, both codes gone, none new.
- **B5 splitter footprint one tile off.** `occupies` in `logic/bp/ends.lua` (~:42-44) uses floor(position) as the
  first tile; route stores splitters by CENTRE, so the true tiles are floor(centre-0.5) and +1. A working iron-ore
  belt got turned away from its own splitter. Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_endsfoot.lua`).
- **Freeze E.** `Ends.turn_heads` calls `tile_accepts` (scan of all entities) per belt end: 6.6 s single tick on
  this sheet. Fix (reference `/home/dev_zaigraev_gmail_com/wt-rrc-int/docs/tasks/r47_probes/p_ends.lua`, A/B on checkpoint 8.98 s → 0.031 s, same result): build occupancy +
  anchor tile indexes once per call; splitter entries registered on all 8 neighbour tiles (superset; `occupies` still
  decides); feeder check looks only at entities anchored on the 4 neighbours.
- **Freeze V.** Validate ticks of 1.5-2.1 s: `cell_occupant` (~:1780, scan of `work.infos` per call, from
  `transfer_endpoint_error` / `validate_inserter_endpoints`), `occupant_at` inside `check_port_approaches` (~:2544,
  scans all infos AND all segments per port), `declared_flow_ids` rebuilt per call (~:280-310, from
  `transport_accepts_flow` in `mark_path`). Fix: tile index of infos (all tiles of each rect, list in infos order so
  "first match" is unchanged), per-tile segment index for occupant_at, memo of declared_flow_ids per info. Caches
  live in a module-local weak-keyed table keyed by `work` (never in saved state; rebuilt when missing).
  Same errors in same order.

## What to build

1. `tests/test_validate_row_ports.lua` VP1 (red on base): candidate with 2 row blocks of different steps sharing
   port id `row:in:item-a` (use generic names) → both blocks keep their ports, no "has no own port" error. VP2:
   genuine duplicate (same id, same step, same member) still collapses.
2. `tests/test_validate_false_alarms.lua` FA1 (red on base): plain pipe beside a same-fluid pipe-to-ground span → no
   BP_V_UNDERGROUND_UNPAIRED. FA2 (red on base): two belt ends facing head-on → no BP_V_ROUTE_LOOP. FA3: a real belt
   loop is still reported. FA4: a belt beside a belt underground span still reported as before.
3. `tests/test_ends_splitter.lua` ES1 (red on base): splitter stored by centre, belt ending into its real tile is not
   turned. ET1: 5,000-belt synthetic, `turn_heads` ≤ 0.2 s and result identical to a naive O(n^2) reference kept
   inside the test.
4. `tests/test_validate_tile_index.lua` VT1: synthetic candidate, error list identical with caches on and a
   reference run (e.g. force-clear cache per call); VT2: 10,000-entity synthetic, no validate step call > 300 ms at
   2000 ops (red on base).
5. `logic/bp/validate.lua`, `logic/bp/ends.lua`: short comments with measured numbers + date.
6. Also keep green (one at a time, `timeout 90`): `test_validate`, `test_validate_rows`, `test_validate_ticks`,
   `test_validate_splitter`, `test_validate_splitter_rules`, `test_validate_splitter_chain`,
   `test_validate_witness_underground`, `test_validate_ptg_sides`, `test_validate_port_approach`,
   `test_validate_parallel_ports`, `test_validate_bleed`, `test_validate_belt_no_source`,
   `test_validate_source_duplicate`, `test_validate_transport_shapes`, `test_ends_turn`, `test_route_dead_ends`,
   `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/bp/validate.lua, logic/bp/ends.lua, tests/test_validate_row_ports.lua, tests/test_validate_false_alarms.lua,
tests/test_ends_splitter.lua, tests/test_validate_tile_index.lua, docs/tasks/273_validate_ports_alarms_ends.md. Never
touch anything else.

## Commit, THEN check

Commit on `lane/273`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane273-tests", "command": "git diff --name-only round-47-base HEAD | grep -Ev '^(logic/bp/validate\\.lua|logic/bp/ends\\.lua|tests/test_validate_row_ports\\.lua|tests/test_validate_false_alarms\\.lua|tests/test_ends_splitter\\.lua|tests/test_validate_tile_index\\.lua|docs/tasks/273_validate_ports_alarms_ends\\.md)$' | ( ! grep . ) && git diff --quiet round-47-base HEAD -- docs/tasks && for t in test_validate_row_ports test_validate_false_alarms test_ends_splitter test_validate_tile_index test_validate test_validate_rows test_validate_ticks test_validate_splitter test_validate_splitter_rules test_validate_splitter_chain test_validate_witness_underground test_validate_ptg_sides test_validate_port_approach test_validate_parallel_ports test_validate_bleed test_validate_belt_no_source test_validate_source_duplicate test_validate_transport_shapes test_ends_turn test_route_dead_ends test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane273-tests-ok", "expect_exit": 0, "expect_regex": "lane273-tests-ok", "timeout_s": 3000}
{"name": "lane273-fast", "command": "out=$(for t in test_validate_row_ports test_validate_false_alarms test_ends_splitter test_validate_tile_index; do lua5.2 tests/$t.lua 2>&1; done); for c in VP1 VP2 FA1 FA2 FA3 FA4 ES1 ET1 VT1 VT2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | grep -c ' 0 failed' | grep -q '^4$' && echo lane273-ok", "expect_exit": 0, "expect_regex": "lane273-ok", "timeout_s": 900}
```

# bound: 3600s
