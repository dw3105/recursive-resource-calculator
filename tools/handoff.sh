#!/bin/sh
# Build, test, and record the exact archives that are ready to hand to a player.
# Usage: handoff.sh [--diagnostic] <commit-ish> <2.0 version> <2.1 version>
#
# RRC_HANDOFF_KEEP_ARCHIVES=<dir> copies the two archives this command verified into <dir>, so what reaches a
# player is the same bytes the record names. Rebuilding instead would produce a different sha256, and the record
# would then describe an archive nobody holds. Archives are copied only when the record passes.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

usage() {
    echo "usage: handoff.sh [--diagnostic] <sha> <2.0 version> <2.1 version>" >&2
    exit 2
}

DIAGNOSTIC_MODE=0
if [ "${1:-}" = "--diagnostic" ]; then
    DIAGNOSTIC_MODE=1
    shift
fi

[ "$#" -eq 3 ] || usage

REQUESTED_SHA=$1
VERSION20=$2
VERSION21=$3
[ -n "$REQUESTED_SHA" ] && [ -n "$VERSION20" ] && [ -n "$VERSION21" ] || usage

if ! CANDIDATE_SHA=$(git -C "$ROOT" rev-parse --verify "$REQUESTED_SHA^{commit}" 2>/dev/null); then
    echo "handoff refused: candidate does not resolve to a commit: $REQUESTED_SHA" >&2
    exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rrc-handoff.XXXXXX")
BUILD_DIR=$WORK/archives
STAGE20=$WORK/2.0
STAGE21=$WORK/2.1
CHECKS_FILE=$WORK/checks.tsv
INFO_FILE=$WORK/informational.tsv
REASONS_FILE=$WORK/reasons.txt
BLOCKERS_FILE=$WORK/blockers.tsv
BUILD_LOG=$WORK/build.log
DISCOVERY=$WORK/discover.lua
LUA_INIT_FILE=$WORK/lua-init.lua
mkdir -p "$BUILD_DIR" "$STAGE20" "$STAGE21"
: > "$CHECKS_FILE"
: > "$INFO_FILE"
: > "$REASONS_FILE"
: > "$BLOCKERS_FILE"

OVERALL_FAILURE=0
RECORD_WRITTEN=0
HASH20=missing
HASH21=missing
PACKAGE20=
PACKAGE21=
DISC20=
DISC21=
ACC20=
ACC21=
QUALITY20=
QUALITY21=
ARCHIVE20=$BUILD_DIR/RRC-Fork_${VERSION20}_factorio-2.0-test.zip
ARCHIVE21=$BUILD_DIR/RRC-Fork_${VERSION21}_factorio-2.1-test.zip

refuse() {
    OVERALL_FAILURE=1
    printf '%s\n' "$1" >> "$REASONS_FILE"
    echo "handoff refused: $1" >&2
}

# A caller that already narrowed either selector is asking for a different
# proof. Refuse it before building so a partial run can never be mistaken for
# the full handoff. Unset selectors are supplied with the full values below.
if [ "${RRC_SHAPES+x}" = x ] && [ "$RRC_SHAPES" != '2.0,2.1' ]; then
    refuse "RRC_SHAPES is narrowed; unset it for the full handoff"
fi
if [ "${LUAS+x}" = x ] && [ "$LUAS" != 'lua5.2 lua5.4' ]; then
    refuse "LUAS is narrowed; unset it for the full handoff"
fi

cleanup() {
    rm -rf "$WORK"
}

archive_hash() {
    if [ -f "$1" ]; then
        sha256sum "$1" | awk '{print $1}'
    else
        printf '%s' missing
    fi
}

archive_set_hash() {
    printf '2.0\t%s\t%s\n2.1\t%s\t%s\n' \
        "$VERSION20" "$HASH20" "$VERSION21" "$HASH21" \
        | sha256sum | awk '{print $1}'
}

record_blocker() {
    blocker_branch=$1
    blocker_name=$2
    blocker_exit=$3
    blocker_reason=$4
    blocker_log_sha256=${5:-missing}
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$blocker_branch" "$blocker_name" "$blocker_exit" "$blocker_reason" "$blocker_log_sha256" >> "$BLOCKERS_FILE"
}

