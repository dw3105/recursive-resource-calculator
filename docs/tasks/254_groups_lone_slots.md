# 254_groups_lone_slots a lone machine with five item flows fits by face slots, not by one face per flow

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-254`, branch `lane/254`,
base tag `round-45-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind except the ONE delivers test named below.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

Player's `player-am2-chain` sheet (built 316 entities on 2026-09-21) now fails `BP_P_NO_FIT` "more distinct
port-bound item flows than machine faces for block:assembling-machine-2". That block is ONE machine with 5 item
flows: am1 1/s, circuit 3/s, gear 5/s (2 hands), steel 2/s, am2 out 1/s = 6 hands; faces give 12 slots. The flat
gate `if #flow_ids > 4 then` (`logic/bp/groups.lua` ~1480, inside `if logical_face_layout and not row_layout`, from
lane 134 "one face per flow", 2026-09-22) refuses it before the existing lone-machine long-side share (~1548-1567:
a flow may share `left`/`right` on a long side) can place the 5th flow.

Fix: for a lone machine (`#block.machines == 1`) the gate refuses only when more flows than faces can take with the
long-side share (at most 6: 4 faces + 1 extra flow on each long side), i.e. `> (#block.machines == 1 and 6 or 4)`.
Multi-machine blocks keep `> 4`. Measured in memory on this sheet (2026-09-27): am2 block builds: am1 + am2-out on
left (2 of 3 slots), gear x2 on top, steel bottom, circuit right. Old sheets never reach this path (they pass the
`> 4` gate today), so their groups output stays byte-identical.

Second fault on this sheet (after the gate): validate refuses one dead-end molten-iron pipe (`BP_V_TRANSPORT_UNUSED`
r:763 at (9.5,14.5), a stub hanging off pipe (9.5,15.5) between pipe-to-ground ends). Route's
`prune_dead_route_segments` handles belts only, and publication (`result_for(work, true)`) calls `PipeRuns.bury`
AFTER it, which leaves the stub. Fix: at the end of `PipeRuns.bury` (`logic/bp/pipe_runs.lua`), when `work.demands`
exists (real route; synthetic unit tests have none), repeatedly drop plain pipes with at most 1 same-fluid
connection (pipe-to-ground counts only on its exposed side) that are not a route endpoint (demand source/sink,
`endpoint_by_id`) and not a port cell. Reference (measured in memory): `docs/tasks/ref/254_patch_reference_bury_leaf.lua`.
With gate + leaf prune the whole sheet generates `ok=true`, 287 entities, 31 s CPU; `test_pipe_prune`,
`test_pipe_runs` and 12 route test files stay green. (The case input was rebuilt from the player's export by the
integrator in the base commit: the old capture had empty inserter offsets.)

Replay pattern (0.5-1.7 s, measured legalcopilot-dev 2026-09-27; copy `tests/test_groups_beacon_pad.lua`):
```lua
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.0")
local f = assert(io.open("tests/fixtures/groups_am2.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a"))); f:close()
local state = Groups.begin(fixture)
while not state.done do Groups.step(state, {ops = 100}) end
-- base: state.ok == false, one failure BP_P_NO_FIT
```

## What to build

1. `tests/test_groups_lone_slots.lua`:
   - LS1: replay `tests/fixtures/groups_am2.json` -> `state.ok == true`, no failures; block
     `block:assembling-machine-2` has hands for all 5 item flows, no two hands share one face slot (same face +
     same column), every hand port is on the machine's face.
   - LS2: synthetic or fixture-based multi-machine block with 5 distinct item flows is still refused with the same
     `BP_P_NO_FIT` detail (the `> 4` rule stays for multi-machine blocks). If building a synthetic input takes over 15
     minutes, instead assert on the source: the gate expression still refuses `#flow_ids > 4` when
     `#block.machines > 1` (unit-test the condition through a tiny exported helper is NOT allowed; use a real
     `Groups.begin` input copied from `tests/test_groups.lua` shapes).
2. `tests/test_am2_chain_delivers.lua` (copy `tests/test_red1s_foundry_delivers.lua`, case `player-am2-chain`):
   AM1 generate returns `"ok": true`. This is the ONLY whole-sheet run you may do (about 60 s), and only as the last
   step before checks.
3. `logic/bp/groups.lua`: the gate change, with a short comment citing the block and date.
4. `logic/bp/pipe_runs.lua`: the leaf prune as above; plus `tests/test_pipe_leaf_prune.lua` LP1: synthetic route
   `work` with `demands` and a dead-end plain pipe off a run -> stub removed, endpoints and port tiles kept; LP2: same
   without `work.demands` -> nothing removed.

## Files this lane owns

logic/bp/groups.lua, logic/bp/pipe_runs.lua, tests/test_groups_lone_slots.lua, tests/test_pipe_leaf_prune.lua, tests/test_am2_chain_delivers.lua, docs/tasks/254_groups_lone_slots.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/254`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane254-tests", "command": "git diff --name-only round-45-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|logic/bp/pipe_runs\\.lua|tests/test_pipe_leaf_prune\\.lua|tests/test_groups_lone_slots\\.lua|tests/test_am2_chain_delivers\\.lua|docs/tasks/254_groups_lone_slots\\.md)$' | ( ! grep . ) && git diff --quiet round-45-base HEAD -- docs/tasks && ! git diff round-45-base HEAD -- logic tools | grep -q '^+.*coroutine' && for t in test_groups_lone_slots test_pipe_leaf_prune test_am2_chain_delivers test_pipe_prune test_pipe_runs test_route test_route_pipe_join test_route_tidy test_route_tidy_junk test_groups test_groups_beacon_pad test_groups_beacon_row test_groups_belt_split test_groups_buffer test_groups_chunk_retry_ids test_groups_coverage_split test_groups_faces_beacon_rows test_groups_fluid_box_order test_groups_fluid_row test_groups_hand_count test_groups_hands_overflow test_groups_interior_port test_groups_long_hands test_groups_one test_groups_row_inserter_name test_groups_rows test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane254-tests-ok", "expect_exit": 0, "expect_regex": "lane254-tests-ok", "timeout_s": 3000}
{"name": "lane254-fast", "command": "out=$(lua5.2 tests/test_groups_lone_slots.lua 2>&1); for c in LS1 LS2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane254-ok", "expect_exit": 0, "expect_regex": "lane254-ok", "timeout_s": 600}
```

# bound: 3000s
