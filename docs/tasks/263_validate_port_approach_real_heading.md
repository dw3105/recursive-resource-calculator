# 263_validate_port_approach_real_heading port approach checks follow the real belt, not the declared heading

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-263`, branch `lane/263`,
base tag `round-45-w5`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tools/route_fail_snapshot.lua`, `tools/game_test.sh`, `factorio`,
or any full suite, sheet run or headless run of any kind, except the ONE stack1 delivers test named below.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No game item or
entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header comment); commit it red
first.

## Explain very simply

`check_port_approaches` in `logic/bp/validate.lua` (~2520-2600) refuses `BP_V_PORT_EDGE_WRONG` when a foreign flow
occupies the tile AHEAD of an output port or BEHIND an input port, both along the port's DECLARED `travel_dir`.
Route may legally lay the port's belt in another heading (free heading, curves), so on
`player-inserter-10s-stack1` (legalcopilot-dev, 2026-09-28) two physically correct layouts were refused:
- copper-cable output hand 5 of `casting-copper-cable`: port (21,19) declared east, the cable belt on it runs north;
  a product underground at (22,19) was flagged although no cable ever goes there.
- iron-plate input hand 2 of `inserter:3`: port (43,58) declared south, iron arrives from the north exit (43,57) and
  the belt turns west; a product underground at (44,58) beside it was flagged although it feeds nothing into the port.

Fix (item ports only; fluid ports keep today's rule, pipes have no heading and always connect):
- OUT: when a same-flow belt occupies the port tile, "ahead" follows that belt's real direction.
- IN: a foreign belt on the "behind" tile is reported only if its own direction points into the port tile.
Reference patches (measured in memory): `docs/tasks/ref/263_patch_reference_out.lua` then
`docs/tasks/ref/263_patch_reference_in.lua`. Measured: stack1's first validated candidate goes from 1
PORT_EDGE_WRONG to `ok=true`; with route rules merged the whole sheet generates `ok=true`, 841 entities; all
`tests/test_validate*.lua`, `test_placed_port_geometry`, `test_groups_interior_port`, `test_route_layout_contract`
stay green (incl. `test_validate_fluid_port` "a foreign pipe behind a fluid port is refused").

Fixture: `tests/fixtures/route_snaps/stack1_validate_candidate.lua.gz` = Search state at stack1's first validate
(load with `require("tools.lib.graph_dump").load(path)`; `.state.work.validate_candidate`, `.state.work.plan_result`,
`.state.work.input.catalog`). Validate-only replay (about 5 s):
```lua
local st = require("tools.lib.graph_dump").load("tests/fixtures/route_snaps/stack1_validate_candidate.lua.gz").state
local v = Validate.begin({candidate = st.work.validate_candidate, plan = st.work.plan_result,
    catalog = st.work.input.catalog, ring_bump = st.work.attempt or 0})
while not v.done do Validate.step(v, {ops = 100000}) end
```

## What to build

1. `tests/test_validate_port_approach.lua` (commit red first; do NOT require tests.harness BEFORE loading the fixture
   state is fine either way, use `package.path = "./?.lua;" .. package.path`):
   - PA1: replay above -> `v.ok == true` (base: one `BP_V_PORT_EDGE_WRONG`).
   - PA2: synthetic item output port whose same-flow belt runs AWAY and whose ahead-by-real-direction tile holds a
     foreign belt -> still refused (the rule is followed, not dropped). Build it from shapes in
     `tests/test_validate.lua`.
2. `logic/bp/validate.lua`: both rules, short comments citing tiles + date.
3. Last, once: `lua5.2 tests/test_inserter_stack1_delivers.lua` (about 15 min; allowed) — report its last line.

## Files this lane owns

logic/bp/validate.lua, tests/test_validate_port_approach.lua, docs/tasks/263_validate_port_approach_real_heading.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/263`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane263-tests", "command": "git diff --name-only round-45-w5 HEAD | grep -Ev '^(logic/bp/validate\\.lua|tests/test_validate_port_approach\\.lua|docs/tasks/263_validate_port_approach_real_heading\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w5 HEAD -- docs/tasks && for t in test_validate_port_approach test_validate test_validate_fluid_port test_placed_port_geometry test_groups_interior_port test_route_layout_contract test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane263-tests-ok", "expect_exit": 0, "expect_regex": "lane263-tests-ok", "timeout_s": 3000}
{"name": "lane263-fast", "command": "out=$(lua5.2 tests/test_validate_port_approach.lua 2>&1); for c in PA1 PA2; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane263-ok", "expect_exit": 0, "expect_regex": "lane263-ok", "timeout_s": 600}
```

# bound: 3000s
