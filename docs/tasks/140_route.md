# 140 route: every laid run reaches its own sink, and a refused splitter is a refused route

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-140`, branch `lane/140`, base tag `round-16-base` (resolve with `git rev-parse round-16-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 28, rules **28.2**, **28.5**, **28.7**, **28.8**, **28.9**.
Frozen census baseline: `docs/round-16-census-baseline.json`. Ledger: `docs/round-16-baseline.md` sections 1
and 2. Frozen red list: `docs/round-16-red-list.txt`.

Round 15 closed the port anchor. Every hand owns its belt tile on a perimeter face of its own flow, and every
code saying *a hand cannot be served* is gone. Two codes remain on the player's real captured sheet, measured
on this host 2026-09-22 at 5,000,000 ops with 3 candidates reaching `validate`: **853**
`BP_V_TRANSPORT_UNUSED` and **63** `BP_V_ROUTE_DISCONTINUOUS`.

They are one fault counted twice. Unused hands per candidate are 21, 22, 20; discontinuous records per
candidate are 21, 22, 20; totals 63 and 63. `logic/bp/validate.lua:1443-1445` marks a belt served only along
a path `connection_path` returned, reachable only inside `if port then` at `:1556` and `:1635`, so one broken
run costs one discontinuous record plus every belt on it.

`sh tools/route_chain_probe.sh player-red-science-1s 5000000 lua5.2` prints the first candidate to reach
`validate` and walks it with the validator's own successor rule, `logic/bp/validate.lua:478-512`:

```
CHAIN candidate entities=437 belts=382 inserters=26 machines=11 ports=29
CHAIN splitters=2 undergrounds=44
CHAIN bindings=22 whole=13 broken=9
CHAIN reason nothing ahead                                  7
CHAIN reason walk closed with no dead end and no target     2
```

Seven of nine runs stop **short of their sink**, 4 to 24 tiles away, with empty ground ahead of their last
belt:

```
in:item/iron-ore -> iron-plate:...:3:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=4
in:item/iron-ore -> iron-plate:...:2:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=8
in:item/iron-ore -> iron-plate:...:1:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=12
iron-gear-wheel:out -> science:...:2:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=10
iron-gear-wheel:out -> science:...:1:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=12
copper-plate:...:2:output:1 -> science:...:2   stopped_at=(20,3)  facing=W ahead=(19,3)  empty distance=10
iron-gear-wheel:out -> science:...:3:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=24
```

Every one of those sources feeds several sinks: four science machines take gear from one gear machine, three
iron-plate machines take ore from one supply. `logic/bp/route.lua:1083` and `logic/bp/route.lua:1116` append
one binding per sink carrying `segment_id = first_segment.segment_id`, and `add_allocation` puts that sink's
rate on the shared trunk. **The trunk is laid once and the branch from trunk to each further sink's own port
tile is never laid.** The binding is recorded anyway, so routing reports success on a run ending in mid-air.
The remaining two breaks are the science output runs, where the walk closes with no dead end and no target,
which is a cycle over a shared run reused past the point it still leads anywhere.

Splitter conversion is NOT the cause. That hypothesis was written into the plan and refuted at spine before
this lane was cut: the whole candidate carries **2** splitters and not one break tile is a splitter.

`logic/bp/route.lua:1042-1058` carries a separate, real defect. It has no `else`: when
`splitter_branch_allowed` refuses, the block falls through with no `return reject(...)` and the
direction-mismatched crossing is committed. Measured at HEAD on `shared_splitter_input`, an east belt at
`(5,3)` feeds a north belt at `(5,2)` with no splitter and no junction, which Factorio cannot build.
`logic/bp/route.lua:1149-1153` admits any direction mismatch merely because `work.belt.splitter` exists,
never asking whether the splitter's second tile is free, and that asymmetry is what lets the fall-through
happen. `splitter_can_absorb` at `logic/bp/route.lua:812-814` reads like the guard meant to sit at 1042 and
has **no callers**.

