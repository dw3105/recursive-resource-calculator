# 178 tests: test_search BP-20 comparison rows validate their two candidates

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-178`, branch
`lane/178`, base tag `round-25-fix2`, merge target `int/r25`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 35 minutes — do NOT stop early

Commit early, commit again, then run the checks LAST. Stopping with uncommitted work is a failed lane.

**NEVER run `tests/run.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full suite.** Run only
the single test files named here, one at a time, with `lua5.2 tests/<file>.lua` and `lua5.4 tests/<file>.lua`,
and the quick probe `sh tools/first_verdict.sh` (about 12 s).

## Explain very simply

The whole test suite must be green before this work merges to `main`. One old test file is still red. Find
the real cause, fix it, and prove the fix with that one file. A test that asserts the wrong thing is fixed in
the test with a comment naming the measurement; a real bug is fixed in the code. Never loosen an assertion
just to make it pass.

The machine buffer-zone rule (`logic/bp/buffer.lua`, read it) is new and correct: two different machines need
both rings of empty tiles between them; the same machine and recipe may share ring space in one row or column.

## The red rows

`tests/test_search.lua` BP-20 "the better candidate found second wins", "the better first candidate survives
a worse follow-up", "equal beacon counts defer to footprint area" (both shapes: 6 failures; 48 of 54 pass).
Red since at least round 18 (`c14ad83`). History measured 2026-09-23 on legalcopilot-dev:

- the fixture grid was 3x5 and the blocks (`block:a` 2x3, `block:b` 3x3, beacon rows) never fit:
  `BP_P_NO_FIT` in pack. Round 25 fix loop set the grid to 10x10 (`comparison_input`), so packing now
  succeeds;
- now every candidate is refused by the validator with `BP_V_BEACON_REDUNDANT` ("removing beacon leaves every
  configured beacon count satisfied", `logic/bp/validate.lua` about :1037): the beacons built for
  `comparison_group("group-a"/"group-b")` influence no machine, or match no group. The rows then end
  `BP_FAIL_NO_LAYOUT_GRID_LIMIT`.

## What to build

1. Find why those beacons are redundant: print (temporarily) each beacon's rect, supply area, and the
   machines it influences, using the fixture's catalog (`comparison_catalog`, `base_catalog`).
2. Fix the cause. If the fixture's beacon/catalog data is wrong (for example no supply area), fix the fixture
   with a comment. If `logic/bp/groups.lua` places a beacon that cannot reach its machine, fix groups. Do not
   touch `logic/bp/validate.lua`.
3. `tests/test_search.lua` must reach 54 of 54 on both interpreters.

## Traps

- **Determinism** and **no coroutines, no closures in saved state** (`logic/jobs.lua:3`).
- **Never touch** `logic/bp/buffer.lua`, `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
  `docs/**` except this task, and any file not listed under "Files this lane owns".

## Files this lane owns

`tests/test_search.lua`, `logic/bp/groups.lua`

## Commit, THEN check

Commit on `lane/178` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "search-rows", "command": "git diff --name-only round-25-fix2 HEAD | grep -v '^docs/tasks/178' | grep -Ev '^(tests/test_search\\.lua|logic/bp/groups\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_search test_groups test_groups_buffer test_beacon_coverage test_beacon_placement_incident; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo search-rows-ok", "expect_exit": 0, "expect_regex": "search-rows-ok", "timeout_s": 1500}
{"name": "search-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc178-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc178-first.txt && echo search-probe-ok", "expect_exit": 0, "expect_regex": "search-probe-ok", "timeout_s": 300}
```

# bound: 2400s
