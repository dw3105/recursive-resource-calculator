#!/bin/sh
# sha256 of the delivered blueprint bytes for one golden case (generation is deterministic).
# Usage: sh tools/bytes_hash.sh player-red-science-1s   -> "BYTES <case> <sha256>"
case_id=${1:?case id}
d=$(mktemp -d)
lua5.2 tests/golden/generate.lua --input "tests/golden/cases/$case_id/prepared_input.json" --output "$d/r.json" >/dev/null 2>&1
python3 tools/blueprint_string.py "$d/r.json" -o "$d/bp.txt" >/dev/null 2>&1 || { echo "BYTES $case_id none"; exit 0; }
echo "BYTES $case_id $(sha256sum "$d/bp.txt" | cut -c1-64)"
