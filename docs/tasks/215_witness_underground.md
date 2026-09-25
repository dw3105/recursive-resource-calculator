# 215_witness_underground validate: a belt line through underground or splitter is witnessed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-215_witness_underground`, branch `lane/215_witness_underground`,
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

Measured on base (legalcopilot-dev, 2026-09-25): red-10s first validate verdict reports 12 `item/iron-gear-wheel`
belts `BP_V_TRANSPORT_UNUSED`: (14,15) west to (7,15), then (6,15) north to (6,13). That line continues through an
underground pair and a splitter near (7,13)-(7,14) into the science row's gear feed. The witness that marks used
belts (`mark_path` in `check_physical_transfers`, `logic/bp/validate.lua`) walks plain belts only
(`transport_kind(current) == "belt"`), and the side-feed neighbour search in `transport_neighbors` also only looks at
belts; an underground exit or splitter output feeding a used belt is not followed backwards.

## What to build

1. Witness follows every transport that feeds a used transport: belt, underground (exit ← its pair ← entrance),
   splitter (either input), straight from behind or side-load.
2. A real dead-end stub stays `BP_V_TRANSPORT_UNUSED`.
3. Test (red at base first): new `tests/test_validate_witness_underground.lua`: belt → underground pair → belt into a
   used belt → no unused; belt → splitter → used belt → no unused; a stub ending in nothing → unused.
4. Red-10s: no iron-gear-wheel `BP_V_TRANSPORT_UNUSED` left.

## Files this lane owns

logic/bp/validate.lua, tests/test_validate_witness_underground.lua, tests/test_validate.lua, tests/test_validate_two_feeds.lua, docs/tasks/215_witness_underground.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/215_witness_underground`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane215-tests", "command": "git diff --name-only round-36-int1 HEAD | grep -Ev '^(logic/bp/validate\\\\.lua|tests/test_validate_witness_underground\\\\.lua|tests/test_validate\\\\.lua|tests/test_validate_two_feeds\\\\.lua|docs/tasks/215_witness_underground\\\\.md)$' | ( ! grep . ) && ! git diff round-36-int1 HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_validate_witness_underground test_validate test_validate_two_feeds test_validate_fluid_port test_validate_fluid_mix test_validate_bleed test_validate_splitter test_validate_splitter_rules; do [ -f tests/$t.lua ] || continue; timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane215-tests-ok", "expect_exit": 0, "expect_regex": "lane215-tests-ok", "timeout_s": 2400}
{"name": "lane215-measure", "command": "lua5.2 tools/verdict_codes.lua tests/golden/cases/player-red-science-10s/prepared_input.json 2>/dev/null | grep -c 'BP_V_TRANSPORT_UNUSED item/iron-gear-wheel' | grep -qx 0 && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && echo lane215-ok", "expect_exit": 0, "expect_regex": "lane215-ok", "timeout_s": 1800}
```

# bound: 3000s
