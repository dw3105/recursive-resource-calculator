#!/bin/sh
#The lane verifier. One lane's checks, chosen by its exact tag.
#
#Why this exists: lane_gate reads verify.<tag> before verify.default, but lane_config refuses any [verify] key
#outside {default, scaffold, ci_collect, perf, reference_dir}, so a per-tag key makes the whole configuration
#unloadable. The split therefore lives here, reached through the supported default key.
#
#Round 9: two consumer lanes cannot run the whole suite on their own base, because
#tests/test_blueprint_pipeline.lua drives a real calculation through Generation.start and demands success, and it
#succeeds today only because recipe and receiver facts are absent. Their producer is lane 085.
#
#Round 10: a lane never runs the whole suite. Full suites and the full golden matrix belong to integration, so a
#sibling's unmerged work is never charged to this lane. Lane 093 is a Python lane, so it needs a Python dispatch:
#the Lua loop below would hand a .py file to lua5.2. And spine must gate this file before any lane has written
#its new test, so --dispatch-only resolves a tag and prints its selection without executing anything.
set -eu

dispatch_only=0
if [ "${1:-}" = "--dispatch-only" ]; then
    dispatch_only=1
    shift
fi

#--dispatch-only is parsed in the FIRST position only. Written last it was silently ignored and the command
#EXECUTED, so a review could read a dry-run command and get a real run: round 13's plan carried exactly that
#mistake. An option anywhere else, or any extra argument, is refused instead of being dropped.
if [ "$#" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "usage: verify_round9_lane.sh [--dispatch-only] <worktree> <tag>" >&2
    exit 2
fi
case "$2" in
    -*)
        echo "verify_round9_lane.sh: a tag may not start with '-': $2" >&2
        echo "usage: verify_round9_lane.sh [--dispatch-only] <worktree> <tag>" >&2
        exit 2
        ;;
esac
worktree=$1
tag=$2

if [ ! -d "$worktree" ]; then
    echo "verify_round9_lane.sh: no such worktree: $worktree" >&2
    exit 2
fi
cd "$worktree"

