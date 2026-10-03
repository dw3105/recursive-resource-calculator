#!/bin/sh
# Headless Factorio tests (FactorioTest). Integrator only: merge and release. Lanes NEVER run headless.
# usage: tools/game_test.sh <2.0|2.1> '<file>::<describe> > <it>'    one test
#        tools/game_test.sh <2.0|2.1> --full                       every tests/game test
#        tools/game_test.sh <2.0|2.1> --shard I/N                  test files I, I+N, I+2N... of tests/game/index.lua
# RRC_PROFILE=player (2.0 only): the player's exact mods (tests/player_mods.lock.json, tools/fetch_player_mods.py)
# plus their startup settings (~/share/RRC/mod-settings.dat via tools/mod_settings_dat.py); build dir build/<FV>-player.
# One-test mode fails unless exactly one test ran and passed (a typo never passes on zero tests).
# Runner logic copied from ~/sushi-packer-mod tools/run_tests.sh (same host, same CLI, 2026-09-26).
sh tools/slow_guard.sh game_test.sh "${2:-}" || exit $?
set -eu
FV=${1:?usage: tools/game_test.sh <2.0|2.1> '<file>::<name>' | --full}
T=${2:?usage: tools/game_test.sh <2.0|2.1> '<file>::<name>' | --full}
# Player rule 2026-09-26: lanes never run headless, not even one test. lane_run sets LANE_RUN_ID.
if [ -n "${LANE_RUN_ID:-}" ]; then
  echo "game_test: refuse, lanes never run headless Factorio; use lua5.2 tests/game/offline.lua <file>" >&2
  exit 2
fi
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FACTORIO=${FACTORIO_ROOT:-$HOME/factorio-$FV/factorio}
FT_ZIP_DIR=${FT_ZIP_DIR:-$HOME/share/sushi-packer}
case "$FV" in 2.0) FT_VER=3.0.1 ;; 2.1) FT_VER=3.1.0 ;; *) echo "FV must be 2.0 or 2.1" >&2; exit 2 ;; esac
# FactorioTest CLI 3.6.0 serves both versions. Installed once in the main checkout; worktrees share it. The CLI
# shells out to `npx fmtk`, which resolves from cwd, so it runs with cwd = its install dir and absolute paths.
MAIN=$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
FT=${RRC_FT_DIR:-$MAIN/tools/ft}
CLI=$FT/node_modules/.bin/factorio-test
PROFILE=${RRC_PROFILE:-vanilla}
#RRC_BUILD_ROOT keeps a fixture's fake game out of the repo build (round 55: a 1-byte factorio-test zip left there by
#tests/tools/test_release_gate.py made every later real run in a fresh worktree load no test runner).
BUILD_ROOT=${RRC_BUILD_ROOT:-$ROOT/build}
case "$PROFILE" in
  vanilla) BUILD=$BUILD_ROOT/$FV ;;
  player) [ "$FV" = 2.0 ] || { echo "game_test: player profile is 2.0 only (mods captured on 2.0.77)" >&2; exit 2; }
          BUILD=$BUILD_ROOT/$FV-player ;;
  *) echo "game_test: RRC_PROFILE must be vanilla or player" >&2; exit 2 ;;
esac
SHARD=
case "$T" in --shard) SHARD=${3:?usage: --shard I/N} ;; esac

