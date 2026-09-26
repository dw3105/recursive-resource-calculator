# 234_pipe_runs a straight run of plain pipes is buried as one pipe-to-ground pair

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-234`, branch `lane/234`,
base tag `round-41-wave2`, merge target `int/r41`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Touch only the files this lane
owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh`,
`tools/measure_sheet.sh`, `tools/gate_sheet.sh` or any full suite of any kind.** Run only single test files, one at
a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the fast check below (it stops at the first candidate).
Never use `coroutine`. Plain data only. `require` only at file top level (`tests/test_no_runtime_require.lua`).
**No game item or fluid name in code** (`tests/test_no_item_names.lua`; tests use made-up ids like `fluid/a`).
Every new test must FAIL on the base code (write that in the test's header comment).

## Explain very simply

The player's hand fix of red + green science 10/s used 28 pipes + 18 pipe-to-ground where we laid long straight runs
of plain pipe. One pipe-to-ground pair replaces any straight run of 3 or more pipes: fewer entities, and a buried
span touches no neighbour, so it cannot mix fluids.

Base already calls `PipeRuns.bury(work, h)` from `logic/bp/route.lua` `result_for` when publishing (tidy's final
result, before validation), with route's helpers in `h`. It is a stub returning 0 in `logic/bp/pipe_runs.lua`.

Measured (legalcopilot-dev, 2026-09-26) on a probe tree = `int/r41` after wave 1 + `PROBE_PIPERUN` of
`docs/tasks/r41_pipe_runs_reference.diff` (`bury_pipe_runs`, entity for entity), all 9 bytes sheets ok and lane_sim
0/0/0, draftsman loads each, none worse: red-green 624 -> 608, red-10s-bulk 200 -> 188, red-10s 257 -> 247,
red-10s-stack1 277 -> 262, red-1s-bulk 114 -> 104, inserter-10s 365 -> 348, inserter-10s-bulk 265 -> 217, red-1s 148
and green-1s 302 unchanged. The first red-green candidate then holds 26 pipes, 26 pipe-to-ground, 608 entities.

## What to build

1. `PipeRuns.bury(work, h)` = the probe's `bury_pipe_runs` (without the env flag), using `h.*` for route's helpers
   and `require "logic.bp.grid"` for `Grid`. Rules, exactly as the probe:
   - Scan EAST then SOUTH lines of plain (not underground, not removed) pipe segments of one flow.
   - A tile may be inside a buried span only when it is not a port tile (`work.port_cells[key]._port_owners`), no
     same-flow pipe sits on either SIDE of it, and neither side tile is a port tile.
   - Spans of 3..(reach+1) tiles, reach = `h.finite(work.pipe.underground_max_distance, 10)`.
   - The tile before the span and the tile after it must each be a same-flow pipe that connects back (plain pipe,
     or a pipe-to-ground whose `direction` points at the span end).
   - Replace the span by one underground pair segment (entry = first tile, dir opposite the scan direction; exit =
     last tile, dir = scan direction), merge allocations (one per flow+sink), mark old segments and entities
     `_route_removed`, move bindings to the new segment, update `segments_by_cell`, `underground_cells`,
     `entity_by_segment`; drop removed segments from `work.segments`. Return the number of pairs laid.
2. `tests/test_pipe_runs.lua`, hand-built `work` tables (no sheet run): PR1 a 6-tile straight pipe between two pipes
   → one pair, interior gone, both ends open outward; PR2 a run with a same-flow side branch at tile 3 → that tile
   stays a plain pipe; PR3 a run touching a port tile → not buried there; PR4 a 2-tile run → unchanged; PR5 a 14-tile
   run with reach 10 → split, no span longer than reach + 1 tiles.

## Files this lane owns

logic/bp/pipe_runs.lua, tests/test_pipe_runs.lua, docs/tasks/234_pipe_runs.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/234`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane234-tests", "command": "git diff --name-only round-41-wave2 HEAD | grep -Ev '^(logic/bp/pipe_runs\\.lua|tests/test_pipe_runs\\.lua|docs/tasks/234_pipe_runs\\.md)$' | ( ! grep . ) && git diff --quiet round-41-wave2 HEAD -- docs/tasks/234_pipe_runs.md && ! git diff round-41-wave2 HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pipe_runs test_red_green_fluid_ports test_route_fluid_port_ptg test_validate_ptg_sides test_route_bury test_fluid_touch test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane234-tests-ok", "expect_exit": 0, "expect_regex": "lane234-tests-ok", "timeout_s": 3000}
{"name": "lane234-fast", "command": "f=$(mktemp); lua5.2 tools/capture_stage_input.lua tests/golden/cases/player-red-green-science-10s/prepared_input.json $f validate 1 >/dev/null 2>&1; python3 -c \"import json,sys,collections; c=collections.Counter(e.get('name') for e in json.load(open(sys.argv[1]))['candidate']['entities']); print('PIPES', c['pipe'], c['pipe-to-ground'], sum(c.values()))\" $f | grep -qxF 'PIPES 26 26 608' || { echo FAST-WRONG; exit 1; }; echo lane234-ok", "expect_exit": 0, "expect_regex": "lane234-ok", "timeout_s": 1200}
```

# bound: 2400s
