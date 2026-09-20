#!/bin/sh
#The lane verifier for round 9. One lane's checks, chosen by its exact tag.
#
#Why this exists: lane_gate reads verify.<tag> before verify.default, but lane_config refuses any [verify] key
#outside {default, scaffold, ci_collect, perf, reference_dir}, so a per-tag key makes the whole configuration
#unloadable. The split therefore lives here, reached through the supported default key.
#
#Two consumer lanes cannot run the whole suite on their own base: tests/test_blueprint_pipeline.lua drives a real
#calculation through Generation.start and demands success, and it succeeds today only because recipe and receiver
#facts are absent. Their producer is lane 085. Those lanes run their own checks here, and the whole suite runs
#again at slice integration, unchanged.
set -eu

if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "usage: verify_round9_lane.sh <worktree> <tag>" >&2
    exit 2
fi
worktree=$1
tag=$2

if [ ! -d "$worktree" ]; then
    echo "verify_round9_lane.sh: no such worktree: $worktree" >&2
    exit 2
fi
cd "$worktree"

case "$tag" in
    086_preflight_facts)
        tests="tests/test_preflight_quality_facts.lua tests/test_quality_policy.lua tests/test_bp_preflight.lua"
        ;;
    087_planner_facts)
        tests="tests/test_plan_quality_facts.lua tests/test_quality_policy.lua tests/test_bp_plan.lua"
        ;;
    *)
        #Every other lane keeps the whole suite. There is no no-op default here.
        exec gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh
        ;;
esac

status=0
selected=0
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

#Selecting nothing is a failure, never a green result.
if [ "$selected" -eq 0 ]; then
    echo "verify_round9_lane.sh: $tag selected no checks" >&2
    exit 1
fi
echo "verify_round9_lane: $tag ran $selected check(s)"
exit "$status"
