# 130 anchor: a hand and its port are the same tile

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-130`, branch `lane/130`, base tag `round-15-base` (resolve with `git rev-parse round-15-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 27, rules 27.1, 27.2, 27.3, 27.5.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`, 88 cases, both interpreters.
Frozen census baseline: `docs/round-15-census-baseline.json`.

The decisive line is `logic/bp/validate.lua:1381-1382`: for a transfer to be witnessed, a belt carrying the
right flow must sit **on the inserter's own outward tile**. Routing terminates a belt at a block **port**
(`logic/bp/route.lua:406-417`) and reads no inserter at all (`route.lua:3`). Port and hand are placed by
different code and never meet.

Measured on this host by driving `Groups.begin`/`Groups.step` on the player's sheet shape -- 4
assembling-machine-3 for science, 2 electric-furnace for copper, catalog offsets `pickup {0,1}`,
`drop {0,-1}` -- one block came out `w=24 h=5` with **18 inserters and 5 ports**, and **1** of those 18 had
its outward cell on the block edge.

Four causes, each its own edit site:

`logic/bp/groups.lua:490-500` selects `members_by_step[step_id][1]`, the FIRST machine of a step, and mints
one port per (step, flow). Every later machine of a multi-machine step therefore has no port of its own.

`logic/bp/groups.lua:359-360` aims an input inserter at `machine.x - iw`, the machine's LEFT face. Machines
stand side by side (`groups.lua:780`) and `machine_x0` (`groups.lua:745-756`) reserves one inserter width
before the first machine only, so every machine after the leftmost reaches into the block interior.

`logic/bp/groups.lua:1044-1048` raises `block.w` and `block.h` to at least `input_count + output_count`
AFTER the inserters are placed. Measured: `inserter_bottom` is 4, so `block.h` would be 4 and every output
drop cell at `y = 4` would already sit on the bottom edge; the inflation moves it to 5 and that tile becomes
interior ground.

`logic/bp/groups.lua:540-555` already snaps a port onto its inserter's outward cell, but only when that cell
is exactly on the one-tile edge ring, and otherwise falls back to the synthetic slots at `groups.lua:526-536`
and `:598-599`.

`logic/bp/pack.lua:199-200` filters a SOURCE-frame slot by PLACED dimensions. Measured by driving `Pack` on
a 24x4 block with one authored port: a bottom port at `(21,4)` is kept at `dir=N`, MOVED to `(0,-1)` at
`dir=E` and `dir=S`, and MOVED to `(-1,0)` at `dir=W`. The stale comment above that line claims the validator
applies its edge predicate to the placed envelope; `validate.lua:635-647` applies it to `block.w`/`block.h`,
and the placed-geometry branch at `:648-655` fires only when `port.x` is set, which `Groups.materialize` does
only at `dir == NORTH`.

`logic/bp/pack.lua:254-274` `scan_region` tries only the region's own corner, so when the block lands at
`(0,0)` an authored attach tile is off-area, `cell_is_free` fails, and a fallback edge slot wins.

`logic/bp/pack.lua:49-56` `copy_port` does not copy `inserter_id`, so pack cannot tell an anchored port from
a synthetic one even in principle.

`logic/bp/groups.lua:1336-1340` applies pack's slot override over the snap.

The refusal path already exists and needs no new plumbing: `groups.lua:459` sets
`block.failure = {name = "inserter-reach", code = "BP_P_NO_FIT", ...}`, `groups.lua:1213-1218` records a
failing grouping and keeps emitting the others, and `partition_specs` (`groups.lua:1103-1135`) enumerates
every partition of the steps including one block per step. `BP_P_NO_FIT` is registered at
`logic/bp/reason_codes.lua:29`.

Spine has already minted step-qualified port ids in `step_ports` (`groups.lua:1154`, `:1176`), which is the
shape `tests/test_blueprint_physical_contract.lua:130-136` already asserts. Extending them to one id per
inserter is this lane's work.

`tests/test_pack.lua` P3 (`:98`) and P13 (`:229`) `deep_equal` the whole errors table, so the `BP_P_NO_FIT`
error-record shape must stay byte-identical; extra diagnostics belong on `state.stats`.

`tests/test_port_edges.lua:62-71` `edge_legal` applies the edge predicate in the PLACED frame and `:96` PE1
asserts it for all four directions. That assertion encodes an invariant no validator path requires and is the
one existing assertion this round relaxes.

PRESERVE: `logic/bp/validate.lua`, `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/power.lua`,
`logic/bp/grid.lua`, `logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/serialize.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/test_census_codes_live.lua`, `tests/golden/cases/player-red-science-1s/`,
`docs/round-15-census-baseline.json`, `docs/feature-contracts.md`, `tools/**`, `info.json`,
`mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/groups.lua`, `logic/bp/pack.lua`, `tests/test_groups.lua`,
`tests/test_pack.lua`, `tests/test_inserter_geometry.lua`, `tests/test_port_edges.lua`,
`tests/test_placed_port_geometry.lua`, `tests/test_port_not_self_blocked.lua`,
`tests/test_transport_handshake.lua` (new).

## What to build

Write `tests/test_transport_handshake.lua` FIRST. Drive `Groups` on the player's sheet shape and assert, per
block: every port-bound inserter's outward cell lies on the block perimeter; exactly one port per port-bound
inserter, carrying that inserter's id; every port id distinct. It is red when written and stays red until the
layout work lands. Record its exact failure counts so each later commit's improvement is attributable.

Carry `pinned` on the copied port in `pack.lua:49-56`, set from `port.inserter_id`. Return only the port's
own slot from `port_slots` when pinned. Filter slots by `block.w`/`block.h` rather than the placed
dimensions. Let `scan_region` try an offset inside its region when a pinned option was rejected only for
freeness, so a pinned port becomes a different place for the BLOCK rather than an immediate refusal. Make
`groups.lua:1336-1340` refuse a slot override that is not identical to the port's own attach.

Mint one port per port-bound inserter in `block_ports`, carrying that inserter's `member_id` and `inserter_id`,
and stop selecting `members_by_step[step_id][1]`.

Place every port-bound item inserter so its outward cell is on the block perimeter, and anchor its port to
exactly that cell. An inserter whose counterpart is another member of the same block is machine-to-machine,
is exempt by rule 27.5, and keeps the existing placement search -- `append_inserters` already distinguishes
it at `groups.lua:437-441`, and `tests/test_inserter_geometry.lua` IG11 depends on that.

Delete the `port_count` inflation at `groups.lua:1044-1048`.

Refuse by name rather than fall back, both through the existing `BP_P_NO_FIT`: more port-bound item flows on
a machine than it has face columns, and a beacon layout that claims the face the inserters need
(`groups.lua:679` adds a bottom beacon row when `count_per_machine > 2` and `groups.lua:804-808` anchors it
below the inserter row). Keep the new refusals distinct from `inserter-reach` and run them after it, so
`tests/test_inserter_geometry.lua` IG9 keeps reporting the reach failure it names.

Fix the corridor margin at `pack.lua:301`: it is `#block.ports`, which grows with per-inserter ports and
would reserve a ring far wider than the grid can hold. Size it from the distinct flows the block actually
attaches.

Relax `tests/test_port_edges.lua` PE1 to the source frame, with the `validate.lua:635-647` citation in the
comment, and keep its four-direction loop.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_transport_handshake.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S port-anchor-off >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_transport_handshake.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "handshake", "command": "sh tools/lane_rows.sh tests/test_transport_handshake.lua --min-cases 6", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "no-synthetic-fallback", "command": "grep -q 'port_count' logic/bp/groups.lua && { echo 'the port_count envelope inflation survives'; exit 1; }; grep -q 'pinned' logic/bp/pack.lua || { echo 'pack still cannot tell an anchored port from a synthetic one'; exit 1; }; echo anchored", "expect_exit": 0, "expect_regex": "anchored", "timeout_s": 120}
{"name": "case-frozen", "command": "git diff --quiet round-15-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tests/test_census_codes_live.lua docs/round-15-census-baseline.json && echo case-frozen || { echo 'this lane changed the pinned sheet, the census tooling or the baseline'; exit 1; }", "expect_exit": 0, "expect_regex": "case-frozen", "timeout_s": 120}
{"name": "codes-live", "command": "lua5.2 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' && echo codes-live", "expect_exit": 0, "expect_regex": "codes-live", "timeout_s": 300}
{"name": "census-fast", "command": "python3 tools/census_gate.py --baseline docs/round-15-census-baseline.json --tier fast --require-down BP_V_TRANSFER_BROKEN,BP_V_INSERTER_GEOMETRY --waiver docs/tasks/130.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 600}
{"name": "census-full", "command": "python3 tools/census_gate.py --baseline docs/round-15-census-baseline.json --tier full --require-down BP_V_TRANSFER_BROKEN,BP_V_INSERTER_GEOMETRY,BP_V_TRANSPORT_UNUSED --waiver docs/tasks/130.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 1800}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 130_anchor", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-15-base --manifest docs/tasks/130.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 5400s
