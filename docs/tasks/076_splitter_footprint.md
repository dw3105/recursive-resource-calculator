# 076 — A splitter the router places occupies the two tiles it really covers

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-076`, branch `lane/076`, base tag `splitter-footprint-base` (resolve with `git rev-parse splitter-footprint-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_underground_pairs.lua`, `tests/fixtures/routing/` and new `tests/test_route_footprints.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/validate.lua` is frozen and is the authority. Never weaken a validator rule to make a layout pass.
- `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua` are frozen.
- `tests/fixtures/routing/player_chain_first_candidate.lua` is a frozen positive input. Never edit it.
- **`tests/test_search.lua` and `tests/test_blueprint_pipeline.lua` must stay green.** Both are frozen.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**Write `tests/test_route_footprints.lua` first, before changing the module.**

The cause of `BP_V_COLLISION` is measured and named. Every colliding pair on the player's fixture is a routing
entity against another routing entity, host `legalcopilot-dev`, 2026-09-20:

```text
COLLIDE r:47(underground-belt) box=(12.05,7.05)-(12.95,7.95)  vs  r:66(splitter) box=(10.55,7.05)-(12.45,7.95)
COLLIDE r:64(splitter)         box=(9.55,8.05)-(11.45,8.95)   vs  r:65(transport-belt) box=(11.05,8.05)-(11.95,8.95)
COLLIDE r:64(splitter)         box=(9.55,8.05)-(11.45,8.95)   vs  r:67(splitter) box=(10.05,6.55)-(10.95,8.45)
COLLIDE r:64(splitter)         box=(9.55,8.05)-(11.45,8.95)   vs  r:86(transport-belt) box=(9.05,8.05)-(9.95,8.95)
COLLIDE r:66(splitter)         box=(10.55,7.05)-(12.45,7.95)  vs  r:67(splitter) box=(10.05,6.55)-(10.95,8.45)
COLLIDE r:67(splitter)         box=(10.05,6.55)-(10.95,8.45)  vs  r:76(transport-belt) box=(10.05,6.05)-(10.95,6.95)
```

A transport belt is one tile wide, box about 0.9. A splitter is **two tiles wide**, box about 1.9. Routing turns
an existing belt into a splitter at `logic/bp/route.lua:719`:

```lua
entity.name = work.belt.splitter
entity.splitter = true
```

It changes the name and the direction, and it never claims the second tile. The splitter then reaches into a
neighbouring cell that another belt, another splitter or an underground end already owns.

Two earlier lanes were sent at `logic/bp/groups.lua` and `logic/bp/pack.lua` for this count and neither could
move it; one made it 18 to 200. Blocks are not the cause. This is.

Measured counts on this base, twelve grid trials on `docs/tasks/058_reproducer.lua`:

```text
BP_V_BEACON_COVERAGE_SHORT  21
BP_V_COLLISION              18
BP_V_PORT_EDGE_WRONG        21
```

Run it yourself and read the `DETAIL` lines:

```sh
timeout 800 lua5.2 docs/tasks/058_reproducer.lua
```

## What to build

Drive `BP_V_COLLISION` to zero. A splitter must occupy both tiles it covers, and the second tile must be free
and claimed when it is created, or the branch must not become a splitter at all and the demand takes another
path. A splitter's second tile is beside it, across its travel direction, and which side depends on the belt
direction: derive it, never guess it.

Leave `BP_V_PORT_EDGE_WRONG` and `BP_V_BEACON_COVERAGE_SHORT` alone. They belong to another owner.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout splitter-footprint-base -- logic/bp/route.lua; out=$(cd \"$S\" && lua5.2 tests/test_route_footprints.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_route.lua && lua5.4 tests/test_route.lua && lua5.2 tests/test_route_budget.lua && lua5.4 tests/test_route_budget.lua && lua5.2 tests/test_underground_pairs.lua && lua5.2 tests/test_route_footprints.lua && lua5.4 tests/test_route_footprints.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "frozen-input-routes", "command": "lua5.2 -e 'local i = dofile(\"tests/fixtures/routing/player_chain_first_candidate.lua\"); local R = require \"logic.bp.route\"; local s = R.begin(i); local n = 0; while not s.done and n < 4000000 do local b = {ops = 20000}; R.step(s, b); n = n + (20000 - b.ops) end; assert(s.done and s.ok); print(\"frozen ok ops=\" .. n)'", "expect_exit": 0, "expect_regex": "frozen ok", "timeout_s": 300}
{"name": "search-and-pipeline-stay-green", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.2 tests/test_validate.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "no-collision", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -E 'BP_V_COLLISION' && exit 1; echo no-collision", "expect_exit": 0, "expect_regex": "no-collision", "timeout_s": 900}
{"name": "fixture-still-terminates", "command": "out=$(timeout 700 lua5.2 docs/tasks/058_reproducer.lua 2>&1); printf '%s\\n' \"$out\" | grep -qE 'REPRO state=(failure|success)' && echo fixture-terminates", "expect_exit": 0, "expect_regex": "fixture-terminates", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base splitter-footprint-base --manifest docs/tasks/076.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_route_footprints.lua` walks a route result with an independently written box predicate: build every
entity's real rectangle from its name and direction, and assert no two overlap. It must cover a splitter created
beside an existing belt, a splitter beside an underground end, and two splitters that would share a tile.

## Files this lane owns

`logic/bp/route.lua`, `tests/test_route.lua`, `tests/test_route_budget.lua`, `tests/test_underground_pairs.lua`, `tests/fixtures/routing/`, `tests/test_route_footprints.lua`.

# bound: 1918s
