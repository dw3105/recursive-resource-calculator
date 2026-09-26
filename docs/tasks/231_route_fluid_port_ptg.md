# 231_route_fluid_port_ptg a pipe-to-ground on a fluid port tile opens into its machine

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-231`, branch `lane/231`,
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

The player's red + green science 10/s blueprint (round 40) built but 5 of 8 casting foundries got no fluid. A
pipe-to-ground joins ONLY its open side (its `dir`) and its underground partner. The router let an underground pair
start or end ON a foundry's fluid port tile facing any way: (16,13) opened east, the foundry is north, so the foundry
got nothing. Blue science needs the opposite case too: a chem plant's fluid face sits under its own beacon row, so
the only way in is a pipe-to-ground dropping onto the port tile, opening INTO the machine; the router today never
dives from a machine port tile (`(not first or search.demand.source.perimeter)` in the search step).

Measured (legalcopilot-dev, 2026-09-26) on the probe tree with `PROBE_PTGFACE` only:
`sh tools/first_verdict.sh player-red-green-science-10s` prints `FIRST-VERDICT ok=false BP_V_TRANSPORT_UNUSED=1`
(that one record is an old validator false alarm another task removes) and `tests/test_red_green_fluid_ports.lua`
RGF2 passes (RGF1 stays red; it is another task's).

## What to build

In `logic/bp/route.lua`, exactly as the `PROBE_PTGFACE` parts of the reference diff:

1. `normalize_endpoint`: for a fluid endpoint keep its heading as `endpoint.fluid_travel_dir` before
   `travel_dir` is cleared.
2. `reserve_port_cells`: for a fluid endpoint also store `reserved[key]._fluid_dir = endpoint.fluid_travel_dir` on
   its own tile.
3. `crossing_targets`, pipe demands only: a tile whose reservation has `_port_owners` and any `flow:fluid/...` key
   is a fluid port tile. An underground may START (current tile) or END (exit tile) on a fluid port tile only when
   `reserved._fluid_dir == direction` (the pipe-to-ground then opens into the machine). Every other tile: unchanged.
4. Search step: a pipe demand may dive on its FIRST step from its source port tile
   (`not first or source.perimeter or demand.kind == "pipe"`). Item ports keep the old rule.
5. `tests/test_route_fluid_port_ptg.lua`, hand-built `Route.begin` inputs (see `tests/test_route_bury.lua` for the
   shape): FP1 a fluid sink port with an obstacle over its front tile → route ok, the pipe-to-ground on the port
   tile has `dir` == the port heading; FP2 a sink reachable more cheaply by a sideways dive onto the port tile →
   no pipe-to-ground on the port tile opens away; FP3 a fluid SOURCE port with an obstacle in front → route ok by
   diving from the port tile; FP4 an item source port with an obstacle in front still never dives from its tile.

## Files this lane owns

logic/bp/route.lua, tests/test_route_fluid_port_ptg.lua, docs/tasks/231_route_fluid_port_ptg.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/231`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane231-tests", "command": "git diff --name-only round-41-base HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_fluid_port_ptg\\.lua|docs/tasks/231_route_fluid_port_ptg\\.md)$' | ( ! grep . ) && git diff --quiet round-41-base HEAD -- docs/tasks/231_route_fluid_port_ptg.md && ! git diff round-41-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_fluid_port_ptg test_red_green_fluid_ports test_route_bury test_fluid_touch test_side_feed test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane231-tests-ok", "expect_exit": 0, "expect_regex": "lane231-tests-ok", "timeout_s": 3000}
{"name": "lane231-fast", "command": "sh tools/first_verdict.sh player-red-green-science-10s | grep -qxF 'FIRST-VERDICT ok=false BP_V_TRANSPORT_UNUSED=1' || { echo FAST-WRONG; exit 1; }; echo lane231-ok", "expect_exit": 0, "expect_regex": "lane231-ok", "timeout_s": 900}
```

# bound: 2400s
