# 134 faces: one face per flow, so a belt can reach every hand

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-134`, branch `lane/134`, base tag `round-15-bindings` (resolve with `git rev-parse round-15-bindings`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 27, rules 27.1, 27.2, 27.3, 27.5, **27.6**.
Frozen census baseline: `docs/round-15-census-baseline.json`. Ledger: `docs/round-15-baseline.md` sections 11
and 12.

Lane 130 anchored every port-bound hand to its own outward cell on the block perimeter, and put every hand of
every flow on the **one** bottom face. Driving `Groups` on the player's sheet shape prints, for
`block:copper+science` with `w=23 h=4`, every port on row `y = 4`:

```
(0,4) item/copper-ore       (1,4) item/copper-plate    (2,4) item/stone
(4,4) item/copper-ore       (5,4) item/copper-plate    (6,4) item/stone
(8,4) item/iron-gear-wheel  (9,4) item/iron-plate      (10,4) item/automation-science-pack
(12,4) item/iron-gear-wheel (13,4) item/iron-plate     (14,4) item/automation-science-pack
```

`logic/bp/route.lua:1061-1072` `path_cell_free` lets a belt cross a reserved port tile **only** when the tile
shares that belt's flow, which is correct. A copper-ore belt reaching `(0,4)` and `(4,4)` must cross `(1,4)`
and `(2,4)`, which belong to copper-plate and stone, so it cannot. A row carrying several flows is not
routable.

Lane 131 made `build_demands` create one demand per port. Measured on the player's sheet at `--ops 5000000`:
candidates reaching `validate` fell from **2 to 0**, with `BP_R_NO_PATH` 3 at stage `route`,
`BP_PW_UNCOVERED` 2 and `BP_PW_DISCONNECTED` 2 at stage `power`. That is this layout meeting that router,
and it is why 27.6 exists.

`logic/bp/groups.lua:565-568` keeps one route-visible endpoint per (step, flow, role) and
`logic/bp/groups.lua:678` gives every other hand `rate_per_second = 0`, so the unbound ports stop being
counted. Measured in a throwaway worktree: restoring those rates and changing nothing else moves
`BP_V_PORT_UNREACHABLE` from rate 5.0 to 17.0, from 10 records to 34, and moves nothing else at all. The
aggregation routes no product; it hides unbound ports. With lane 131's per-port demands it is actively wrong,
because a router asking per port must see every port's real rate.

Reference budgets, from a factory the player built for this same sheet that the game runs
(`tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt`): 131 entities, 84 transport-belt,
22 inserter, 10 medium-electric-pole, 6 electric-furnace, 5 assembling-machine-3, 4 roboport, 12 wires, zero
undergrounds, zero splitters, zero pipes, zero beacons. Its machines stand in a column with a belt lane per
side.

`tests/test_transport_handshake.lua` asserts that ports exist, are anchored and are distinct. It never
asserts that anything routes to them, which is why lane 130's gates stayed green while the factory starved.

PRESERVE: `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/search.lua`, `logic/bp/grid.lua`,
`logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/test_census_codes_live.lua`, `tests/test_bindings_per_hand.lua`,
`tests/golden/cases/player-red-science-1s/`, `docs/round-15-census-baseline.json`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`,
`tests/test_pack.lua`, `tests/test_inserter_geometry.lua`, `tests/test_port_edges.lua`,
`tests/test_transport_handshake.lua`, `tests/test_placed_port_geometry.lua`.

## What to build

Extend `tests/test_transport_handshake.lua` with a case that fails today: no two ports on one block face
carry different `flow_id`s. Record its failure count before changing the layout.

Give each flow its own machine face. A machine has four faces and the player's science step needs three, two
in and one out. Keep every hand's outward cell on the block perimeter, so rules 27.2 and 27.3 continue to
hold and the pinned-port machinery in `logic/bp/pack.lua` keeps working. The block envelope grows on the axes
that now carry hands; keep it as tight as that allows.

When a machine's distinct item flows outnumber the faces it can reach the perimeter on, fail by name with the
already-registered `BP_P_NO_FIT` and let `logic/bp/groups.lua:1213-1218` hand the search another partition.
Do not silently put two flows back on one face.

Delete the `route_live` aggregation at `logic/bp/groups.lua:565-585` and the zeroed rate at `:678`. Every
anchored port carries the real rate its hand moves: the step's rate for that flow divided across the machines
of the step, so the rates over a step's hands sum to the step's own demand rather than each claiming all of
it.

This lane changes layout only. It does not touch routing, and it does not change which underground, splitter
or crossing the router chooses, on the user's explicit decision that the router keeps its behaviour.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_transport_handshake.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S one-face-per-flow-off >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_transport_handshake.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "handshake", "command": "sh tools/lane_rows.sh tests/test_transport_handshake.lua --min-cases 7", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "no-route-live", "command": "grep -q route_live logic/bp/groups.lua && { echo 'the route_live aggregation survives, so unbound ports are still hidden by a zero rate'; exit 1; }; echo route-live-gone", "expect_exit": 0, "expect_regex": "route-live-gone", "timeout_s": 120}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "candidates-reach-validate", "command": "python3 tools/real_sheet_census.py --ops 5000000 --json /tmp/rrc134.json -q >/dev/null 2>&1 && python3 -c \"import json,sys; d=json.load(open('/tmp/rrc134.json')); n=d['counters']['validate_attempts']; print('validate_attempts',n); sys.exit(0 if n>=8 else 1)\"", "expect_exit": 0, "expect_regex": "validate_attempts", "timeout_s": 900}
{"name": "no-path-gone", "command": "python3 -c \"import json,sys; d=json.load(open('/tmp/rrc134.json')); n=d['census'].get('BP_R_NO_PATH',0); print('no_path',n); sys.exit(1 if n else 0)\"", "expect_exit": 0, "expect_regex": "no_path 0", "timeout_s": 300}
{"name": "case-frozen", "command": "git diff --quiet round-15-bindings HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tests/test_census_codes_live.lua docs/round-15-census-baseline.json && echo case-frozen || { echo 'this lane changed the pinned sheet, the census tooling or the baseline'; exit 1; }", "expect_exit": 0, "expect_regex": "case-frozen", "timeout_s": 120}
{"name": "census-fast", "command": "python3 tools/census_gate.py --baseline docs/round-15-census-baseline.json --tier fast --require-down BP_V_TRANSPORT_UNUSED,BP_V_TRANSFER_BROKEN --waiver docs/tasks/134.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 900}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 134_faces", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-15-bindings --manifest docs/tasks/134.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
