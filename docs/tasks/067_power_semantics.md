# 067 — A pole covers a machine it overlaps, and every beacon needs power

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-067`, branch `lane/067`, base tag `power-semantics-base` (resolve with `git rev-parse power-semantics-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/power.lua`, `logic/bp/search.lua`, `tests/test_power.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua` and new `tests/test_power_semantics.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/route.lua` has another owner right now. Never edit it. `logic/bp/validate.lua` and `logic/bp/serialize.lua` are frozen: the validator must stay an independent check, never a copy of the planner's predicate.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Three false rejections, each reproduced on this base, host `legalcopilot-dev`, 2026-09-19.

### Fault 1: coverage demands full containment

`consumer_covered` in `logic/bp/power.lua` requires the pole's supply square to contain the consumer's whole
rectangle. `logic/bp/validate.lua` instead requires the consumer's centre to sit in the supply square. Neither is
the engine rule. A pole powers a machine when its supply area overlaps that machine at all; a pole beside a 5x5
machine cannot contain it, and full containment would put the pole inside the machine.

```lua
local P = require('logic.bp.power')
local s = P.begin({grid_w=14, grid_h=14,
  occupied={{rect={x=4,y=4,w=5,h=5}}},
  consumers={{id='machine',rect={x=4,y=4,w=5,h=5}}},
  pole={name='small-electric-pole',tile_w=1,tile_h=1,supply_w=2.5,supply_h=2.5,wire_reach=7.5}})
for _ = 1, 20000 do P.step(s, {ops = 1}); if s.done then break end end
print(s.ok, s.result.pole_count, s.result.components, #s.result.uncovered)
--> false  0  0  1
```

`supply_area_distance` is the radius of the supply square, so the supply square of a pole at tile `(x, y)` with
`supply_w = supply_h = 2.5` spans 5 by 5 tiles centred on that pole. Coverage is overlap with the consumer's own
rectangle, never containment, and it is quality aware through the catalog's per-quality value.

### Fault 2: generated beacons are never electrical consumers

`power_consumers` in `logic/bp/search.lua` keeps an entity when `kind == "machine"`, `type == "machine"` or
`step_id ~= nil`. A generated beacon carries `kind = "beacon"` and no `step_id`, so no beacon is ever a placement
requirement. `needs_power` in `logic/bp/validate.lua` does require power for a beacon. A candidate can route,
finish the power stage and then fail validation for a beacon the power stage was never told about. Inserters are
included today only because they happen to carry `step_id`; that is an accident, not a rule.

### Fault 3: relays are pinned to a global lattice

A pole covering no consumer is kept only when both its coordinates are multiples of `floor(wire_reach / 2)`. An
obstacle can force the only legal relay off that lattice.

```lua
local P = require('logic.bp.power')
local s = P.begin({grid_w=22, grid_h=3,
  occupied={{rect={x=0,y=0,w=22,h=1}}, {rect={x=0,y=2,w=22,h=1}},
            {rect={x=1,y=1,w=1,h=1}}, {rect={x=19,y=1,w=1,h=1}}},
  consumers={{id='a',rect={x=1,y=1,w=1,h=1}}, {id='b',rect={x=19,y=1,w=1,h=1}}},
  pole={name='test-pole',tile_w=1,tile_h=1,supply_w=1.5,supply_h=1.5,wire_reach=9}})
for _ = 1, 20000 do P.step(s, {ops = 1}); if s.done then break end end
print(s.ok, s.result.pole_count, s.result.components, #s.result.uncovered)
--> false  2  2  0
```

Poles at `(0,1)`, `(9,1)` and `(18,1)` cover both consumers and form one chain. The middle one covers nothing and
its `y = 1` fails the lattice test, as does every other relay in the only free row.

That lattice exists for a measured reason: without it the candidate list on a 54 by 54 grid was 2916 and the
stage took 61.3 s. Keep the sparse lattice as the **preferred** candidate set, and add bounded off-lattice search
only where a component must be connected.

## What to build

1. Coverage is overlap of the pole's quality-aware supply square with the consumer's rectangle. Fix it in the
   planner. Never edit the validator to agree; it is the independent check.
2. Classify electrical consumers from what an entity is, not from whether it carries `step_id`: machines,
   beacons, inserters and any supported powered transport. Roboports stay excluded, as asked.
3. Keep the sparse relay lattice as preferred candidates, and allow bounded local off-lattice candidates when
   connecting two components. Exhausting the bound reports failure to find a layout within limits, never proof
   that none exists.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout power-semantics-base -- logic/bp/power.lua logic/bp/search.lua; out=$(cd \"$S\" && lua5.2 tests/test_power_semantics.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_power.lua && lua5.4 tests/test_power.lua && lua5.2 tests/test_power_semantics.lua && lua5.4 tests/test_power_semantics.lua && lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua && lua5.4 tests/test_search_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "validator-untouched", "command": "git diff --name-only power-semantics-base HEAD | grep -qE '^logic/bp/(validate|serialize|route)\\.lua$' && exit 1; echo validator-untouched", "expect_exit": 0, "expect_regex": "validator-untouched", "timeout_s": 120}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua && lua5.2 tests/test_validate.lua && lua5.2 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base power-semantics-base --manifest docs/tasks/067.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_power_semantics.lua` must contain, at least: both probes above, now succeeding; a pole that overlaps
a rotated non-square consumer; a pole whose supply square misses a consumer by one tile, which must stay
uncovered; a quality whose supply distance differs; a generated beacon out of range of every machine-covering
pole, which must force another pole or a clear failure; and a genuinely disconnected case that still terminates
inside its bound.

## Files this lane owns

`logic/bp/power.lua`, `logic/bp/search.lua`, `tests/test_power.lua`, `tests/test_power_semantics.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`.

# bound: 1918s
