# 232_validate_ptg_sides the validator joins a pipe-to-ground only on its open side

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-232`, branch `lane/232`,
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

The player's red + green science 10/s blueprint (round 40) built but 5 of 8 casting foundries got no fluid: a
pipe-to-ground stood on each foundry's fluid port tile opening AWAY from the foundry. In the engine a
pipe-to-ground joins ONLY its open side (the tile its `dir` points at) and its underground partner. The validator
walk (`transport_neighbors`, `logic/bp/validate.lua:588`) joins every pipe on all four sides, and the fluid-box
check (`fluid_connection_cells` then `connection_path`) starts on the port tile without asking which way a
pipe-to-ground there opens. So it accepted a factory that does not run.

Measured (legalcopilot-dev, 2026-09-26) on the probe tree with `PROBE_VPTG` only: the frozen round-40 candidate
`tests/fixtures/validate_red_green_r40_c1.json` gives exactly five `BP_V_FLUID_DISCONNECTED` (casting-copper,
casting-copper-cable, both gear foundries, casting-iron 2) — `tests/test_red_green_fluid_ports.lua` RGF1 passes.

## What to build

In `logic/bp/validate.lua`, exactly as the `PROBE_VPTG` parts of the reference diff:

1. `transport_neighbors`, pipes: a pipe-to-ground (name contains `pipe-to-ground` or `type == "pipe-to-ground"`)
   reaches only the tile at its `dir` vector plus its pair; a neighbour that is a pipe-to-ground is joined only when
   ITS open side faces back to this tile (its pair always).
2. Fluid box, both the input and the output loop: a connection cell holding a pipe-to-ground whose direction is
   not `Grid.dir_opposite(connection.direction)` does not connect (try the next connection; none left →
   `BP_V_FLUID_DISCONNECTED` as today).
3. `tests/test_validate_ptg_sides.lua`, hand-built `Validate.begin` inputs (see
   `tests/test_validate_fluid_port.lua`): VS1 a plain pipe beside a pipe-to-ground's closed side is not joined;
   VS2 beside its open side it is; VS3 a machine whose fluid port tile holds a pipe-to-ground opening away →
   `BP_V_FLUID_DISCONNECTED`; VS4 opening into the machine → connected.

## Files this lane owns

logic/bp/validate.lua, tests/test_validate_ptg_sides.lua, docs/tasks/232_validate_ptg_sides.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/232`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane232-tests", "command": "git diff --name-only round-41-base HEAD | grep -Ev '^(logic/bp/validate\\.lua|tests/test_validate_ptg_sides\\.lua|docs/tasks/232_validate_ptg_sides\\.md)$' | ( ! grep . ) && git diff --quiet round-41-base HEAD -- docs/tasks/232_validate_ptg_sides.md && ! git diff round-41-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_validate_ptg_sides test_validate_fluid_mix test_validate_fluid_port test_validate_witness_underground test_blueprint_physical_contract test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane232-tests-ok", "expect_exit": 0, "expect_regex": "lane232-tests-ok", "timeout_s": 3000}
{"name": "lane232-fast", "command": "lua5.2 tests/test_red_green_fluid_ports.lua 2>&1 | grep -c '^FAIL RGF1' | sed 's/^0$/RGF1-PASS/' | grep -qxF 'RGF1-PASS' || { echo FAST-WRONG; exit 1; }; echo lane232-ok", "expect_exit": 0, "expect_regex": "lane232-ok", "timeout_s": 900}
```

# bound: 2400s
