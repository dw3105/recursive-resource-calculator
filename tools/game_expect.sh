#!/bin/sh
# Offline side of the headless parity test: generate one golden case with tests/golden/generate.lua, encode it with
# tools/blueprint_string.py (the delivered bytes), decode, and write tests/game/expected/<case>.txt: one sorted line
# per entity, "<name> <x> <y> <direction>" with %.1f positions. The game test decodes its own blueprint string the
# same way and must match line for line. Rerun after any layout change. usage: sh tools/game_expect.sh <case>
set -eu
case_id=${1:?usage: tools/game_expect.sh <case>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
d=$(mktemp -d)
lua5.2 tests/golden/generate.lua --input "tests/golden/cases/$case_id/prepared_input.json" --output "$d/r.json" >/dev/null 2>&1
python3 tools/blueprint_string.py "$d/r.json" -o "$d/bp.txt" >/dev/null
mkdir -p tests/game/expected
python3 - "$d/bp.txt" "tests/game/expected/$case_id.txt" <<'PY'
import base64, json, sys, zlib
src, dst = sys.argv[1:]
s = open(src).read().strip()
bp = json.loads(zlib.decompress(base64.b64decode(s[1:])))["blueprint"]
lines = sorted("%s %.1f %.1f %d" % (e["name"], e["position"]["x"], e["position"]["y"], e.get("direction", 0))
               for e in bp.get("entities", []))
open(dst, "w").write("\n".join(lines) + "\n")
print("game-expect %s entities=%d" % (sys.argv[2], len(lines)))
PY
rm -rf "${d:?}"
