#!/bin/sh
# Runs every offline test file under each interpreter in LUAS (default: lua5.2, which Factorio's runtime is based on, then lua5.4)
cd "$(dirname "$0")/.." || exit 1
status=0
for lua in ${LUAS:-lua5.2 lua5.4}; do
    for test_file in tests/test_*.lua; do
        "$lua" "$test_file" || status=1
    done
done
# No test loads the data stage: at least refuse a syntax error there (prototype schemas and graphics files stay in-game checks)
for file in data.lua settings.lua; do
    luac5.2 -p "$file" || status=1
done
exit $status
