#!/bin/sh
# Print the named physical collision pairs in the player's first candidate.
#
# The full BP_V_COLLISION census cost 414 s on legalcopilot-dev (2026-09-22).
# One measured collision probe run: 23.32 s on legalcopilot-dev (2026-09-22).
#
# The validator's record carries only two ids and two world boxes.  This probe
# stops at the exact candidate Search hands to Validate.begin, then lets the
# Python report join those boxes back to names, positions and tiles.  It uses
# generate.lua's library prefix in memory; no file in the tree is changed.
#
# usage: collision_probe.sh [case] [ops] [interpreter]
set -eu

case_id=${1:-player-red-science-1s}
ops=${2:-5000000}
lua=${3:-lua5.2}
root=$(cd "$(dirname "$0")/.." && pwd)
input="$root/tests/golden/cases/$case_id/prepared_input.json"

if [ ! -f "$input" ]; then
    echo "collision_probe.sh: no such case input: $input" >&2
    exit 2
fi

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

# Keep JSON, sha256, read_file and captured_plan in the same lexical scope as
# the probe body, just as tools/route_chain_probe.sh does.
awk '/^local input_path, output_path/{exit} {print}' \
    "$root/tests/golden/generate.lua" > "$work/probe.lua"

cat >> "$work/probe.lua" <<'LUA'

local probe_input, probe_ops = arg[1], tonumber(arg[2])
local prepared = JSON.decode(read_file(probe_input))
if type(prepared) ~= "table" then fail("prepared input must be an object") end
if type(prepared.prepared_input) == "table" then prepared = prepared.prepared_input end
local plan, plan_error = captured_plan(prepared, sha256(read_file(probe_input)))
if not plan then fail("captured_plan refused: " .. tostring(plan_error)) end
prepared.plan_result = plan
prepared.search_budget = probe_ops

local Search = require "logic.bp.search"
local state = Search.begin(prepared)
local guard = 0
while not state.done and state.work.validate_candidate == nil do
    guard = guard + 1
    if guard > 2000000 then fail("probe exceeded its own step guard") end
    Search.step(state, {ops = 2000})
end
local candidate = state.work.validate_candidate
if candidate == nil then fail("no candidate reached validate; search ended at phase " .. tostring(state.phase)) end
io.write(json_encode({schema_version = 1, case_ops = probe_ops, phase = state.phase,
    ops_used = state.ops_used, candidate = candidate}))
LUA

"$lua" "$work/probe.lua" "$input" "$ops" > "$work/candidate.json"
python3 "$root/tools/collision_report.py" "$work/candidate.json"
