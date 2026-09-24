# 203_inserter_sheet groups + pack: fluid steps keep their pipes, enough hands per flow

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-203_inserter_sheet`, branch `lane/203_inserter_sheet`,
base tag `round-33-base`, merge target `int/r33`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio 2.0 and 2.1)
when it touches the GUI or control.

Read `docs/contracts/round33.md` first: it is the contract. Your clauses: I1, I2.

## Explain very simply

The player's inserter sheet (`tests/golden/cases/player-inserter-10s`, a real capture: foundries making molten
iron/copper and casting plates, gears, cable; one EM plant for circuits; 4 assemblers for inserters) must give a
working blueprint. Measured on base (legalcopilot-dev, 2026-09-24):
`sh tools/measure_sheet.sh player-inserter-10s` → `BP_FAIL_NO_LAYOUT`, `BP_R_PORT_BLOCKED` ×3: every step with 2+
machines becomes a row (`logic/bp/groups.lua:1055-1058`) and the row rebuilds ITEM ports only
(`groups.lua:1768-1812`), so the 2-foundry casting-iron row has no molten-iron input and route cannot bind it. Next in
line: one hand per flow; copper cable into the EM plant is 15/s, one hand carries 4.62/s
(`catalog.inserter.items_per_second`), validate will say `BP_V_INSERTER_CAPACITY` (`logic/bp/validate.lua:2437`).
Route already binds one port per hand (`tests/test_bindings_per_hand.lua`).

## What to build

1. I1 (pick by measuring the inserter sheet; red/green have no fluid so they must not change).
2. I2 hands per flow per machine = ceil(rate / items_per_second), each its own port on a free face tile.
3. Keep going until the inserter sheet delivers. If a blocker outside your files remains (route/validate), stop at
   the first one you cannot fix inside groups.lua/pack.lua, commit, and write it in `docs/tasks/203_inserter_sheet.md`
   under "## Left" with the exact code, count and file:line.
4. Tests (red at base first): new `tests/test_groups_fluid_row.lua` (a 2-machine fluid-fed step keeps a fluid input
   port the route can bind), new `tests/test_groups_hand_count.lua` (15/s flow at 4.62/s per hand → 4 hands, 4 ports,
   each on a free face tile; 3/s → 1 hand).

## Measure (one command each)

`sh tools/measure_sheet.sh player-inserter-10s` → `ok=true`, `mixed=0 starved=0 bleed=0`.
`sh tools/measure_sheet.sh player-red-science-1s` → `ok=true`, entities <= 169, `mixed=0 starved=0 bleed=0`.
`sh tools/measure_sheet.sh player-green-science-1s` → `ok=true`, entities <= 322, `mixed=0 starved=0 bleed=0`.

## Files this lane owns

logic/bp/groups.lua, logic/bp/pack.lua, tests/test_groups_fluid_row.lua, tests/test_groups_hand_count.lua,
tests/test_groups.lua, tests/test_groups_long_hands.lua, tests/test_pack.lua, docs/tasks/203_inserter_sheet.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/203_inserter_sheet`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane203_inserter_sheet-tests", "command": "git diff --name-only round-33-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|logic/bp/pack\\.lua|tests/test_groups_fluid_row\\.lua|tests/test_groups_hand_count\\.lua|tests/test_groups\\.lua|tests/test_groups_long_hands\\.lua|tests/test_pack\\.lua|docs/tasks/203_inserter_sheet\\.md)$' | ( ! grep . ) && ! git diff round-33-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_fluid_row test_groups_hand_count test_groups test_groups_long_hands test_pack test_bindings_per_hand; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane203_inserter_sheet-tests-ok", "expect_exit": 0, "expect_regex": "lane203_inserter_sheet-tests-ok", "timeout_s": 2400}
{"name": "lane203_inserter_sheet-measure", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/measure_sheet.sh player-inserter-10s | tail -1 | grep -E 'ok=true .*mixed=0 starved=0 bleed=0' && sh tools/measure_sheet.sh player-red-science-1s | tail -1 | awk '/ok=true/ && /mixed=0 starved=0 bleed=0/ {split($0,a,\"entities=\"); split(a[2],b,\" \"); if (b[1] <= 169) ok=1} END {exit !ok}' && sh tools/measure_sheet.sh player-green-science-1s | tail -1 | awk '/ok=true/ && /mixed=0 starved=0 bleed=0/ {split($0,a,\"entities=\"); split(a[2],b,\" \"); if (b[1] <= 322) ok=1} END {exit !ok}' && echo lane203_inserter_sheet-ok", "expect_exit": 0, "expect_regex": "lane203_inserter_sheet-ok", "timeout_s": 1500}
```

# bound: 3600s

## Built

- Fluid input or output keeps a multi-machine step out of row layout, so the normal block port builder carries the fluid connection into routing.
- Item flows are split into `ceil(rate / inserter.items_per_second)` individual hands. Each gets its own port id and rate share; port placement uses that hand's captured face position.
- Added fluid-row and hand-count coverage across all harness API shapes.

## Left

None known before the required sheet measurements.
