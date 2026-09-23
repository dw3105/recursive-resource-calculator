# 182 validate: BP_V_LANE_MIX, paired input flows ride different lanes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-182`, branch
`lane/182`, base tag `round-26-base`, merge target `int/r26`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 35 minutes — do NOT stop early

Commit early, commit again, then run the checks LAST. Stopping with uncommitted work is a failed lane.

**NEVER run `tests/run.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full suite.** Run only
the single test files named here, one at a time, with `lua5.2 tests/<file>.lua` and `lua5.4 tests/<file>.lua`,
and the quick probe `sh tools/first_verdict.sh` (about 12 s).

## Explain very simply

The player's rule: machines of one machine name and one recipe may stand touching in one row or column
(`logic/bp/buffer.lua`). So a step with several machines becomes ONE **row block**: machines touching, one input
belt along the top, one output belt along the bottom, one inserter per machine on each side. The packer places
the row once and may turn it 90 degrees. The science row has two inputs (copper plates and gears) on ONE belt:
copper rides the left lane, gears the right lane, filled at a **head tile** before the first machine by
side-loading from both sides.

**Read first:** `docs/contracts/row_block.md` (the exact shapes every part of the mod uses) and
`tests/fixtures/row_block.lua` (`RowFixture.science_row(dir, ox, oy)`: one placed science row built by hand,
in `Grid.NORTH` and `Grid.EAST`). Code against those shapes; test with that fixture; never change them.

## Where the code is

`logic/bp/validate.lua`: `check_transport_shapes` (about :1398) already simulates belt lanes (left/right per
tile, seeded from inserter drop tiles and feeds, side-loads onto the near lane, underground/splitter rules).
`transfer_cells` finds each inserter's pickup/drop tile. Reason codes live in `logic/bp/reason_codes.lua`.
A paired input hand has `flow_ids = {A, B}` (contract 28.1/28.3).

## What to build

1. **Lane witness per flow**: extend the lane simulation to track WHICH flow rides each lane (seed each flow
   where it enters: a producing inserter's drop tile, an input port / side-load). For every input hand with
   two flows, its pickup tile must carry each flow, and the two flows must ride different lanes. Otherwise
   record `BP_V_LANE_MIX` with the hand id, the tile, and the flows found per lane.
2. Register `BP_V_LANE_MIX` in `logic/bp/reason_codes.lua`.
3. `tests/test_validate_rows.lua` (new), rows red at `round-26-base`, candidates built from
   `RowFixture.science_row` plus belts along its runs and short feed belts:
   - **VL1** copper side-loaded from the left, gears from the right: no `BP_V_LANE_MIX`.
   - **VL2** both flows side-loaded from the same side: `BP_V_LANE_MIX` names the hands.
   - **VL3** gears never reach the run: `BP_V_LANE_MIX`.
   - **VL4** a single-flow hand is never judged by this check.

## Traps

- **Determinism**; **no coroutines, no closures in saved state** (`logic/jobs.lua:3`).
- **Never touch** `docs/contracts/row_block.md`, `tests/fixtures/row_block.lua`, `logic/bp/buffer.lua`,
  `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except this task, and any file
  not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/validate.lua`, `logic/bp/reason_codes.lua`, `tests/test_validate_rows.lua`

## Commit, THEN check

Commit on `lane/182` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "validate-tests", "command": "git diff --name-only round-26-base HEAD | grep -v '^docs/tasks/182' | grep -Ev '^(logic/bp/validate\\.lua|logic/bp/reason_codes\\.lua|tests/test_validate_rows\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_validate_rows test_validate test_validate_transport_shapes test_validate_buffer; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo validate-tests-ok", "expect_exit": 0, "expect_regex": "validate-tests-ok", "timeout_s": 1200}
{"name": "validate-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc182-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc182-first.txt && echo validate-probe-ok", "expect_exit": 0, "expect_regex": "validate-probe-ok", "timeout_s": 300}
```

# bound: 2400s