#runner is "lua" for a Lua set under both interpreters, or "python" for a unittest module. There is no third
#kind: the whole suite belongs to integration, which runs `sh tests/run.sh` itself, so a lane can never charge
#a sibling's unmerged failure to its own gate.
runner=lua
tests=
case "$tag" in
    086_preflight_facts)
        tests="tests/test_preflight_quality_facts.lua tests/test_quality_policy.lua tests/test_bp_preflight.lua"
        ;;
    087_planner_facts)
        tests="tests/test_plan_quality_facts.lua tests/test_quality_policy.lua tests/test_bp_plan.lua"
        ;;
    091_export_payload)
        tests="tests/test_export_completeness.lua tests/test_export_payload.lua"
        ;;
    092_attempt_lookup)
        tests="tests/test_generation_attempt_lookup.lua tests/test_generation_reload.lua tests/test_generation_record_handoff.lua"
        ;;
    093_diagnostic_handoff)
        runner=python
        tests="tests.tools.test_handoff"
        ;;
    #Round 11. One lane, one file. A lane gate tests isolated component behaviour only: every cross-component
    #check belongs to integration, where both its producers have landed.
    094_beacon_geometry)
        tests="tests/test_groups.lua tests/test_beacon_coverage.lua"
        ;;
    095_validator_symmetry)
        tests="tests/test_validate.lua tests/test_power_semantics.lua tests/test_validated_candidate.lua"
        ;;
    096_roboport_facts)
        tests="tests/test_catalog.lua tests/test_export_payload.lua tests/test_export_completeness.lua"
        ;;
    #tests/test_search_allowance.lua does not exist yet: docs/tasks/084_search_allowance.md mandates it and this
    #lane writes it. --dispatch-only resolves the selection without demanding the file, which is why spine can
    #gate this dispatcher before the lane starts.
    097_search_truth)
        tests="tests/test_search.lua tests/test_search_budget.lua tests/test_search_allowance.lua tests/test_generation_reload.lua tests/test_generation_attempt_lookup.lua tests/test_blueprint_pipeline.lua tests/test_external_ports.lua tests/test_locale_keys.lua"
        ;;
    098_golden_truth)
        runner=python
        tests="tests.tools.test_capture_workflow"
        ;;
    099_release_lifecycle)
        runner=python
        tests="tests.tools.test_handoff"
        ;;
    #Round 13. Six lanes, each bounded to the files it owns. Before these entries existed every one of these
    #tags fell through the old `*)` arm to the whole suite, so each lane's "focused" gate would have inherited
    #its siblings' failures and the deliberately red spine oracle.
    110_producer)
        tests="tests/test_groups.lua tests/test_serialize.lua tests/test_beacon_coverage.lua tests/test_beacons.lua"
        ;;
    111_validator)
        tests="tests/test_validate.lua tests/test_validated_candidate.lua tests/test_blueprint_delivery.lua"
        ;;
    112_capture)
        tests="tests/test_catalog.lua tests/test_catalog_recipe_facts.lua tests/test_export_payload.lua tests/test_export_completeness.lua"
        ;;
    113_layout)
        tests="tests/test_route.lua tests/test_route_footprints.lua tests/test_route_layout_contract.lua tests/test_pack.lua tests/test_search.lua tests/test_search_budget.lua tests/test_search_allowance.lua"
        ;;
    114_harness)
        tests="tests/test_engine_scenario.lua tests/test_engine_runtime_adapter.lua tests/test_engine_test_api.lua"
        ;;
    115_goldens)
        runner=python
        tests="tests.tools.test_golden_tools tests.tools.test_incident_capture"
        ;;
    #Round 14. Five lanes, one file set each, no file shared between two lanes. Each lane also names the new
    #test file it must write; --dispatch-only resolves a selection without demanding the file exists, which is
    #how spine gates this dispatcher before any lane has written anything.
    120_gate)
        tests="tests/test_validate.lua tests/test_validated_candidate.lua tests/test_power_semantics.lua tests/test_blueprint_delivery.lua tests/test_physical_witness.lua"
        ;;
    121_hands)
        tests="tests/test_groups.lua tests/test_serialize.lua tests/test_beacon_coverage.lua tests/test_beacons.lua tests/test_inserter_geometry.lua"
        ;;
    122_router)
        tests="tests/test_route.lua tests/test_route_budget.lua tests/test_route_footprints.lua tests/test_route_layout_contract.lua tests/test_underground_pairs.lua tests/test_route_network.lua"
        ;;
    123_layout)
        tests="tests/test_search.lua tests/test_search_budget.lua tests/test_search_allowance.lua tests/test_external_ports.lua tests/test_port_tile_flow.lua tests/test_demand_terminals.lua"
        ;;
    124_goldens)
        runner=python
        tests="tests.tools.test_golden_tools tests.tools.test_incident_capture tests.tools.test_blueprint_audit tests.tools.test_capture_workflow"
        ;;
    #Round 15. The port anchor: a hand and its port are the same tile (contract section 27).
    130_anchor)
        tests="tests/test_groups.lua tests/test_pack.lua tests/test_inserter_geometry.lua tests/test_port_edges.lua tests/test_placed_port_geometry.lua tests/test_port_not_self_blocked.lua tests/test_transport_handshake.lua"
        ;;
    131_bindings)
        tests="tests/test_route.lua tests/test_route_network.lua tests/test_route_layout_contract.lua tests/test_demand_terminals.lua tests/test_port_tile_flow.lua tests/test_bindings_per_hand.lua"
        ;;
    134_faces)
        tests="tests/test_groups.lua tests/test_pack.lua tests/test_inserter_geometry.lua tests/test_port_edges.lua tests/test_placed_port_geometry.lua tests/test_transport_handshake.lua"
        ;;
    132_witness)
        tests="tests/test_validate.lua tests/test_physical_witness.lua tests/test_validated_candidate.lua tests/test_census_codes_live.lua"
        ;;
    133_goldens)
        runner=python
        tests="tests.tools.test_golden_tools tests.tools.test_real_sheet_census tests.tools.test_capture_workflow"
        ;;
    #Round 16.  Every arm below names EVERY test file that requires the module its lane owns, because round
    #15's `131_bindings` arm omitted tests/test_route_footprints.lua and tests/test_route_budget.lua, the lane
    #broke both, and its gate reported PASS: a lane gate sees only what its tag names.  tools/red_list.sh is
    #the belt to this arm's braces -- it names no file at all and refuses any file that got worse -- and every
    #round 16 task carries it, so an omission here can no longer hide a regression.
    140_route)
        tests="tests/test_route.lua tests/test_route_network.lua tests/test_route_footprints.lua \
tests/test_route_budget.lua tests/test_route_layout_contract.lua tests/test_underground_pairs.lua \
tests/test_port_tile_flow.lua tests/test_port_not_self_blocked.lua tests/test_demand_terminals.lua \
tests/test_bindings_per_hand.lua tests/test_route_chain.lua tests/test_external_ports.lua"
        ;;
    141_witness)
        tests="tests/test_validate.lua tests/test_physical_witness.lua tests/test_validated_candidate.lua \
tests/test_external_ports.lua tests/test_placed_port_geometry.lua tests/test_census_codes_live.lua \
tests/test_power_wires.lua tests/test_route_layout_contract.lua tests/test_demand_terminals.lua"
        ;;
    142_economy)
        tests="tests/test_groups.lua tests/test_pack.lua tests/test_inserter_geometry.lua \
tests/test_port_edges.lua tests/test_placed_port_geometry.lua tests/test_port_not_self_blocked.lua \
tests/test_transport_handshake.lua tests/test_hand_economy.lua tests/test_beacon_coverage.lua"
        ;;
    #An unknown tag FAILS. The old arm here set runner=suite, so a typo, a renamed lane, or a tag nobody had
    #mapped yet quietly ran the whole suite and reported the result as that lane's focused gate. A lane that
    #genuinely wants the suite says so with its own entry.
    *)
        echo "verify_round9_lane.sh: unknown tag: $tag" >&2
        echo "verify_round9_lane.sh: add an explicit entry for it; there is no suite fallback" >&2
        exit 2
        ;;
