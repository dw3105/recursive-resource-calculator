#!/bin/sh
# Measure one golden sheet end to end from delivered bytes (round 30).
# Usage: sh tools/measure_sheet.sh player-red-science-1s|player-green-science-1s
# Last line: MEASURE case=<c> ok=<true|false> entities=<n> belts=<n> splitters=<n> mixed=<m> starved=<s> bleed=<b> wall_s=<t>
sh tools/slow_guard.sh measure_sheet "tests/golden/cases/${1:-}/prepared_input.json" || exit $?
case_id=${1:?case id}
input=tests/golden/cases/$case_id/prepared_input.json
d=$(mktemp -d)
t0=$(date +%s)
lua5.2 tests/golden/generate.lua --input "$input" --output "$d/r.json" >/dev/null 2>&1
t1=$(date +%s)
ok=false; entities=0; belts=0; splitters=0; mixed=-; starved=-; bleed=-
if python3 tools/blueprint_string.py "$d/r.json" -o "$d/bp.txt" >/dev/null 2>&1; then
  ok=true
  python3 tools/blueprint_audit.py "$d/bp.txt" > "$d/audit.txt" 2>&1
  entities=$(awk '/^  entities /{print $2; exit}' "$d/audit.txt")
  belts=$(awk '/^  belts /{print $2; exit}' "$d/audit.txt")
  python3 tools/lane_sim.py "$d/bp.txt" --input "$input" > "$d/lanes.txt" 2>&1
  mixed=$(tail -1 "$d/lanes.txt" | sed -n 's/.*mixed=\([0-9]*\).*/\1/p')
  starved=$(tail -1 "$d/lanes.txt" | sed -n 's/.*starved=\([0-9]*\).*/\1/p')
  bleed=$(tail -1 "$d/lanes.txt" | sed -n 's/.*bleed=\([0-9]*\).*/\1/p')
  splitters=$(python3 -c "
import sys; sys.path.insert(0,'tools')
from blueprint_audit import load_entities; from pathlib import Path
print(sum(1 for e in load_entities(Path('$d/bp.txt'))[0] if 'splitter' in e['name']))")
  grep -E 'STARVED|MIXED|BLEED' "$d/lanes.txt" | head -5
else
  python3 - "$d/r.json" <<'PY'
import json, sys, collections
try: r = json.load(open(sys.argv[1]))
except Exception as e: print("no result:", e); sys.exit(0)
found = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'reason_details' and isinstance(v, list): found.extend(v)
            walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(r)
print("errors", [e.get('code') for e in r.get('errors', [])])
c = collections.Counter(d.get('code') for d in found if isinstance(d, dict))
print("rejections", dict(c.most_common(8)))
PY
fi
echo "bytes: $d/bp.txt"
echo "MEASURE case=$case_id ok=$ok entities=$entities belts=$belts splitters=$splitters mixed=$mixed starved=$starved bleed=$bleed wall_s=$((t1 - t0))"
