# 223b_collector_witness validate + route: collector belt hands are witnessed; sheets build

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-223b_collector_witness`, branch `lane/223b_collector_witness`,
base tag `round-37-223b-base`, merge target `int/r37`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Never make a validate code non-fatal or skip a check to pass.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine`. Plain data only. **No game item or fluid name in code**
(`tests/test_no_item_names.lua` must stay green).

Tools: `lua5.2 tools/stage_fail.lua <prepared_input.json>`; `lua5.2 tools/verdict_codes.lua <prepared_input.json>`;
`lua5.2 tools/capture_stage_input.lua <prepared_input.json> <out.json> <stage> <call>`;
`sh tools/gate_sheet.sh <case> <max_entities> [max_belts]` (bytes gate, last line `GATE-OK`/`GATE-FAIL`).
Every new test must FAIL on the code before your fix (write that in the test's header comment).

## Explain very simply

Base commit (previous lane's work) makes same-flow output hands of one machine share ONE collector belt
(`combine_adjacent_output_hands` in `logic/bp/route.lua`) -- the player's own fix of red science 10/s does this
(`tests/fixtures/player_red10s_fix.txt`, 139 belts vs our 176). Route test passes. But measured on base
(legalcopilot-dev, 2026-09-25) sheets break:
- `player-red-science-10s`: no blueprint. Every retry: `BP_V_TRANSPORT_UNUSED item/iron-gear-wheel
  m:inserter:casting-iron-gear-wheel:1:output:1` and `... r:577`. The collector binding names one port; the
  validator's witness (`mark_path` in `logic/bp/validate.lua`, walks upstream from each sink) never credits the
  OTHER hand that drops onto the collector, so it calls that hand and belt unused.
- `player-inserter-10s`, `player-red-science-10s-stack1`: no blueprint.
- (Attempt 1 of red-10s also shows the old calcite shortfall; that is NOT yours -- retries used to pass; they must
  pass again.)

## What to build

1. Validate witness: a hand whose drop tile lies on a witnessed belt of its own flow is used (any number of hands on
   one collector). Output rate of all hands on the collector counts toward the sink.
2. Fix whatever else stops the three sheets once (1) is in: measure with `tools/stage_fail.lua` and
   `tools/verdict_codes.lua`, fix at the named line, repeat.
3. Test `tests/test_validate_collector_witness.lua` on a frozen validate input of red-10s (capture with
   `tools/capture_stage_input.lua ... validate <call>`, save `tests/fixtures/validate_red10s_collector.json`):
   0 `BP_V_TRANSPORT_UNUSED`.

## Files this lane owns

logic/bp/route.lua, logic/bp/validate.lua, tests/test_validate_collector_witness.lua, tests/fixtures/validate_red10s_collector.json, tests/test_route_collector.lua, tests/test_route.lua, tests/test_validate.lua, docs/tasks/223b_collector_witness.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/223b_collector_witness`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane223b-tests", "command": "git diff --name-only round-37-223b-base HEAD | grep -Ev '^(logic/bp/route\\\\.lua|logic/bp/validate\\\\.lua|tests/test_validate_collector_witness\\\\.lua|tests/fixtures/validate_red10s_collector\\\\.json|tests/test_route_collector\\\\.lua|tests/test_route\\\\.lua|tests/test_validate\\\\.lua|docs/tasks/223b_collector_witness\\\\.md)$' | ( ! grep . ) && git diff --quiet round-37-223b-base HEAD -- docs/tasks/223b_collector_witness.md && ! git diff round-37-223b-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_validate_collector_witness test_route_collector test_route test_validate test_route_tidy test_route_tidy_shapes test_route_rows test_route_feed_curve_retry test_red10s_edge_rules test_validate_parallel_ports test_validate_side_feed_witness test_validate_witness_underground test_no_item_names test_no_runtime_require; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane223b-tests-ok", "expect_exit": 0, "expect_regex": "lane223b-tests-ok", "timeout_s": 2400}
{"name": "lane223b-measure", "command": "sh tools/gate_sheet.sh player-red-science-10s 275 150 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-inserter-10s 373 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-10s-stack1 283 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-red-science-1s 148 | tail -1 | grep -q GATE-OK && sh tools/gate_sheet.sh player-green-science-1s 305 | tail -1 | grep -q GATE-OK && echo lane223b-ok", "expect_exit": 0, "expect_regex": "lane223b-ok", "timeout_s": 3600}
```

# bound: 3600s
