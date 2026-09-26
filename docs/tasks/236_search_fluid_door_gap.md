# 236_search_fluid_door_gap two fluid doors of different fluids never touch

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-236`, branch `lane/236`,
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

Port the `PROBE_DOORGAP` blocks of the search part of the reference diff into `logic/bp/search.lua`
(`generated_perimeter_ports`): a map-edge door of a fluid flow never takes a slot whose 4 neighbours hold a door of
ANOTHER fluid (keep a `fluid_doors` map of slots already given to fluid doors). Water's door once sat right beside
crude oil's door; the door's only exit tile then touched crude's pipe and water could not leave.

1. The rule above, exactly as the reference, without the env flag.
2. `tests/test_search_fluid_door_gap.lua`: DG1 two fluid flows entering one edge get doors with at least one free
   slot between them; DG2 two ITEM flows may still take neighbouring slots (unchanged); DG3 one fluid + one item may
   be neighbours.

Alone this rule does not change the blue sheet's first route (it matters once the route lane lands): the fast check
proves the first route is unchanged.

## Files this lane owns

logic/bp/search.lua, tests/test_search_fluid_door_gap.lua, docs/tasks/236_search_fluid_door_gap.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/236`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane236-tests", "command": "git diff --name-only round-41-wave2b HEAD | grep -Ev '^(logic/bp/search\\.lua|tests/test_search_fluid_door_gap\\.lua|docs/tasks/236_search_fluid_door_gap\\.md)$' | ( ! grep . ) && git diff --quiet round-41-wave2b HEAD -- docs/tasks/236_search_fluid_door_gap.md && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*coroutine' && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*PROBE_' && for t in test_search_fluid_door_gap test_search test_red10s_edge_rules test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane236-tests-ok", "expect_exit": 0, "expect_regex": "lane236-tests-ok", "timeout_s": 3000}
{"name": "lane236-fast", "command": "lua5.2 tools/first_stage.lua player-blue-science-10s route 15 2>&1 >/dev/null | grep '^FIRST' | grep -qxF 'FIRST-ROUTE ok=false BP_R_FLUID_MIX=1 flow=fluid/light-oil src=11,20 sink=42,24' || { echo FAST-WRONG; exit 1; }; echo lane236-ok", "expect_exit": 0, "expect_regex": "lane236-ok", "timeout_s": 1200}
```

# bound: 2400s
