# 132 witness: every machine is judged by its own port

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-132`, branch `lane/132`, base tag `round-15-base` (resolve with `git rev-parse round-15-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 27, rules 27.1, 27.4, 27.5.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`, 88 cases, both interpreters.
Frozen census baseline: `docs/round-15-census-baseline.json`.

`logic/bp/validate.lua:1296-1311` `machine_port_for` prefers a port whose `member_id` names the machine and
otherwise returns `fallback`, the first port of the step. So when a step runs several machines, machines two
and beyond are judged against the FIRST machine's port while `transfer_matches` (`validate.lua:1381-1382`)
demands a belt at that machine's OWN outward tile. Those two can never agree, and no geometry change can make
them agree. Lane 130 mints one port per inserter carrying its `member_id`; this lane removes the fallback
that hid the mismatch.

`logic/bp/validate.lua:681-685`, `:700` and `:1741-1742` carry `work.external_ids`, added in round 14. Its
whole job (`validate.lua:674-680`) was to recover the `perimeter` marker that the dedupe in `collect_ports`
(`validate.lua:317-330`) destroyed when a block port and a perimeter terminal shared an id byte for byte.
Spine has made those id spaces disjoint: `logic/bp/groups.lua` now mints `<step_id>:<role>:<flow_id>` and
`logic/bp/plan.lua:646` still mints `in:<full_name>` with no step. `is_external_port` (`validate.lua:595-597`)
classifies correctly on its own once ids no longer collide.

`tests/fixtures/validate/item_chain_first.lua` carries `port_id = "in:item/plate"` 21 times and
`tests/fixtures/routing/player_chain_first_candidate.lua` carries it 7 times. A hard duplicate-id rejection
in the validator would turn those frozen inputs red without regenerating them, so this lane adds no such
rejection.

The census counts what this file emits, so a code this lane stops emitting reads as an improvement.
`tests/test_census_codes_live.lua` builds a candidate that must provoke each counted code and is
PRESERVE-listed here precisely because this lane owns `tests/test_validate.lua` and could otherwise weaken
the test that guards it. Measured: renaming `BP_V_TRANSPORT_UNUSED` turns its CL3 case red.

A stricter validator finds MORE, not less, so this lane is gated with `--require-new` rather than
`--require-down`. A no-op change leaves the census byte-identical and fails that gate.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/pack.lua`, `logic/bp/route.lua`, `logic/bp/search.lua`,
`logic/bp/power.lua`, `logic/bp/grid.lua`, `logic/bp/geometry.lua`, `logic/bp/plan.lua`,
`logic/bp/serialize.lua`, `logic/catalog.lua`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/fixtures/validate/item_chain_first.lua`, `tests/fixtures/routing/player_chain_first_candidate.lua`,
`tests/golden/cases/player-red-science-1s/`, `docs/round-15-census-baseline.json`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/validate.lua`, `tests/test_validate.lua`, `tests/test_physical_witness.lua`,
`tests/test_validated_candidate.lua`.

## What to build

Delete the `fallback` in `machine_port_for`. A machine with no port of its own is a defect in the candidate
and must reject by name, never borrow another machine's port. Name the machine and the flow in the rejection.

Delete `work.external_ids` entirely: the build at `validate.lua:681-685`, the field at `:700`, and both reads
at `:1741-1742`. `is_external_port` alone must classify correctly, and a binding whose source or sink carries
the wrong role must still reject as `BP_V_PORT_EDGE_WRONG` naming the failing half.

Make each counted code mean one thing. `BP_V_TRANSFER_BROKEN` and `BP_V_ROUTE_DISCONTINUOUS` are chosen by
one shared ladder at `validate.lua:1564-1569` and `:1641-1646`; a reader cannot tell from the code whether
the belt is missing, the inserter is missing, or the whole candidate has no transport. Give each branch a
detail that names which of those it found, keeping the codes themselves unchanged so the census stays
comparable to its baseline.

Every negative case starts from an independently valid candidate that PASSES first. A base that rejects
everything proves nothing.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' || rc=1; sh tools/lane_mutate.sh $S census-code-unused >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_census_codes_live.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "no-borrowed-port", "command": "grep -q 'fallback = fallback or port' logic/bp/validate.lua && { echo 'a machine can still borrow the first machine port'; exit 1; }; grep -q 'external_ids' logic/bp/validate.lua && { echo 'the round 14 external_ids workaround survives'; exit 1; }; echo own-port", "expect_exit": 0, "expect_regex": "own-port", "timeout_s": 120}
{"name": "oracle-whole", "command": "lua5.2 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && lua5.4 tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' && echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "case-frozen", "command": "git diff --quiet round-15-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tests/test_census_codes_live.lua docs/round-15-census-baseline.json && echo case-frozen || { echo 'this lane changed the pinned sheet, the census tooling or the baseline'; exit 1; }", "expect_exit": 0, "expect_regex": "case-frozen", "timeout_s": 120}
{"name": "codes-live", "command": "lua5.2 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' && lua5.4 tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '0 failed' && echo codes-live", "expect_exit": 0, "expect_regex": "codes-live", "timeout_s": 300}
{"name": "census-sees-more", "command": "python3 tools/census_gate.py --baseline docs/round-15-census-baseline.json --tier fast --allow-total-rise --waiver docs/tasks/132.census-waiver.json", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 600}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 132_witness", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-15-base --manifest docs/tasks/132.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 5400s
