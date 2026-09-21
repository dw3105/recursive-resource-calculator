#!/bin/sh
#Gate a lane on named cases of a Lua harness file, without failing open.
#
#Why this exists: a gate written as "grep for FAIL <case>; if absent, pass" reports success when the
#interpreter never ran. Measured on this host 2026-09-21 with a stub interpreter that printed a startup error
#and exited 77: the gate printed its success token and exited 0. Absent FAIL is not evidence of executed and
#passed, so this script requires positive evidence instead:
#
#  * a completed harness summary line, under EVERY interpreter;
#  * at least the expected number of cases, so a truncated or filtered run cannot satisfy it;
#  * zero [error] lines, so a crash is never read as an assertion failure;
#  * each --pass case absent from the FAIL list;
#  * each --fail case present in the FAIL list, which is how a red proof states what it expects.
#
#usage: lane_rows.sh <test-file> --min-cases <n> [--pass a,b,c] [--fail x,y] [--interpreters "lua5.2 lua5.4"]
set -eu

test_file=${1:-}
shift 2>/dev/null || true
min_cases=0
pass_list=
fail_list=
interpreters="lua5.2 lua5.4"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --min-cases) min_cases=${2:-0}; shift 2 ;;
        --pass) pass_list=${2:-}; shift 2 ;;
        --fail) fail_list=${2:-}; shift 2 ;;
        --interpreters) interpreters=${2:-}; shift 2 ;;
        *) echo "lane_rows.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$test_file" ] || [ ! -f "$test_file" ]; then
    echo "lane_rows.sh: no such test file: $test_file" >&2
    exit 2
fi
if [ "$min_cases" -le 0 ] 2>/dev/null; then
    echo "lane_rows.sh: --min-cases must be a positive count, got '$min_cases'" >&2
    exit 2
fi

commas_to_spaces() { printf '%s\n' "$1" | tr ',' ' '; }

status=0
for lua in $interpreters; do
    if out=$("$lua" "$test_file" 2>&1); then
        run_status=0
    else
        run_status=$?
    fi

    summary=$(printf '%s\n' "$out" | grep -E 'cases, [0-9]+ passed, [0-9]+ failed' | tail -1 || true)
    if [ -z "$summary" ]; then
        echo "lane_rows.sh: $lua produced no harness summary (exit $run_status)" >&2
        printf '%s\n' "$out" | tail -20 >&2
        exit 1
    fi

    total=$(printf '%s\n' "$summary" | sed -E 's/.*: ([0-9]+) cases,.*/\1/')
    if [ "$total" -lt "$min_cases" ]; then
        echo "lane_rows.sh: $lua ran $total cases, fewer than the expected $min_cases" >&2
        echo "  $summary" >&2
        exit 1
    fi

    if printf '%s\n' "$out" | grep -qE '\[error\]'; then
        echo "lane_rows.sh: $lua reported an [error]; a crash is never an assertion result" >&2
        printf '%s\n' "$out" | grep -E '\[error\]' | head -5 >&2
        exit 1
    fi

    for case_id in $(commas_to_spaces "$pass_list"); do
        [ -n "$case_id" ] || continue
        #The harness prints failures and totals, never individual passes, so "no FAIL line" is also what a
        #case that does not exist looks like. Requiring the id to appear in the file turns absence into a
        #refusal instead of a silent pass -- measured: --pass CG1 against a file with no CG1 exited 0.
        if ! grep -q "$case_id" "$test_file"; then
            echo "lane_rows.sh: $test_file names no case $case_id" >&2
            exit 1
        fi
        if printf '%s\n' "$out" | grep -qE "^FAIL [0-9.]+ $case_id "; then
            echo "lane_rows.sh: $lua still red: $case_id" >&2
            printf '%s\n' "$out" | grep -E "^FAIL [0-9.]+ $case_id " -A 2 | head -6 >&2
            status=1
        fi
    done

    for case_id in $(commas_to_spaces "$fail_list"); do
        [ -n "$case_id" ] || continue
        if ! grep -q "$case_id" "$test_file"; then
            echo "lane_rows.sh: $test_file names no case $case_id" >&2
            exit 1
        fi
        if ! printf '%s\n' "$out" | grep -qE "^FAIL [0-9.]+ $case_id "; then
            echo "lane_rows.sh: $lua did NOT fail $case_id, so the mutation was not detected" >&2
            echo "  $summary" >&2
            status=1
        fi
    done

    echo "lane_rows.sh: $lua $summary"
done

[ "$status" -eq 0 ] || exit 1
echo lane-rows-ok
