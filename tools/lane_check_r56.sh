#!/bin/sh
#Round 56 lane checks (plan ~/.claude/plans/pasted-content-id-fbeb-both-plan-jazzy-cake.md). One lane = one tag.
#Each check: diff stays inside the lane's own files; its new tests pass and print every marker; each related test
#file it can break ends " 0 failed"; guards green. Single test files only, each under timeout 100. Never a suite,
#census, whole golden sheet or headless run. Usage: sh tools/lane_check_r56.sh <308..315>
set -u
lane=${1:?lane number}
base=round-56-base
R309='test_bindings_per_hand test_blueprint_pipeline test_candidate_links test_demand_terminals test_export_attempt_integration test_export_payload test_external_ports test_feature_flags test_flip_geometry test_fluid_touch test_force_turn_flip test_generation_attempt_lookup test_generation_controls test_generation_interim test_generation_prune test_generation_reload test_groups_belt_split test_port_not_self_blocked test_port_tile_flow test_power_demand test_red10s_edge_rules test_route test_route_belt_chain test_route_budget test_route_bury test_route_bury_row_flow test_route_chain test_route_chain_jump_commit test_route_collector test_route_collision test_route_crowded_fluids test_route_dead_pair test_route_edge_twin test_route_end_feed test_route_feed_curve_retry test_route_fluid_keepout test_route_fluid_port_ptg test_route_footprints test_route_free_cell test_route_hand_slide test_route_hop test_route_hop_multi test_route_improve test_route_improve_waste test_route_journal2 test_route_keys test_route_lane_cap test_route_merge_feed test_route_network test_route_no_replay test_route_output_join test_route_pipe_join test_route_prune_splitter test_route_reanchor_pipe test_route_rear_curve test_route_row_book test_route_row_ids test_route_row_reuse test_route_row_seed test_route_rows test_route_source_block test_route_splitter_physics test_route_splitter_second_tile test_route_splitter_side_feed test_route_splitter_straight test_route_ticks test_route_tidy test_route_tidy_junk test_route_tidy_shapes test_route_twin_survives_tidy test_route_ug_exit_rear test_route_underground_feed test_route_underground_weave test_route_waste test_search test_search_allowance test_search_budget test_search_draw_phase test_search_exit_slot test_search_fluid_door_gap test_search_pipeline test_search_retry test_search_stop test_search_strict test_search_tidy_beacons test_side_feed test_turn_trial test_underground_pairs '
R310='test_beacon_coverage test_belt_stack test_blueprint_physical_contract test_candidate_links test_demand_terminals test_external_ports test_feature_flags test_fluid_box test_force_turn_flip test_groups test_groups_beacon_pad test_groups_beacon_row test_groups_belt_split test_groups_buffer test_groups_chunk_retry_ids test_groups_coverage_split test_groups_face_gap_bound test_groups_faces_beacon_rows test_groups_fluid_box_order test_groups_fluid_row test_groups_hand_count test_groups_hand_off_pipe test_groups_hands_overflow test_groups_interior_port test_groups_lone_slots test_groups_long_hands test_groups_one test_groups_pad_faces test_groups_port_heading test_groups_row_inserter_name test_groups_rows test_groups_split_steps test_hand_economy test_inserter_direction test_inserter_geometry test_orient test_port_edges test_ports_on_edge_ring test_route test_route_merge_feed test_row_even_width test_row_even_width_end test_rows_integration test_run_dir test_search_allowance test_search_budget test_search_draw_phase test_search_stop test_serialize test_strip_fluid_clash test_transport_handshake test_turn_trial test_turned_block '
R311='test_demand_terminals test_external_ports test_force_turn_flip test_pack test_pack_adjacent_producers test_pack_budget test_pack_buffer test_pack_drawn test_pack_layered test_pack_links test_pack_slow_hands test_pack_ticks test_pack_zone_blockers test_port_edges test_power test_power_budget test_power_make_room test_power_ops test_power_relay_chain test_power_semantics test_power_ticks test_power_wires test_rows_integration test_search test_search_allowance test_search_budget test_search_draw_phase test_search_retry test_search_stop test_turn_trial '
R312='test_beacon_prune test_belt_stack test_blueprint_physical_contract test_census_codes_live test_demand_terminals test_ends_turn test_external_ports test_feature_flags test_groups_interior_port test_long_inserter_catalog test_physical_witness test_placed_port_geometry test_power_wires test_reason_codes_registry test_red_green_fluid_ports test_route_layout_contract test_route_merge_feed test_search test_search_allowance test_search_budget test_search_stop test_search_strict test_turn_trial test_twins_coverage test_validate test_validate_belt_no_source test_validate_bleed test_validate_bound_box_mix test_validate_buffer test_validate_collector_witness test_validate_dead_pair test_validate_exit_sideload test_validate_false_alarms test_validate_fluid_mix test_validate_fluid_output_port_first test_validate_fluid_port test_validate_lane_overload test_validate_parallel_ports test_validate_port_approach test_validate_port_owner test_validate_ptg_sides test_validate_roboport_zone test_validate_row_ports test_validate_rows test_validate_side_feed_witness test_validate_source_duplicate test_validate_splitter test_validate_splitter_chain test_validate_splitter_rules test_validate_ticks test_validate_tile_index test_validate_transport_shapes test_validate_witness_underground test_validated_candidate '
R313='test_blueprint_pipeline test_case_capture test_engine_test_api test_export_attempt_integration test_export_payload test_generation_attempt_lookup test_generation_boundary_rules test_generation_controls test_generation_interim test_generation_prune test_generation_recipe_facts test_generation_record_handoff test_generation_reload test_job_flow test_note_kinds test_panel_sweep test_progress_status_line test_progress_view test_update_stops_jobs '
R308='test_box_binding test_ckpt test_golden_profile test_slow_guard test_force_turn_flip test_material_cost'
R314='test_game_runner_guard test_turn_flip_cases test_turn_flip_census_tool test_twins test_twins_coverage test_export_completeness test_slow_guard'
R315='test_harness test_harness_api test_no_runtime_require'
GUARDS='test_no_runtime_require test_no_item_names test_locale_keys'
case "$lane" in
    308) OWNS='^(tools/gate56\.sh|tools/tick_cost\.lua|tools/bytes_baseline\.py|logic/bp/box_binding\.lua|tests/golden/generate\.lua|tools/ckpt\.lua|tools/first_stage\.lua|tools/golden_profile\.lua|tests/test_tick_cost\.lua|tests/test_bytes_baseline\.py|tests/test_box_binding_offline\.lua|tests/test_gate56\.lua|tests/fixtures/r56/308/.*)$'
         NEW='test_tick_cost:TC1,TC2 test_box_binding_offline:BO1,BO2,BO3 test_gate56:GT1,GT2 test_bytes_baseline.py:BB1,BB2,BB3'; REL=$R308 ;;
    309) OWNS='^(logic/bp/route\.lua|logic/bp/search\.lua|tests/test_route_fix_bundle\.lua|tests/test_copy_share\.lua|tests/fixtures/r56/309/.*)$'
         NEW='test_route_fix_bundle:RF1,RF2,RF3,RF4 test_copy_share:CS1,CS2,CS3'; REL=$R309 ;;
    310) OWNS='^(logic/bp/groups\.lua|tests/test_groups_slices\.lua|tests/fixtures/r56/310/.*)$'
         NEW='test_groups_slices:GS1,GS2,GS3,GS4'; REL=$R310 ;;
    311) OWNS='^(logic/bp/pack\.lua|logic/bp/power\.lua|tests/test_pack_reject_charge\.lua|tests/test_power_fast\.lua|tests/fixtures/r56/311/.*)$'
         NEW='test_pack_reject_charge:PR1,PR2 test_power_fast:PF1,PF2,PF3'; REL=$R311 ;;
    312) OWNS='^(logic/bp/validate\.lua|tests/test_validate_slices\.lua|tests/fixtures/r56/312/.*)$'
         NEW='test_validate_slices:VS1,VS2,VS3,VS4,VS5'; REL=$R312 ;;
    313) OWNS='^(logic/bp/generation\.lua|tests/test_publish_cost\.lua|tests/fixtures/r56/313/.*)$'
         NEW='test_publish_cost:PC1,PC2,PC3'; REL=$R313 ;;
    314) OWNS='^(tests/test_turn_flip_census\.lua|tests/game/test_turn_flip_sims\.lua|tests/game/test_twins\.lua|tests/run\.sh|tools/game_test\.sh|tools/turn_flip_slice\.lua|tests/test_turn_flip_slice\.lua)$'
         NEW='test_turn_flip_slice:TS1,TS2,TS3,TS4,TS5'; REL=$R314 ;;
    315) OWNS='^(tests/harness\.lua|tools/junit\.lua|tools/suite_units\.sh|tests/game/support\.lua|ci/suite-runner/rrc\.recipe\.json|ci/image/Dockerfile|ci/image\.lock|tests/test_split_units\.lua|tests/tools/test_recipe\.py|tests/fixtures/r56/315/.*)$'
         NEW='test_split_units:SU1,SU2,SU3,SU4,SU5 tools/test_recipe.py:RC1,RC2,RC3'; REL=$R315 ;;
    *) echo "lane_check_r56: unknown lane $lane" >&2; exit 2 ;;
esac
bad=$(git diff --name-only "$base" HEAD | grep -Ev "$OWNS")
[ -z "$bad" ] || { echo "SCOPE files outside lane $lane:"; echo "$bad"; exit 1; }
run_lua() { o=$(timeout 100 lua5.2 "tests/$1.lua" 2>&1); echo "$o" | tail -1 | grep -q ' 0 failed' || { echo "FAIL $1"; echo "$o" | tail -5; return 1; }; LAST=$o; }
run_py() { o=$(timeout 100 python3 "tests/$1" 2>&1); r=$?; [ $r -eq 0 ] || { echo "FAIL $1"; echo "$o" | tail -5; return 1; }; LAST=$o; }
for spec in $NEW; do
    file=${spec%%:*}; marks=${spec#*:}
    case "$file" in *.py) run_py "$file" || exit 1 ;; *) run_lua "$file" || exit 1 ;; esac
    for m in $(echo "$marks" | tr ',' ' '); do echo "$LAST" | grep -qw "$m" || { echo "NOMARK $m in $file"; exit 1; }; done
done
for t in $REL $GUARDS; do run_lua "$t" || exit 1; done
echo "lane$lane-ok"
