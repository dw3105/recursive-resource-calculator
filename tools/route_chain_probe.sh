#!/bin/sh
#Print WHERE a routed belt run stops being a directed chain, on the player's real captured sheet.
#
#Why this exists.  The validator reports BP_V_ROUTE_DISCONTINUOUS with a machine and a flow and no geometry
#(logic/bp/validate.lua:1471-1489), and BP_V_TRANSPORT_UNUSED with an entity id and nothing else
#(logic/bp/validate.lua:1691-1692).  Measured 2026-09-22 on legalcopilot-dev, 20 to 22 of about 26 item
#obligations per candidate fail the walk, and every belt on those runs is then reported as waste -- 853
#records over 3 candidates.  Neither record says which tile broke, so round 15's handoff guessed the cause
#and guessed wrong.  This prints the tile.
#
#It reuses tests/golden/generate.lua's own JSON reader, sha256 and captured_plan by appending a probe body to
#that file's source in memory, so the probe reads the SAME prepared input the generator reads.  No file in the
#tree is edited and generate.lua is not modified.
#
#usage: route_chain_probe.sh [case] [ops] [interpreter]
set -eu

case_id=${1:-player-red-science-1s}
ops=${2:-5000000}
lua=${3:-lua5.2}
root=$(cd "$(dirname "$0")/.." && pwd)
input="$root/tests/golden/cases/$case_id/prepared_input.json"

if [ ! -f "$input" ]; then
    echo "route_chain_probe.sh: no such case input: $input" >&2
    exit 2
fi

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

#Everything in generate.lua BEFORE `local input_path,` is a library: JSON, sha256, read_file, captured_plan.
#Keeping those locals in scope is the whole point, so the probe body is appended to the same chunk.  The cut
#is at the argument parser, not at the xpcall: the parser runs at load time and refuses arguments it does not
#know.  tests/test_beacon_placement_incident.lua:51 slices the same file at the same line.
awk '/^local input_path, output_path/{exit} {print}' \
    "$root/tests/golden/generate.lua" > "$work/probe.lua"

cat >> "$work/probe.lua" <<'LUA'

--Probe body.  Runs the real search until the first candidate reaches `validate`, then prints that candidate
--as JSON on stdout.  `state.work.validate_candidate` is set at logic/bp/search.lua:1477, immediately before
--Validate.begin, so this is byte for byte the object the validator judges.
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
python3 "$root/tools/route_chain_report.py" "$work/candidate.json"
