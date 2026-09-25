# 210_validate_rules validate: fluid ports by kind, fluids never mix, every feed path counts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-210_validate_rules`, branch `lane/210_validate_rules`,
base tag `round-36-base`, merge target `int/r36`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data in `storage` only (no closures, no metatables). Unit tests
finish in under 20 s; GUI/control tests loop over `H.shapes()` and move time only with `H.run_ticks(world, n)`.

Read `docs/contracts/round36.md` first: it is the contract. Your clauses: F1, F2, F3.

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>` (every stage verdict per attempt);
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK` or `GATE-FAIL`).

## Explain very simply

Two validator rules refuse good layouts (measured on base, legalcopilot-dev 2026-09-25):
(1) `check_port_approaches` in `logic/bp/validate.lua` refuses any other flow on the tile behind a port; for a fluid
port that refused an iron-gear belt behind a molten-copper pipe port (`BP_V_PORT_EDGE_WRONG`). A belt never touches
fluid. (2) A foundry with two output hands (rate split) feeds one belt head by two paths: one straight from behind,
one side-load. The transfer witness follows only one, so 7 belts of the other path are `BP_V_TRANSPORT_UNUSED`; the
lane simulator shows items do flow. With both rules corrected (in memory), inserter-10s passes its FIRST attempt
(layered pack) with 373 entities instead of falling back to MaxRects (413). Today:
`lua5.2 tools/stage_fail.lua tests/golden/cases/player-inserter-10s/prepared_input.json` shows the first validate
verdict ok=false. No rule stops two different fluids' pipes from touching today; add it.

## What to build

1. F1 approach rule by kind.
2. F2 `BP_V_FLUID_MIX` (add to `logic/bp/reason_codes.lua`).
3. F3 witness follows every belt path into a used belt (from behind and side-load).
4. Tests (red at base first): new `tests/test_validate_fluid_port.lua` (belt behind fluid port accepted; foreign pipe
   there refused), `tests/test_validate_fluid_mix.lua` (two fluids' pipes adjacent → `BP_V_FLUID_MIX`; a
   pipe-to-ground next to a foreign pipe it does not face → no error), `tests/test_validate_two_feeds.lua` (two paths
   of one flow into one belt, one from behind, one side-load → no `BP_V_TRANSPORT_UNUSED`; a real dead-end stub still
   reported).

## Files this lane owns

logic/bp/validate.lua, logic/bp/reason_codes.lua, tests/test_validate_fluid_port.lua, tests/test_validate_fluid_mix.lua, tests/test_validate_two_feeds.lua, tests/test_validate.lua, tests/test_validate_bleed.lua, docs/tasks/210_validate_rules.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/210_validate_rules`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane210-tests", "command": "git diff --name-only round-36-base HEAD | grep -Ev '^(logic/bp/validate\\\\.lua|logic/bp/reason_codes\\\\.lua|tests/test_validate_fluid_port\\\\.lua|tests/test_validate_fluid_mix\\\\.lua|tests/test_validate_two_feeds\\\\.lua|tests/test_validate\\\\.lua|tests/test_validate_bleed\\\\.lua|docs/tasks/210_validate_rules\\\\.md)$' | ( ! grep . ) && ! git diff round-36-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_validate_fluid_port test_validate_fluid_mix test_validate_two_feeds test_validate test_validate_bleed test_validate_splitter test_validate_splitter_rules test_route_network; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane210-tests-ok", "expect_exit": 0, "expect_regex": "lane210-tests-ok", "timeout_s": 2400}
{"name": "lane210-measure", "command": "lua5.2 tools/stage_fail.lua tests/golden/cases/player-inserter-10s/prepared_input.json | grep '^STAGE validate' | head -1 | grep -q 'ok=true' && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && echo lane210-ok", "expect_exit": 0, "expect_regex": "lane210-ok", "timeout_s": 1800}
```

# bound: 3600s
