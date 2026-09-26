# 238_pipe_prune a pipe tile that connects nothing new is dropped before burial

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-238`, branch `lane/238`,
base tag `round-41-wave2c`, merge target `int/r41`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 30 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/first_stage.lua`, `tests/golden/generate.lua` or any full suite or sheet run of any
kind.** Every check here takes seconds: run only single test files, one at a time, with `lua5.2 tests/<file>.lua`
(lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or fluid name in code**
(tests use made-up ids like `fluid/a`). Every new test must FAIL on the base code (write that in its header comment).

## Explain very simply

On the player's blue science sheet, tidy's re-route pass joined a new petroleum path to its network one tile early,
leaving a 2x2 square of pipes. Its fourth corner (42,11) carries nothing: the validator says
`BP_V_TRANSPORT_UNUSED` and the whole sheet fails. Measured (legalcopilot-dev, 2026-09-26) on a probe tree =
`int/r41` + `docs/tasks/r41_prune_reference.diff`: the blue sheet's first candidate with the real tidy pass then
validates (`FIRST-VALIDATE ok=true`).

## What to build

1. `PipeRuns.prune_redundant(work, h)` exactly as the reference diff, and `PipeRuns.bury` calls it first. A plain
   pipe tile (not a port tile) with 2+ same-flow neighbours (a pipe-to-ground counts only on its open side, plus
   its partner) is dropped when every neighbour still reaches the first neighbour without it (breadth-first, at
   most 64 tiles); its bindings move to that first neighbour's segment; repeat until nothing changes; return the
   count.
2. `tests/test_pipe_prune.lua`, hand-built `work` tables and `h = {key=..., coordinate_from_key=...}`:
   PP1 the blue shape: pipes at (42,11) (43,11) (44,11) (41,12) (42,12) (43,12) (43,13) → exactly (42,11) removed,
   returns 1; PP2 a straight line of 5 pipes → nothing removed; PP3 a square whose corner is a port tile
   (`work.port_cells[key]._port_owners`) → that corner stays; PP4 a pipe beside a pipe-to-ground's CLOSED side
   counts no link there (keep it); PP5 a binding on the removed tile moves to a surviving segment.

## Files this lane owns

logic/bp/pipe_runs.lua, tests/test_pipe_prune.lua, docs/tasks/238_pipe_prune.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/238`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane238-tests", "command": "git diff --name-only round-41-wave2c HEAD | grep -Ev '^(logic/bp/pipe_runs\\.lua|tests/test_pipe_prune\\.lua|docs/tasks/238_pipe_prune\\.md)$' | ( ! grep . ) && git diff --quiet round-41-wave2c HEAD -- docs/tasks/238_pipe_prune.md && ! git diff round-41-wave2c HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pipe_prune test_pipe_runs test_red_green_fluid_ports test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane238-tests-ok", "expect_exit": 0, "expect_regex": "lane238-tests-ok", "timeout_s": 1800}
{"name": "lane238-fast", "command": "lua5.2 tests/test_pipe_prune.lua 2>&1 | grep -q 'PP1' && lua5.2 tests/test_pipe_prune.lua 2>&1 | tail -1 | grep -q ' 0 failed' && echo lane238-ok", "expect_exit": 0, "expect_regex": "lane238-ok", "timeout_s": 120}
```

# bound: 1800s
