#!/bin/sh
# One sheet's delivery gate from bytes (round 36).
# Usage (repository root): sh tools/gate_sheet.sh <case> <max_entities> [max_belts]
# Last line: GATE-OK <case> entities=<n> belts=<n>  or  GATE-FAIL <case> <why>
sh tools/slow_guard.sh gate_sheet "tests/golden/cases/${1:-}/prepared_input.json"
case_id=${1:?case}; cap=${2:?max entities}; belt_cap=${3:-999999}
input=tests/golden/cases/$case_id/prepared_input.json
d=$(mktemp -d)
lua5.2 tests/golden/generate.lua --input "$input" --output "$d/r.json" >/dev/null 2>&1
if ! python3 tools/blueprint_string.py "$d/r.json" -o "$d/bp.txt" >/dev/null 2>&1; then echo "GATE-FAIL $case_id no-blueprint"; exit 1; fi
lanes=$(python3 tools/lane_sim.py "$d/bp.txt" --input "$input" 2>&1 | tail -1)
names=$(python3 tools/entity_names.py "$d/bp.txt" "$input" 2>&1 | tail -1)
audit=$(python3 tools/blueprint_audit.py "$d/bp.txt" 2>&1)
entities=$(echo "$audit" | awk '/^  entities /{print $2; exit}')
belts=$(echo "$audit" | awk '/^  belts /{print $2; exit}')
echo "$lanes"; echo "$names"
[ "$lanes" = "LANE-SIM mixed=0 starved=0 bleed=0" ] || { echo "GATE-FAIL $case_id lanes"; exit 1; }
[ "$names" = "NAMES-OK" ] || { echo "GATE-FAIL $case_id names"; exit 1; }
[ "$entities" -le "$cap" ] || { echo "GATE-FAIL $case_id entities=$entities cap=$cap"; exit 1; }
[ "$belts" -le "$belt_cap" ] || { echo "GATE-FAIL $case_id belts=$belts cap=$belt_cap"; exit 1; }
echo "GATE-OK $case_id entities=$entities belts=$belts"
