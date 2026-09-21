#!/bin/sh
#Gate a lane on named cases of a Lua harness file, from an executed-case inventory.
#
#Two generations of this gate failed open, both measured on this host 2026-09-21.
#
#First it inferred success from silence: "grep for FAIL <case>; if absent, pass". With a stub interpreter that
#printed a startup error and exited 77, it printed its success token and exited 0.
#
#Then it required the case id to appear in the test file. That is still source text, not execution. A file
#whose CG1 appeared only in a COMMENT satisfied it; so did a file containing only CG10, because CG1 is its
#substring; so did a case that genuinely FAILED under a shape label the regex did not match; so did a run that
#printed its summary and then crashed.
#
#So this reads the harness's own inventory. Under RRC_CASE_REPORT=1 the harness prints `CASE <outcome> <name>`
#for every case it executes and `CASES-COMPLETE <n>` when it terminates. A case that did not run has no line,
#which is a refusal, and a crash after the summary loses the terminator, which is also a refusal.
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
if ! [ "$min_cases" -gt 0 ] 2>/dev/null; then
    echo "lane_rows.sh: --min-cases must be a positive count, got '$min_cases'" >&2
    exit 2
fi

commas_to_spaces() { printf '%s\n' "$1" | tr ',' ' '; }

#The outcome of one case id, as reported by the harness itself. Most suites register a case once per shape
#(`2.0 CG1 ...`), and some register it once with no shape at all (`CX1 ...`), so the shape is OPTIONAL here.
#Demanding it refused lane 112's CX1, CX2 and CX3 although all three existed and passed.
outcomes_for() {
    printf '%s\n' "$2" \
        | sed -n -e "s/^CASE \\([a-z]*\\) [0-9.][0-9.]* $1 .*/\\1/p" -e "s/^CASE \\([a-z]*\\) $1 .*/\\1/p"
}

status=0
for lua in $interpreters; do
    if out=$(RRC_CASE_REPORT=1 "$lua" "$test_file" 2>&1); then
        run_status=0
    else
        run_status=$?
    fi

    complete=$(printf '%s\n' "$out" | grep -E '^CASES-COMPLETE [0-9]+$' | tail -1 || true)
    if [ -z "$complete" ]; then
        echo "lane_rows.sh: $lua never reached CASES-COMPLETE (exit $run_status)" >&2
        echo "lane_rows.sh: the run crashed, was truncated, or the file never called H.done" >&2
        printf '%s\n' "$out" | tail -20 >&2
        exit 1
    fi

    summary=$(printf '%s\n' "$out" | grep -E 'cases, [0-9]+ passed, [0-9]+ failed' | tail -1 || true)
    if [ -z "$summary" ]; then
        echo "lane_rows.sh: $lua produced no harness summary (exit $run_status)" >&2
        exit 1
    fi

    #A crash AFTER the summary still prints both lines. The exit status is what gives it away: the harness
    #exits 0 when nothing failed and 1 when something did, so any other status means something ran past the
    #terminator or died on the way out.
    failed_count=$(printf '%s\n' "$summary" | sed -E 's/.*, ([0-9]+) failed.*/\1/')
    if [ "$failed_count" -eq 0 ]; then expected_status=0; else expected_status=1; fi
    if [ "$run_status" -ne "$expected_status" ]; then
        echo "lane_rows.sh: $lua exited $run_status with $failed_count failed; expected exit $expected_status" >&2
        echo "  $summary" >&2
        exit 1
    fi

    total=${complete#CASES-COMPLETE }
    if [ "$total" -lt "$min_cases" ]; then
        echo "lane_rows.sh: $lua executed $total cases, fewer than the expected $min_cases" >&2
        echo "  $summary" >&2
        exit 1
    fi

    #An [error] means the case never reached its assertion. It is never an assertion result, so it can neither
    #satisfy a --pass nor kill a mutant for a --fail.
    if printf '%s\n' "$out" | grep -qE '^CASE error '; then
        echo "lane_rows.sh: $lua reported a case that errored before its assertion" >&2
        printf '%s\n' "$out" | grep -E '^CASE error ' | head -5 >&2
        exit 1
    fi

    for case_id in $(commas_to_spaces "$pass_list"); do
        [ -n "$case_id" ] || continue
        seen=$(outcomes_for "$case_id" "$out")
        if [ -z "$seen" ]; then
            echo "lane_rows.sh: $lua executed no case named $case_id in $test_file" >&2
            status=1
            continue
        fi
        for outcome in $seen; do
            if [ "$outcome" != "pass" ]; then
                echo "lane_rows.sh: $lua case $case_id reported '$outcome', expected pass" >&2
                printf '%s\n' "$out" | grep -E "^FAIL [0-9.]+ $case_id " -A 2 | head -6 >&2
                status=1
            fi
        done
    done

    for case_id in $(commas_to_spaces "$fail_list"); do
        [ -n "$case_id" ] || continue
        seen=$(outcomes_for "$case_id" "$out")
        if [ -z "$seen" ]; then
            echo "lane_rows.sh: $lua executed no case named $case_id in $test_file" >&2
            status=1
            continue
        fi
        for outcome in $seen; do
            if [ "$outcome" != "fail" ]; then
                echo "lane_rows.sh: $lua case $case_id reported '$outcome'; the mutation was not detected" >&2
                status=1
            fi
        done
    done

    echo "lane_rows.sh: $lua $summary"
done

[ "$status" -eq 0 ] || exit 1
echo lane-rows-ok
