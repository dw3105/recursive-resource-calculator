#!/bin/sh
set -u
USAGE='usage: tools/calc_budget.sh [--budget <seconds>] <case> [<case> ...]'
if [ -n "${LANE_RUN_ID:-}" ] && [ -z "${RRC_LUA:-}" ]; then
  echo 'calc_budget: refuse, lanes never run a whole sheet' >&2
  exit 2
fi
budget=5
if [ "${1:-}" = --budget ]; then
  [ "$#" -ge 3 ] || { echo "$USAGE" >&2; exit 2; }
  budget=$2
  shift 2
fi
case "$budget" in ''|*[!0-9]*|0) echo "$USAGE" >&2; exit 2 ;; esac
[ "$#" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
LUA=${RRC_LUA:-lua5.2}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
failed=0
for case_name in "$@"; do
  input="tests/golden/cases/$case_name/prepared_input.json"
  if [ ! -f "$input" ]; then echo "calc_budget: no input $input" >&2; exit 2; fi
  start=$(date +%s%N)
  timeout -k 2 "$budget" "$LUA" tests/golden/generate.lua --input "$input" --output "$work/$case_name.json" >"$work/$case_name.log" 2>&1
  rc=$?
  end=$(date +%s%N)
  wall=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.2f", (e-s)/1000000000 }')
  if [ "$rc" -eq 0 ] && python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ok") is True else 1)' "$work/$case_name.json" 2>/dev/null; then
    echo "calc-budget $case_name ok wall_s=$wall budget_s=$budget"
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "calc-budget $case_name FAIL timeout wall_s=$wall budget_s=$budget"; failed=1
  elif [ "$rc" -ne 0 ]; then
    echo "calc-budget $case_name FAIL exit=$rc wall_s=$wall budget_s=$budget"; failed=1
  else
    echo "calc-budget $case_name FAIL not-ok wall_s=$wall budget_s=$budget"; failed=1
  fi
done
if [ "$failed" -eq 0 ]; then echo calc-budget-ok; exit 0; fi
echo calc-budget-FAIL
exit 1
