# 214_calcite_hand a bound calcite hand keeps its belt through to validate

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-214_calcite_hand`, branch `lane/214_calcite_hand`,
base tag `round-36-int1`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only.

Read `docs/contracts/round36.md` first (context). Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every
stage verdict per attempt); `sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate).
Case `tests/golden/cases/player-red-science-10s/prepared_input.json` is the player's sheet that must deliver.

## Explain very simply

Measured on base (legalcopilot-dev, 2026-09-25): red-10s attempt 1 route binds calcite (external, left edge
`in:item/calcite` at (0,8)) to molten-copper's hand port `in:item/calcite:inserter:molten-copper:1:input:1` (sink
(1,9), hand (2,9)); route ok=true. The first validate verdict then reports for that same hand
`m:inserter:molten-copper:1:input:1`: `BP_V_INSERTER_GEOMETRY` pickup cell (1,37) "empty ground",
`BP_V_PORT_UNREACHABLE` "no binding uses this port as a sink", `BP_V_TARGET_SHORTFALL` calcite 0.0396/s,
`BP_V_TRANSFER_BROKEN` missing_belt. So between route and validate (search pipeline: route → hands → power (make
room) → tidy (keep-if-cheaper) → `Ends.turn_heads` → `Hands.place` → validate, `logic/bp/search.lua`) the calcite
hand moves or its belt/binding is dropped. Print the calcite hand position and its belt tiles after each stage
(hook each stage's step like `tools/stage_fail.lua` does) and fix the stage that loses it.

## What to build

1. Find the stage that loses the calcite hand's belt or binding (write it under "## Built" with file:line).
2. Fix it there; the fix must hold for any hand, not only calcite.
3. Test (red at base first): new `tests/test_hand_keeps_belt.lua` reproducing the loss at unit level (smallest input
   that shows it).
4. Red-10s: no calcite error left (`lua5.2 tools/stage_fail.lua` validate lines have no calcite; errors of other
   flows may remain).

## Files this lane owns

logic/bp/route.lua, logic/bp/hands.lua, logic/bp/ends.lua, logic/bp/power.lua, tests/test_hand_keeps_belt.lua, tests/test_route.lua, tests/test_route_tidy.lua, tests/test_hands.lua, tests/test_power.lua, docs/tasks/214_calcite_hand.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/214_calcite_hand`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane214-tests", "command": "git diff --name-only round-36-int1 HEAD | grep -Ev '^(logic/bp/route\\\\.lua|logic/bp/hands\\\\.lua|logic/bp/ends\\\\.lua|logic/bp/power\\\\.lua|tests/test_hand_keeps_belt\\\\.lua|tests/test_route\\\\.lua|tests/test_route_tidy\\\\.lua|tests/test_hands\\\\.lua|tests/test_power\\\\.lua|docs/tasks/214_calcite_hand\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int1 HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_hand_keeps_belt test_route test_route_tidy test_route_budget test_route_rows test_route_network test_power; do [ -f tests/$t.lua ] || continue; timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane214-tests-ok", "expect_exit": 0, "expect_regex": "lane214-tests-ok", "timeout_s": 2400}
{"name": "lane214-measure", "command": "lua5.2 tools/verdict_codes.lua tests/golden/cases/player-red-science-10s/prepared_input.json 2>/dev/null | grep -cE 'calcite|molten-copper:1:input:1' | grep -qx 0 && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane214-ok", "expect_exit": 0, "expect_regex": "lane214-ok", "timeout_s": 1800}
```

# bound: 3000s
