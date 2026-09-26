#!/bin/sh
# Stage RRC for one headless Factorio version into build/<FV>/: mods/RRC-Fork_<ver>/, mod-list.json, config.ini.
# usage: tools/game_stage.sh <2.0|2.1>    prints the staged mod dir
# Copies the working tree (release files + tests/game), marks the copy packaged (logic/build_id.lua) so the
# rrc-engine-test interface registers, adds "? factorio-test" so control.lua can load the test runner, and turns
# each case in tests/game/fixtures.txt into tests/game/fixtures/<case>.lua (prepared input as one JSON string).
# Setup copied from ~/sushi-packer-mod tools/stage.sh (same host, same binaries, 2026-09-26).
set -eu
FV=${1:?usage: tools/game_stage.sh <2.0|2.1>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
case "$FV" in 2.0|2.1) ;; *) echo "game_stage: FV must be 2.0 or 2.1" >&2; exit 2 ;; esac
OUT=${STAGE_DIR:-$ROOT/build/$FV}
FACTORIO=${FACTORIO_ROOT:-$HOME/factorio-$FV/factorio}
test -x "$FACTORIO/bin/x64/factorio" || { echo "game_stage: no Factorio at $FACTORIO (sh tools/fetch_factorio.sh $FV)" >&2; exit 2; }
VER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/info.json")
MOD="$OUT/mods/RRC-Fork_$VER"
rm -rf "${OUT:?}/mods/RRC-Fork_"*
mkdir -p "$MOD/tests" "$OUT/write"
for f in info.json control.lua data.lua settings.lua updates.lua changelog.txt thumbnail.png LICENSE; do  # = generate_release.sh list
  test -e "$ROOT/$f" && cp "$ROOT/$f" "$MOD/"
done
for d in gui locale logic; do cp -r "$ROOT/$d" "$MOD/"; done
cp -r "$ROOT/tests/game" "$MOD/tests/"
rm -f "$MOD/tests/game/offline.lua"
SHA=$(cd "$ROOT" && git rev-parse HEAD)
cat > "$MOD/logic/build_id.lua" <<LUA
return {candidate_sha = "$SHA", mod_version = "$VER", factorio_branch = "$FV", packaged = true}
LUA
python3 - "$MOD" "$FV" "$ROOT" <<'PY'
import json, os, sys
mod, fv, root = sys.argv[1:]
p = os.path.join(mod, "info.json")
d = json.load(open(p)); d["factorio_version"] = fv
d["dependencies"] = d.get("dependencies", []) + ["? factorio-test"]
json.dump(d, open(p, "w"), indent=4)
listing = os.path.join(root, "tests/game/fixtures.txt")
out = os.path.join(mod, "tests/game/fixtures")
os.makedirs(out, exist_ok=True)
for case in (l.strip() for l in open(listing) if l.strip() and not l.startswith("#")):
    text = open(os.path.join(root, "tests/golden/cases", case, "prepared_input.json")).read()
    level = "=="
    while "]" + level + "]" in text: level += "="
    with open(os.path.join(out, case.replace("-", "_") + ".lua"), "w") as f:
        f.write("return [" + level + "[" + text + "]" + level + "]\n")
    expected = open(os.path.join(root, "tests/game/expected", case + ".txt")).read()
    with open(os.path.join(out, case.replace("-", "_") + "_expected.lua"), "w") as f:
        f.write("return [==[" + expected + "]==]\n")
PY
python3 - "$FACTORIO/data" "$OUT/mods" <<'PY'
import json, os, sys
data, mods = sys.argv[1:]
names = [n for n in ("base", "elevated-rails", "quality", "recycler", "space-age") if os.path.isdir(os.path.join(data, n))]
names += ["RRC-Fork"]
if any(f.startswith("factorio-test_") for f in os.listdir(mods)): names.append("factorio-test")
json.dump({"mods": [{"name": n, "enabled": True} for n in names]}, open(os.path.join(mods, "mod-list.json"), "w"), indent=2)
PY
cat > "$OUT/config.ini" <<CFG
[path]
read-data=$FACTORIO/data
write-data=$OUT/write
CFG
echo "$MOD"
