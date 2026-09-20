# 079 — A port is never blocked by a neighbour port's reservation

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-079`, branch `lane/079`, base tag `port-block-base` (resolve with `git rev-parse port-block-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_port_tile_flow.lua`, `tests/fixtures/routing/` and new `tests/test_port_not_self_blocked.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- **`tests/test_search.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_validate.lua` and `tests/test_port_tile_flow.lua` must stay green.**
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_port_not_self_blocked.lua` first, before changing the module.**

The validator now rejects nothing at all on the player's fixture: collisions, wires, underground pairing, port
edges and beacon coverage are each zero. The fixture also went from about six minutes to **1.8 seconds**. It
still ends `BP_FAIL_SEARCH_BUDGET` with no incumbent, because every candidate now dies in routing, measured host
`legalcopilot-dev`, 2026-09-20, twelve grid trials, 48720 operations:

```text
DISCARD route  24
ROUTECODE BP_R_PORT_BLOCKED flow=item/cable detail=src=(6,4 owner=nil) sink=(14,0 owner=nil)   7
ROUTECODE BP_R_PORT_BLOCKED flow=item/plate detail=src=(0,12 owner=nil) sink=(15,0 owner=nil)  6
ROUTECODE BP_R_PORT_BLOCKED flow=item/cable detail=src=(1,6 owner=nil) sink=(14,4 owner=nil)   5
ROUTECODE BP_R_PORT_BLOCKED flow=item/plate detail=src=(0,14 owner=nil) sink=(13,0 owner=nil)  5
ROUTECODE BP_R_NO_PATH      flow=item/plate detail=nil                                          1
```

Both ends report `owner=nil`, so no entity stands on either tile. The block comes from
`endpoint_reservation_conflict` at `logic/bp/route.lua:599`:

```lua
local own_flow = "flow:" .. tostring(endpoint.flow_id)
for key, _ in pairs(reserved) do
    if tostring(key):sub(1, 5) == "flow:" and key ~= own_flow then return true end
end
```

A port is declared blocked when its tile carries **any** other flow tag. But `reserve_port_cells` claims each
port's own tile **and** its approach tile, and two ports of different flows sit on neighbouring tiles of the same
block, so one port's approach tile is often another port's own tile. Each then declares the other blocked before
routing begins. Twenty-three of twenty-four candidates die that way.

The `flow:` keys exist for one purpose only: letting a belt of the same flow pass through a reserved tile. They
were never a test of whether a port is usable.

## What to build

A port is blocked only when something actually stands on its tile, or when another **port** owns that exact tile.
A neighbouring port's flow tag never blocks it. Keep what lane 077 bought: a foreign flow must still not take a
port's own tile, and `tests/test_port_tile_flow.lua` stays green.

Run the fixture yourself; it costs under two seconds now:

```sh
timeout 200 lua5.2 docs/tasks/058_reproducer.lua
```

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout port-block-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_port_not_self_blocked.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.2 tests/test_route_footprints.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_port_tile_flow.lua && lua5.4 tests/test_port_tile_flow.lua && lua5.2 tests/test_port_not_self_blocked.lua && lua5.4 tests/test_port_not_self_blocked.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "search-and-pipeline-stay-green", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "no-self-block", "command": "out=$(timeout 300 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_R_PORT_BLOCKED' && exit 1; echo no-self-block", "expect_exit": 0, "expect_regex": "no-self-block", "timeout_s": 600}
{"name": "validator-still-clean", "command": "out=$(timeout 300 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_' && exit 1; echo validator-clean", "expect_exit": 0, "expect_regex": "validator-clean", "timeout_s": 600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base port-block-base --manifest docs/tasks/079.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_port_not_self_blocked.lua` must include: two ports of different flows on neighbouring tiles of one
block, both routable; a port whose tile genuinely holds a foreign belt, which stays blocked; and a port whose own
approach tile is a neighbour port's tile, which stays routable.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_route_footprints.lua`, `tests/test_underground_pairs.lua`, `tests/test_port_tile_flow.lua`, `tests/fixtures/routing/`, `tests/test_port_not_self_blocked.lua`.

# bound: 1918s
