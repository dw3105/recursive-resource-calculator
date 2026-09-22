# 142 economy: one hand, two ingredients, one belt, both lanes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-142`, branch `lane/142`, base tag `round-16-base` (resolve with `git rev-parse round-16-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 28, rules **28.1** and **28.3**, and section 27 rules 27.1,
27.2, 27.3, 27.5, 27.6 which stay in force.
Frozen census baseline: `docs/round-16-census-baseline.json`. Ledger: `docs/round-16-baseline.md` section 2.
Frozen red list: `docs/round-16-red-list.txt`.

The player's own factory for this exact sheet runs **22** inserters over **11** machines: two hands per
machine, every one of them. Ours plans **26**. Their science machine takes `item/copper-plate` and
`item/iron-gear-wheel` through **ONE** hand from **ONE** belt, using both lanes of that belt. Decoded from
their blueprint bytes: 8 inserters on the 4 science machines, feeding at `(210.5, 1076.5 / 1079.5 / 1082.5 /
1085.5)` and draining at `(206.5, …)`.

That economy is load-bearing rather than cosmetic. The end of contract section 27 named it as a later round's
work; the player's decision for this round is that delivery must match their factory closely, so it is this
round's work. Measured candidate on this host 2026-09-22: 437 entities, 382 belts, 44 underground endpoints,
2 splitters, **26** inserters, 11 machines, against their 131, 84, 0, 0, **22**, 11.

`append_inserters` at `logic/bp/groups.lua:497-556` makes one hand per **port**: `:500-502` collects non-fluid
`step.inputs`, `:503-505` the same for `step.outputs`, `:508` iterates one hand per entry and `:533-552`
appends exactly one record for each. The record carries a **scalar** `flow_id` at `logic/bp/groups.lua:539`,
and downstream reads it as a scalar: `block_ports` matches `inserter.flow_id == flow_id` at
`logic/bp/groups.lua:586-591` and again at `:629-630`, the port cell comes from that hand's `pickup_position`
at `:666-667`, the port id is suffixed with the hand id at `:722`, and `pickup_target` and `drop_target` fall
back to `"port:" .. flow_id` at `:545-550`.

**Three face guards actively refuse the sharing shape**, which is correct under 27.6 and must become correct
under 28.1 instead: `logic/bp/groups.lua:1108-1112` fails the block with `BP_P_NO_FIT` "two port-bound item
flows claim one machine face", `:1085-1088` with "bottom machine face is claimed by two flows", and the
two-face strip variant fails at `:990-992`.

Two checks elsewhere already model both-lanes capacity correctly, so this lane needs neither: `segment_capacity`
at `logic/bp/validate.lua:752` returns `catalog.belt.items_per_second`, the whole belt, both lanes; and the
mixing rule at `logic/bp/validate.lua:980-983` fires only for `kind == "pipe"`, so items are exempt. The
segment kind `"lane"` at `logic/bp/route.lua:7` is a dead enum nothing writes: two flows on one belt is a
multi-flow segment under whole-belt capacity, never a geometric lane.

`multi_flow_hands` at `logic/bp/groups.lua:502` is `false`. **This lane's whole behaviour sits behind it and
it stays `false` at the tip of this branch.** Lane 140 gives the belt its flow set and lane 141 witnesses a
hand per flow behind the same switch; integration flips all three together. So the census cannot move for
this lane, and this lane is **not** gated on any code falling. It is gated on
`tests/test_hand_economy.lua` going green with the switch forced on, on the frozen red list, and on the
oracle.

The rate a shared hand moves is the **sum** of its flows' shares, and each flow keeps its own share. Round 15
established that a step's hands' rates sum to that step's demand; pairing two flows onto one hand must not
break that, and must not make one flow claim the pair's whole rate.

The frozen oracle `tests/test_blueprint_physical_contract.lua` builds candidates with explicit coordinates
and carries no `attach_dx`, so it judges `logic/bp/validate.lua` and this lane cannot reach it. Keep it whole
anyway: 88 of 88 on both interpreters.

