--The second opinion: everything a finished candidate claims, checked again from the exact prototype geometry.
--
--Owned by lane W3-validate. It may not call the packer, the router, the grouper or the power module, and it does
--not use the integer occupancy grid: collisions come from collision boxes and masks, beacon reception from the
--engine's own rule. A checker that shares the builder's model cannot catch the builder's mistake.
--
--Order matters for wires: every edge is checked for legality first (both endpoints exist, both connectors are
--copper, the distance is within the smaller of the two poles' reach at their own quality), and only edges that
--passed build the graph whose connectivity is then checked. A connected graph of illegal edges is not a network.
--
--Flows are checked as allocations, not as rates: per flow, what is produced plus what is supplied from outside
--equals what is consumed plus what leaves; per segment, the sum of its allocations fits its capacity; and every
--consumer's share is reachable at the same time as every other's.
--
--  state.result = {score = {beacon_count, footprint_area, pole_count, route_length, entity_count, coord_key},
--                  metrics = {beacon_effects_by_step_id, peak_power_w, pollution_per_min, achieved_rate_by_port_id}}
--  state.errors = {{code = "BP_V_...", ids = {string}, detail = table}}
local Validate = {}

function Validate.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "validating", done_units = 0}}
end

function Validate.step(state, budget)
    return state
end

--The only place the user's priority is expressed: fewer physical beacons, then smaller footprint, then fewer
--poles, then deterministic tie-breakers. The packer's own fit score never decides which layout wins.
function Validate.compare(a_score, b_score)
    return 0
end

return Validate
