# 262_route_commit_refuses_chain_jump route commit refuses any path with two underground jumps in a row

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-262`, branch `lane/262`,
base tag `round-45-w5b`, merge target `int/r44`. Host `legalcopilot-dev`.

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

A path whose jump ends on a tile that also starts the next jump (A->B underground, B->C underground) cannot be built:
tile B holds one entity. `append_normal_path` (`logic/bp/route.lua`) consumes the exit tile with the first pair and
never lays the second jump, leaving an underground exit pointing into whatever lies ahead. Round 44 (lane 246) only
retries such a path when `route_chain_reaches_sink` refuses it; when ANOTHER branch of the same flow already reaches
the sink, the check passes and the broken piece is published. On `player-inserter-10s-stack1` (legalcopilot-dev,
2026-09-28) product `item/inserter` dove (31,35)->(31,33) and again (31,33)->(31,26); only the first pair was laid,
its exit at (31,33) pointed into the circuit trunk at (31,32): 26 `BP_V_BELT_BLEED` and the candidate was refused.

Fix: at the top of `append_normal_path` (before `local sink = sink_key(...)`), if any `i` has
`is_crossing_step(path[i-1], path[i]) and is_crossing_step(path[i], path[i+1])`, `return reject("route-discontinuous")`.
The existing `route-discontinuous` branch in `Route.step` then retries with `no_chain_dive` (lane 246). Reference
(measured in memory): `docs/tasks/ref/262_patch_reference.lua`. Measured: bytes of all 11 gated golden sheets
unchanged; stack1 generates `ok=true` 841 entities only with this rule (plus the lane 263 validator rule).

## What to build

1. `tests/test_route_chain_jump_commit.lua` (commit red first; case names start `CJ`): synthetic (`Route.begin`, shapes of
   `tests/test_route.lua`): one flow, two sources, one sink; source 1 reaches the sink directly; source 2's cheapest
   path must cross two parallel walls one tile apart (so its search plans jump A->B then B->C). Assert no published
   underground exit of the flow points into a tile that is not the next same-flow transport (walk `state.result`
   entities), and `ok == true`. If you cannot make it red on base in 20 minutes, assert instead that
   `work.counters` shows at least one `route-discontinuous` retry on the fixed code for that geometry, and say so in
   the header.
2. `logic/bp/route.lua`: the rule, short comment citing the tiles and date.
3. Last, once: `lua5.2 tests/test_inserter_stack1_delivers.lua` (about 15 min; allowed) — report its last line
   (it may stay red until the validator lane lands; say which codes remain).

## Files this lane owns

logic/bp/route.lua, tests/test_route_chain_jump_commit.lua, docs/tasks/262_route_commit_refuses_chain_jump.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/262`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane262-tests", "command": "git diff --name-only round-45-w5b HEAD | grep -Ev '^(logic/bp/route\\.lua|tests/test_route_chain_jump_commit\\.lua|docs/tasks/262_route_commit_refuses_chain_jump\\.md)$' | ( ! grep . ) && git diff --quiet round-45-w5b HEAD -- docs/tasks && for t in test_route_chain_jump_commit test_route test_route_belt_chain test_route_chain test_route_collision test_route_budget test_route_underground_feed test_route_no_self_cross test_route_self_cross_occupied test_route_ug_exit_rear test_route_pipe_join test_pipe_runs test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane262-tests-ok", "expect_exit": 0, "expect_regex": "lane262-tests-ok", "timeout_s": 3000}
{"name": "lane262-fast", "command": "out=$(lua5.2 tests/test_route_chain_jump_commit.lua 2>&1); echo \"$out\" | grep -q CJ || { echo MISSING CJ; exit 1; }; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane262-ok", "expect_exit": 0, "expect_regex": "lane262-ok", "timeout_s": 600}
```

# bound: 3000s
