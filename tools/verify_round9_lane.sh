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

if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "usage: verify_round9_lane.sh [--dispatch-only] <worktree> <tag>" >&2
    exit 2
fi
worktree=$1
tag=$2

if [ ! -d "$worktree" ]; then
    echo "verify_round9_lane.sh: no such worktree: $worktree" >&2
    exit 2
fi
cd "$worktree"

#runner is "lua" for a Lua set under both interpreters, "python" for a unittest module, "suite" for the whole
#suite through gateslot.
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
    *)
        runner=suite
        #Every other lane keeps the whole suite. There is no no-op default here.
        ;;
esac

if [ "$runner" = suite ]; then
    if [ "$dispatch_only" -eq 1 ]; then
        echo "verify_round9_lane: $tag dispatch=suite command=gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh"
        exit 0
    fi
    exec gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh
fi

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
        for lua in lua5.2 lua5.4; do
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
