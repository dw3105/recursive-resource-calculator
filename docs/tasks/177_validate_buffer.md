# 177 validate: BP_V_BUFFER_ZONE refuses a machine inside another's buffer zone

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-177`, branch
`lane/177`, base tag `round-25-base`, merge target `int/r25`. Host `legalcopilot-dev`.

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

`logic/bp/validate.lua`. `make_work` (about :771) collects `work.machines` and `work.steps` keyed by
`step_id`; `check_geometry` (about :875) runs first and records `BP_V_COLLISION`. Reason codes are
registered in `logic/bp/reason_codes.lua` (about :34-47). Furnaces carry no `recipe` on the entity: take the
recipe from `work.steps[entity.step_id].recipe`, falling back to `entity.recipe`. The catalog is
`work.catalog` (recipes at `catalog.recipe[name].ingredients`). An entity's tile rectangle comes from its
position and size the same way `check_geometry` gets it (`entity_tile_rect`).

## What to build

1. **`check_buffer_zones(work)`**, run right after `check_geometry`: for every pair of machines (only
   machines: never belts, inserters, poles, roboports, pipes, beacons), build
   `{rect = tile rect, ring = Buffer.ring(work.catalog, recipe), key = Buffer.key(entity.name, recipe)}` and
   record `BP_V_BUFFER_ZONE` with both entity ids and both rects when `Buffer.conflict` is true. Iterate in
   a deterministic order (sort by id).
2. Register `BP_V_BUFFER_ZONE` in `logic/bp/reason_codes.lua`.
3. `tests/test_validate_buffer.lua` (new), rows **red at `round-25-base`**, candidates built like
   `tests/test_validate.lua`:
   - **VB1** two different-recipe assemblers 3 tiles apart: `BP_V_BUFFER_ZONE` names both.
   - **VB2** the same two, 5 tiles apart (ring 2 + ring 2 + 1): no such record.
   - **VB3** two same-recipe assemblers in one column 1 tile apart: no record; shifted by one column: record.
   - **VB4** a belt, an inserter, a pole and a beacon inside a machine's ring: no record.

## Traps

- **Determinism.** Same input, same output. Sort anything you iterate from a hash.
- **Factorio has no coroutines** (`logic/jobs.lua:3`) and job state is saved in `storage`: no closures and
  no coroutines in any state that outlives one call.
- **Never touch** `logic/bp/buffer.lua`, `info.json`, `mod-description.md`, `.agent-lane.toml`, `tools/**`,
  `docs/**` except this task, and every file not listed under "Files this lane owns".

## Files this lane owns

`logic/bp/validate.lua`, `logic/bp/reason_codes.lua`, `tests/test_validate_buffer.lua`

## Commit, THEN check

Commit on `lane/177` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "validate-tests", "command": "git diff --name-only round-25-base HEAD | grep -v '^docs/tasks/177' | grep -Ev '^(logic/bp/validate\\.lua|logic/bp/reason_codes\\.lua|tests/test_validate_buffer\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do for t in test_validate_buffer test_validate test_buffer; do $l tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $l $t; exit 1; }; done; done && echo validate-tests-ok", "expect_exit": 0, "expect_regex": "validate-tests-ok", "timeout_s": 900}
{"name": "validate-probe", "command": "sh tools/first_verdict.sh | tee /tmp/rrc177-first.txt; grep -q 'FIRST-VERDICT' /tmp/rrc177-first.txt && echo validate-probe-ok", "expect_exit": 0, "expect_regex": "validate-probe-ok", "timeout_s": 300}
```

# bound: 2400s