`tests/test_route_footprints.lua` is 6 failing and `tests/test_route_budget.lua` is 2 failing at the base
tag, per interpreter, and both are in the frozen red list. Lane 131 caused them with the nine-line demand
sort at `logic/bp/route.lua:748-757`. **Removing that sort is refused, and the refusal is measured**: with the
sort 853 and 63 over 3 candidates, without it **949** and **67** over 3 candidates, so removal makes the
product worse. The sort stays. Rule 28.9 says what replaces it: once 28.5, 28.7 and 28.8 hold, the outcome
must not depend on which demand routes first.

What this candidate builds, against a factory the player built for this same sheet that the game runs
(`tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt`):

| metric | this candidate | player's factory |
|---|---:|---:|
| entities | 437 | 131 |
| transport belts | 382 | 84 |
| underground endpoints | 44 | **0** |
| splitters | 2 | **0** |
| inserters | 26 | 22 |
| machines | 11 | 11 |

The player's decision for this round is that delivery must match their factory closely, so belt count is a
gate rather than a note.

Two checks already model both-lanes capacity correctly and must NOT change: `segment_capacity` at
`logic/bp/validate.lua:752` returns `catalog.belt.items_per_second`, the whole belt; and the mixing rule at
`logic/bp/validate.lua:980-983` fires only for `kind == "pipe"`. The segment kind `"lane"` declared at
`logic/bp/route.lua:7` is a dead enum nothing writes.

`multi_flow_hands` at `logic/bp/route.lua:617` is `false` and **stays false in this lane**. Lanes 141 and 142
build the other two halves of 28.1 behind the same switch, and integration flips all three together.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/validate.lua`, `logic/bp/search.lua`, `logic/bp/pack.lua`,
`logic/bp/grid.lua`, `logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/power.lua`,
`logic/bp/serialize.lua`, `logic/catalog.lua`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/golden/cases/player-red-science-1s/`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

Files this lane owns: `logic/bp/route.lua`, `tests/test_route_chain.lua` (new), `tests/test_route.lua`,
`tests/test_route_network.lua`, `tests/test_route_footprints.lua`, `tests/test_route_budget.lua`,
`tests/test_route_layout_contract.lua`, `tests/test_underground_pairs.lua`, `tests/test_port_tile_flow.lua`,
`tests/test_port_not_self_blocked.lua`, `tests/test_demand_terminals.lua`, `tests/test_bindings_per_hand.lua`.

## What to build

**S1. `tests/test_route_chain.lua`, the characterisation test.** For every binding the router records, walk a
directed same-flow chain from its source tile to its **own sink tile**, using the same successor rule as
`logic/bp/validate.lua:503-507`: a belt's only successor is the tile it faces, plus a splitter's side tile and
an underground endpoint's partner. Assert every binding's chain completes. Assert the belt count of the
candidate. Record the failing counts before changing any behaviour. This test is red until S3 and that is its
purpose: it is the only artefact proving the fault before it closes, and it puts the validator's own rule
inside the router's own tests where the router can be held to it.

**S2. Rule 28.5.** Give `logic/bp/route.lua:1042-1058` its missing `else return reject("splitter-footprint")`
so a refused footprint refuses the route by name instead of committing a mismatched crossing. Make
`logic/bp/route.lua:1149-1153` ask the same question the materializer asks, so the search never admits a
mismatch the materializer would refuse. Wire `splitter_can_absorb` in at 1042 or delete it; do not leave it
dead. Add a case that asks the underground guard at `logic/bp/route.lua:832` and `:834` **directly**: today
`tests/test_route_footprints.lua` RF2 reaches that guard only by routing accident, so an order change stops
it testing anything.

**S3. Rules 28.7 and 28.8, one job.** A binding may not record a sink it laid no belt to. Two demands of one
flow whose runs overlap share one trunk, and sharing the trunk does not discharge the branch: each sink still
gets its own belt from the trunk to its own port tile. When no such branch can be laid, refuse the demand by
name rather than recording the binding. Sharing the trunk is what removes most of the belt, and the 382 belts
against the player's 84 is the same fault seen from the other side.

