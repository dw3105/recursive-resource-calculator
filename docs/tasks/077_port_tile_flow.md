# 077 — A port's own tile never carries another flow

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-077`, branch `lane/077`, base tag `last-two-codes-base` (resolve with `git rev-parse last-two-codes-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/fixtures/routing/` and new `tests/test_port_tile_flow.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua` has another owner right now. `logic/bp/pack.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- **`tests/test_search.lua` and `tests/test_blueprint_pipeline.lua` must stay green.**
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_port_tile_flow.lua` first, before changing the module.**

Two codes remain on the player's fixture. Yours is the first, measured host `legalcopilot-dev`, 2026-09-20:

```text
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_PORT_EDGE_WRONG        21
```

`BP_V_PORT_EDGE_WRONG` here is not a geometry fault. `check_port_approaches` in `logic/bp/validate.lua` reports
`port-owned tile carries another flow`, and every instance on the fixture is the same tile:

```text
PORTTILE port=out:item/cable tile=(8,4) port_flow=item/cable occupant=r:8 occupant_flow=item/circuit
```

So a belt carrying `item/circuit` stands on the tile that the `item/cable` output port owns. Routing already
reserves a port's own tile and its approach tile in `reserve_port_cells`, and lets a belt of the **same flow**
pass. Something still puts a foreign flow there. Candidates worth checking before changing arithmetic: a splitter
whose second tile lands on a reserved tile, a crossing whose entry or exit lands on one, a rip-up that drops a
reservation, and whether the reservation is keyed by the placed port position the validator reads.

Run it yourself and read the `DETAIL` lines:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Drive `BP_V_PORT_EDGE_WRONG` to zero. Leave `BP_V_BEACON_COVERAGE_SHORT` alone; it has another owner and its
count will move under you.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout last-two-codes-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_port_tile_flow.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.4 tests/test_port_tile_flow.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "search-and-pipeline-stay-green", "command": "lua5.2 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "no-port-edge", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_PORT_EDGE_WRONG' && exit 1; echo no-port-edge", "expect_exit": 0, "expect_regex": "no-port-edge", "timeout_s": 900}
{"name": "fixture-still-terminates", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base last-two-codes-base --manifest docs/tasks/077.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_port_tile_flow.lua` walks a route result with an independently written predicate: no entity of one
flow stands on a tile owned by a port of another flow, including a splitter's second tile and both ends of a
crossing.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/fixtures/routing/`, `tests/test_port_tile_flow.lua`.

# bound: 1918s
