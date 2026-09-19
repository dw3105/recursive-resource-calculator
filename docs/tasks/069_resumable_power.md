# 069 — One charged operation is bounded work, so Cancel means something

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-069`, branch `lane/069`, base tag `resumable-power-base` (resolve with `git rev-parse resumable-power-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/power.lua`, `tests/test_power.lua`, `tests/test_power_semantics.lua` and new `tests/test_power_budget.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/search.lua`, `logic/bp/route.lua`, `logic/bp/validate.lua` and `logic/bp/serialize.lua` are frozen. Never edit them.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

`Power.step` charges one operation, then runs `greedy_selection`, `connect_selection`, `remove_redundant` and
`better_selection` from beginning to end for one seed. Each contains nested candidate scans and rebuilds the
component graph on every iteration. Measured by an independent probe, host `legalcopilot-dev`, 2026-09-19: 15
consumers in a 54 by 54 grid, one call with `{ops = 1}` after candidates were enumerated:

```text
charged=1
candidate_count=418
approx_lua_instructions=3290000
cpu_seconds=0.049835
```

A budget of `Jobs.OPS_PER_TICK = 2000` cannot bound a tick while one operation has that shape. An aggregate stage
time says nothing about the longest uninterruptible tick, and a two-tick cancel claim is empty without bounded
tick work.

An earlier repair already shrank the inputs: poles counted per consumer plus relays in wire reaches, seeds from
256 to 8, candidates from 2916 to 233 on the player's sheet. That reduced a sample. It never changed the shape of
one operation.

## What to build

1. Give candidate evaluation, greedy selection, relay connection and pruning their own resumable cursor phases in
   plain data, exactly as `logic/bp/route.lua` and `logic/bp/search.lua` already do. No closures, no metatables,
   no LuaObjects in the state.
2. Charge bounded work inside the inner loops, so a charged operation is roughly constant work.
3. Do not rebuild the component graph from scratch on every iteration when an incrementally maintained frontier
   answers the same question.
4. For a good-enough first result, one deterministic greedy pass plus bounded repair beats eight complete
   selections. Pruning is optional work, and it never blocks publication.
5. Same input and same total budget produce the same poles and the same wires, whatever the slice size.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout resumable-power-base -- logic/bp/power.lua; out=$(cd \"$S\" && lua5.2 tests/test_power_budget.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_power.lua && lua5.4 tests/test_power.lua && lua5.2 tests/test_power_semantics.lua && lua5.4 tests/test_power_semantics.lua && lua5.2 tests/test_power_budget.lua && lua5.4 tests/test_power_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "instructions-per-op", "command": "lua5.2 -e 'local P = require(\"logic.bp.power\"); local consumers, occupied = {}, {}; for row = 0, 2 do for i = 1, 5 do local x, y = 4 + i * 7, 6 + row * 14; consumers[#consumers + 1] = {id = \"m\" .. row .. i, rect = {x = x, y = y, w = 3, h = 3}}; occupied[#occupied + 1] = {rect = {x = x, y = y, w = 3, h = 3}} end end; local s = P.begin({grid_w = 54, grid_h = 54, consumers = consumers, occupied = occupied, pole = {name = \"medium-electric-pole\", tile_w = 1, tile_h = 1, supply_w = 3.5, supply_h = 3.5, wire_reach = 9}}); local worst = 0; while not s.done do local count = 0; debug.sethook(function() count = count + 1000 end, \"\", 1000); P.step(s, {ops = 1}); debug.sethook(); if count > worst then worst = count end end; print(\"worst_instructions_per_op=\" .. worst); assert(worst < 200000, \"one charged operation must stay bounded, saw \" .. worst)'", "expect_exit": 0, "expect_regex": "worst_instructions_per_op", "timeout_s": 600}
{"name": "power-untouched-elsewhere", "command": "git diff --name-only resumable-power-base HEAD | grep -qE '^logic/bp/(search|route|validate|serialize)\\.lua$' && exit 1; echo neighbours-untouched", "expect_exit": 0, "expect_regex": "neighbours-untouched", "timeout_s": 120}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_search.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base resumable-power-base --manifest docs/tasks/069.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_power_budget.lua` must contain, at least: identical poles and wires at `{ops = 1}` and at
`{ops = 10^6}`; a run interrupted mid-selection, its state carried over, and the same result on resume; a state
walk proving no function, metatable or userdata is reachable from it; and a cancellation observed within two
steps.

## Files this lane owns

`logic/bp/power.lua`, `tests/test_power.lua`, `tests/test_power_semantics.lua`, `tests/test_power_budget.lua`.

# bound: 1918s