PRESERVE: `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/search.lua`, `logic/bp/grid.lua`,
`logic/bp/geometry.lua`, `logic/bp/plan.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua`,
`logic/catalog.lua`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/test_census_codes_live.lua`, `tests/golden/cases/player-red-science-1s/`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `tools/**`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/groups.lua`, `tests/test_hand_economy.lua` (new), `tests/test_groups.lua`,
`tests/test_pack.lua`, `tests/test_inserter_geometry.lua`, `tests/test_port_edges.lua`,
`tests/test_transport_handshake.lua`.

## What to build

**S1. `tests/test_hand_economy.lua`, the characterisation test.** Drive `Groups` on the player's real sheet
shape with `multi_flow_hands` forced on, and assert: **11** machines, **22** port-bound hands, and that each
science machine's single input hand declares both `item/copper-plate` and `item/iron-gear-wheel` with a share
each. Assert every hand's outward cell is still on the block perimeter, so 27.2 and 27.3 keep holding. Red
until S3, and that is its purpose: it is the only artefact proving the gap before it closes. Record the
counts it reports before changing behaviour.

Also assert the switch's default: with `multi_flow_hands` off, the same sheet still plans 26 hands and every
existing assertion holds. A lane whose new behaviour leaks into the default breaks every other lane's base.

**S2. Plural flows on a hand.** `logic/bp/groups.lua:539` carries a flow **set** plus a per-flow share
instead of a scalar. `:586-591` and `:629-630` select a port by set membership. `:545-550` stop falling back
to `"port:" .. flow_id` for a shared hand. `:722` keeps the port id unique per hand, which it already does.
One hand still publishes exactly **one** port on **one** outward cell, and that port advertises the hand's
whole set: that is rule 28.3, and two ports must never claim one tile.

**S3. The pairing rule and the face guards.** `logic/bp/groups.lua:508` pairs two input item flows onto one
hand when rule 28.1 allows it: both arrive on the same belt tile and their summed rate fits
`catalog.belt.items_per_second`. At most two flows per hand, because a belt has two lanes; a third refuses.
Fluids never pair. The three guards at `:990-992`, `:1085-1088` and `:1108-1112` exempt a face whose flows
all belong to **one** hand, and keep refusing a face that mixes flows of different hands, which is what 27.6
forbids and what `logic/bp/route.lua`'s reserved-tile rule cannot cross.

When a step's flows cannot be paired into the faces its machine has, refuse by name with the
already-registered `BP_P_NO_FIT` and let `logic/bp/groups.lua:1213-1218` hand the search another partition.
Never silently put two flows of two different hands back on one face.

This lane changes layout only. It lays no belt and witnesses no transfer.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_hand_economy.lua >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S shared-hand-off >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_hand_economy.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "economy-cases", "command": "sh tools/lane_rows.sh tests/test_hand_economy.lua --min-cases 5", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "twenty-two-hands", "command": "for l in lua5.2 lua5.4; do $l tests/test_hand_economy.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; done; echo twenty-two-hands", "expect_exit": 0, "expect_regex": "twenty-two-hands", "timeout_s": 900}
{"name": "switch-off-by-default", "command": "grep -q '^local multi_flow_hands = false' logic/bp/groups.lua && echo switch-off || { echo 'the switch is on at the tip of this branch; lanes 140 and 141 build the other halves behind it and integration flips all three together'; exit 1; }", "expect_exit": 0, "expect_regex": "switch-off", "timeout_s": 120}
{"name": "handshake", "command": "sh tools/lane_rows.sh tests/test_transport_handshake.lua --min-cases 8", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "codes-live", "command": "for l in lua5.2 lua5.4; do $l tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '7 passed, 0 failed' || exit 1; done; echo codes-live-ok", "expect_exit": 0, "expect_regex": "codes-live-ok", "timeout_s": 900}
{"name": "frozen", "command": "git diff --quiet round-16-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tools/red_list.sh tools/route_chain_probe.sh tools/route_chain_report.py tests/test_census_codes_live.lua docs/round-16-census-baseline.json docs/round-16-red-list.txt docs/feature-contracts.md && echo frozen || { echo 'this lane changed the pinned sheet, the census tooling, the red list or the contract'; exit 1; }", "expect_exit": 0, "expect_regex": "frozen", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "census-no-rise", "command": "python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier fast --waiver docs/tasks/142.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 1800}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 142_economy", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-base --manifest docs/tasks/142.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
