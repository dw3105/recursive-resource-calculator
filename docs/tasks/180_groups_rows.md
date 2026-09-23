# 180 groups: same-recipe machines built as one touching row with shared belt runs

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-180`, branch
`lane/180`, base tag `round-26-base`, merge target `int/r26`. Host `legalcopilot-dev`.

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

`logic/bp/groups.lua`:
- `make_candidates` (about :1865-1893) splits a step with more than 2 distinct item flows and more than one
  machine into single-machine `_force_block` fragments, because a row has only two long sides.
- `build_block` (about :999-1171) lays machines out: `face_layout` (column, at most 2 machines) or the
  horizontal strip (`x += layout_w + 1`).
- Face assignment (about :1192-1368): the strip already puts flow 1 on `top` and flow 2 on `bottom` when there
  are at most 2 flows (:1233-1253).
- Hand pairing: `hand_groups_for` (about :575-611) pairs two inputs into one hand when `multi_flow_hands`.
- `block_ports` (about :769-968) makes one port per hand.
- `allowed_dirs = {NORTH}` (about :976).
- `Groups.materialize` (about :1983-2093) rotates members and ports.

## What to build

1. **Row layout** for a step with N >= 2 machines when, after hand pairing, each machine has at most one input
   hand and one output hand (at most 2 item inputs, paired, and one item output): machines **touching**
   (`x = x0 + i * w`), input hand on the top face and output hand on the bottom face, both in the machine's
   middle column. Only then; every other step is built exactly as today.
2. **The `_force_block` split** applies only when a row is impossible. The science step (copper + gear -> pack,
   4 machines) must become ONE row block.
3. **`block.row`, `block.belt_runs`** and the ports exactly as `docs/contracts/row_block.md` says, in the block
   frame: input run with head one tile before the first pickup tile, two feeds (flow 1 from the run's left
   side, flow 2 from its right side), output run with one port after its last tile. ONE port per flow per row
   (the feed side tiles, the output port); hands keep `port_id` naming the row port they are served by. Port
   attach geometry must stay legal for `tests/test_port_edges.lua` (attach on the block boundary, normal
   inward).
4. **`Groups.materialize`** returns `placed.belt_runs` in world coordinates for every direction, matching
   `RowFixture.science_row(dir, ...)` when the block is placed like the fixture.
5. **Rows get `allowed_dirs = {NORTH, EAST}`**; other blocks keep `{NORTH}`. `buffer_zones` per machine as today.
6. `tests/test_groups_rows.lua` (new), rows red at `round-26-base`:
   - **GR1** a 4-machine copper+gear -> pack step yields one block with `row.machines == 4`, touching machines,
     one paired input hand per machine on the top face and one output hand on the bottom face.
   - **GR2** its `belt_runs` and ports match the contract: every pickup tile on the input run, head first,
     feeds adjacent to the head, one port per flow.
   - **GR3** `Groups.materialize` with `NORTH` and `EAST` places runs, hands and machines like
     `RowFixture.science_row` (compare relative positions).
   - **GR4** a 1-machine step and a step with 3 item inputs are built exactly as today.

## Traps

- **Determinism**; **no coroutines, no closures in saved state** (`logic/jobs.lua:3`).
- **Never touch** `docs/contracts/row_block.md`, `tests/fixtures/row_block.lua`, `logic/bp/buffer.lua`,
  `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except this task, and any file
  not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_groups_rows.lua`

## Commit, THEN check

Commit on `lane/180` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "groups-tests", "command": "git diff --name-only round-26-base HEAD | grep -v '^docs/tasks/180' | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_rows\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_groups_rows test_groups test_groups_buffer test_inserter_geometry test_beacon_coverage test_port_edges test_buffer; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo groups-tests-ok", "expect_exit": 0, "expect_regex": "groups-tests-ok", "timeout_s": 1200}
{"name": "groups-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc180-first.txt; grep -q 'FIRST-VERDICT' /tmp/rrc180-first.txt && echo groups-probe-ok", "expect_exit": 0, "expect_regex": "groups-probe-ok", "timeout_s": 300}
```

# bound: 2400s
