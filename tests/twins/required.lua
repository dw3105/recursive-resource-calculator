--Round 48 D3: every code and auditor count the twins must cover, its owner lane and its class.
--  twin     = needs >=1 clean twin (truth ok) and >=1 breach twin (truth defect|waste) with rule = this code
--  player   = the player's taste, the engine has no opinion (G3): no twin
--  contract = our own tables agreeing with each other (plan vs layout ids, sheet limits): no engine meaning, no twin
--tests/test_twins_coverage.lua greps logic/ for every emitted code; a code with no row here is red.
local T, P, C = "twin", "player", "contract"
return {
    --L279 transport and fluid
    {"BP_V_BELT_BLEED", "L279", T}, {"BP_V_LANE_MIX", "L279", T}, {"BP_V_LANE_OVERLOAD", "L279", T}, {"BP_V_BELT_NO_SOURCE", "L279", T},
    {"BP_V_SPLITTER_CHAIN", "L279", T}, {"BP_V_UNDERGROUND_SIDELOAD_BLOCKED", "L279", T},
    {"BP_V_UNDERGROUND_BACK_TO_BACK", "-", P, "matches the player's hand-built factory (0 adjacent tunnels, commit 4553a97); the engine pairs and runs back-to-back tunnels as planned (headless 2.0.77 + 2.1.20)"}, {"BP_V_ROUTE_LOOP", "L279", T}, {"BP_V_ROUTE_DISCONTINUOUS", "L279", T},
    {"BP_V_UNDERGROUND_DEAD", "-", P, "player ruling 2026-09-30 (round 52 grill Q2): an underground pair that carries nothing is invalid in every pack; the engine runs it harmlessly (waste), so the rule is taste, not engine truth"},
    {"BP_V_ROUTE_MISSING", "L279", T}, {"BP_V_TRANSFER_BROKEN", "L279", T}, {"BP_V_TRANSPORT_UNUSED", "L279", T},
    {"BP_V_UNDERGROUND_UNPAIRED", "L279", T}, {"BP_V_UNDERGROUND_RANGE", "L279", T},
    {"BP_V_FLUID_DISCONNECTED", "L279", T}, {"BP_V_FLUID_MIX", "L279", T}, {"BP_V_FLUID_MIXING", "-", C, "route segment table claims two fluids in one segment: bookkeeping; the physical case is BP_V_FLUID_MIX"},
    {"audit:blueprint_audit:unpairable_underground_belt", "L279", T}, {"audit:blueprint_audit:unpairable_pipe_to_ground", "L279", T},
    {"audit:blueprint_audit:unused_belt_tiles", "L279", T}, {"audit:blueprint_audit:unused_pipe_tiles", "L279", T},
    {"audit:blueprint_audit:sideload_blocked", "L279", T}, {"audit:blueprint_audit:back_to_back", "L279", T},
    {"audit:blueprint_audit:cycles", "L279", T},
    {"audit:lane_sim:mixed", "L279", T}, {"audit:lane_sim:starved", "L279", T}, {"audit:lane_sim:bleed", "L279", T},

    --L280 placement, power, beacons, hands, rates, identity, artifact, preflight
    {"BP_V_COLLISION", "L280", T}, {"BP_V_ROBO_DISCONNECTED", "L280", T}, {"BP_V_BEACON_COVERAGE_SHORT", "L280", T},
    {"BP_V_BEACON_REDUNDANT", "L280", T}, {"BP_V_SPEED_BEACON_ON_QUALITY", "L280", T}, {"BP_V_POWER_UNCOVERED", "L280", T},
    {"BP_V_WIRE_ILLEGAL", "L280", T}, {"BP_V_WIRE_DISCONNECTED", "L280", T}, {"BP_V_INSERTER_GEOMETRY", "L280", T},
    {"BP_V_FLUID_INSERTER", "L280", T}, {"BP_V_TRANSFER_CAPACITY", "L280", T}, {"BP_V_INSERTER_CAPACITY", "L280", T},
    {"BP_V_TARGET_SHORTFALL", "L280", T}, {"BP_V_FLOW_IMBALANCE", "L280", T}, {"BP_V_MACHINE_IDENTITY", "L280", T},
    {"BP_V_MODULE_MISMATCH", "L280", T}, {"BP_V_MACHINE_COUNT_MISMATCH", "L280", T},
    {"BP_V_ARTIFACT_INCOMPLETE", "L280", T}, {"BP_V_ARTIFACT_DIRECTION", "L280", T}, {"BP_V_ARTIFACT_MACHINE_COUNT", "L280", T},
    {"BP_V_ARTIFACT_MACHINE_IDENTITY", "L280", T}, {"BP_V_ARTIFACT_MODULE_MISMATCH", "L280", T},
    {"BP_V_ARTIFACT_BEACON_IDENTITY", "L280", T}, {"BP_V_ARTIFACT_WIRE_MISMATCH", "L280", T},
    {"BP_REJ_SPOILAGE", "L280", T}, {"BP_REJ_PROBABILISTIC", "L280", T}, {"BP_REJ_RANDOM_AMOUNT", "-", C, "no vanilla/Space Age recipe has an amount range (engine discovery 2026-09-29): guard for mod content"},
    {"BP_REJ_MINING", "L280", T}, {"BP_REJ_BURNER_MACHINE", "L280", T}, {"BP_REJ_NON_ELECTRIC", "L280", T},
    {"BP_REJ_FUEL_CONSUMER", "L280", T}, {"BP_REJ_UNSUPPORTED_GEOMETRY", "-", C, "no vanilla/Space Age machine gets this catalog flag (discovery 2026-09-29): guard for mod content"}, {"BP_REJ_UNSUPPORTED_INTERFACE", "-", C, "no vanilla/Space Age machine gets this catalog flag (discovery 2026-09-29): guard for mod content"},
    {"BP_REJ_UNSUPPORTED_FLUIDBOX", "-", C, "no vanilla/Space Age machine gets this catalog flag (discovery 2026-09-29): guard for mod content"}, {"BP_REJ_MODULE_SLOTS_EXCEEDED", "L280", T},
    {"BP_REJ_BEACON_SPEED_ON_QUALITY", "L280", T}, {"BP_REJ_QUALITY_CHANGING", "L280", T}, {"BP_REJ_QUALITY_UNAVAILABLE", "-", C, "research state of the player's force, not a prototype fact"},
    {"BP_REJ_SURFACE_RESTRICTED", "-", C, "option computed by the calculator, not read from a prototype"}, {"BP_REJ_HANDCRAFT", "-", C, "solver found no machine for the column: solver bookkeeping"}, {"BP_REJ_BELT_FAMILY_MISSING", "-", C, "our catalog's completeness"},
    {"BP_REJ_CYCLE", "-", C, "solver verdict on the sheet, not a prototype fact"}, {"BP_REJ_QUALITY_LOOP", "-", C, "solver verdict on the sheet, not a prototype fact"},
    {"audit:blueprint_audit:invalid_inserters", "L280", T}, {"audit:blueprint_audit:backward_hands", "L280", T},
    {"audit:blueprint_audit:redundant_beacons", "L280", T},

    --no twin
    {"BP_V_BUFFER_ZONE", "-", P, "player ring around machines (logic/bp/buffer.lua:1-40)"},
    {"BP_V_BUFFER_ROBOPORT", "-", P, "player ring around roboports"},
    {"BP_V_SOURCE_DUPLICATE", "-", P, "player rule: one input item = one edge source"},
    {"BP_V_OUT_OF_GRID", "-", C, "sheet bounds are ours; the engine has no grid"},
    {"BP_V_PORT_EDGE_WRONG", "-", C, "port table vs perimeter"}, {"BP_V_PORT_UNREACHABLE", "-", C, "port table vs route"},
    {"BP_V_METRIC_MISSING", "-", C, "validator bookkeeping"},
    {"BP_REJ_SIZE_MACHINES", "-", C, "our request limit"}, {"BP_REJ_SIZE_STEPS", "-", C, "our request limit"},
    {"BP_REJ_SNAPSHOT_STALE", "-", C, "sheet state"}, {"BP_REJ_SOLVER_NOT_OK", "-", C, "sheet state"},
    {"BP_REJ_NO_ACTIVE_STEPS", "-", C, "sheet state"}, {"BP_REJ_NON_FINITE_RATE", "-", C, "solver output"},
    {"BP_REJ_EDGES_EQUAL", "-", C, "our options"}, {"BP_REJ_OPTION_PROTOTYPE_MISSING", "-", C, "our options"},
    {"BP_REJ_PROTOTYPE_FACTS_MISSING", "-", C, "our catalog completeness"}, {"BP_REJ_UNRESOLVED_PROTOTYPE", "-", C, "our catalog completeness"},
}
