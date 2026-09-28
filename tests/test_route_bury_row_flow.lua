--BF1 is red on c743751: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-28 - the advanced-circuit row run
--(flow_id nil, flow_ids {advanced-circuit}) was buried under a crossing at (26,157); the new underground pair was
--published with flow nil, the belt end turner took it for a foreign entrance and turned row belt (26,155) east.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local E, S = Grid.EAST, Grid.SOUTH

H.test("BF1 a buried row run publishes its underground pair with the row's flow", function()
    local work = {segments = {}, segments_by_cell = {}, entities = {}, entity_by_segment = {}, bindings = {}, demands = {},
        obstacles = {}, grid = {}, underground_cells = {}, splitter_blocked_cells = {}, next_segment = 0, next_entity = 0,
        belt = {underground = "u", underground_max_distance = 5}}
    for x = 0, 6 do
        local seg = {segment_id = "row" .. x, kind = "belt", direction = E, fixed = true, flow_ids = {["item/a"] = true},
            allocations = {{flow_id = "item/a", sink = "step:t", rate_per_second = 5}}, capacity_per_second = 60}
        local ent = {id = "e" .. x, flow_id = "item/a", segment_id = seg.segment_id}
        work.segments[#work.segments + 1] = seg; work.segments_by_cell[key(x, 0)] = seg
        work.entities[#work.entities + 1] = ent; work.entity_by_segment[seg.segment_id] = ent
    end
    H.equal(Route._test.apply_bury(work, {x = 3, y = 0, cross_direction = S}, true), true)
    local flows = {}
    for _, e in ipairs(work.entities) do if e.ug_role then flows[#flows + 1] = tostring(e.flow_id) end end
    H.equal(#flows, 2)
    H.equal(flows[1], "item/a"); H.equal(flows[2], "item/a")
    io.write("BF1\n")
end)
H.done("test_route_bury_row_flow")
