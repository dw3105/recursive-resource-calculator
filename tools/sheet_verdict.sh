#!/bin/sh
# Round 51 verdict row for one golden sheet from delivered bytes: sha256, entity mix, lane_sim, names, wall time.
# Usage: sh tools/sheet_verdict.sh <case> <outdir>   (RRC_PACK passes through: sugiyama = drawn pack)
# Keeps <outdir>/<case>.r.json and <case>.bp.txt. Last line:
# VERDICT case=<c> pack=<mode> sha=<sha|none> entities= belts= undergrounds= splitters= pipes= ptg= machines= flipped=
#         turned= lanes=<mixed/starved/bleed> names=<NAMES-OK|..> wall_s=<t>
sh tools/slow_guard.sh measure_sheet "tests/golden/cases/${1:-}/prepared_input.json" || exit $?
case_id=${1:?case id}; out=${2:?outdir}
input=tests/golden/cases/$case_id/prepared_input.json
mkdir -p "$out"
t0=$(date +%s)
# REUSE=1 scores an existing <outdir>/<case>.r.json (a long sheet generated separately under its own slot).
if [ "${REUSE:-}" != 1 ] || [ ! -f "$out/$case_id.r.json" ]; then
  lua5.2 tests/golden/generate.lua --input "$input" --output "$out/$case_id.r.json" >"$out/$case_id.log" 2>&1
fi
t1=$(date +%s)
mode=${RRC_PACK:-layered}
fell_back=$(python3 - "$out/$case_id.r.json" <<'PY'
import json, sys
try:
    data=json.load(open(sys.argv[1]))
    result=data.get('result', data)
    print(1 if (result.get('search') or {}).get('fell_back') else 0)
except Exception:
    print(0)
PY
)
draw_stats=$(python3 - "$out/$case_id.r.json" <<'PY'
import json, sys
try:
    data=json.load(open(sys.argv[1])); draw=((data.get('result', data).get('search') or {}).get('draw') or {})
    print('pred_ug=%s dir_overrides=%s' % (draw.get('ug_pred', '-'), draw.get('dir_overrides', '-')))
except Exception:
    print('pred_ug=- dir_overrides=-')
PY
)
if ! python3 tools/blueprint_string.py "$out/$case_id.r.json" -o "$out/$case_id.bp.txt" >/dev/null 2>&1; then
  codes=$(grep -o 'BP_[A-Z_]*' "$out/$case_id.r.json" 2>/dev/null | sort | uniq -c | tr -s ' \n' ' ')
  echo "VERDICT case=$case_id pack=$mode sha=none codes=[$codes] lanes=none fell_back=$fell_back wall_s=$((t1 - t0)) $draw_stats"
  exit 0
fi
sha=$(sha256sum "$out/$case_id.bp.txt" | cut -c1-64)
lanes=$(python3 tools/lane_sim.py "$out/$case_id.bp.txt" --input "$input" 2>&1 | tail -1 | sed 's/LANE-SIM //; s/ /,/g')
names=$(python3 tools/entity_names.py "$out/$case_id.bp.txt" "$input" 2>&1 | tail -1)
mix=$(python3 - "$out/$case_id.bp.txt" <<'PY'
import sys
sys.path.insert(0, 'tools')
from pathlib import Path
from blueprint_audit import load_entities
ents = load_entities(Path(sys.argv[1]))[0]
def n(f): return sum(1 for e in ents if f(e))
crafting = lambda e: e.get('name', '').startswith(('assembling-machine', 'chemical-plant', 'oil-refinery', 'foundry',
    'biochamber', 'cryogenic-plant', 'electromagnetic-plant'))
print('entities=%d belts=%d undergrounds=%d splitters=%d pipes=%d ptg=%d machines=%d flipped=%d turned=%d' % (
    len(ents), n(lambda e: e['name'].endswith('transport-belt')), n(lambda e: e['name'].endswith('underground-belt')),
    n(lambda e: e['name'].endswith('splitter')), n(lambda e: e['name'] == 'pipe'), n(lambda e: e['name'] == 'pipe-to-ground'),
    n(crafting), n(lambda e: crafting(e) and e.get('mirror')), n(lambda e: crafting(e) and e.get('direction', 0) != 0)))
PY
)
echo "VERDICT case=$case_id pack=$mode sha=$sha $mix lanes=$lanes fell_back=$fell_back names=$names wall_s=$((t1 - t0)) $draw_stats"
