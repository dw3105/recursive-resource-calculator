# 141 witness: say WHICH belt is orphaned and WHICH sink is short, and witness a hand per flow

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-141`, branch `lane/141`, base tag `round-16-base` (resolve with `git rev-parse round-16-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 28, rules **28.4** and **28.6**.
Frozen census baseline: `docs/round-16-census-baseline.json`. Ledger: `docs/round-16-baseline.md` sections 2
and 4. Frozen red list: `docs/round-16-red-list.txt`.

**The validator's walk is correct and this lane does not repair it.** Measured on this host 2026-09-22, all
63 `BP_V_ROUTE_DISCONTINUOUS` records on the player's real sheet carry `cause = "disconnected_route"` and
**none** carries `missing_port_machine`, so `machine_port_for` finds its port and the break is in the belt
geometry. The early `nil` at `logic/bp/validate.lua:1355` was suspected at spine and **refuted** by that
measurement. Do not change it on the strength of the old suspicion.

The geometry fault belongs to lane 140: measured, 9 of 22 bindings on the real sheet record a sink they laid
no belt to, 7 of them stopping 4 to 24 tiles short with empty ground ahead. This lane's jobs are the two
things the validator gets wrong on its own account, plus its half of contract 28.1.

**The waste record carries no geometry.** `logic/bp/validate.lua:1691-1692` emits
`{reason = "inserter serves no required transfer"}` with one entity id, and `:1697-1698` emits
`{reason = "transport entity serves no required transfer"}` with one entity id. Nothing else. Verbatim, from a
live run:

```
{"code":"BP_V_TRANSPORT_UNUSED","detail":{"reason":"transport entity serves no required transfer"},"ids":["r:100"],"attempt":1,"stage":"validate"}
```

853 records over 3 candidates, 790 of them the transport line and 63 the inserter line, and no tile, no flow
and no facing in any of them. So the census can count the waste and can never locate it, and locating it took
a new tool at spine (`tools/route_chain_probe.sh`) that re-runs the whole generator. `BP_V_TRANSPORT_UNUSED`
also counts per **entity** where every other live code counts per **obligation**, which is why it dominates
the census by about 13x without carrying 13x the information.

**`BP_V_TARGET_SHORTFALL` counts 3, one per candidate.** `logic/bp/validate.lua:996-999` fires when a
consumer's required share is not reached at its sink, where `reached` comes from
`allocation_by_flow_sink`, built from segment allocations. 3 is far under the census sensitivity floor of 50,
so the rate gate cannot judge it and only a direct test can. `tests/test_census_codes_live.lua` CL5a and CL5b
were added at spine and proved red-capable: renaming the code takes that file from 7 of 7 to 6 of 7.

**One hand is witnessed once, and that is what blocks contract 28.1.** Three lines forbid a hand serving two
flows, independently: `logic/bp/validate.lua:1368` consumes a hand with `used[info.id]` so a hand spent on
flow A is invisible to flow B for the rest of validation; `:1372` compares a single `entity.flow_id` against
a single wanted flow; and `transport_at` at `:471` demands the belt carry the wanted flow.

Two checks already model both-lanes capacity correctly and must **NOT** change: `segment_capacity` at
`logic/bp/validate.lua:752` returns `catalog.belt.items_per_second`, the whole belt, both lanes, so two item
flows under that sum already pass `:978-979`; and the mixing rule at `:980-983` fires only for
`kind == "pipe"`, so items are exempt and there is no `BP_V_ITEM_MIXING` in `logic/bp/reason_codes.lua`. The
`kind == "lane"` branch at `:751` is a dead enum nothing writes.

`multi_flow_hands` at `logic/bp/validate.lua:403` is `false` and **stays false in this lane**. Lanes 140 and
142 build the other two halves of 28.1 behind the same switch, and integration flips all three together.

The frozen oracle `tests/test_blueprint_physical_contract.lua` judges `logic/bp/validate.lua` and nothing
else, 88 cases on both interpreters. This lane can reach it and must keep it whole.

