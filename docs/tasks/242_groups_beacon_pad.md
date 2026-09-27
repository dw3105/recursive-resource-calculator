# 242_groups_beacon_pad a lone machine short of beacons gets one retry with room for a beacon on its left

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-242`, branch `lane/242`,
base tag `round-43-base`, merge target `int/r43`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 30 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/game_test.sh`, `tools/game_load_check.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). The one generator run allowed is inside `tests/test_red1s_foundry_delivers.lua`
(37 s red, 5 s green). Never use `coroutine`. `require` only at file top level. **No game item or entity name in
`logic/`.** Every new test must FAIL on the base code (write that in its header comment).

## Explain very simply

The player's red science 1/s sheet (`tests/golden/cases/player-red-science-1s-foundry`, export 1.1.95, 2026-09-27)
gets no blueprint: `BP_FAIL_NO_LAYOUT`. Every one of 98 attempts is refused in groups:
`BP_P_NO_FIT configured beacon coverage cannot be split` (`logic/bp/groups.lua` in `make_candidates_once`).

Only one block fails: the lone red-science machine that wants 3 beacons. It is a face layout block (1-2 machines,
hands on the machine faces), so its strip starts at `machine_x0 = 1` and `row_x` returns `machine_x0`: the beacon
row starts flush with the machine and only goes right. Beacons land at x=1, 4, 7; the machine spans x=1..4; the
beacon at x=7 is too far and covers nothing: `got=2 req=3`. Non-face blocks already pad the strip one beacon
width on the left (`machine_x0 = math.max(machine_x0, row.w)`); face layout never does.

Fix: when a block misses its beacon coverage and cannot be split further, retry it ONCE with `_beacon_pad = true`:
the machine strip moves right by one beacon width and the beacon row starts at x=1, so beacons at x=1, 4, 7
straddle the machine at x=4..7 and all 3 reach it.

Measured with exactly these three edits patched in memory (legalcopilot-dev, 2026-09-27): the player sheet builds
`ok=true` in 4.8 s, 81 entities, lane sim `mixed=0 starved=0 bleed=0`, red-science machine reached by 3 beacons;
the frozen fixture groups with 0 failures in 0.6 s; the pad retry fires 0 times on the 10 other golden sheets and
their bytes do not move.

## What to build

1. `tests/test_groups_beacon_pad.lua` (copy the shape of `tests/test_groups_coverage_split.lua`), fixture
   `tests/fixtures/groups_red1s_foundry.json` (already in the base, `Groups.begin({plan = fixture.plan,
   catalog = fixture.catalog})`, step with `{ops = 100}` until done):
   - BP1 grouping succeeds: `state.ok == true`, 0 failures.
   - BP2 every physical machine gets its configured beacon count by signature (same check as the coverage split
     test), and every machine of plan step `automation-science-pack` gets at least 3.
   - BP3 every beacon of every block lies inside its block: `x >= 0`, `y >= 0`, `x + w <= block.w`,
     `y + h <= block.h`.
   - BP4 no member of any block overlaps another member of that block (tile rectangles).
   Commit it red first.
2. `tests/test_red1s_foundry_delivers.lua` (copy `tests/test_red10s_bulk_delivers.lua`): generate
   `tests/golden/cases/player-red-science-1s-foundry/prepared_input.json` → result has `"ok":true`. Commit red.
3. `logic/bp/groups.lua`, three edits:
   a. In `build_block`, the loop that sets `machine_x0` from `beacon_row_specs`: add
      `if face_layout and steps[1]._beacon_pad then machine_x0 = math.max(machine_x0, 1 + row.w) end`.
   b. In `build_block`, `row_x`: `return face_layout and (steps[1]._beacon_pad and 1 or machine_x0) or 0`.
   c. In `make_candidates_once`, the `if block.invalid_coverage and machine_total > 1 then ... else failure end`
      chain: add before the `else`:
      ```lua
      elseif block.invalid_coverage and not block.failure and not group[1]._beacon_pad then
          local padded = copy(group[1])
          padded._beacon_pad = true
          table.insert(work.buckets, work.bucket_index + 1, {padded})
      ```
      with a comment saying why (a face layout strip starts flush at the block's left edge, so its beacon row
      reaches a lone machine from one side only; 3 beacons per row never fit; the padded retry gives the row a
      beacon width on the left).
   Update the comments above `machine_x0` and `row_x` so they state the padded case.

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_beacon_pad.lua, tests/test_red1s_foundry_delivers.lua,
docs/tasks/242_groups_beacon_pad.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/242`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane242-tests", "command": "git diff --name-only round-43-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_beacon_pad\\.lua|tests/test_red1s_foundry_delivers\\.lua|docs/tasks/242_groups_beacon_pad\\.md)$' | ( ! grep . ) && git diff --quiet round-43-base HEAD -- docs/tasks/242_groups_beacon_pad.md && ! git diff round-43-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_beacon_pad test_red1s_foundry_delivers test_groups_coverage_split test_groups_beacon_row test_beacon_coverage test_beacon_placement_incident test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane242-tests-ok", "expect_exit": 0, "expect_regex": "lane242-tests-ok", "timeout_s": 1800}
{"name": "lane242-fast", "command": "lua5.2 tests/test_groups_beacon_pad.lua 2>&1 | grep -q 'BP1' && lua5.2 tests/test_groups_beacon_pad.lua 2>&1 | tail -1 | grep -q ' 0 failed' && echo lane242-ok", "expect_exit": 0, "expect_regex": "lane242-ok", "timeout_s": 120}
```

# bound: 1800s
