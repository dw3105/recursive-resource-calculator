--Belts, undergrounds, splitters and pipes between blocks, with enough capacity for every consumer at once.
--
--Owned by lane W3-route. It creates no inserters: a block already carries the ones that serve its machines.
--
--Capacity is an allocation, not a rate comparison: a segment carries a list of who gets how much through it, so
--one belt cannot promise its whole throughput to an intermediate consumer and again to an external output.
--  Segment = {segment_id, kind = "belt"|"lane"|"pipe"|"inserter", capacity_per_second,
--             allocations = {{flow_id, sink = "step:<id>"|"port:<id>", rate_per_second}}}
--
--Underground pairing is resolved from the rotated runtime connections, never from a vanilla rule: an endpoint
--pairs when its own connection of type "underground" faces its partner's, within that connection's own
--max_underground_distance. The exposed connection of a vanilla pipe-to-ground faces away from its partner.
local Route = {}

function Route.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "routing", done_units = 0}}
end

function Route.step(state, budget)
    return state
end

return Route
