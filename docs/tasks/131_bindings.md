# 131 bindings: every hand gets its own belt

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-131`, branch `lane/131`, base tag `round-15-anchor` (resolve with `git rev-parse round-15-anchor`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 27, rules 27.1, 27.2, 27.5.
Frozen census baseline: `docs/round-15-census-baseline.json`. Ledger: `docs/round-15-baseline.md`.

Lane 130 landed the producer half of contract 27. A block now publishes **one port per port-bound inserter**,
anchored to that inserter's outward cell, and packing carries a `pinned` flag that stops relocating it. Port
ids read `copper-plate:in:item/copper-ore:inserter:copper-plate:2:input:1`.

Routing has not caught up, and the census says exactly where. Measured on `tests/golden/cases/player-red-science-1s`
at `--ops 5000000` against the frozen fast tier:

| code | baseline rate | now | |
|---|---:|---:|---|
| `BP_V_TRANSPORT_UNUSED` | 140.25 | 92.0 | fell |
| `BP_V_TRANSFER_BROKEN` | 24.00 | 17.0 | fell |
| `BP_V_INSERTER_GEOMETRY` | 10.75 | 17.0 | rose |
| `BP_V_ROUTE_DISCONTINUOUS` | 2.00 | 7.0 | rose |
| `BP_V_PORT_UNREACHABLE` | 0 | 5.0 | new |
| `BP_R_NO_PATH` | 0 | 1.0 | new, stage `route` |
| `BP_PW_DISCONNECTED` | 0 | 1.5 | new, stage `power` |
| candidates reaching `validate` | 8 | 2 | fell |

Every new `BP_V_PORT_UNREACHABLE` record carries `reason = "no binding uses this port as a sink"` and names a
per-inserter port, for example `automation-science-pack:in:item/copper-plate:inserter:automation-science-pack:4:input:1`.
Every new `BP_V_INSERTER_GEOMETRY` record carries `reason = "inserter pickup cell has invalid occupant"`,
`found = "empty ground"`, at cells such as `{x = 26, y = 9}` and `{x = 27, y = 9}`.

The cause is one function. `logic/bp/route.lua:612` `build_demands` creates one producer entry per
`flow.producers` entry and one consumer entry per `flow.consumers` entry -- that is, one per **plan** entry,
never one per port. `logic/bp/route.lua:597-607` `demand_endpoint_candidates` returns every endpoint of that
flow and step, and `:621` and `:626` take `candidates[1]` as *the* endpoint while treating the rest as
interchangeable alternatives for the same single demand. So where a step used to publish one port per flow
and the candidate list had one entry, it now publishes one per hand and all but one are never bound. The
share at `share_of(entry)` is the whole plan entry's rate, so it is also never split.

`BP_R_NO_PATH` at stage `route` and `BP_PW_DISCONNECTED` at stage `power` are downstream of the same thing:
unrouted anchored ports leave cells bare and poles with nothing to reach.

The denominator fell from 8 to 2 because a pinned port whose tile is unusable now rejects the **placement**
(`logic/bp/pack.lua`, contract 27.3), so fewer candidates fit. That is intended, and it is what the
`--allow-rise` clause below accounts for rather than hides.

`tools/real_sheet_census.py` and `tools/census_gate.py` are the instruments; `tests/test_census_codes_live.lua`
proves each counted code can still be provoked, and renaming `BP_V_TRANSPORT_UNUSED` turns its CL3 case red.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/validate.lua`, `logic/bp/grid.lua`,
`logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/serialize.lua`, `logic/catalog.lua`,
`tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/test_transport_handshake.lua`, `tests/golden/cases/player-red-science-1s/`,
`docs/round-15-census-baseline.json`, `docs/feature-contracts.md`, `tools/**`, `info.json`,
`mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `logic/bp/search.lua`, `tests/test_route.lua`,
`tests/test_route_network.lua`, `tests/test_route_layout_contract.lua`, `tests/test_demand_terminals.lua`,
`tests/test_port_tile_flow.lua`, `tests/test_bindings_per_hand.lua` (new).

## What to build

Write `tests/test_bindings_per_hand.lua` first. Drive `Route` on a block that publishes several ports for one
flow on one step, and assert every such port is the sink of some binding and that the plan entry's rate is
divided across them. It is red when written.

Make `build_demands` create one consumer entry per **port**, not per plan entry, and one producer entry per
port the same way, dividing that entry's `share_of` across the ports it serves in proportion to each port's
own `rate_per_second` where the port carries one, and evenly where it does not. A port that carries no demand
at all is a defect in the candidate and must fail by name, never be dropped quietly.

Keep the existing pairing cost and its tie-breaks. This lane does **not** change underground, splitter or
crossing policy, on the user's explicit decision that the router keeps its current behaviour: the change is
which endpoints get demands, never how a route between two endpoints is found.

Whatever survives after routing must still serve an obligation. Do not let per-port demands reintroduce
abandoned geometry that contract 26.2 rejects as `BP_V_TRANSPORT_UNUSED`.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_bindings_per_hand.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S per-port-demands-off >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_bindings_per_hand.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "bindings", "command": "sh tools/lane_rows.sh tests/test_bindings_per_hand.lua --min-cases 4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "handshake-holds", "command": "lua5.2 tests/test_transport_handshake.lua 2>&1 | tail -1 | grep -q '0 failed' && lua5.4 tests/test_transport_handshake.lua 2>&1 | tail -1 | grep -q '0 failed' && echo handshake-holds", "expect_exit": 0, "expect_regex": "handshake-holds", "timeout_s": 600}
{"name": "codes-live", "command": "lua5.2 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' && echo codes-live", "expect_exit": 0, "expect_regex": "codes-live", "timeout_s": 300}
{"name": "case-frozen", "command": "git diff --quiet round-15-anchor HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tests/test_census_codes_live.lua docs/round-15-census-baseline.json && echo case-frozen || { echo 'this lane changed the pinned sheet, the census tooling or the baseline'; exit 1; }", "expect_exit": 0, "expect_regex": "case-frozen", "timeout_s": 120}
{"name": "port-unreachable-gone", "command": "python3 tools/real_sheet_census.py --ops 5000000 --json /tmp/rrc131.json -q >/dev/null 2>&1 && python3 -c \"import json,sys; d=json.load(open('/tmp/rrc131.json')); n=d['census'].get('BP_V_PORT_UNREACHABLE',0); print('unreachable',n); sys.exit(1 if n else 0)\"", "expect_exit": 0, "expect_regex": "unreachable 0", "timeout_s": 900}
{"name": "census-fast", "command": "python3 tools/census_gate.py --baseline docs/round-15-census-baseline.json --tier fast --require-down BP_V_TRANSPORT_UNUSED,BP_V_TRANSFER_BROKEN --waiver docs/tasks/131.census-waiver.json --prove-waiver", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 900}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 131_bindings", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-15-anchor --manifest docs/tasks/131.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
