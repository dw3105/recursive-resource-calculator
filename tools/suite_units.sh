#!/bin/sh
# Collect stable Suite Runner JUnit addresses, or execute precisely the addresses supplied.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

stem() { basename "$1" .lua; }
junit_id() { printf '%s::%s\n' "$1" "$2"; }
record() { lua5.2 tools/junit.lua record "${RRC_JUNIT_DIR:-$ROOT}" "$1" "$2" "$3" "$4" "${5:-}"; }

collect_lua() {
    directory=$1
    pattern=$2
    for file in "$directory"/$pattern; do
        [ -f "$file" ] || continue
        RRC_COLLECT=1 lua5.2 "$file"
    done
}

collect_all() {
    if [ -n "${RRC_SUITE_ROOT:-}" ]; then
        collect_lua "$RRC_SUITE_ROOT" '*.lua'
        return
    fi
    for file in tests/test_*.lua; do
        [ -f "$file" ] || continue
        [ "$(stem "$file")" = test_turn_flip_census ] && continue
        RRC_COLLECT=1 lua5.2 "$file"
    done

    # The census tool consumes one fixture case per unit; ids stay case-addressable without running the census.
    python3 - <<'PY'
import json
from pathlib import Path
for fixture in sorted(Path("tests/fixtures").glob("turn_flip_cases_*.json")):
    data = json.loads(fixture.read_text())
    for case in sorted(data.get("cases", {})):
        print(f"census/{case}::sim")
PY

    # One ordinary headless unit per file; the two simulation files are expanded below by sheet.
    for file in tests/game/test_*.lua; do
        [ -f "$file" ] || continue
        name=$(stem "$file")
        case "$name" in test_sheets|test_turn_flip_sims) continue ;; esac
        junit_id "game/$name" "$name"
    done
    for file in tests/fixtures/sheets/*.bp.txt; do
        [ -f "$file" ] || continue
        case_name=$(basename "$file" .bp.txt)
        junit_id "sheets/$case_name" sim
    done
    for file in tests/fixtures/turn_flip_sheets/*/*.bp.txt; do
        [ -f "$file" ] || continue
        case_name=$(basename "$file" .bp.txt)
        junit_id "turnflip/$case_name" sim
    done
}

collect() { collect_all | LC_ALL=C sort -u; }

