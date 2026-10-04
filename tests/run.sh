#!/bin/sh
# Runs every offline test file under lua5.2 only: Factorio runs Lua 5.2; player dropped lua5.4 on 2026-09-23 (LUAS overrides)
sh tools/slow_guard.sh tests/run.sh "tests/test_*.lua" || exit $?
#Child tests inherit RRC_SLOW: the *_delivers tests generate whole sheets under this suite slot (unsetting it made
#8 files red, round 47 suite 2, 2026-09-29); tests/test_slow_guard.lua clears it itself for its refusal cases.
cd "$(dirname "$0")/.." || exit 1
status=0
RRC_FULL_TURN_FLIP=${RRC_FULL_TURN_FLIP:-0}
RRC_ROUND=${RRC_ROUND:-56}
export RRC_FULL_TURN_FLIP RRC_ROUND
for lua in ${LUAS:-lua5.2}; do
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
# Headless in shards (round 48 D8: every shard < 120 s): vanilla 2.0 and 2.1, then the player's mod set on 2.0.
GAME_SHARDS=${GAME_SHARDS:-8}
for fv in 2.0 2.1; do
    if [ -x "${FACTORIO_ROOT:-$HOME/factorio-$fv/factorio}/bin/x64/factorio" ]; then
        i=1
        while [ $i -le "$GAME_SHARDS" ]; do
            sh tools/game_test.sh "$fv" --shard "$i/$GAME_SHARDS" || status=1
            i=$((i + 1))
        done
        if [ "$fv" = 2.0 ] && [ -f tests/player_mods.lock.json ]; then
            i=1
            while [ $i -le "$GAME_SHARDS" ]; do
                RRC_PROFILE=player sh tools/game_test.sh 2.0 --shard "$i/$GAME_SHARDS" || status=1
                i=$((i + 1))
            done
        fi
    else
        echo "game-skip $fv: no headless Factorio (sh tools/fetch_factorio.sh $fv)"
    fi
done
exit $status