PRESERVE: `logic/bp/route.lua`, `logic/bp/groups.lua`, `logic/bp/search.lua`, `logic/bp/pack.lua`,
`logic/bp/grid.lua`, `logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/power.lua`,
`logic/bp/serialize.lua`, `logic/catalog.lua`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/golden/cases/player-red-science-1s/`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

Files this lane owns: `logic/bp/validate.lua`, `tests/test_validate.lua`, `tests/test_physical_witness.lua`,
`tests/test_validated_candidate.lua`, `tests/test_external_ports.lua`, `tests/test_placed_port_geometry.lua`.

## What to build

**S1. Give `BP_V_TRANSPORT_UNUSED` geometry.** Every record names its tile, its flow id and its facing
direction, for both the inserter line at `logic/bp/validate.lua:1691-1692` and the transport line at
`:1697-1698`. For an inserter, the tile is its outward cell — pickup for an input hand, drop for an output
hand — because that is the cell a fix has to reach. Add a case to `tests/test_validate.lua` asserting those
fields are present and correct on a candidate with one deliberately orphaned belt.

The detail keys are **mandated**: `x`, `y`, `flow_id` and `facing`. `tools/lane_mutate.sh`'s
`unused-detail-bare` binds its red proof to `facing`, and a mutation that binds to nothing proves nothing.

**S2. Make `BP_V_TARGET_SHORTFALL` say which sink is short by how much.** The record at
`logic/bp/validate.lua:999` already carries `required`, `reached` and `sink` in its detail; assert that it
does, on the real sheet's shape, and add the consumer step id where it is missing. **Taking the count to zero
is not this lane's job**: the measured cause is a binding with no belt behind it, which is lane 140's. This
lane makes the record trustworthy and proves it still fires for the right reason. Do not weaken the check to
lower the count.

**S3. Rule 28.4, behind `multi_flow_hands`, which stays `false`.** `used` becomes per `(hand, flow)` at
`logic/bp/validate.lua:1368`, `:1572` and `:1649`, so a hand spent proving flow A stays available for flow B.
The flow comparison at `:1372` becomes set membership over the hand's declared flow set. `transport_at` at
`:471` accepts a belt whose flow set contains the wanted flow. **No capacity change and no mixing change**:
`segment_capacity` and the pipe-only mixing rule are already right. Prove this half with the switch forced on
inside this lane's own tests only.

A hand with no declared flow must keep failing closed, not open. `logic/bp/validate.lua:1372` admits any flow
when `actual` is `nil`, which is a nullable marker rather than an empty set; under 28.4 an empty or absent
flow set is **not** a wildcard.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_validate.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S unused-detail-bare >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_validate.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "red-proof-shortfall", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_mutate.sh $S census-code-shortfall >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_census_codes_live.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-shortfall-ok", "expect_exit": 0, "expect_regex": "red-proof-shortfall-ok", "timeout_s": 1800}
{"name": "waste-located", "command": "python3 -c \"import json,subprocess,sys,pathlib; p=json.loads(pathlib.Path('tests/golden/cases/player-red-science-1s/prepared_input.json').read_text()); p['search_budget']=5000000; r=subprocess.run(['lua5.2','tests/golden/generate.lua','--input','/dev/stdin','--output','/dev/stdout'],input=json.dumps(p),capture_output=True,text=True); d=json.loads(r.stdout); recs=[x for e in (d.get('errors') or []) for x in (e.get('reason_details') or []) if x.get('code')=='BP_V_TRANSPORT_UNUSED']; print('unused records',len(recs)); bad=[x for x in recs if not all(k in (x.get('detail') or {}) for k in ('x','y','flow_id','facing'))]; print('records missing geometry',len(bad)); sys.exit(0 if recs and not bad else 1)\"", "expect_exit": 0, "expect_regex": "records missing geometry 0", "timeout_s": 1800}
{"name": "validate-cases", "command": "sh tools/lane_rows.sh tests/test_validate.lua --min-cases 43", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "witness-cases", "command": "sh tools/lane_rows.sh tests/test_physical_witness.lua --min-cases 8", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "codes-live", "command": "for l in lua5.2 lua5.4; do $l tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '7 passed, 0 failed' || exit 1; done; echo codes-live-ok", "expect_exit": 0, "expect_regex": "codes-live-ok", "timeout_s": 900}
{"name": "capacity-untouched", "command": "git diff round-16-base HEAD -- logic/bp/validate.lua | grep -E '^[-+].*(items_per_second|BP_V_FLUID_MIXING)' && { echo 'this lane changed whole-belt capacity or the pipe-only mixing rule; both are already correct, contract 28.2'; exit 1; }; echo capacity-untouched", "expect_exit": 0, "expect_regex": "capacity-untouched", "timeout_s": 120}
{"name": "frozen", "command": "git diff --quiet round-16-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tools/red_list.sh tools/route_chain_probe.sh tools/route_chain_report.py tests/test_census_codes_live.lua docs/round-16-census-baseline.json docs/round-16-red-list.txt docs/feature-contracts.md && echo frozen || { echo 'this lane changed the pinned sheet, the census tooling, the red list or the contract'; exit 1; }", "expect_exit": 0, "expect_regex": "frozen", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "census-no-rise", "command": "python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier fast --waiver docs/tasks/141.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 1800}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 141_witness", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-base --manifest docs/tasks/141.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
