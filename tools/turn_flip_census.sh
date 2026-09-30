#!/bin/sh
# Integrator only: generate and stage every Turn and Flip sheet, then run the full game lab for both versions.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
SUMMARIES=$(mktemp)
trap 'rm -f "$SUMMARIES"' EXIT HUP INT TERM
for ver in 2.0 2.1; do
  fixture="tests/fixtures/turn_flip_cases_$ver.json"
  test -f "$fixture" || { echo "turn_flip_census: missing $fixture" >&2; exit 2; }
  out="tests/fixtures/turn_flip_sheets/$ver"
  mkdir -p "$out"
  log=$(mktemp)
  lua5.2 tools/turn_flip_census.lua "$fixture" --export tests/fixtures/turn_flip_sheets >"$log"
  cat "$log"
  grep '^CENSUS-SUMMARY ' "$log" >> "$SUMMARIES"
  rm -f "$log"
  RRC_TURN_FLIP_FULL=1 sh tools/game_test.sh "$ver" --full
done
cat "$SUMMARIES"