esac

#Selecting nothing is a failure, never a green result. Checked before execution so --dispatch-only catches it.
if [ -z "$tests" ]; then
    echo "verify_round9_lane.sh: $tag selected no checks" >&2
    exit 1
fi

if [ "$dispatch_only" -eq 1 ]; then
    #Resolve and print. Never execute, and never require a file a lane has not written yet.
    count=0
    for item in $tests; do
        count=$((count + 1))
        echo "verify_round9_lane: $tag dispatch=$runner item=$item"
    done
    echo "verify_round9_lane: $tag dispatch=$runner selected $count item(s)"
    exit 0
fi

status=0
selected=0

if [ "$runner" = python ]; then
    for module in $tests; do
        path=$(printf '%s\n' "$module" | tr '.' '/').py
        if [ ! -f "$path" ]; then
            echo "verify_round9_lane.sh: $tag names a missing test module: $path" >&2
            exit 1
        fi
        selected=$((selected + 1))
        python3 -m unittest -v "$module" || status=1
    done
else
    for test_file in $tests; do
        if [ ! -f "$test_file" ]; then
            echo "verify_round9_lane.sh: $tag names a missing test: $test_file" >&2
            exit 1
        fi
        for lua in lua5.2; do
            selected=$((selected + 1))
            "$lua" "$test_file" || status=1
        done
    done
fi

if [ "$selected" -eq 0 ]; then
    echo "verify_round9_lane.sh: $tag selected no checks" >&2
    exit 1
fi
echo "verify_round9_lane: $tag ran $selected check(s)"
exit "$status"
