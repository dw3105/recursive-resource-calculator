# 195_validate_ticks validate: same verdict, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-195_validate_ticks`, branch `lane/195_validate_ticks`,
base tag `round-30c-base`, merge target `int/r30b`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the
tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game ticks).
Every unit test you write must finish in under 20 s.

## Explain very simply

The game runs the blueprint job one step per tick with a budget of 2000 ops (`logic/jobs.lua` OPS_PER_TICK). One op
should cost about 8 us, so one tick about 16 ms. A call that ignores the budget and does all its work at once freezes
the game for that long. `lua5.2 tools/tick_parts.lua <case>` prints the worst single call per function
(`MAXCALL <Module.fn> <seconds>`) and the tick count (`TICKS n`). Measured on this base (2026-09-24,
legalcopilot-dev), worst call in seconds, red / green:
Validate.step 0.073 / 0.322; Route.begin 0.036 / 0.247; Route.tidy_step 0.102 / 0.177; Route.step 0.047 / 0.175;
Groups.step 0.010 / 0.111; Pack.step 0.076 / 0.066. TICKS red 414, green 1575.

`Validate.step` (`logic/bp/validate.lua`) runs ~14 checks. Some check does its whole pass in one call (belt walks `transport_path` BFS per inserter, lane witness simulation, collision, power cover): 0.322 s on green in ONE call.

## Same answer, byte for byte

Generation is deterministic. `tests/fixtures/bytes_round30.txt` holds the sha256 of the delivered blueprints.
`sh tools/bytes_hash.sh player-red-science-1s` and `sh tools/bytes_hash.sh player-green-science-1s` must print the
SAME lines after your change. You change HOW MUCH work one call does, never WHAT it decides.

## What to build

1. Measure first which check/pass is heavy (probe of your own, not committed); name it in the commit.
2. Make every heavy pass resumable: keep a cursor in plain state, charge `budget.ops` honestly (~8 us per op), stop when the budget is spent, continue next call. Same checks, same order, same errors, same ids.
3. New `tests/test_validate_ticks.lua` (red at base first, < 20 s): a synthetic candidate with ~300 belts and ~40 hands: (a) the errors list equals a one-call big-budget run exactly, (b) no single `Validate.step(state, {ops = 2000})` over 0.03 s. Keep the other listed validate tests green.

## Done (targets)

Bytes identical on both sheets. On BOTH sheets `tools/tick_parts.lua` MAXCALL of each of Validate.step Validate.begin <= 0.06 s, and
TICKS <= 1.3x base (red 538, green 2047).

## Files this lane owns

logic/bp/validate.lua, tests/test_validate_ticks.lua, tests/test_validate.lua, tests/test_validate_splitter.lua, tests/test_validate_splitter_rules.lua, tests/test_validate_transport_shapes.lua, tests/test_validate_rows.lua, tests/test_validate_buffer.lua, tests/test_validate_roboport_zone.lua, tests/test_validated_candidate.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/195_validate_ticks` with the MAXCALL lines of your functions and TICKS for both sheets in the message. **Run the
checks as the very LAST action.**

## What done mean

```checks
{"name": "lane195_validate_ticks-tests", "command": "git diff --name-only round-30c-base HEAD | grep -v '^docs/tasks/195_validate_ticks' | grep -Ev '^(logic/bp/validate\\.lua|tests/test_validate_ticks\\.lua|tests/test_validate\\.lua|tests/test_validate_splitter\\.lua|tests/test_validate_splitter_rules\\.lua|tests/test_validate_transport_shapes\\.lua|tests/test_validate_rows\\.lua|tests/test_validate_buffer\\.lua|tests/test_validate_roboport_zone\\.lua|tests/test_validated_candidate\\.lua)$' | ( ! grep . ) && ! git diff round-30c-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_validate_ticks test_validate test_validate_splitter test_validate_splitter_rules test_validate_transport_shapes test_validate_rows test_validate_buffer test_validate_roboport_zone test_validated_candidate; do timeout 120 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane195_validate_ticks-tests-ok", "expect_exit": 0, "expect_regex": "lane195_validate_ticks-tests-ok", "timeout_s": 1200}
{"name": "lane195_validate_ticks-same-and-short", "command": "sh tools/bytes_hash.sh player-red-science-1s > /tmp/r195_validate_ticks.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r195_validate_ticks.txt && diff tests/fixtures/bytes_round30.txt /tmp/r195_validate_ticks.txt && for c in player-red-science-1s:538 player-green-science-1s:2047; do lua5.2 tools/tick_parts.lua ${c%%:*} > /tmp/t195_validate_ticks.txt 2>&1; for f in Validate.step Validate.begin; do awk -v f=$f '$1 == \"MAXCALL\" && $2 == f {print; exit !($3 <= 0.06)}' /tmp/t195_validate_ticks.txt || { echo LONG $c $f; exit 1; }; done; awk -v m=${c##*:} '$1 == \"TICKS\" {print; exit !($2 <= m)}' /tmp/t195_validate_ticks.txt || { echo TICKS $c; exit 1; }; done && echo lane195_validate_ticks-ok", "expect_exit": 0, "expect_regex": "lane195_validate_ticks-ok", "timeout_s": 1200}
```

# bound: 3600s
