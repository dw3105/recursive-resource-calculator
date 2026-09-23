# 175 groups: every block carries buffer zones; different recipes never share a block

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-175`, branch
`lane/175`, base tag `round-25-base`, merge target `int/r25`. Host `legalcopilot-dev`.

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

`logic/bp/groups.lua`. A block is built in `build_block` (about :966) with `members` (machines, inserters,
beacons), `w`, `h`, ports. Machines of one step sit in one line with 1-tile gaps (:1035-1039, :1167).
`partition_specs` (about :1713) can join SEVERAL steps into one block when `step_can_join` (about :259)
allows it. The step's recipe name is `step.recipe`; the catalog is available where the plan is normalized
(`normalize_plan`, about :249; recipes at `catalog.recipe[name].ingredients`). Furnaces carry no `recipe` on
the entity, so always take the recipe from the step.

## What to build

1. **Zones on every block.** After a block's members are final, set
   `block.buffer_zones = {{x = <machine member x>, y = <y>, w = <w>, h = <h>, ring = Buffer.ring(catalog,
   step.recipe), key = Buffer.key(machine_name, step.recipe)}, ...}`, one per machine member, in the
   block's own frame (same frame as `members`), sorted by (y, x).
2. **No mixed-recipe blocks.** `step_can_join` refuses to join two steps whose recipes differ, or whose
   machine names differ. Same-step machines stay in one line (row or column) as today, so they satisfy the
   rule.
3. **In-block check.** For every pair of zones inside one block, `Buffer.conflict` is false (assert this in
   the test, and make the builder guarantee it).
4. `tests/test_groups_buffer.lua` (new), rows **red at `round-25-base`**, both shapes via `H.shapes()`,
   fixtures built like `tests/test_groups.lua`:
   - **GB1** a 2-ingredient step with 2 machines: its block has 2 `buffer_zones`, ring 2, same key, same row
     or column, and no conflict.
   - **GB2** a 3-ingredient step gets ring 3; a 5-ingredient step gets ring 4.
   - **GB3** two steps that `step_can_join` accepted at `round-25-base` but have different recipes now land in
     separate blocks.

## Traps

- **Determinism.** Same input, same output. Sort anything you iterate from a hash.
- **Factorio has no coroutines** (`logic/jobs.lua:3`) and job state is saved in `storage`: no closures and
  no coroutines in any state that outlives one call.
- **Never touch** `logic/bp/buffer.lua`, `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
  `docs/**` except this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_groups_buffer.lua`

## Commit, THEN check

Commit on `lane/175` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "groups-tests", "command": "git diff --name-only round-25-base HEAD | grep -v '^docs/tasks/175' | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_buffer\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_groups_buffer test_groups test_inserter_geometry test_beacon_coverage test_buffer; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo groups-tests-ok", "expect_exit": 0, "expect_regex": "groups-tests-ok", "timeout_s": 900}
{"name": "groups-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc175-first.txt; grep -q 'FIRST-VERDICT ok=true' /tmp/rrc175-first.txt && echo groups-probe-ok", "expect_exit": 0, "expect_regex": "groups-probe-ok", "timeout_s": 300}
```

# bound: 2400s
