#!/bin/sh
# Round 21 regression floor: every test file that loads route.lua, search.lua or validate.lua, with the
# number of cases it PASSED at tag round-21-base on legalcopilot-dev 2026-09-23, both interpreters.
# A file may pass MORE cases than its floor, never fewer.  Prints `regress-ok` or names every file that fell.
# Usage: sh tools/round21_regress.sh   (run from the repository root)
fell=0
while read -r file floor; do
    for lua in lua5.2 lua5.4; do
        line=$($lua "tests/$file" 2>&1 | tail -1)
        passed=$(printf '%s\n' "$line" | sed -n 's/.* \([0-9][0-9]*\) passed.*/\1/p')
        if [ -z "$passed" ] || [ "$passed" -lt "$floor" ]; then
            echo "FELL $file [$lua] passed=${passed:-none} floor=$floor :: $line"
            fell=1
        fi
    done
done <<'FLOORS'
test_bindings_per_hand.lua 8
test_blueprint_pipeline.lua 24
test_blueprint_physical_contract.lua 88
test_census_codes_live.lua 7
test_demand_terminals.lua 20
test_export_attempt_integration.lua 10
test_generation_attempt_lookup.lua 16
test_external_ports.lua 14
test_generation_reload.lua 4
test_feature_flags.lua 5
test_generation_controls.lua 8
test_physical_witness.lua 12
test_port_tile_flow.lua 8
test_power_demand.lua 12
test_placed_port_geometry.lua 8
test_power_wires.lua 12
test_port_not_self_blocked.lua 6
test_export_payload.lua 36
test_route_chain.lua 10
test_route_budget.lua 8
test_route_network.lua 14
test_route_waste.lua 12
test_route_layout_contract.lua 12
test_route_splitter_physics.lua 12
test_route.lua 38
test_search_budget.lua 10
test_route_collision.lua 8
test_underground_pairs.lua 2
test_search.lua 48
test_validate.lua 44
test_validate_splitter.lua 12
test_route_footprints.lua 6
test_search_allowance.lua 8
test_validated_candidate.lua 2
test_inserter_direction.lua 10
test_inserter_geometry.lua 26
test_serialize.lua 18
test_power.lua 18
test_transport_handshake.lua 8
FLOORS
[ "$fell" -eq 0 ] && echo regress-ok
exit "$fell"
