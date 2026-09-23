# 176 pack: no machine lands in another machine's buffer zone

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-176`, branch
`lane/176`, base tag `round-25-base`, merge target `int/r25`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-25-base`.

## You have about 35 minutes — do NOT stop early

**Do not end your turn until every item under "What to build" exists, is committed, and both checks have
run.** Commit early: after your first working change, commit, then keep improving and commit again.
Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything else, then
say which item and why.

**NEVER run `tests/run.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any other full suite.**
Run only the single test files named in this task, one at a time, with `lua5.2 tests/<file>.lua` and
`lua5.4 tests/<file>.lua`, and the quick probe `sh tools/first_verdict.sh` (about 12 s).

## Explain very simply

The player's rule, 2026-09-23: every producing machine gets an **empty ring** (buffer zone) around it. Ring
width = number of recipe ingredients: 1-2 -> 2 cells, 3 -> 3 cells, 4 or more -> 4 cells. No other machine may
stand in a machine's ring. Belts, undergrounds, splitters, inserters, poles, roboports, pipes and beacons may.
Two machines of the **same machine name and same recipe** may share ring space, but only when they stand in the
**same row** (equal top `y`) or the **same column** (equal left `x`).

The whole rule already exists in `logic/bp/buffer.lua` (read it first; do not edit it) and is tested by
`tests/test_buffer.lua`:

- `Buffer.ring(catalog, recipe)` -> 2, 3 or 4
- `Buffer.key(machine_name, recipe)`
- `Buffer.zone(rect, ring)` -> the footprint grown by `ring`
- `Buffer.conflict(a, b)` with `a = {rect = {x, y, w, h}, ring = n, key = k}` -> true when the two machines
  break the rule

Use these functions; never re-implement the rule.

## Where the code is

- `logic/bp/pack.lua`: MaxRects with best-short-side-fit. `Pack.begin` builds free regions; `copy_block`
  (about :60) copies only known block fields into pack state; `scan_origin` (about :312) scores one origin;
  `place` (about :390) commits a placement (and reserves a one-sided margin ring). Rotation of a block-frame
  rectangle to the world: `Grid.rotate_rect(x, y, w, h, block_w, block_h, dir)` (`logic/bp/grid.lua`).
- `logic/bp/search.lua` `candidate_fits_grid` (about :1495): an area pre-check with block w/h plus one tile
  per port side.

Blocks will arrive with `block.buffer_zones = {{x, y, w, h, ring, key}, ...}` in block frame (machine
footprints). A block without `buffer_zones` behaves exactly as today.

## What to build

1. `copy_block` keeps `buffer_zones`.
2. **Zone-aware origins.** For each candidate origin and direction, rotate the block's zones to world
   coordinates; refuse the origin if any of them `Buffer.conflict`s with a zone already placed. `place`
   stores the placed block's world zones on state (a plain list, sorted by insertion). Keep today's
   one-sided margin ring as it is. Keep the round 23-24 op accounting and resumable scan intact.
3. **Fit pre-check.** `candidate_fits_grid` adds each machine's ring to its area lower bound (a machine needs
   at least `(w + ring) * (h + ring)` tiles), so a candidate that cannot fit is refused before packing.
   Touch nothing else in `search.lua`.
4. `tests/test_pack_buffer.lua` (new), rows **red at `round-25-base`**, fixtures with hand-built
   `buffer_zones` (do not depend on `logic/bp/groups.lua`):
   - **PZ1** two blocks with different keys, ring 2 each: the second never lands with fewer than 4 empty
     tiles between the machine footprints.
   - **PZ2** two blocks with the same key: they may pack closer, but only in one row or one column.
   - **PZ3** packing with budget 1 op per call and 10^9 ops gives identical placements.
   - **PZ4** a block without `buffer_zones` packs exactly as today (compare against `round-25-base` output
     stored in the test).

## Traps

- **Determinism.** Same input, same output. Sort anything you iterate from a hash.
- **Factorio has no coroutines** (`logic/jobs.lua:3`) and job state is saved in `storage`: no closures and
  no coroutines in any state that outlives one call.
- **Never touch** `logic/bp/buffer.lua`, `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
  `docs/**` except this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/pack.lua`, `logic/bp/search.lua`, `tests/test_pack_buffer.lua`

## Commit, THEN check

Commit on `lane/176` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "pack-tests", "command": "git diff --name-only round-25-base HEAD | grep -v '^docs/tasks/176' | grep -Ev '^(logic/bp/pack\\.lua|logic/bp/search\\.lua|tests/test_pack_buffer\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_pack_buffer test_pack test_pack_budget test_port_edges test_buffer; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo pack-tests-ok", "expect_exit": 0, "expect_regex": "pack-tests-ok", "timeout_s": 900}
{"name": "pack-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc176-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc176-first.txt && echo pack-probe-ok", "expect_exit": 0, "expect_regex": "pack-probe-ok", "timeout_s": 300}
```

# bound: 2400s
