# 235_route_crowded_fluids fluids around a crowded machine get out, cross and join

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-235`, branch `lane/235`,
base tag `round-41-wave2b`, merge target `int/r41`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal. Touch only the files this lane
owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh`,
`tools/measure_sheet.sh`, `tools/gate_sheet.sh`, `tools/bytes_hash.sh` or any full suite of any kind.** Run only
single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the fast check
`tools/first_stage.lua` (it stops at the first candidate; `FAST_TIDY=1` skips tidy's slow improvement pass).
Never use `coroutine`. Plain data only. `require` only at file top level (`tests/test_no_runtime_require.lua`).
**No game item or fluid name in code** (`tests/test_no_item_names.lua`; tests use made-up ids like `fluid/a`).
Every new test must FAIL on the base code (write that in the test's header comment). The reference is
`docs/tasks/r41_blue_reference.diff`: port the named `PROBE_*` blocks exactly, WITHOUT the env flags (always on).

## Explain very simply

The player's blue science sheet (`tests/golden/cases/player-blue-science-10s`: oil refinery with 3 fluid outputs 2
tiles apart under its own beacon row, light/heavy oil crackers, sulfur and plastic chemical plants, electromagnetic
plant rows) never builds. Measured (legalcopilot-dev, 2026-09-26) on a probe tree = `int/r41` + ALL blocks of the
reference diff: `FAST_TIDY=1 lua5.2 tools/first_stage.lua player-blue-science-10s validate 15` →
`FIRST-VALIDATE ok=true`; the 8 older sheets stay byte-identical or smaller. Three lanes each port one part.

Port every `PROBE_CROWD`, `PROBE_ORD`, `PROBE_NET` and `PROBE_NOUGSEED` block of the route part of the reference
diff into `logic/bp/route.lua`:

1. Crowded block = a block with 3 or more distinct fluid ports (`reserve_port_cells` computes
   `work.crowded_blocks`). Each fluid port of a crowded block claims its FRONT tile: the first tile outward along its
   fluid heading that no block member covers (walk at most 9 tiles). Its own port tile is marked `_crowded`.
2. `path_cell_free`: a pipe tile beside another fluid's claimed front, or beside another fluid's crowded port tile,
   is refused like a foreign pipe (`search.touch_refused = true`). `search.touch_ok` skips both touch rules.
3. For a demand whose source or sink block is crowded (`crowded_demand`): an underground exit ignores the touch
   rules (it joins only along its line), and a tile refused ONLY by touch rules may still be entered as mode 3
   ("dive-only": from it the search may only dive straight on).
4. Demand order: fluid demands touching a crowded block (not from a map-edge door) are routed first.
5. Fluid network join: a pipe demand is done when it steps onto a same-flow pipe whose network already reaches its
   sink (`route_chain_walk`); `route_chain_reaches_sink` then accepts a pipe path that ends there.
6. A pipe demand never seeds a branch from an underground pipe tile (it joins only its open side).
7. `tests/test_route_crowded_fluids.lua`, hand-built `Route.begin` inputs (see `tests/test_route_fluid_port_ptg.lua`):
   CF1 a 3-fluid-output machine, outputs 2 tiles apart, all sinks far away → route ok, no shortfall; CF2 a second
   source of one fluid whose sink already has a pipe network → route ok and the new path ends on that network;
   CF3 a trunk with an underground pair → a branch never starts on either underground end; CF4 a machine with ONE
   fluid port routes exactly as on base (same entities).

Measured with ONLY these blocks on `int/r41` (the door-gap and groups/validate parts are other lanes'):
the fast check below prints exactly the expected line.

## Files this lane owns

logic/bp/route.lua, tests/test_route_crowded_fluids.lua, docs/tasks/235_route_crowded_fluids.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/235`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane235-tests", "command": "git diff --name-only round-41-wave2b HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_crowded_fluids\\.lua|docs/tasks/235_route_crowded_fluids\\.md)$' | ( ! grep . ) && git diff --quiet round-41-wave2b HEAD -- docs/tasks/235_route_crowded_fluids.md && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*coroutine' && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*PROBE_' && for t in test_route_crowded_fluids test_route_fluid_port_ptg test_fluid_touch test_side_feed test_route_bury test_pipe_runs test_red_green_fluid_ports test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane235-tests-ok", "expect_exit": 0, "expect_regex": "lane235-tests-ok", "timeout_s": 3000}
{"name": "lane235-fast", "command": "FAST_TIDY=1 lua5.2 tools/first_stage.lua player-blue-science-10s validate 15 2>&1 >/dev/null | grep '^FIRST' | grep -qxF 'FIRST-VALIDATE ok=false BP_V_FLUID_MIX=1 BP_V_PORT_EDGE_WRONG=2 BP_V_TRANSPORT_UNUSED=1' || { echo FAST-WRONG; exit 1; }; echo lane235-ok", "expect_exit": 0, "expect_regex": "lane235-ok", "timeout_s": 1200}
```

# bound: 2400s
