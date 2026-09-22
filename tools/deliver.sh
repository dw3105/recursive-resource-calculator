#!/bin/sh
# Generate, encode and byte-audit one captured golden case.
#
# The generator's result is an internal artifact. It must pass through
# blueprint_string.py before it is written to the player's share directory;
# the final file is then the only thing the auditor is allowed to judge.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TODAY=$(date -u +%Y%m%d)
case_id=
keep_dir=
target_path="$ROOT/docs/round-16-delivery-target.json"

usage() {
    echo "usage: tools/deliver.sh <case> [--keep-intermediate DIR] [--target PATH]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --keep-intermediate)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                echo "deliver.sh: --keep-intermediate needs a directory" >&2
                usage
                exit 2
            fi
            keep_dir=$2
            shift 2
            ;;
        --target)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                echo "deliver.sh: --target needs a file" >&2
                usage
                exit 2
            fi
            target_path=$2
            shift 2
            ;;
        --*)
            echo "deliver.sh: unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            if [ -n "$case_id" ]; then
                echo "deliver.sh: expected one case, got another argument: $1" >&2
                usage
                exit 2
            fi
            case_id=$1
            shift
            ;;
    esac
done

if [ -z "$case_id" ]; then
    usage
    exit 2
fi

case_dir="$ROOT/tests/golden/cases/$case_id"
input_path="$case_dir/prepared_input.json"
output_path="${HOME:-}/share/RRC/${case_id}-${TODAY}.txt"

family_keys="belts undergrounds splitters inserters machines poles pipes beacons roboports other entities_excluding_roboports"
audit_keys="entities wires invalid_inserters unpairable_underground unpairable_underground_belt unpairable_pipe_to_ground unused_belt_tiles unused_pipe_tiles inferred_terminals redundant_beacons"
for key in $family_keys $audit_keys; do
    eval "count_$key=-"
done

generation_s=0.000
encode_s=0.000
audit_s=0.000
total_s=0.000
byte_count=-
verdict=refused
exit_status=1
reason=
reason_code=none
scratch_dir=
result_path=
audit_json=

now_ns() {
    date +%s%N
}

seconds_between() {
    awk -v begin="$1" -v finish="$2" 'BEGIN { printf "%.3f", (finish - begin) / 1000000000 }'
}

# The auditor's --json output is intentionally simple and pretty-printed. This
# also accepts compact JSON, keeping the wrapper independent of jq or another
# extra parser. Values are all integer census fields.
read_count() {
    count_key=$1
    count_file=$2
    awk -v marker="\"$count_key\"" '
        {
            if (match($0, marker "[[:space:]]*:[[:space:]]*[0-9]+")) {
                value = substr($0, RSTART, RLENGTH)
                sub(/^[^:]*:[[:space:]]*/, "", value)
                sub(/[^0-9].*$/, "", value)
                print value
                exit
            }
        }
    ' "$count_file"
}

load_counts() {
    if [ ! -s "$audit_json" ]; then
        return 0
    fi
    for key in $family_keys $audit_keys; do
        value=$(read_count "$key" "$audit_json")
        if [ -n "$value" ]; then
            eval "count_$key=$value"
        fi
    done
}

print_summary() {
    printf 'deliver: case=%s output=%s bytes=%s' \
        "$case_id" "$output_path" "$byte_count"
    for key in $family_keys $audit_keys; do
        eval "value=\${count_$key}"
        printf ' %s=%s' "$key" "$value"
    done
    printf ' verdict=%s reason=%s generation_s=%s encode_s=%s audit_s=%s total_s=%s\n' \
        "$verdict" "$reason_code" "$generation_s" "$encode_s" "$audit_s" "$total_s"
}

finish() {
    finish_ns=$(now_ns)
    total_s=$(seconds_between "$run_start" "$finish_ns")
    if [ -n "$reason" ]; then
        printf 'deliver.sh: %s\n' "$reason" >&2
    fi
    print_summary
    exit "$exit_status"
}

