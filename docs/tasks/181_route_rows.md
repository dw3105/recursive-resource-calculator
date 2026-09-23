# 181 route: lay row belt runs as fixed segments and feed their heads

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-181`, branch
`lane/181`, base tag `round-26-base`, merge target `int/r26`. Host `legalcopilot-dev`.

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

- `logic/bp/route.lua`: `Route.begin` -> `normalize_input` (endpoints, obstacles, demands,
  `reserve_port_cells`); `append_normal_path` commits a path as per-tile segments with `allocations` per flow
  and sink; a belt may carry two flows (`segment_flow_count < 2`, `work.multi_flow_hands`);
  `route_chain_walk` follows laid runs; `improve_routes` / `improve_step` re-route bindings (resumable, round
  24); `lift_binding` lifts a binding's own tiles.
- `logic/bp/search.lua` `make_route_input` builds the route input from the placed blocks.

## What to build

1. `make_route_input` passes `input.belt_runs` = every placed block's `belt_runs` (world), in a stable order.
   Touch nothing else in `search.lua`.
2. **Lay every run at `Route.begin`** as fixed segments along `tiles` in `dir`, before any demand is searched:
   input runs carry both flows (one allocation per flow for the hands they serve), output runs carry their
   flow. Mark them fixed so `improve_step` / `lift_binding` never lift them and no demand overwrites them.
3. **Demands meet the runs**: a flow's demand toward a row ends on its feed `side_tile` travelling
   `travel_dir` into the head (a side-load onto the head); the row's output demand starts at `port`. The
   bindings still name the row's ports, so the validator's port checks hold.
4. `tests/test_route_rows.lua` (new), rows red at `round-26-base`, with `RowFixture.science_row` placed on a
   grid with perimeter sources for copper and gears and a perimeter sink for packs:
   - **RR1** the route finishes ok; every input run tile holds a belt in `dir` carrying both flows; every
     output run tile holds a belt carrying packs.
   - **RR2** copper's path ends on its feed side tile heading into the head; gears likewise from the other
     side; nothing enters the head from behind.
   - **RR3** the same with `Grid.EAST`.
   - **RR4** after the improve pass the run segments are unchanged.

## Traps

- **Determinism**; **no coroutines, no closures in saved state** (`logic/jobs.lua:3`).
- **Never touch** `docs/contracts/row_block.md`, `tests/fixtures/row_block.lua`, `logic/bp/buffer.lua`,
  `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`, `docs/**` except this task, and any file
  not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route_rows.lua`

## Commit, THEN check

Commit on `lane/181` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "route-tests", "command": "git diff --name-only round-26-base HEAD | grep -v '^docs/tasks/181' | grep -Ev '^(logic/bp/route\\.lua|logic/bp/search\\.lua|tests/test_route_rows\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_route_rows test_route_hand_slide test_route_improve test_route_bury test_placed_port_geometry; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo route-tests-ok", "expect_exit": 0, "expect_regex": "route-tests-ok", "timeout_s": 1200}
{"name": "route-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc181-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc181-first.txt && echo route-probe-ok", "expect_exit": 0, "expect_regex": "route-probe-ok", "timeout_s": 300}
```

# bound: 2400s
