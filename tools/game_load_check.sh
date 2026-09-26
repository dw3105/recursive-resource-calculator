#!/bin/sh
# Headless load of a delivered zip: create a map with only base game mods + the zip, fail on any error line.
# usage: tools/game_load_check.sh <zip> <2.0|2.1>    prints load-check-<FV>-ok or load-check-<FV>-FAIL
# Integrator only (release). Copied from ~/sushi-packer-mod tools/load_check.sh (2026-09-26).
set -eu
ZIP=${1:?usage: tools/game_load_check.sh <zip> <2.0|2.1>}
FV=${2:?usage: tools/game_load_check.sh <zip> <2.0|2.1>}
if [ -n "${LANE_RUN_ID:-}" ]; then echo "game_load_check: refuse, lanes never run headless Factorio" >&2; exit 2; fi
case "$FV" in 2.0|2.1) ;; *) echo "FV must be 2.0 or 2.1" >&2; exit 2 ;; esac
test -f "$ZIP" || { echo "game_load_check: no zip $ZIP" >&2; exit 2; }
FACTORIO=${FACTORIO_ROOT:-$HOME/factorio-$FV/factorio}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/load-$FV
rm -rf "${OUT:?}"
mkdir -p "$OUT/mods" "$OUT/write"
# Factorio loads a zip only under <name>_<version>.zip; delivered test zips carry a -test suffix.
CANON=$(python3 -c '
import json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
info = json.loads(z.read(next(n for n in z.namelist() if n.count("/") == 1 and n.endswith("/info.json"))))
print("%s_%s.zip" % (info["name"], info["version"]))' "$ZIP")
cp "$ZIP" "$OUT/mods/$CANON"
python3 - "$FACTORIO/data" "$OUT/mods" <<'PY'
import json, os, sys
data, mods = sys.argv[1:]
names = [n for n in ("base", "elevated-rails", "quality", "recycler", "space-age") if os.path.isdir(os.path.join(data, n))]
json.dump({"mods": [{"name": n, "enabled": True} for n in names + ["RRC-Fork"]]}, open(os.path.join(mods, "mod-list.json"), "w"), indent=2)
PY
printf '[path]\nread-data=%s/data\nwrite-data=%s/write\n' "$FACTORIO" "$OUT" > "$OUT/config.ini"
if "$FACTORIO/bin/x64/factorio" --config "$OUT/config.ini" --mod-directory "$OUT/mods" --create "$OUT/check.zip" > "$OUT/load.log" 2>&1 \
   && grep -q "Loading mod RRC-Fork" "$OUT/load.log" && ! grep -qiE "error|failed" "$OUT/load.log"; then
  echo "load-check-$FV-ok"
else
  tail -40 "$OUT/load.log"; echo "load-check-$FV-FAIL"; exit 1
fi