# This helper is deliberately run from the extracted package.  Its H.test
# replacement counts the cases that the candidate source would register, but
# does not execute their bodies.  That gives the gate an environment-independent
# census against which the real run is compared.
printf '%s\n' \
    'local H = require "tests.harness"' \
    'local count = 0' \
    'H.test = function() count = count + 1 end' \
    'H.done = function() end' \
    'for i = 1, #arg do' \
    '    local file = assert(io.open(arg[i], "rb"))' \
    '    local source = file:read("*a")' \
    '    file:close()' \
    '    if source:find("local function test", 1, true) then' \
    '        for _ in source:gmatch("\ntest%s*%(") do count = count + 1 end' \
    '    else' \
    '        local ok, err = pcall(dofile, arg[i])' \
    '        if not ok then io.stderr:write(arg[i] .. ": " .. tostring(err) .. "\\n"); os.exit(3) end' \
    '    end' \
    'end' \
    'print(count)' > "$DISCOVERY"

# Lua's source searcher reports the path it selected.  Keep the path absolute
# and reject every source file outside the package, including a live-checkout
# module accidentally found through an inherited LUA_PATH.
printf '%s\n' \
    'local root = assert(os.getenv("RRC_HANDOFF_ROOT"))' \
    'local function inside(path)' \
    '    if type(path) ~= "string" then return false end' \
    '    if path:sub(1, 1) ~= "/" then' \
    '        for part in path:gmatch("[^/]+") do if part == ".." then return false end end' \
    '        return true' \
    '    end' \
    '    return path == root or path:sub(1, #root + 1) == root .. "/"' \
    'end' \
    'local searchers = package.searchers or package.loaders' \
    'local source = searchers[2]' \
    'searchers[2] = function(name)' \
    '    local loader, path = source(name)' \
    '    if path ~= nil and not inside(path) then' \
    '        error("handoff refused: module " .. tostring(name) .. " resolved outside extracted root: " .. tostring(path), 0)' \
    '    end' \
    '    return loader, path' \
    'end' > "$LUA_INIT_FILE"

run_lua() {
    package_root=$1
    shift
    (cd "$package_root" && env \
        RRC_HANDOFF_ROOT="$package_root" \
        LUA_PATH="$package_root/?.lua;$package_root/?/init.lua" \
        LUA_CPATH= \
        LUA_INIT="@$LUA_INIT_FILE" \
        LUA_INIT_5_2="@$LUA_INIT_FILE" \
        LUA_INIT_5_4="@$LUA_INIT_FILE" \
        RRC_SHAPES='2.0,2.1' \
        LUAS='lua5.2 lua5.4' \
        "$@")
}

