--MS1 is red on b713659: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-29 - a north splitter at (13,23) took
--(12,23) as its second tile; (12,23) was the WEST-facing iron-ore belt feeding (11,23) -> underground (8,23) ->
--molten-iron:1, which lost its whole feed (BP_V_ROUTE_DISCONTINUOUS + 5 unused).
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local N, W = Grid.NORTH, Grid.WEST
local merge = Route._test.merge_splitter_footprint

local function belt(id, dir)
    return {segment_id = id, kind = "belt", flow_id = "ore", flow_ids = {ore = true}, direction = dir, capacity_per_second = 60,
        allocations = {{flow_id = "ore", sink = "s", rate_per_second = 5}}}
end
local function world(second_dir, downstream)
    local anchor, second = belt("a", N), belt("b", second_dir)
    local work = {segments = {anchor, second}, segments_by_cell = {[key(13, 23)] = anchor, [key(12, 23)] = second},
        entities = {}, entity_by_segment = {}, bindings = {}}
    if downstream then local d = belt("c", W); work.segments[3] = d; work.segments_by_cell[key(11, 23)] = d end
    return work, anchor
end

H.test("MS1 a splitter never takes a second tile that turns away to feed its own downstream", function()
    local work, anchor = world(W, true)
    H.equal(merge(work, anchor, key(12, 23), {flow_id = "ore"}), nil)
    io.write("MS1\n")
end)
H.test("MS2 a second tile running with the splitter, or feeding nothing, may be merged", function()
    local work, anchor = world(N, true)
    H.equal(merge(work, anchor, key(12, 23), {flow_id = "ore"}), anchor)
    local lone, lone_anchor = world(W, false)
    H.equal(merge(lone, lone_anchor, key(12, 23), {flow_id = "ore"}), lone_anchor)
    io.write("MS2\n")
end)
H.done("test_route_splitter_second_tile")