run_one() {
    address=$1
    case "$address" in *::* ) ;; *) echo "suite_units: invalid JUnit address: $address" >&2; return 2 ;; esac
    class=${address%%::*}
    name=${address#*::}
    [ -n "$name" ] && [ "$name" != "$address" ] || { echo "suite_units: invalid JUnit address: $address" >&2; return 2; }
    case "$class" in *::* ) echo "suite_units: classname contains ::: $class" >&2; return 2 ;; esac
    case "$class" in
        lua/*)
            file=${class#lua/}
            case "$file" in */*|*..*) echo "suite_units: invalid Lua classname: $class" >&2; return 2 ;; esac
            path="tests/$file.lua"
            if [ -n "${RRC_SUITE_ROOT:-}" ]; then path="$RRC_SUITE_ROOT/$file.lua"; fi
            [ -f "$path" ] || { echo "suite_units: unknown Lua unit: $address" >&2; return 2; }
            RRC_CASE=$name lua5.2 "$path"
            ;;
        sheets/*)
            case_name=${class#sheets/}
            [ "$name" = sim ] || { echo "suite_units: invalid sheet unit: $address" >&2; return 2; }
            version=2.0 profile=vanilla
            case "$case_name" in
                player-*) profile=player ;;
                vanilla-2.1-*) version=2.1 ;;
            esac
            if RRC_PROFILE=$profile tools/game_test.sh "$version" "tests.game.test_sheets > $case_name"; then
                record tests/game/test_sheets.lua sim "$class" pass
            else record tests/game/test_sheets.lua sim "$class" fail "FactorioTest sheet unit failed"; return 1; fi
            ;;
        turnflip/*)
            case_name=${class#turnflip/}
            [ "$name" = sim ] || { echo "suite_units: invalid Turn/Flip unit: $address" >&2; return 2; }
            status=0 found=0
            for config in "2.0 vanilla" "2.0 player" "2.1 vanilla"; do
                set -- $config
                version=$1 profile=$2
                fixture="tests/fixtures/turn_flip_sheets/$version/$case_name.bp.txt"
                [ -f "$fixture" ] || continue
                found=1
                RRC_PROFILE=$profile tools/game_test.sh "$version" "tests.game.test_turn_flip_sims > $case_name" || status=1
            done
            [ "$found" -eq 1 ] || { echo "suite_units: unknown Turn/Flip case: $case_name" >&2; return 2; }
            if [ "$status" -eq 0 ]; then record tests/game/test_turn_flip_sims.lua sim "$class" pass
            else record tests/game/test_turn_flip_sims.lua sim "$class" fail "FactorioTest Turn/Flip unit failed"; fi
            [ "$status" -eq 0 ] || return 1
            ;;
        census/*)
            case_name=${class#census/}
            [ "$name" = sim ] || { echo "suite_units: invalid census unit: $address" >&2; return 2; }
            status=0 found=0
            for fixture in tests/fixtures/turn_flip_cases_2.0.json tests/fixtures/turn_flip_cases_2.1.json; do
                [ -f "$fixture" ] || continue
                if python3 - "$fixture" "$case_name" <<'PY'
import json, sys
raise SystemExit(0 if sys.argv[2] in json.load(open(sys.argv[1])).get("cases", {}) else 1)
PY
                then
                    found=1
                    output=$(mktemp)
                    if lua5.2 tools/turn_flip_census.lua "$fixture" --case "$case_name" >"$output" 2>&1; then
                        cat "$output"
                        if grep -q 'result=FAIL' "$output"; then status=1; fi
                    else cat "$output"; status=1; fi
                    rm -f "$output"
                fi
            done
            [ "$found" -eq 1 ] || { echo "suite_units: unknown census case: $case_name" >&2; return 2; }
            if [ "$status" -eq 0 ]; then record tools/turn_flip_census.lua sim "$class" pass
            else record tools/turn_flip_census.lua sim "$class" fail "census unit failed"; fi
            [ "$status" -eq 0 ] || return 1
            ;;
        game/*)
            file=${class#game/}
            [ "$name" = "$file" ] || { echo "suite_units: invalid headless file unit: $address" >&2; return 2; }
            status=0
            for config in "2.0 vanilla" "2.0 player" "2.1 vanilla"; do
                set -- $config
                version=$1 profile=$2
                RRC_PROFILE=$profile tools/game_test.sh "$version" --pattern "tests.game.$file" || status=1
            done
            if [ "$status" -eq 0 ]; then
                record "tests/game/$file.lua" "$file" "$class" pass
            else record "tests/game/$file.lua" "$file" "$class" fail "FactorioTest file unit failed"; return 1; fi
            ;;
        *) echo "suite_units: unknown classname: $class" >&2; return 2 ;;
    esac
}

case "${1:-}" in
    collect) [ "$#" -eq 1 ] || { echo "usage: suite_units.sh collect" >&2; exit 2; }; collect ;;
    run)
        shift
        [ "$#" -gt 0 ] || { echo "usage: suite_units.sh run <junit-address...>" >&2; exit 2; }
        status=0
        seen='|'
        for address in "$@"; do
            case "$address" in *::* ) ;; *) echo "suite_units: invalid JUnit address: $address" >&2; exit 2 ;; esac
            class=${address%%::*}
            case "$class" in *::* ) echo "suite_units: classname contains ::: $class" >&2; exit 2 ;; esac
            case "$seen" in *"|$class|"*) continue ;; esac
            seen="$seen$class|"
            names=
            for member in "$@"; do
                [ "${member%%::*}" = "$class" ] || continue
                member_name=${member#*::}
                case "$member_name" in *,*) echo "suite_units: case names cannot contain commas: $member_name" >&2; exit 2 ;; esac
                if [ -n "$names" ]; then names="$names,$member_name"; else names=$member_name; fi
            done
            run_one "$class::$names" || status=1
        done
        exit "$status"
        ;;
    *) echo "usage: suite_units.sh collect | run <junit-address...>" >&2; exit 2 ;;
esac
