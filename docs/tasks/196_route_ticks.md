# 196_route_ticks route: same belts, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-196_route_ticks`, branch `lane/196_route_ticks`,
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

`Route.begin` (`logic/bp/route.lua`) builds every demand and pairs producers with consumers by `pairing_route_cost` (~627: a static BFS per pair) all in one call: 0.247 s on green. `Route.step` / `Route.tidy_step` charge one op per A* expansion (~3399) but some steps do bulk work (commit of a path, snapshot/restore in the improve pass ~1288, `restart_with_priority` tearing out every segment ~2533): 0.175 / 0.177 s.

## Same answer, byte for byte

Generation is deterministic. `tests/fixtures/bytes_round30.txt` holds the sha256 of the delivered blueprints.
`sh tools/bytes_hash.sh player-red-science-1s` and `sh tools/bytes_hash.sh player-green-science-1s` must print the
SAME lines after your change. You change HOW MUCH work one call does, never WHAT it decides.

## What to build

1. Measure first which parts are heavy (probe of your own, not committed); name them in the commit.
2. Move demand building/pairing out of `Route.begin` into resumable `Route.step` stages (cursor in plain state, honest ops). Split or charge the bulk parts of `Route.step` / `Route.tidy_step` so each call stays short. Same demands, same order, same paths.
3. New `tests/test_route_ticks.lua` (red at base first, < 20 s): a synthetic grid with ~10 blocks and ~20 demands: (a) result entities equal a one-call big-budget run, (b) `Route.begin` and every `Route.step(state, {ops = 2000})` / `Route.tidy_step` under 0.03 s. Keep the other listed route tests green (`test_route_budget.lua` numbers may move only if op accounting changes; say why).

## Done (targets)

Bytes identical on both sheets. On BOTH sheets `tools/tick_parts.lua` MAXCALL of each of Route.begin Route.step Route.tidy_step Route.tidy_begin <= 0.06 s, and
TICKS <= 1.3x base (red 538, green 2047).

## Files this lane owns

logic/bp/route.lua, tests/test_route_ticks.lua, tests/test_route.lua, tests/test_route_budget.lua, tests/test_route_rows.lua, tests/test_route_improve.lua, tests/test_route_tidy.lua, tests/test_route_merge_feed.lua, tests/test_route_splitter_straight.lua, tests/test_route_rear_curve.lua, tests/test_route_chain.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/196_route_ticks` with the MAXCALL lines of your functions and TICKS for both sheets in the message. **Run the
checks as the very LAST action.**

## What done mean

```checks
{"name": "lane196_route_ticks-tests", "command": "git diff --name-only round-30c-base HEAD | grep -v '^docs/tasks/196_route_ticks' | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_ticks\\.lua|tests/test_route\\.lua|tests/test_route_budget\\.lua|tests/test_route_rows\\.lua|tests/test_route_improve\\.lua|tests/test_route_tidy\\.lua|tests/test_route_merge_feed\\.lua|tests/test_route_splitter_straight\\.lua|tests/test_route_rear_curve\\.lua|tests/test_route_chain\\.lua)$' | ( ! grep . ) && ! git diff round-30c-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_route_ticks test_route test_route_budget test_route_rows test_route_improve test_route_tidy test_route_merge_feed test_route_splitter_straight test_route_rear_curve test_route_chain; do timeout 120 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane196_route_ticks-tests-ok", "expect_exit": 0, "expect_regex": "lane196_route_ticks-tests-ok", "timeout_s": 1200}
{"name": "lane196_route_ticks-same-and-short", "command": "sh tools/bytes_hash.sh player-red-science-1s > /tmp/r196_route_ticks.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r196_route_ticks.txt && diff tests/fixtures/bytes_round30.txt /tmp/r196_route_ticks.txt && for c in player-red-science-1s:538 player-green-science-1s:2047; do lua5.2 tools/tick_parts.lua ${c%%:*} > /tmp/t196_route_ticks.txt 2>&1; for f in Route.begin Route.step Route.tidy_step Route.tidy_begin; do awk -v f=$f '$1 == \"MAXCALL\" && $2 == f {print; exit !($3 <= 0.06)}' /tmp/t196_route_ticks.txt || { echo LONG $c $f; exit 1; }; done; awk -v m=${c##*:} '$1 == \"TICKS\" {print; exit !($2 <= m)}' /tmp/t196_route_ticks.txt || { echo TICKS $c; exit 1; }; done && echo lane196_route_ticks-ok", "expect_exit": 0, "expect_regex": "lane196_route_ticks-ok", "timeout_s": 1200}
```

# bound: 3600s
