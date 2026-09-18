--Machines and the beacons that serve them, arranged together before anything is placed on the map.
--
--Owned by lane W3-groups. Beacon count is the first thing the search minimises, so sharing has to be planned
--here: packing machines first and sprinkling beacons afterwards would miss the objective the user asked for.
--
--A block is a rectangle with its contents laid out relative to its own corner, its beacons already assigned, its
--inserters already placed, and its ports on the outside:
--  BlockPort = {port_id, role = "in"|"out", kind = "item"|"fluid", flow_id, rate_per_second,
--               attach_dx, attach_dy,   -- the tile OUTSIDE the envelope this port attaches to
--               normal_dir,             -- from that tile INTO the block
--               travel_dir,             -- transport travel: into the block for an input, out of it for an output
--               member_id}
--Adjacency is bounded on both axes, so a port cannot sit far off the edge while satisfying one equality:
--  (attach_dx == -1 or attach_dx == w) and 0 <= attach_dy < h, or the same with the axes swapped.
--
--A machine holding a quality module must never end up inside a speed beacon's influence. That is a hard
--placement rule here and a hard failure in the validator, not a score.
local Groups = {}

function Groups.begin(input)
    return {done = false, ok = nil, cursor = {}, progress = {phase = "grouping", done_units = 0}}
end

function Groups.step(state, budget)
    return state
end

--A placed block's entities, ids prefixed "m:", rotated through Grid.place_member and Grid.place_port only
function Groups.materialize(block, placement)
    return {}
end

return Groups
