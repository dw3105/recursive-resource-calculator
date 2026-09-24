# 193c_pack_groups_ticks pack + groups: less work, honest ops, no long tick

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-193c_pack_groups_ticks`, branch `lane/193c_pack_groups_ticks`,
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

A previous attempt (branch `lane/193b`, commits 3de2eea, fe47b7f) cut pack CPU 3.85 -> 1.62 s with identical bytes (origin dedupe, link lower bound, sliced placement) BUT charged far too many ops per unit of work: red then took 2206 ticks instead of ~400 (10x game time). Take its CPU gain (`git diff round-30b-base lane/193b -- logic/bp/pack.lua`, its `tests/test_pack_ticks.lua`) and make the op charge honest (~8 us per op). `Groups.step` also does one 0.111 s call on green: slice it the same way.

## Same answer, byte for byte

Generation is deterministic. `tests/fixtures/bytes_round30.txt` holds the sha256 of the delivered blueprints.
`sh tools/bytes_hash.sh player-red-science-1s` and `sh tools/bytes_hash.sh player-green-science-1s` must print the
SAME lines after your change. You change HOW MUCH work one call does, never WHAT it decides.

## What to build

1. Port lane/193b's pack changes; re-measure: bytes identical, TICKS back near CPU/16 ms.
2. Calibrate op charges so 2000 ops ~ 16 ms of pack work; keep `Pack.step` <= 0.06 s.
3. Slice the heavy `Groups.step` work (measure which part first) with the same cursor pattern.
4. Tests (< 20 s each): `tests/test_pack_ticks.lua` (from lane/193b, plus: evaluated origins <= 50% of the uncut run and no `Pack.step(state, {ops = 2000})` over 0.03 s). Keep the listed pack and groups tests green.

## Done (targets)

Bytes identical on both sheets. On BOTH sheets `tools/tick_parts.lua` MAXCALL of each of Pack.step Pack.begin Groups.step Groups.begin <= 0.06 s, and
TICKS <= 1.3x base (red 538, green 2047).

## Files this lane owns

logic/bp/pack.lua, logic/bp/groups.lua, tests/test_pack_ticks.lua, tests/test_pack.lua, tests/test_pack_budget.lua, tests/test_pack_buffer.lua, tests/test_pack_links.lua, tests/test_pack_zone_blockers.lua, tests/test_groups.lua, tests/test_groups_rows.lua, tests/test_groups_buffer.lua, tests/test_groups_long_hands.lua, tests/test_groups_one.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/193c_pack_groups_ticks` with the MAXCALL lines of your functions and TICKS for both sheets in the message. **Run the
checks as the very LAST action.**

## What done mean

```checks
{"name": "lane193c_pack_groups_ticks-tests", "command": "git diff --name-only round-30c-base HEAD | grep -v '^docs/tasks/193c_pack_groups_ticks' | grep -Ev '^(logic/bp/pack\\.lua|logic/bp/groups\\.lua|tests/test_pack_ticks\\.lua|tests/test_pack\\.lua|tests/test_pack_budget\\.lua|tests/test_pack_buffer\\.lua|tests/test_pack_links\\.lua|tests/test_pack_zone_blockers\\.lua|tests/test_groups\\.lua|tests/test_groups_rows\\.lua|tests/test_groups_buffer\\.lua|tests/test_groups_long_hands\\.lua|tests/test_groups_one\\.lua)$' | ( ! grep . ) && ! git diff round-30c-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_pack_ticks test_pack test_pack_budget test_pack_buffer test_pack_links test_pack_zone_blockers test_groups test_groups_rows test_groups_buffer test_groups_long_hands test_groups_one; do timeout 120 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane193c_pack_groups_ticks-tests-ok", "expect_exit": 0, "expect_regex": "lane193c_pack_groups_ticks-tests-ok", "timeout_s": 1200}
{"name": "lane193c_pack_groups_ticks-same-and-short", "command": "sh tools/bytes_hash.sh player-red-science-1s > /tmp/r193c_pack_groups_ticks.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r193c_pack_groups_ticks.txt && diff tests/fixtures/bytes_round30.txt /tmp/r193c_pack_groups_ticks.txt && for c in player-red-science-1s:538 player-green-science-1s:2047; do lua5.2 tools/tick_parts.lua ${c%%:*} > /tmp/t193c_pack_groups_ticks.txt 2>&1; for f in Pack.step Pack.begin Groups.step Groups.begin; do awk -v f=$f '$1 == \"MAXCALL\" && $2 == f {print; exit !($3 <= 0.06)}' /tmp/t193c_pack_groups_ticks.txt || { echo LONG $c $f; exit 1; }; done; awk -v m=${c##*:} '$1 == \"TICKS\" {print; exit !($2 <= m)}' /tmp/t193c_pack_groups_ticks.txt || { echo TICKS $c; exit 1; }; done && echo lane193c_pack_groups_ticks-ok", "expect_exit": 0, "expect_regex": "lane193c_pack_groups_ticks-ok", "timeout_s": 1200}
```

# bound: 3600s
