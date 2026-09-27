# 255_groups_pad_faces a lone machine short of face slots under a beacon row retries with its beacon beside it

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-255`, branch `lane/255`,
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

Player's `player-inserter-10s-stack1` (slow hands: fast inserter 2.31/s) fails `BP_P_NO_FIT` "no free machine face
for item/electronic-circuit". Block: ONE 4x4 electromagnetic plant with one beacon above it (plant at (1,4), beacon
x=1..3, y=0..2). Hands per flow = ceil(rate / 2.31): copper cable 15/s -> 7, iron plate 5/s -> 3, circuit out 10/s
-> 5 = 15 hands. `new_face_allocator` (`logic/bp/groups.lua` ~754-780) sets `top = 0` when the block has a top beacon
row (~763, commit 915103b "a face under a beacon row takes no hand", correct: ports landed on the beacon). Slots:
left 4 + right 4 + bottom 4 = 12 < 15. The `_beacon_pad` retry (~2393-2417: shift the beacon strip beside the machine,
used today for `invalid_coverage`) never fires on an `inserter-face` failure. It built before 915103b (2026-09-25).

Fix (fires ONLY where the build fails today, so passing sheets keep byte-identical groups output):
- In the retry branch: a lone face-layout machine whose block failed with `failure.name == "inserter-face"` and has a
  top beacon row gets ONE retry with `_beacon_pad`.
- In a padded block, the top face is excluded only for machine columns that lie under the beacon row's x-span
  (instead of zeroing the whole top face). Unpadded blocks keep `top = 0` exactly as today.
Measured in memory (2026-09-27): padded machine at x=4..7, beacon x=1..3, all 4 top columns free -> 16 slots, 15 hands
placed, top ports at y=2.5 x=4..7 clear of the beacon, beacon coverage valid. Without the column rule only 13 slots.

Replay pattern (0.5-1.7 s, measured legalcopilot-dev 2026-09-27; copy `tests/test_groups_beacon_pad.lua`):
```lua
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
H.new_world("2.0")
local f = assert(io.open("tests/fixtures/groups_ins_stack1.json", "r"))
local fixture = assert(helpers.json_to_table(f:read("*a"))); f:close()
local state = Groups.begin(fixture)
while not state.done do Groups.step(state, {ops = 100}) end
-- base: state.ok == false, one failure BP_P_NO_FIT
```

## What to build

1. `tests/test_groups_pad_faces.lua`:
   - PF1: replay `tests/fixtures/groups_ins_stack1.json` -> `state.ok == true`, no failures; the electromagnetic-plant
     block (find it by the machine's step producing `item/electronic-circuit`) has 15 hands, no hand port on a
     beacon tile, every machine keeps its beacon coverage (`block.beacon_coverage`).
   - PF2: `tests/test_groups_hands_overflow.lua` stays green (its 3rd case: never a hand under a beacon row) — it is in
     the checks list; do not copy it.
   - PF3: replay `tests/fixtures/groups_red1s_foundry.json` (existing) -> same `state.result` as base for every
     block (serialize blocks to a string with sorted keys and compare to a hash you compute on the base commit and
     paste into the test) — guards "passing sheets unchanged".
2. `tests/test_inserter_stack1_delivers.lua` (copy `tests/test_red1s_foundry_delivers.lua`, case
   `player-inserter-10s-stack1`): IS1 generate returns `"ok": true`. ONLY whole-sheet run you may do (about 170 s),
   only as the last step before checks.
3. `logic/bp/groups.lua`: retry trigger + padded-block column rule, short comments citing the block and date.

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_pad_faces.lua, tests/test_inserter_stack1_delivers.lua, docs/tasks/255_groups_pad_faces.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/255`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane255-tests", "command": "git diff --name-only round-45-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_pad_faces\\.lua|tests/test_inserter_stack1_delivers\\.lua|docs/tasks/255_groups_pad_faces\\.md)$' | ( ! grep . ) && git diff --quiet round-45-base HEAD -- docs/tasks && ! git diff round-45-base HEAD -- logic tools | grep -q '^+.*coroutine' && for t in test_groups_pad_faces test_inserter_stack1_delivers test_groups test_groups_beacon_pad test_groups_beacon_row test_groups_belt_split test_groups_buffer test_groups_chunk_retry_ids test_groups_coverage_split test_groups_faces_beacon_rows test_groups_fluid_box_order test_groups_fluid_row test_groups_hand_count test_groups_hands_overflow test_groups_interior_port test_groups_long_hands test_groups_one test_groups_row_inserter_name test_groups_rows test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane255-tests-ok", "expect_exit": 0, "expect_regex": "lane255-tests-ok", "timeout_s": 3000}
{"name": "lane255-fast", "command": "out=$(lua5.2 tests/test_groups_pad_faces.lua 2>&1); for c in PF1 PF3; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane255-ok", "expect_exit": 0, "expect_regex": "lane255-ok", "timeout_s": 600}
```

# bound: 3000s
