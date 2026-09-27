# 258_groups_hand_off_pipe_tile a machine hand never sits on the tile where its fluid pipe connects

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-258`, branch `lane/258`,
base tag `round-45-w2`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind except the ONE route probe and ONE delivers test named below.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

`player-inserter-10s-stack1` (slow hands 2.31/s) now passes groups (lanes 254/255 merged), then route refuses
`BP_R_PORT_BLOCKED` for `fluid/molten-copper`: sink (16,24) owned by `machine:block:casting-copper-cable`
(`lua5.2 tools/first_stage.lua player-inserter-10s-stack1 route` with `DETAIL=1`, legalcopilot-dev 2026-09-27).
Cause, from `tests/fixtures/groups_ins_stack1.json` replayed through Groups: block `block:casting-copper-cable`
(one 5x5 foundry at (1,4), beacon (1,0) 3x3) needs 7 copper-cable output hands (15/s / 2.31). The face allocator
(`new_face_allocator`, `logic/bp/groups.lua` ~754) gives 5 on the left face and 2 on the bottom face at (1,9) and
(2,9). The molten-copper fluid port's pipe tile is ALSO (2,9) (port `attach_dx=2, attach_dy=9`): the port position is
computed later in `place_side` (~1100-1125: catalog connection position -> machine tile -> one tile outward). The hand
allocator never knows that tile, so a hand lands on it and route sees the pipe tile blocked.

Fix: before hands are allocated for a machine (`append_multi_flow_inserters` ~871 and `append_single_flow_inserters`
~804 both call `new_face_allocator`), compute the machine's fluid pipe tiles with the SAME formula as `place_side`
(connection position rotated by `machine.dir`, `cell_of(machine.x + machine.w/2 + dx)`, one tile along the rotated
connection direction when the connection tile is inside the machine) for every fluid port of the machine's step, and
make the allocator skip any face slot whose inserter tile (see `desired_x, desired_y` ~443-468 for slot -> tile) is a
fluid pipe tile. Capacity of that face drops by one per skipped slot; `hand_face_spread` then moves the hand to the next
face. Share one helper between `place_side` and the allocator (no duplicated formula). Blocks whose hands never touch a
fluid pipe tile keep identical output (the skip never fires) -> passing sheets stay byte-identical.

Replay pattern (1.7 s, copy `tests/test_groups_pad_faces.lua`): `Groups.begin(fixture)` on
`tests/fixtures/groups_ins_stack1.json`, step until done.

## What to build

1. `tests/test_groups_hand_off_pipe.lua` (commit red first):
   - HP1: replay `tests/fixtures/groups_ins_stack1.json` -> for every block, no inserter tile (`x`,`y`) equals any
     fluid port's `attach_dx`,`attach_dy`; block `block:casting-copper-cable` still has 7 output hands. Red before.
   - HP2: replay `tests/fixtures/groups_red1s_foundry.json` -> blocks serialize to the same hash as base (copy PF3's
     hash approach from `tests/test_groups_pad_faces.lua`; compute the base hash on `round-45-w2` and paste it).
2. `logic/bp/groups.lua`: helper + allocator skip, short comment citing block, tile and date.
3. Then, once, run `DETAIL=1 lua5.2 tools/first_stage.lua player-inserter-10s-stack1 route` (allowed: one run, about
   3-10 min) and report its last line in your final message. If it still refuses, name the new fault (code, flow,
   tiles) in your final message; do not try to fix beyond this task.
4. Last: `lua5.2 tests/test_inserter_stack1_delivers.lua` once (already in repo, currently red).

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_hand_off_pipe.lua, docs/tasks/258_groups_hand_off_pipe_tile.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/258`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane258-tests", "command": "git diff --name-only round-45-w2 HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_hand_off_pipe\\.lua|docs/tasks/258_groups_hand_off_pipe_tile\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w2 HEAD -- docs/tasks && ! git diff round-45-w2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_hand_off_pipe test_groups_pad_faces test_groups_lone_slots test_groups test_groups_beacon_pad test_groups_beacon_row test_groups_belt_split test_groups_buffer test_groups_chunk_retry_ids test_groups_coverage_split test_groups_faces_beacon_rows test_groups_fluid_box_order test_groups_fluid_row test_groups_hand_count test_groups_hands_overflow test_groups_interior_port test_groups_long_hands test_groups_one test_groups_row_inserter_name test_groups_rows test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane258-tests-ok", "expect_exit": 0, "expect_regex": "lane258-tests-ok", "timeout_s": 3000}
{"name": "lane258-fast", "command": "out=$(lua5.2 tests/test_groups_hand_off_pipe.lua 2>&1); for c in HP1 HP2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane258-ok", "expect_exit": 0, "expect_regex": "lane258-ok", "timeout_s": 600}
```

# bound: 3000s
