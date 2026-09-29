#!/bin/sh
# Runs every offline test file under each interpreter in LUAS (default: lua5.2, which Factorio's runtime is based on, then lua5.4)
sh tools/slow_guard.sh tests/run.sh "tests/test_*.lua" || exit $?
#Child tests inherit RRC_SLOW: the *_delivers tests generate whole sheets under this suite slot (unsetting it made
#8 files red, round 47 suite 2, 2026-09-29); tests/test_slow_guard.lua clears it itself for its refusal cases.
cd "$(dirname "$0")/.." || exit 1
status=0
for lua in ${LUAS:-lua5.2 lua5.4}; do
    for test_file in tests/test_*.lua; do
        "$lua" "$test_file" || status=1
    done
done
# Tooling regressions (the mutation runner's checkout selection and kill classification). Cheap, offline, no game:
# a gate nobody runs is not a gate, and these rules are what every later mutation batch is trusted on.
python3 -m unittest discover -s tests/tools -p 'test_*.py' -t . || status=1
# Top-level python tests sat outside discovery (round 48 B7: test_entity_names, test_lane_sim, test_prepared_from_export).
for py_file in tests/test_*.py; do
    python3 -m unittest "tests.$(basename "$py_file" .py)" || status=1
done
# No test loads the data stage: at least refuse a syntax error there (prototype schemas and graphics files stay in-game checks)
for file in data.lua settings.lua; do
    luac5.2 -p "$file" || status=1
done
# Game test files on the mock first (seconds), then headless on the real engine, both versions (round 42). Headless is
# integrator only: tools/game_test.sh refuses under LANE_RUN_ID, and a host without the binary prints game-skip.
for game_file in tests/game/test_*.lua; do
    lua5.2 tests/game/offline.lua "$game_file" || status=1
done
for fv in 2.0 2.1; do
    if [ -x "${FACTORIO_ROOT:-$HOME/factorio-$fv/factorio}/bin/x64/factorio" ]; then
        sh tools/game_test.sh "$fv" --full || status=1
    else
        echo "game-skip $fv: no headless Factorio (sh tools/fetch_factorio.sh $fv)"
    fi
done
exit $status
