#!/bin/sh
#Measure one generation against the player's hard limit, and FAIL over it.
#
#The limit is the user's own, stated 2026-09-21: "NO SINGLE CALCULATION SHOULD TAKE MORE THAN 5 SECONDS!!!!
#IT WOULD BE UNPLAYABLE IN GAME ANYWAY!!!!". Round 13 measured 29.41s on the player's sheet with route at
#85.2% of it, and the number was carried in prose from one report to the next. Prose is not a gate, so this
#is a command that exits non-zero.
#
#It refuses a successful-looking run that did not actually deliver. Measured 2026-09-21, an earlier version of
#this check read `{"ok":true,"validation":{"ok":false}}` and printed `ceiling-met 2ms`, because it timed a
#refusal. So the result must carry ok, a passing validation, and a non-empty entity list before its time
#counts for anything.
#
#usage: ceiling.sh [case] [seconds] [interpreter]
set -eu

case_id=${1:-player-am2-chain}
limit=${2:-5.00}
lua=${3:-lua5.2}
root=$(cd "$(dirname "$0")/.." && pwd)
input="$root/tests/golden/cases/$case_id/prepared_input.json"

if [ ! -f "$input" ]; then
    echo "ceiling.sh: no such case input: $input" >&2
    exit 2
fi

out=$(mktemp) || exit 2
trap 'rm -f "$out"' EXIT

start=$(date +%s.%N)
status=0
"$lua" "$root/tests/golden/generate.lua" --input "$input" --output "$out" >/dev/null 2>&1 || status=$?
end=$(date +%s.%N)
elapsed=$(awk -v a="$start" -v b="$end" 'BEGIN{printf "%.2f", b-a}')

delivered=$(python3 - "$out" <<'PY'
import json, pathlib, sys
try:
    payload = json.loads(pathlib.Path(sys.argv[1]).read_text() or "{}")
except Exception:
    print("no-json"); raise SystemExit
result = payload.get("result") or {}
validation = payload.get("validation") or {}
if payload.get("ok") is not True:
    print("ok-false")
elif validation.get("ok") is not True:
    print("validation-false")
elif not (result.get("entities") or []):
    print("no-entities")
else:
    print("delivered %d" % len(result["entities"]))
PY
)

printf 'ceiling: case=%s interpreter=%s elapsed=%ss limit=%ss exit=%s result=%s\n' \
    "$case_id" "$lua" "$elapsed" "$limit" "$status" "$delivered"

case "$delivered" in
    delivered\ *) ;;
    *)
        echo "ceiling.sh: nothing was delivered, so the time measures a refusal and means nothing" >&2
        exit 1 ;;
esac

over=$(awk -v e="$elapsed" -v l="$limit" 'BEGIN{print (e>l) ? 1 : 0}')
if [ "$over" -eq 1 ]; then
    echo "ceiling.sh: $elapsed s is over the $limit s limit" >&2
    exit 1
fi
echo ceiling-met