discover_cases() {
    package_root=$1
    helper=$2
    kind=$3
    shift 3
    set -- "$package_root"/tests/test_*.lua
    if [ "$kind" = acceptance ]; then
        set -- "$package_root"/tests/acceptance/*_case.lua
    elif [ "$kind" = quality ]; then
        set -- "$package_root"/tests/test_quality_policy.lua
    elif [ "$kind" = export ]; then
        set -- "$package_root"/tests/test_export_completeness.lua
    fi
    if [ "$#" -eq 0 ] || [ ! -f "$1" ]; then
        printf '%s\n' 0
        return 0
    fi
    file_count=$#
    if ! output=$(run_lua "$package_root" lua5.2 "$helper" "$@"); then
        echo "case discovery failed in $package_root ($kind)" >&2
        printf '%s\n' 0
        return 1
    fi
    count=$(printf '%s\n' "$output" | tail -1 | sed -n 's/^\([0-9][0-9]*\)$/\1/p')
    case $count in
        ''|*[!0-9])
            echo "case discovery returned no count in $package_root ($kind)" >&2
            printf '%s\n' 0
            return 1
            ;;
    esac
    printf '%s\n' "$count $file_count"
}

stage_archive() {
    archive=$1
    extract=$2
    package_root=
    if ! python3 -m zipfile -e "$archive" "$extract" >/dev/null 2>&1; then
        refuse "cannot extract archive: $(basename "$archive")"
        return 1
    fi
    package_count=$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print | wc -l | tr -d ' ')
    if [ "$package_count" -ne 1 ]; then
        refuse "archive does not contain exactly one package directory: $(basename "$archive")"
        return 1
    fi
    package_root=$(find "$extract" -mindepth 1 -maxdepth 1 -type d -print | sed -n '1p')
    if [ ! -f "$package_root/info.json" ] || [ ! -d "$package_root/logic" ]; then
        refuse "archive has no production package root: $(basename "$archive")"
        return 1
    fi
    # Only the candidate commit is allowed to supply these files.  In
    # particular, do not copy tests from the checkout running this command.
    staged_tar=$WORK/$(basename "$extract")-source.tar
    if ! git -C "$ROOT" archive "$CANDIDATE_SHA" tests tools > "$staged_tar"; then
        refuse "cannot archive candidate tests and tools for $(basename "$archive")"
        return 1
    fi
    if ! tar -x -f "$staged_tar" -C "$package_root"; then
        refuse "cannot stage candidate tests and tools for $(basename "$archive")"
        return 1
    fi
    # The repository's Python tests use pinned extracts and golden fixtures
    # under docs.  Stage them when the candidate has them, while keeping the
    # command usable with a deliberately tiny fixture repository as well.
    if git -C "$ROOT" cat-file -e "$CANDIDATE_SHA:docs" 2>/dev/null; then
        docs_tar=$WORK/$(basename "$extract")-docs.tar
        if ! git -C "$ROOT" archive "$CANDIDATE_SHA" docs > "$docs_tar"; then
            refuse "cannot archive candidate supporting docs for $(basename "$archive")"
            return 1
        fi
        if ! tar -x -f "$docs_tar" -C "$package_root"; then
            refuse "cannot stage candidate supporting docs for $(basename "$archive")"
            return 1
        fi
    fi
    if [ ! -f "$package_root/tests/run.sh" ] \
        || [ ! -f "$package_root/tests/acceptance/run" ] \
        || [ ! -f "$package_root/tests/golden/run" ] \
        || [ ! -f "$package_root/tests/test_quality_policy.lua" ]; then
        refuse "candidate staging is incomplete for $(basename "$archive")"
        return 1
    fi
    printf '%s\n' "$package_root"
}

run_check() {
    package_root=$1
    branch=$2
    name=$3
    command=$4
    gating=$5
    expected_cases=$6
    expected_summaries=$7
    log=$WORK/$(printf '%s-%s.log' "$branch" "$name" | tr '/ ' '__')
    rc=0
    if (cd "$package_root" && env \
        RRC_HANDOFF_ROOT="$package_root" \
        LUA_PATH="$package_root/?.lua;$package_root/?/init.lua" \
        LUA_CPATH= \
        LUA_INIT="@$LUA_INIT_FILE" \
        LUA_INIT_5_2="@$LUA_INIT_FILE" \
        LUA_INIT_5_4="@$LUA_INIT_FILE" \
        RRC_SHAPES='2.0,2.1' \
        LUAS='lua5.2 lua5.4' \
        sh -c "$command") > "$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    case_summaries=$(sed -n 's/.*: \([0-9][0-9]*\) cases, [0-9][0-9]* passed, [0-9][0-9]* failed.*/\1/p' "$log")
    direct_summaries=$(sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed$/\1 \2/p' "$log" \
        | awk '{print $1 + $2}')
    summary_count=$(printf '%s\n%s\n' "$case_summaries" "$direct_summaries" \
        | sed '/^$/d' | awk '{n += 1} END {print n + 0}')
    executed_cases=$(printf '%s\n%s\n' "$case_summaries" "$direct_summaries" \
        | sed '/^$/d' | awk '{n += $1} END {print n + 0}')
    status=passed
    failed=0
    failure_reason="$branch $name failed (exit=$rc, summaries=$summary_count/$expected_summaries, cases=$executed_cases/$expected_cases)"
    if [ "$rc" -ne 0 ] || [ "$summary_count" -ne "$expected_summaries" ] || [ "$executed_cases" -ne "$expected_cases" ]; then
        failed=1
    fi
    log_sha256=$(sha256sum "$log" | awk '{print $1}')
    if [ "$failed" -eq 1 ]; then
        status=refused
        if [ "$DIAGNOSTIC_MODE" -eq 1 ] && [ "$name" != export-completeness ]; then
            record_blocker "$branch" "$name" "$rc" "$failure_reason" "$log_sha256"
        elif [ "$gating" = true ]; then
            refuse "$failure_reason"
        fi
    fi
    if [ "$gating" = false ]; then
        status=informational
    fi
    output_file=$CHECKS_FILE
    [ "$gating" = true ] || output_file=$INFO_FILE
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$branch" "$name" "$command" "$rc" "$status" "$expected_cases" "$executed_cases" "$log_sha256" >> "$output_file"
}

run_package() {
    package_root=$1
    branch=$2
    test_discovery=$3
    acceptance_discovery=$4
    test_file_count=$5
    acceptance_file_count=$6
    quality_discovery=$7

    if [ -z "$test_discovery" ] || [ "$test_discovery" -le 0 ]; then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker "$branch" tests-discovery 1 "$branch has empty test case discovery"
        else
            refuse "$branch has empty test case discovery"
        fi
        return 0
    fi
    if [ -z "$acceptance_discovery" ] || [ "$acceptance_discovery" -le 0 ]; then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker "$branch" acceptance-discovery 1 "$branch has empty acceptance case discovery"
        else
            refuse "$branch has empty acceptance case discovery"
        fi
        return 0
    fi
    if [ -z "$quality_discovery" ] || [ "$quality_discovery" -le 0 ]; then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker "$branch" quality-policy-discovery 1 "$branch has empty quality-policy case discovery"
        else
            refuse "$branch has empty quality-policy case discovery"
        fi
        return 0
    fi

    run_check "$package_root" "$branch" tests-run 'sh tests/run.sh' true \
        "$((test_discovery * 2))" "$((test_file_count * 2))"
    run_check "$package_root" "$branch" acceptance 'sh tests/acceptance/run' true \
        "$acceptance_discovery" "$acceptance_file_count"
    run_check "$package_root" "$branch" quality-policy 'lua5.2 tests/test_quality_policy.lua' true \
        "$quality_discovery" 1
    # The corpus is intentionally informational: draft/captured cases and the
    # branch-2.1 empty accepted set are expected on this host.
    run_check "$package_root" "$branch" golden-corpus 'sh tests/golden/run --branch 2.0 --drafts report' false 0 0
}

#The census is discovered, never assumed. A fixed expected count silently refuses a real run the moment the
#export test grows a case, which is exactly what a hand-written 1 did against its 36 real cases.
run_export_check() {
    package_root=$1
    branch=$2
    expected=$3
    if [ -z "$expected" ] || [ "$expected" -le 0 ]; then
        refuse "$branch has empty export-completeness case discovery"
        return 0
    fi
    run_check "$package_root" "$branch" export-completeness 'lua5.2 tests/test_export_completeness.lua' true \
        "$expected" 1
}

write_record() {
    [ "$RECORD_WRITTEN" -eq 0 ] || return 0
    RECORD_WRITTEN=1
    HASH20=$(archive_hash "$ARCHIVE20")
    HASH21=$(archive_hash "$ARCHIVE21")
    set_hash=$(archive_set_hash)
    record_dir=$ROOT/docs/handoff/$CANDIDATE_SHA
    mkdir -p "$record_dir"
    record_path=$record_dir/$set_hash.json
    attempt=1
    while [ -e "$record_path" ]; do
        record_path=$record_dir/${set_hash}-attempt-${attempt}.json
        attempt=$((attempt + 1))
    done
    result=pass
    [ "$OVERALL_FAILURE" -eq 0 ] || result=refused
    if python3 - "$record_path" "$CANDIDATE_SHA" "$result" "$set_hash" \
        "$VERSION20" "$HASH20" "$(basename "$ARCHIVE20")" \
        "$VERSION21" "$HASH21" "$(basename "$ARCHIVE21")" \
        "$CHECKS_FILE" "$INFO_FILE" "$REASONS_FILE" "$DIAGNOSTIC_MODE" "$BLOCKERS_FILE" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

(path, candidate, result, archive_set, v20, h20, f20, v21, h21, f21,
 checks_path, info_path, reasons_path, diagnostic_mode, blockers_path) = sys.argv[1:]
checks = []
for line in Path(checks_path).read_text(encoding="utf-8").splitlines():
    if not line:
        continue
    branch, name, command, exit_code, check_state, expected, executed, log_sha256 = line.split("\t")
    checks.append({
        "name": name,
        "command": command,
        "expected_cases": int(expected),
        "executed_cases": int(executed),
        "exit": int(exit_code),
        "log_sha256": log_sha256,
    })
informational = []
for line in Path(info_path).read_text(encoding="utf-8").splitlines():
    if not line:
        continue
    branch, name, command, exit_code, check_state, expected, executed, log_sha256 = line.split("\t")
    informational.append({
        "name": "golden-corpus-status",
        "exit": int(exit_code),
        "log_sha256": log_sha256,
    })
reasons = [line for line in Path(reasons_path).read_text(encoding="utf-8").splitlines() if line]
blockers = []
for line in Path(blockers_path).read_text(encoding="utf-8").splitlines():
    if not line:
        continue
    branch, name, exit_code, reason, log_sha256 = line.split("\t")
    blockers.append({
        "branch": branch,
        "name": name,
        "exit": int(exit_code),
        "reason": reason,
        "log_sha256": log_sha256,
    })
record = {
    "schema_version": 1,
    "candidate_sha": candidate,
    "archive_set_sha256": archive_set,
    "archives": [
        {"branch": "2.0", "version": v20, "sha256": None if h20 == "missing" else h20},
        {"branch": "2.1", "version": v21, "sha256": None if h21 == "missing" else h21},
    ],
    "checks": checks,
    "informational": informational,
    "result": result,
    "reasons": reasons,
    "created_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}
if diagnostic_mode == "1":
    record["mode"] = "diagnostic"
    record["blockers"] = blockers
    for archive in record["archives"]:
        archive["verdict"] = "unverified_internal"
Path(path).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    then
        echo "handoff $result: $record_path"
    else
        echo "handoff refused: could not write handoff record" >&2
        OVERALL_FAILURE=1
    fi
}

trap 'rc=$?; if [ "$RECORD_WRITTEN" -eq 0 ] && [ -n "${CANDIDATE_SHA:-}" ]; then write_record || true; fi; cleanup; exit "$rc"' 0 1 2 15

if [ "$OVERALL_FAILURE" -eq 0 ]; then
    if ! sh "$ROOT/tools/build_test_zip.sh" "$CANDIDATE_SHA" "$VERSION20" "$VERSION21" "$BUILD_DIR" > "$BUILD_LOG" 2>&1; then
        refuse "archive builder failed"
    fi

    if [ ! -f "$ARCHIVE20" ]; then
        refuse "missing 2.0 archive: $(basename "$ARCHIVE20")"
    fi
    if [ ! -f "$ARCHIVE21" ]; then
        refuse "missing 2.1 archive: $(basename "$ARCHIVE21")"
    fi
fi

if [ "$OVERALL_FAILURE" -eq 0 ]; then
    if ! PACKAGE20=$(stage_archive "$ARCHIVE20" "$STAGE20"); then :; fi
    if ! PACKAGE21=$(stage_archive "$ARCHIVE21" "$STAGE21"); then :; fi
fi

keep_archives() {
    [ -n "${RRC_HANDOFF_KEEP_ARCHIVES:-}" ] || return 0
    mkdir -p "$RRC_HANDOFF_KEEP_ARCHIVES" || return 1
    cp "$ARCHIVE20" "$ARCHIVE21" "$RRC_HANDOFF_KEEP_ARCHIVES/" || return 1
    printf 'handoff archives kept: %s\n' "$RRC_HANDOFF_KEEP_ARCHIVES"
}

if [ "$OVERALL_FAILURE" -eq 0 ]; then
    if ! DISC20=$(discover_cases "$PACKAGE20" "$DISCOVERY" tests); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.0 tests-discovery 1 "2.0 test case discovery failed"
        else
            refuse "2.0 test case discovery failed"
        fi
    fi
    if ! DISC21=$(discover_cases "$PACKAGE21" "$DISCOVERY" tests); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.1 tests-discovery 1 "2.1 test case discovery failed"
        else
            refuse "2.1 test case discovery failed"
        fi
    fi
    if ! ACC20=$(discover_cases "$PACKAGE20" "$DISCOVERY" acceptance); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.0 acceptance-discovery 1 "2.0 acceptance case discovery failed"
        else
            refuse "2.0 acceptance case discovery failed"
        fi
    fi
    if ! ACC21=$(discover_cases "$PACKAGE21" "$DISCOVERY" acceptance); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.1 acceptance-discovery 1 "2.1 acceptance case discovery failed"
        else
            refuse "2.1 acceptance case discovery failed"
        fi
    fi
    if ! QUALITY20=$(discover_cases "$PACKAGE20" "$DISCOVERY" quality); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.0 quality-policy-discovery 1 "2.0 quality-policy case discovery failed"
        else
            refuse "2.0 quality-policy case discovery failed"
        fi
    fi
    if ! QUALITY21=$(discover_cases "$PACKAGE21" "$DISCOVERY" quality); then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            record_blocker 2.1 quality-policy-discovery 1 "2.1 quality-policy case discovery failed"
        else
            refuse "2.1 quality-policy case discovery failed"
        fi
    fi
fi

if [ "$OVERALL_FAILURE" -eq 0 ] || [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
    if [ -n "$PACKAGE20" ] && [ -n "$PACKAGE21" ] && [ -n "$DISC20" ] && [ -n "$DISC21" ] \
        && [ -n "$ACC20" ] && [ -n "$ACC21" ] && [ -n "$QUALITY20" ] && [ -n "$QUALITY21" ]; then
        if [ "$DIAGNOSTIC_MODE" -eq 1 ]; then
            EXPORT20=$(discover_cases "$PACKAGE20" "$DISCOVERY" export) || EXPORT20=0
            EXPORT21=$(discover_cases "$PACKAGE21" "$DISCOVERY" export) || EXPORT21=0
            run_export_check "$PACKAGE20" 2.0 "$(printf '%s\n' "$EXPORT20" | awk '{print $1}')"
            run_export_check "$PACKAGE21" 2.1 "$(printf '%s\n' "$EXPORT21" | awk '{print $1}')"
        fi
    TEST_DISC20=$(printf '%s\n' "$DISC20" | awk '{print $1}')
    TEST_FILES20=$(printf '%s\n' "$DISC20" | awk '{print $2}')
    TEST_DISC21=$(printf '%s\n' "$DISC21" | awk '{print $1}')
    TEST_FILES21=$(printf '%s\n' "$DISC21" | awk '{print $2}')
    ACC_DISC20=$(printf '%s\n' "$ACC20" | awk '{print $1}')
    ACC_FILES20=$(printf '%s\n' "$ACC20" | awk '{print $2}')
    ACC_DISC21=$(printf '%s\n' "$ACC21" | awk '{print $1}')
    ACC_FILES21=$(printf '%s\n' "$ACC21" | awk '{print $2}')
    QUALITY_DISC20=$(printf '%s\n' "$QUALITY20" | awk '{print $1}')
    QUALITY_DISC21=$(printf '%s\n' "$QUALITY21" | awk '{print $1}')
    run_package "$PACKAGE20" 2.0 "$TEST_DISC20" "$ACC_DISC20" "$TEST_FILES20" "$ACC_FILES20" "$QUALITY_DISC20"
    run_package "$PACKAGE21" 2.1 "$TEST_DISC21" "$ACC_DISC21" "$TEST_FILES21" "$ACC_FILES21" "$QUALITY_DISC21"
    fi
fi

write_record
if [ "$OVERALL_FAILURE" -ne 0 ]; then
    exit 2
fi
#Only a successful transition may hand over archives, and only the ones this run built.
if ! keep_archives; then
    echo "handoff refused: cannot keep archives in $RRC_HANDOFF_KEEP_ARCHIVES" >&2
    exit 2
fi
exit 0