`tests/test_route_footprints.lua` and `tests/test_route_budget.lua` must reach 6 of 6 and 8 of 8 **with the
demand sort in place**. Do not delete `logic/bp/route.lua:748-757`; that trade was measured and refused, and
the numbers are in the comment above those lines.

Two identifiers are **mandated**, because `tools/lane_mutate.sh` binds its red proofs to them and a mutation
that binds to nothing proves nothing: a module-level `local share_trunk = true` guarding trunk reuse, and a
`chain_reaches_sink` predicate that a binding must satisfy before it is recorded. The mutations
`trunk-sharing-off` and `binding-without-run` set them to `false` and `true` respectively.

**S4. Rule 28.2, behind `multi_flow_hands`, which stays `false`.** A segment carries a set of flows with
per-flow allocations. `logic/bp/route.lua:768` admits a second **item** flow when the summed rate fits
`catalog.belt.items_per_second` and the set stays at **two**; a third flow refuses by name.
`logic/bp/route.lua:1122-1128` passes a reserved tile for any flow in that port's set.
`logic/bp/route.lua:780-790` lets one hand's ports co-own one approach tile. Pipes are unchanged and
`fluid_mix` still refuses. Prove this half with the switch forced on inside this lane's own tests only.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_route_chain.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S splitter-footprint-silent >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_route_footprints.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "chain-cases", "command": "sh tools/lane_rows.sh tests/test_route_chain.lua --min-cases 4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "splitter-files-whole", "command": "for l in lua5.2 lua5.4; do $l tests/test_route_footprints.lua 2>&1 | tail -1 | grep -q '6 passed, 0 failed' || exit 1; $l tests/test_route_budget.lua 2>&1 | tail -1 | grep -q '8 passed, 0 failed' || exit 1; done; echo splitter-files-whole", "expect_exit": 0, "expect_regex": "splitter-files-whole", "timeout_s": 900}
{"name": "sort-kept", "command": "grep -q '_build_order' logic/bp/route.lua && echo sort-kept || { echo 'the demand sort was deleted; removing it makes the census WORSE, 853 to 949 and 63 to 67, measured both ways 2026-09-22'; exit 1; }", "expect_exit": 0, "expect_regex": "sort-kept", "timeout_s": 120}
{"name": "runs-reach-sinks", "command": "sh tools/route_chain_probe.sh player-red-science-1s 5000000 lua5.2 > /tmp/rrc140.chain 2>&1; cat /tmp/rrc140.chain; python3 -c \"import re,sys; t=open('/tmp/rrc140.chain').read(); m=re.search(r'bindings=(\\d+) whole=(\\d+) broken=(\\d+)',t); sys.exit(1) if not m else None; b,w,k=map(int,m.groups()); print('bindings',b,'whole',w,'broken',k); sys.exit(0 if (k==0 and w==b and b>=22) else 1)\" && echo runs-reach-sinks", "expect_exit": 0, "expect_regex": "runs-reach-sinks", "timeout_s": 1800}
{"name": "belt-budget", "command": "python3 -c \"import re,sys; t=open('/tmp/rrc140.chain').read(); m=re.search(r'belts=(\\\\d+)',t); n=int(m.group(1)) if m else 10**6; print('belts',n); sys.exit(0 if n<=126 else 1)\"", "expect_exit": 0, "expect_regex": "belts", "timeout_s": 300}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "codes-live", "command": "lua5.2 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' && echo codes-live-ok", "expect_exit": 0, "expect_regex": "codes-live-ok", "timeout_s": 600}
{"name": "frozen", "command": "git diff --quiet round-16-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tools/red_list.sh tools/route_chain_probe.sh tools/route_chain_report.py tests/test_census_codes_live.lua docs/round-16-census-baseline.json docs/round-16-red-list.txt docs/feature-contracts.md && echo frozen || { echo 'this lane changed the pinned sheet, the census tooling, the red list or the contract'; exit 1; }", "expect_exit": 0, "expect_regex": "frozen", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "census-fast", "command": "python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier fast --require-down BP_V_TRANSPORT_UNUSED,BP_V_ROUTE_DISCONTINUOUS --waiver docs/tasks/140.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 1800}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 140_route", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-base --manifest docs/tasks/140.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
