--Every stable code the blueprint path can report, in one place, because goldens, tests, tooltips and the export
--diagnostics all have to name the same thing. Message text is a locale key, never the identity: a reason is
--compared by code, so a reworded message never changes a test result.
--
--  REJECT   the request cannot be generated at all, decided before any layout work (BP-03, PERF-01)
--  FAIL     the search ended without a layout; this is never a claim that no layout exists (BP-15, PERF-04)
--  INTERNAL a stage told the search to retry or grow; the player never sees one
--  VIOLATION the independent validator refused a finished candidate: a bug or a budget, never a user error
local ReasonCodes = {}

ReasonCodes.REJECT = {
    "BP_REJ_CYCLE", "BP_REJ_QUALITY_LOOP", "BP_REJ_QUALITY_CHANGING", "BP_REJ_SPOILAGE", "BP_REJ_PROBABILISTIC",
    "BP_REJ_RANDOM_AMOUNT", "BP_REJ_MINING", "BP_REJ_BURNER_MACHINE", "BP_REJ_FUEL_CONSUMER", "BP_REJ_HANDCRAFT",
    "BP_REJ_NON_ELECTRIC", "BP_REJ_SOLVER_NOT_OK", "BP_REJ_SNAPSHOT_STALE", "BP_REJ_NON_FINITE_RATE",
    "BP_REJ_NO_ACTIVE_STEPS", "BP_REJ_UNRESOLVED_PROTOTYPE", "BP_REJ_PROTOTYPE_FACTS_MISSING",
    "BP_REJ_UNSUPPORTED_GEOMETRY",
    "BP_REJ_UNSUPPORTED_FLUIDBOX", "BP_REJ_UNSUPPORTED_INTERFACE", "BP_REJ_MODULE_SLOTS_EXCEEDED",
    "BP_REJ_QUALITY_UNAVAILABLE", "BP_REJ_EDGES_EQUAL", "BP_REJ_OPTION_PROTOTYPE_MISSING",
    "BP_REJ_BELT_FAMILY_MISSING", "BP_REJ_SURFACE_RESTRICTED", "BP_REJ_BEACON_SPEED_ON_QUALITY",
    "BP_REJ_SIZE_MACHINES", "BP_REJ_SIZE_STEPS",
}

ReasonCodes.FAIL = {
    "BP_FAIL_SEARCH_BUDGET", "BP_FAIL_GRID_LIMIT", "BP_FAIL_POWER_BOUND", "BP_FAIL_NO_LAYOUT_GRID_LIMIT", "BP_FAIL_ENTITY_BUDGET", "BP_FAIL_CANCELLED",
    "BP_FAIL_REVISION_CHANGED", "BP_FAIL_INTERNAL_ERROR", "BP_FAIL_FLIP_FORBIDDEN", "BP_FAIL_FLIP_REBUILD", "BP_FAIL_FLUID_PORT_BLOCKED",
}

ReasonCodes.INTERNAL = {
    "BP_P_NO_FIT", "BP_P_REGION_LIMIT", "BP_P_TRIAL_PIN", "BP_R_NO_PATH", "BP_R_CAPACITY", "BP_R_EXPANSIONS", "BP_R_PORT_BLOCKED",
    "BP_R_FLUID_MIX", "BP_PW_UNCOVERED", "BP_PW_DISCONNECTED",
}

ReasonCodes.VIOLATION = {
    "BP_V_COLLISION", "BP_V_BUFFER_ZONE", "BP_V_BUFFER_ROBOPORT", "BP_V_OUT_OF_GRID", "BP_V_ROBO_DISCONNECTED", "BP_V_BEACON_COVERAGE_SHORT",
    "BP_V_SPEED_BEACON_ON_QUALITY", "BP_V_POWER_UNCOVERED", "BP_V_WIRE_ILLEGAL",
    "BP_V_WIRE_DISCONNECTED", "BP_V_ROUTE_MISSING", "BP_V_FLUID_MIXING", "BP_V_FLOW_IMBALANCE",
    "BP_V_TARGET_SHORTFALL", "BP_V_UNDERGROUND_RANGE", "BP_V_UNDERGROUND_UNPAIRED",
    "BP_V_INSERTER_CAPACITY", "BP_V_INSERTER_GEOMETRY", "BP_V_PORT_EDGE_WRONG",
    "BP_V_PORT_UNREACHABLE", "BP_V_MACHINE_COUNT_MISMATCH", "BP_V_MODULE_MISMATCH",
    --Emitted by logic/bp/validate.lua since round 13 and never registered here, so ReasonCodes.all() did not
    --know them and nothing could assert against them by name.
    "BP_V_TRANSFER_BROKEN", "BP_V_FLUID_DISCONNECTED", "BP_V_ROUTE_DISCONTINUOUS", "BP_V_FLUID_INSERTER",
    "BP_V_METRIC_MISSING", "BP_V_MACHINE_IDENTITY",
    --Round 14, contract 26.2 and 26.6. A transport entity or inserter that serves no obligation is waste, and
    --a beacon whose removal leaves every machine at its configured count is waste.
    "BP_V_TRANSPORT_UNUSED", "BP_V_BEACON_REDUNDANT",
    "BP_V_UNDERGROUND_SIDELOAD_BLOCKED", "BP_V_UNDERGROUND_BACK_TO_BACK", "BP_V_ROUTE_LOOP", "BP_V_LANE_MIX", "BP_V_BELT_BLEED", "BP_V_LANE_OVERLOAD",
    "BP_V_FLUID_MIX", "BP_V_SOURCE_DUPLICATE",
    "BP_V_SPLITTER_CHAIN", "BP_V_BELT_NO_SOURCE", "BP_V_UNDERGROUND_DEAD",
    "BP_V_TRANSFER_CAPACITY",
    "BP_V_ARTIFACT_INCOMPLETE", "BP_V_ARTIFACT_DIRECTION", "BP_V_ARTIFACT_MACHINE_COUNT",
    "BP_V_ARTIFACT_MACHINE_IDENTITY", "BP_V_ARTIFACT_MODULE_MISMATCH", "BP_V_ARTIFACT_BEACON_IDENTITY",
    "BP_V_ARTIFACT_WIRE_MISMATCH",
}

--The locale key a code is shown with. Codes a player can see (REJECT and FAIL) have one; an internal retry signal
--and a validator violation are diagnostics, and the export carries their code rather than a translated sentence.
function ReasonCodes.locale_key(code)
    if code:match("^BP_REJ_") then return "hxrrc.blueprint_reject_" .. code:sub(8):lower() end
    if code:match("^BP_FAIL_") then return "hxrrc.blueprint_fail_" .. code:sub(9):lower() end
    return nil
end

--Every code, whatever its class, as a set for validation
function ReasonCodes.all()
    local all = {}
    for _, group in ipairs({ReasonCodes.REJECT, ReasonCodes.FAIL, ReasonCodes.INTERNAL, ReasonCodes.VIOLATION}) do
        for _, code in ipairs(group) do all[code] = true end
    end
    return all
end

return ReasonCodes
