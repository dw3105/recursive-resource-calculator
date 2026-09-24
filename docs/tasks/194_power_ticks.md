# 194 power: same poles, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-194`, branch `lane/194`,
base tag `round-30-delivered`, merge target `int/r30b`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and the
tools named below. Never use `coroutine` (Factorio has none). Plain data state only (resumable across game ticks).
Every unit test you write must finish in under 20 s.

## Same answer, byte for byte

Generation is deterministic. `tests/fixtures/bytes_round30.txt` holds the sha256 of the delivered blueprints
(red v11, green v1). After your change `sh tools/bytes_hash.sh player-red-science-1s` and
`sh tools/bytes_hash.sh player-green-science-1s` must print the SAME lines. You change HOW MUCH work one step does,
never WHAT it decides.

## Measure

`sh tools/tick_profile.sh <case>` prints per-phase CPU and worst single tick (the game runs one `Search.step` with
2000 ops per tick; anything over ~0.1 s is a visible stutter). Base on green (2026-09-24, legalcopilot-dev): total
15.69 s, pack 8.83 s worst 0.337 s, power 2.04 s worst 0.496 s, route 3.63 s worst 0.217 s.

## Explain very simply

Power places poles so every machine and hand has electricity (`logic/bp/power.lua`: candidate index, greedy cover,
make-room for uncovered consumers, wiring). `Power.step` charges ONE op per loop turn (`consume`, ~322), but some
turns do far more work than others (e.g. the `collect` mode sorts all positions in one turn, ~526; a make-room try
or a wiring pass may walk every pole). On green one tick took 0.496 s. Find the heavy turns and split them or charge
them honestly, so every tick stays short. Decisions must not change.

A first attempt (`git show lane/193:logic/bp/power.lua` vs base) tried a fixed 128-op charge per turn and an
incremental collect; it also appended positions both in `finalize` and in `collect` (duplicates). Do not repeat that.

## What to build (`logic/bp/power.lua` only)

1. Measure first: time each `Power.step` turn by phase/mode on green (probe of your own, not committed) and name the
   heavy ones in the commit message.
2. Split or charge them so one `Power.step(state, {ops = 2000})` stays under ~0.05 s on both sheets.
3. Tests (red at base first, each < 20 s): new `tests/test_power_ticks.lua`: a synthetic layout with ~20 machines /
   ~50 hands / a few belts that need make-room: (a) same poles and wires as one big-budget run, (b) no single
   `Power.step(state, {ops = 2000})` over 0.05 s. Keep `test_power.lua`, `test_power_make_room.lua`,
   `test_power_budget.lua`, `test_power_ops.lua`, `test_power_demand.lua`, `test_power_semantics.lua`,
   `test_power_wires.lua` green (update `test_power_budget.lua` / `test_power_ops.lua` numbers only if op accounting
   changes; say why).

## Done (targets)

Bytes identical on both sheets; `sh tools/tick_profile.sh` power worst tick <= 0.10 s on both sheets; power CPU not
more than 20% above base (green 2.04 s).

## Files this lane owns

`logic/bp/power.lua`, `tests/test_power_ticks.lua`, `tests/test_power_budget.lua`, `tests/test_power_ops.lua`.
Never touch anything else.

## Commit, THEN check

Commit on `lane/194` with both power worst ticks in the message. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane194-tests", "command": "git diff --name-only round-30-delivered HEAD | grep -v '^docs/tasks/194' | grep -Ev '^(logic/bp/power\\.lua|tests/test_power_ticks\\.lua|tests/test_power_budget\\.lua|tests/test_power_ops\\.lua)$' | ( ! grep . ) && ! git diff round-30-delivered HEAD -- logic | grep -q '^+.*coroutine' && for t in test_power_ticks test_power test_power_make_room test_power_budget test_power_ops test_power_demand test_power_semantics test_power_wires; do timeout 120 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane194-tests-ok", "expect_exit": 0, "expect_regex": "lane194-tests-ok", "timeout_s": 900}
{"name": "lane194-same-and-fast", "command": "sh tools/bytes_hash.sh player-red-science-1s > /tmp/r194.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r194.txt && diff tests/fixtures/bytes_round30.txt /tmp/r194.txt && for c in player-red-science-1s player-green-science-1s; do sh tools/tick_profile.sh $c | awk '$1 == \"power\" {print; exit !($NF <= 0.10)}' || { echo SLOW $c; exit 1; }; done && echo lane194-ok", "expect_exit": 0, "expect_regex": "lane194-ok", "timeout_s": 900}
```

# bound: 3600s