game() {  # game <pattern|""> -> runs FactorioTest, writes build/<FV>/results.json
  pattern=$1
  data="$BUILD/ftdata"
  mkdir -p "$data/mods" "$BUILD/mods"
  #Copy the runner whenever it differs from the source, not only when absent: a stale or fake zip loads no runner.
  cmp -s "$FT_ZIP_DIR/factorio-test_$FT_VER.zip" "$BUILD/mods/factorio-test_$FT_VER.zip" || cp "$FT_ZIP_DIR/factorio-test_$FT_VER.zip" "$BUILD/mods/"
  cmp -s "$FT_ZIP_DIR/factorio-test_$FT_VER.zip" "$data/mods/factorio-test_$FT_VER.zip" || cp "$FT_ZIP_DIR/factorio-test_$FT_VER.zip" "$data/mods/"
  mod=$(STAGE_DIR="$BUILD" RRC_SHARD="$SHARD" "$ROOT/tools/game_stage.sh" "$FV")
  test -x "$CLI" || { echo "game_test: FactorioTest CLI missing: mkdir -p $FT; cp tools/ft/package*.json tools/ft/patch-cli.sh $FT; (cd $FT && npm ci)" >&2; exit 2; }
  FT_DIR="$FT" sh "$ROOT/tools/ft/patch-cli.sh" >/dev/null  # 10 s startup watchdog -> 120 s
  mods="space-age quality elevated-rails"
  test -d "$FACTORIO/data/recycler" && mods="$mods recycler"
  if [ "$PROFILE" = player ]; then
    PM=${RRC_PLAYER_MODS:-$HOME/share/RRC/player-mods/2.0}
    for z in $(python3 -c 'import json,sys; print(" ".join(m["file"] for m in json.load(open(sys.argv[1]))["mods"].values()))' "$ROOT/tests/player_mods.lock.json"); do
      test -f "$PM/$z" || { echo "game_test: missing $PM/$z (python3 tools/fetch_player_mods.py fetch)" >&2; exit 2; }
      ln -sf "$PM/$z" "$data/mods/$z"
    done
    rm -rf "$data/mods/rrc-player-settings_"*
    python3 "$ROOT/tools/mod_settings_dat.py" mod "${RRC_MOD_SETTINGS:-$HOME/share/RRC/mod-settings.dat}" "$data/mods" >/dev/null
    mods="$mods $(python3 "$ROOT/tools/fetch_player_mods.py" list | tr '\n' ' ') rrc-player-settings"
  fi
  rm -f "$BUILD/results.json"
  set -- run -p "$mod" --factorio-path "$FACTORIO/bin/x64/factorio" -d "$data" --no-reorder-failed-first \
    --output-file "$BUILD/results.json" --output-timeout 300 --mods $mods  # long generations print nothing for >15 s
  if [ -n "$pattern" ]; then set -- "$@" --test-pattern "$pattern"; fi
  (cd "$FT" && "$CLI" "$@")
}

PATTERN=
case "$T" in --pattern) PATTERN=${3:?usage: --pattern '<lua pattern on test path>'} ;; esac
if [ "$T" = --full ] || [ -n "$SHARD" ] || [ -n "$PATTERN" ]; then
  game "$PATTERN" || true
  python3 - "$BUILD/results.json" "$FV" <<'PY'
import json, sys
p, fv = sys.argv[1:]
try:
    d = json.load(open(p))
except Exception as e:
    print(f"game_test: no results file ({e})"); sys.exit(1)
s = d["summary"]
bad = [t for t in d["tests"] if t["result"] not in ("passed", "skipped", "todo")]
for t in bad:
    print(f"  {t['result']}: {t['path']}")
    for e in t.get("errors", []): print("    " + e)
print(f"game-summary {fv} ran={s.get('ran')} passed={s.get('passed')} failed={s.get('failed')} describeBlockErrors={s.get('describeBlockErrors', 0)}")
ok = not bad and s.get("describeBlockErrors", 0) == 0 and s.get("passed", 0) > 0
if ok: print(f"game-full-{fv}-ok")
sys.exit(0 if ok else 1)
PY
  exit $?
fi

case "$T" in *::*) ;; *) echo "game_test: refuse, T must be '<file>::<full test name>'" >&2; exit 2 ;; esac
file=${T%%::*}
name=${T#*::}
test -n "$name" || { echo "game_test: refuse, empty test name" >&2; exit 2; }
case "$file" in tests/game/*) ;; *) echo "game_test: refuse, file must be under tests/game/" >&2; exit 2 ;; esac
# FactorioTest matches string.match(path, pattern); path = "tests.game.<file> > <describe> > <it>".
modpath=$(printf '%s' "${file%.lua}" | tr / .)
path="$modpath > $name"
pat="^$(printf '%s' "$path" | sed 's/[][().%+*?^$-]/%&/g')\$"
game "$pat" || true
python3 - "$BUILD/results.json" "$path" <<'PY'
import json, sys
p, want = sys.argv[1:]
try:
    d = json.load(open(p))
except Exception as e:
    print(f"game_test: no results file ({e})"); sys.exit(1)
hits = [t for t in d["tests"] if t["path"] == want]
errs = d["summary"].get("describeBlockErrors", 0)
print(f"game test={want!r} result={[t['result'] for t in hits]} ms={[t.get('durationMs') for t in hits]} describeBlockErrors={errs}")
for t in hits:
    for e in t.get("errors", []): print("  " + e)
sys.exit(0 if len(hits) == 1 and hits[0]["result"] == "passed" and errs == 0 else 1)
PY
