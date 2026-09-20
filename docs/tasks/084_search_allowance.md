# 084 — The search allowance covers the whole pipeline, never one route

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-084`, branch `lane/084`, base tag `search-allowance-base` (resolve with `git rev-parse search-allowance-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`, `tests/test_external_ports.lua` and new `tests/test_search_allowance.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/route.lua`, `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **These must stay green:** `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_route_layout_contract.lua`, `tests/test_port_edges.lua`, `tests/test_port_tile_flow.lua`, `tests/test_port_not_self_blocked.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_beacon_coverage.lua`, `tests/test_pack.lua`, `tests/test_groups.lua`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_search_allowance.lua` first, before changing the module.**

The player's fixture now routes. Measured on this base, host `legalcopilot-dev`, 2026-09-20:

```text
ROUTECODE ok  1          and no route failure of any kind
terminal in 4.78 s
FAILBUDGET grid_trials=1 grid_limit=false power_bound=false ops=326609 incumbent=false
```

One candidate routes successfully, and the run still ends `BP_FAIL_SEARCH_BUDGET` with no layout. It stops after
a **single** grid trial, and neither the grid cap nor the power bound was reached. The whole search allowance was
spent.

The allowance is set in `logic/bp/search.lua`, in the pack-to-route transition:

```lua
state.max_ops = state.ops_used + state.work.route.work.max_expansions
```

That is one route's expansion allowance. The search must also pay for packing, power, validation, serialization,
and every remaining candidate and grid. So the number is far too small for the job it bounds, and the run dies
holding a routed candidate it never validated.

Run the fixture yourself; it costs five seconds:

```sh
timeout 200 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Derive an allowance that covers the work a search really does: at least one full grid's candidates through pack,
route, power, validate and serialize, with headroom for the grid trials the policy permits. Keep it derived from
the problem, bounded, and deterministic; never a guessed constant, and never unbounded.

Keep what the allowance was added for: an expensive power sweep must still not turn a finite route into an
unbounded generation job. Publication stays reserved, so exhausting the allowance with an incumbent still
serializes that incumbent.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout search-allowance-base -- logic/bp/search.lua; out=$(cd \"$S\" && lua5.2 tests/test_search_allowance.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua && lua5.4 tests/test_search_budget.lua && lua5.2 tests/test_external_ports.lua && lua5.2 tests/test_search_allowance.lua && lua5.4 tests/test_search_allowance.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "everything-else-stays-green", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_groups.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "fixture-terminates-in-120s", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 300}
{"name": "validator-clean", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 300}
{"name": "fixture-reaches-success", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=success' && echo fixture-success", "expect_exit": 0, "expect_regex": "fixture-success", "timeout_s": 300}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base search-allowance-base --manifest docs/tasks/084.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_search_allowance.lua` must cover: a plan whose first grid needs pack, route, power and validate for
several candidates finishing inside its allowance; an allowance exhausted with an incumbent still serializing
that incumbent; an allowance exhausted with none reporting the budget code; and the same input giving the same
allowance twice.

If `fixture-reaches-success` stays out of reach, commit what you have with its test and report exactly what the
run ends on, with its counters.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`, `tests/test_external_ports.lua`, `tests/test_search_allowance.lua`.

# bound: 1918s
