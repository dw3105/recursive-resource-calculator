# 073 — Every underground pair the router places is paired

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-073`, branch `lane/073`, base tag `validator-rejection-2-base` (resolve with `git rev-parse validator-rejection-2-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/fixtures/routing/` and new `tests/test_underground_pairs.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua` and `logic/bp/pack.lua` have another owner right now. `logic/bp/search.lua`, `logic/bp/power.lua` and `logic/bp/serialize.lua` are frozen.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

The player's fixture reaches validation and every candidate is refused. Measured on this base, host
`legalcopilot-dev`, 2026-09-19, twelve grid trials:

```text
BP_V_COLLISION              30
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_PORT_EDGE_WRONG        21
BP_V_UNDERGROUND_UNPAIRED    6
```

You own `BP_V_UNDERGROUND_UNPAIRED`. The other three belong to another lane and will move under you; judge your
own code, never the totals.

Run it yourself:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

Routing places an underground pair when a belt must cross another. `append_crossing` writes the entry at the
tile the path dives on and the exit at the tile it surfaces on, with `ug_pair_id` pointing each at the other,
`type = "input"` at the demand's source end and `type = "output"` at its sink end. `logic/bp/validate.lua` pairs
them by `ug_pair_id` and requires the two roles to differ, the direction to face, and the distance to be inside
that connection's own `max_underground_distance`.

Six pairs fail that check. Find which of those four conditions breaks. Candidates: a rip-up restart that clears
segments but leaves an entity behind, a crossing whose partner is removed by a later demand, a pair that was
emitted with both ends carrying the same role, or a distance measured in a different frame from the validator's.

## What to build

Drive `BP_V_UNDERGROUND_UNPAIRED` to zero with the validator untouched. Every underground entity a route result
carries must have exactly one partner in that same result, with opposite roles, facing directions, and a distance
inside its own limit. A rip-up must remove both ends of a pair or neither.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout validator-rejection-2-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_underground_pairs.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.4 tests/test_route_budget.lua && lua5.2 tests/test_underground_pairs.lua && lua5.4 tests/test_underground_pairs.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "no-unpaired", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_UNDERGROUND_UNPAIRED' && exit 1; echo no-unpaired", "expect_exit": 0, "expect_regex": "no-unpaired", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base validator-rejection-2-base --manifest docs/tasks/073.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_underground_pairs.lua` must walk a route result with an independently written predicate: every
entity carrying `ug_pair_id` has exactly one partner in the same result, roles differ, directions face, distance
is inside the limit, and a run that rips up and reroutes leaves no orphan end.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/fixtures/routing/`, `tests/test_underground_pairs.lua`.

# bound: 1918s