# Invalid case names are refused before any path outside the cases directory is
# considered. Keep this diagnostic named and short: this is a CLI refusal, not
# a Lua or Python traceback.
case_pattern_ok=true
case "$case_id" in
    */*|.|..|'') case_pattern_ok=false ;;
esac
if [ "$case_pattern_ok" != true ] || [ ! -d "$case_dir" ] || [ ! -f "$input_path" ]; then
    reason="unknown case '$case_id' (expected a directory with prepared_input.json under tests/golden/cases/)"
    reason_code=unknown_case
    printf 'deliver.sh: %s\n' "$reason" >&2
    print_summary
    exit "$exit_status"
fi

if [ ! -f "$target_path" ]; then
    reason="target file does not exist: $target_path"
    reason_code=target_missing
    printf 'deliver.sh: %s\n' "$reason" >&2
    print_summary
    exit "$exit_status"
fi

if [ -n "$keep_dir" ]; then
    if ! mkdir -p "$keep_dir"; then
        reason="could not create intermediate directory: $keep_dir"
        reason_code=intermediate_directory
        printf 'deliver.sh: %s\n' "$reason" >&2
        print_summary
        exit "$exit_status"
    fi
    if [ -e "$keep_dir/result.json" ]; then
        reason="intermediate result already exists: $keep_dir/result.json"
        reason_code=intermediate_collision
        printf 'deliver.sh: %s\n' "$reason" >&2
        print_summary
        exit "$exit_status"
    fi
fi

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/rrc-deliver.XXXXXX") || {
    reason="could not create a scratch directory"
    printf 'deliver.sh: %s\n' "$reason" >&2
    print_summary
    exit "$exit_status"
}

cleanup() {
    if [ -n "$scratch_dir" ]; then
        rm -rf "$scratch_dir"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ -n "$keep_dir" ]; then
    result_path="$keep_dir/result.json"
else
    result_path="$scratch_dir/result.json"
fi

audit_json="$scratch_dir/audit.json"
run_start=$(now_ns)

generation_begin=$(now_ns)
generation_error="$scratch_dir/generation.err"
generation_status=0
lua5.2 "$ROOT/tests/golden/generate.lua" --input "$input_path" --output "$result_path" \
    >"$scratch_dir/generation.out" 2>"$generation_error" || generation_status=$?
generation_end=$(now_ns)
generation_s=$(seconds_between "$generation_begin" "$generation_end")
if [ "$generation_status" -ne 0 ] || [ ! -s "$result_path" ]; then
    reason_code=generation_failed
    if [ "$generation_status" -ne 0 ]; then
        reason="generation failed (exit $generation_status)"
    else
        reason="generation failed: no result.json was produced"
    fi
    if [ -s "$generation_error" ]; then
        reason="$reason; $(sed -n '1p' "$generation_error")"
    fi
    finish
fi

encoded_tmp="$scratch_dir/blueprint.txt"
encode_begin=$(now_ns)
encode_status=0
if mkdir -p "${HOME:-}/share/RRC" 2>"$scratch_dir/encode.err"; then
    if [ -e "$output_path" ]; then
        encode_status=1
        reason="output collision at $output_path; refusing to overwrite the existing file"
        reason_code=output_collision
    elif python3 "$ROOT/tools/blueprint_string.py" "$result_path" -o "$encoded_tmp" \
            >"$scratch_dir/encode.out" 2>"$scratch_dir/encode.err"; then
        :
    else
        encode_status=$?
        reason="encoding refused (exit $encode_status)"
        reason_code=encoding_refused
        if [ -s "$scratch_dir/encode.err" ]; then
            reason="$reason; $(sed -n '1p' "$scratch_dir/encode.err")"
        fi
    fi
else
    encode_status=$?
    reason="could not create output directory: ${HOME:-}/share/RRC"
    reason_code=output_directory
fi
if [ "$encode_status" -eq 0 ] && [ ! -d "${HOME:-}/share/RRC" ]; then
    encode_status=1
    reason="could not create output directory: ${HOME:-}/share/RRC"
    reason_code=output_directory
elif [ "$encode_status" -eq 0 ] && [ ! -s "$encoded_tmp" ]; then
    encode_status=1
    reason="encoding failed: no blueprint file was produced"
    reason_code=encoding_failed
elif [ "$encode_status" -eq 0 ] && [ -e "$output_path" ]; then
    encode_status=1
    reason="output collision at $output_path; refusing to overwrite the existing file"
    reason_code=output_collision
elif [ "$encode_status" -eq 0 ]; then
    if mv "$encoded_tmp" "$output_path"; then
        :
    else
        encode_status=$?
        reason="could not install encoded blueprint at $output_path"
        reason_code=output_install
    fi
fi
encode_end=$(now_ns)
encode_s=$(seconds_between "$encode_begin" "$encode_end")
if [ "$encode_status" -ne 0 ]; then
    finish
fi

byte_count=$(wc -c < "$output_path" | awk '{print $1}')

audit_begin=$(now_ns)
audit_status=0
python3 "$ROOT/tools/blueprint_audit.py" "$output_path" --expect-target "$target_path" --json \
    >"$audit_json" 2>"$scratch_dir/audit.err" || audit_status=$?
audit_end=$(now_ns)
audit_s=$(seconds_between "$audit_begin" "$audit_end")
load_counts

if [ "$audit_status" -eq 0 ]; then
    verdict=accepted
    exit_status=0
else
    reason="audit refused (exit $audit_status)"
    reason_code=audit_refused
    if [ -s "$scratch_dir/audit.err" ]; then
        reason="$reason; $(sed -n '1p' "$scratch_dir/audit.err")"
    fi
fi

finish
