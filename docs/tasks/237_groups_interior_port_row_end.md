# 237_groups_interior_port_row_end an inside port on free ground is valid; a row belt ends at its last hand

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-237`, branch `lane/237`,
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

Port the `PROBE_LX` and `PROBE_IFREE` blocks of the groups + validate parts of the reference diff:

1. Row block: `last_x = machine.x + floor((machine.w - 1) / 2)` for the last machine (same value for odd widths;
   for a 4-wide electromagnetic plant the near belt no longer runs one tile past the last plain hand — that tile
   served nothing: `BP_V_TRANSPORT_UNUSED`).
2. Groups, just before `table.sort(block.ports, ...)`: an item port whose attach tile lies INSIDE the block envelope
   and is covered by no member and no inserter gets `port.interior_free = true` (the plastic plant's output hand
   drops onto free ground under the beacon row, one tile inside the envelope).
3. Validate (port ring check): a port with `interior_free` counts as bounded and inward, exactly like `hopped`.
4. `tests/test_row_even_width_end.lua`: RE1 a row of 4x4 machines → the near belt's last tile is the last plain
   hand's column; RE2 3x3 row unchanged. `tests/test_groups_interior_port.lua`: IP1 a single chemical-plant-like
   block (3x3 machine, beacons two wide above, hands left and right) → right port has `interior_free`; IP2 a port on
   the ring never gets it; IP3 validator accepts an `interior_free` port and still refuses an inside port without it.

Alone these rules do not change the blue sheet's first route: the fast check proves it is unchanged.

## Files this lane owns

logic/bp/groups.lua, logic/bp/validate.lua, tests/test_groups_interior_port.lua, tests/test_row_even_width_end.lua, docs/tasks/237_groups_interior_port_row_end.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/237`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane237-tests", "command": "git diff --name-only round-41-wave2b HEAD | grep -Ev '^(logic/bp/groups\\.lua|logic/bp/validate\\.lua|tests/test_groups_interior_port\\.lua|tests/test_row_even_width_end\\.lua|docs/tasks/237_groups_interior_port_row_end\\.md)$' | ( ! grep . ) && git diff --quiet round-41-wave2b HEAD -- docs/tasks/237_groups_interior_port_row_end.md && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*coroutine' && ! git diff round-41-wave2b HEAD -- logic | grep -q '^+.*PROBE_' && for t in test_groups_interior_port test_row_even_width_end test_row_even_width test_groups_fluid_box_order test_validate_ptg_sides test_groups test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane237-tests-ok", "expect_exit": 0, "expect_regex": "lane237-tests-ok", "timeout_s": 3000}
{"name": "lane237-fast", "command": "lua5.2 tools/first_stage.lua player-blue-science-10s route 15 2>&1 >/dev/null | grep '^FIRST' | grep -qxF 'FIRST-ROUTE ok=false BP_R_FLUID_MIX=1 flow=fluid/light-oil src=11,20 sink=42,24' || { echo FAST-WRONG; exit 1; }; echo lane237-ok", "expect_exit": 0, "expect_regex": "lane237-ok", "timeout_s": 1200}
```

# bound: 2400s
