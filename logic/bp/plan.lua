--The sheet's numbers turned into what has to be built: whole machines, their modules and beacons, and the flows
--between them.
--
--Owned by lane W2-plan. This is the only blueprint module allowed to read prototypes, storage or the version
--flag; everything after it takes plain data.
--
--  Step = {step_id, recipe, recipe_quality, machine, machine_quality, machine_count, crafts_per_second_total,
--          crafts_per_second_per_machine, modules = {{name, quality, count}}, beacon_groups = {BeaconGroup},
--          has_quality_module, forbids_speed_beacon, power_w, pollution_per_min, inputs, outputs}
--  Flow = {flow_id, full_name, item_name, quality, is_fluid, rate_per_second,
--          producers = {{step_id, share_per_second}}, consumers = {{step_id, share_per_second}}}
--          step_id "$external" is the world outside the blueprint, on both sides
--  PlanPort = {port_id, role, full_name, is_fluid, rate_per_second, kind, min_lanes}
--
--machine_count is computed once, here, from the full-precision rate: the round-up checkbox is a display setting
--and must never reach a physical count. Nothing downstream may call Utils.machine_amount; the validator counts
--what was placed and compares it against this number instead of recomputing the requirement.
local Plan = {}

Plan.SCHEMA_VERSION = 1

function Plan.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "planning", done_units = 0}}
end

function Plan.step(state, budget)
    return state
end

--Whole machines for one step: ceil of the full-precision requirement, with the calculator's own tolerance, and
--at least one for any step that has work to do
function Plan.machine_count(crafts_per_second, crafts_per_second_per_machine)
    return 0
end

return Plan
