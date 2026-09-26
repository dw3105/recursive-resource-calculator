# 233_groups_fluid_box_even_head each fluid of a machine gets its own fluid box; a row head clears its first hand

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-233`, branch `lane/233`,
base tag `round-41-base`, merge target `int/r41`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Touch only the files this lane
owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh`,
`tools/measure_sheet.sh`, `tools/gate_sheet.sh` or any full suite of any kind.** Run only single test files, one at
a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the fast checks `tools/first_verdict.sh <case>`,
`tools/first_route.sh <case>` (each stops at the first candidate). Never use `coroutine`. Plain data only.
`require` only at file top level (`tests/test_no_runtime_require.lua`). **No game item or fluid name in code**
(`tests/test_no_item_names.lua`; tests use made-up ids like `fluid/a`). Every new test must FAIL on the base code
(write that in the test's header comment). The reference for every rule is `docs/tasks/r41_probe_reference.diff`
(a probe tree with env flags; port the named flags' code exactly, without the flags and without any `io.stderr`).

## Explain very simply

The player's blue science 10/s sheet hung in "placing blocks" in game (offline: 30 min, no layout). Two groups
bugs, both measured (legalcopilot-dev, 2026-09-26):

- An oil refinery takes water + crude and makes heavy oil, light oil, petroleum. `fluid_connection`
  (`logic/bp/groups.lua:110`) gives EVERY fluid of one role the same box, so crude and water ports land on one
  tile, and all three outputs on one tile. Pack then refuses every origin (`choose_port_slots`), on every grid,
  forever. The engine assigns a recipe's fluids to a machine's unfiltered boxes IN ORDER: 1st fluid ingredient →
  1st input box, 2nd → 2nd; 1st fluid product → 1st output box, and so on (the catalog carries recipe order and
  box `production_type`).
- An electromagnetic plant is 4x4 (even width). A row block puts its belt head at
  `first_x = machine.x + floor(w / 2)` (`groups.lua:1978`) but the plain hand at `machine.x + floor((w - 1) / 2)`.
  For odd widths these match; for 4 wide the second input's side-feed tile IS the hand tile, so route says
  `BP_R_PORT_BLOCKED` for electronic circuits into the advanced-circuit row.

Measured on the probe tree with `PROBE_BOX` + `PROBE_FX` only:
`sh tools/first_route.sh player-blue-science-10s` prints
`FIRST-ROUTE ok=false BP_R_FLUID_MIX=1 flow=fluid/petroleum-gas src=13,20 sink=48,11` (pack fits, the e-circuit
port is reachable; the fluid mix is later work, not this task's).

## What to build

In `logic/bp/groups.lua`, exactly as the `PROBE_BOX` and `PROBE_FX` parts of the reference diff:

1. `fluid_connection`: when the entry names no box and the step's recipe (`catalog.recipe[step.recipe]`) has TWO
   or more fluids of this role (ingredients for input, results/products for output), the k-th of them (by
   `"fluid/" .. name` == the entry's flow id) takes the k-th box whose `production_type` is this role, in box
   index order. One fluid of that role: behaviour unchanged (other sheets must stay byte-identical).
2. Row block: `first_x = machine.x + floor((machine.w - 1) / 2)` (same value for odd widths).
3. `tests/test_groups_fluid_box_order.lua`: FB1 a 5x5 machine with 2 input boxes + 3 output boxes and a recipe of
   2 fluid ingredients + 3 fluid products → ports on 5 distinct tiles, k-th fluid on k-th box; FB2 a recipe with one
   fluid input and one item input keeps today's box. `tests/test_row_even_width.lua`: RW1 a row of 4x4 machines
   with two input flows → the second feed's side tile is no hand tile and not inside any member; RW2 a 3x3 row is
   unchanged (same ports as base).

## Files this lane owns

logic/bp/groups.lua, tests/test_groups_fluid_box_order.lua, tests/test_row_even_width.lua, docs/tasks/233_groups_fluid_box_even_head.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/233`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane233-tests", "command": "git diff --name-only round-41-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_fluid_box_order\\.lua|tests/test_row_even_width\\.lua|docs/tasks/233_groups_fluid_box_even_head\\.md)$' | ( ! grep . ) && git diff --quiet round-41-base HEAD -- docs/tasks/233_groups_fluid_box_even_head.md && ! git diff round-41-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_fluid_box_order test_row_even_width test_fluid_box test_groups_fluid_row test_groups test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane233-tests-ok", "expect_exit": 0, "expect_regex": "lane233-tests-ok", "timeout_s": 3000}
{"name": "lane233-fast", "command": "sh tools/first_route.sh player-blue-science-10s | grep -qxF 'FIRST-ROUTE ok=false BP_R_FLUID_MIX=1 flow=fluid/petroleum-gas src=13,20 sink=48,11' || { echo FAST-WRONG; exit 1; }; echo lane233-ok", "expect_exit": 0, "expect_regex": "lane233-ok", "timeout_s": 900}
```

# bound: 2400s
