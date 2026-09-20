# 083 — More ports must not mean less budget

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-083`, branch `lane/083`, base tag `many-ports-base` (resolve with `git rev-parse many-ports-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua` and new `tests/test_external_ports.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- **These must stay green:** `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua`, `tests/test_route_layout_contract.lua`, `tests/test_port_edges.lua`, `tests/test_port_tile_flow.lua`, `tests/test_port_not_self_blocked.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_beacon_coverage.lua`, `tests/test_pack.lua`, `tests/test_groups.lua`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Commit `e8949e0` on branch `lane/082` is unmerged work at this problem. Read it with `git show e8949e0`. It gives
an external flow as many perimeter ports as its consumers need, and its own test
`tests/test_external_ports.lua` is 10 of 10. **Take it as your starting point; never merge that branch.**

What it changed, measured host `legalcopilot-dev`, 2026-09-20, on `docs/tasks/058_reproducer.lua`:

```text
this base            DISCARD route 24   BP_R_NO_PATH item/plate 14, item/machine 5, BP_R_EXPANSIONS item/cable 5
lane/082 commit      DISCARD route 24   BP_R_EXPANSIONS item/plate 19, BP_R_NO_PATH item/machine 5
```

`item/plate` stopped reporting *no path* and started reporting *out of expansions*. With more ports a path
plausibly exists and the search runs out of budget before finding it. That is the fault to fix.

It also costs more: this base is terminal in about two seconds, and that commit takes about two minutes.

The expansion budget is derived from the reachable cell count times four directions times four direction orders,
and it is one cumulative budget for a whole routing run. More ports mean more demands sharing that one budget,
so each demand gets less of it exactly when the geometry got easier.

## What to build

1. Make the budget scale with the work a run actually has to do: the demands it must route, not only the cells
   one of them can reach. Keep it derived and bounded, never a guessed constant, and keep one cumulative budget
   per run so a hopeless run still ends.
2. Keep the cost near this base. The fixture must reach a terminal result inside 120 seconds.
3. `item/machine` still reports `BP_R_NO_PATH` five times on both trees. Say in your report whether your change
   moves it, and never claim it fixed if the count stands.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout many-ports-base -- logic/bp/route.lua logic/bp/search.lua; out=$(cd \"$S\" && lua5.2 tests/test_external_ports.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua && lua5.2 tests/test_external_ports.lua && lua5.4 tests/test_external_ports.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "everything-else-stays-green", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_port_edges.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_beacon_coverage.lua && lua5.2 tests/test_pack.lua && lua5.2 tests/test_groups.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "fixture-terminates-in-120s", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 300}
{"name": "validator-clean", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 300}
{"name": "no-plate-expansions", "command": "out=$(timeout 120 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_R_EXPANSIONS' && exit 1; echo no-expansions", "expect_exit": 0, "expect_regex": "no-expansions", "timeout_s": 300}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base many-ports-base --manifest docs/tasks/083.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Add to `tests/test_external_ports.lua`: a run whose demands outnumber one demand's reachable cells still gives
each demand a usable share, and a hopeless run still ends inside its bound.

## Files this lane owns

`logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`, `tests/test_external_ports.lua`.

# bound: 1918s
