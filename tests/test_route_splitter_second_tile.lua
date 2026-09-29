--MS1: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-29 - a north splitter at (13,23) took (12,23) as its
--second tile; (12,23) was the WEST-facing iron-ore belt feeding (11,23) -> molten-iron:1, whose feed was orphaned.
--The merge notes every binding riding the turned tile; append_normal_path refuses the path when one of them no
--longer reaches its sink. MS2: an aligned second tile flags nothing (a local rule refused 4 harmless merges on
--stack1 and broke its power, bisected to c9e0305).
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local N, W = Grid.NORTH, Grid.WEST
local merge, reach = Route._test.merge_splitter_footprint, Route._test.binding_path

local n = 0
local function belt(dir)
    n = n + 1
    return {segment_id = "s" .. n, kind = "belt", flow_id = "ore", flow_ids = {ore = true}, direction = dir,
        capacity_per_second = 60, allocations = {{flow_id = "ore", sink = "step:m", rate_per_second = 5}}}
end
local function world(second_dir)
    local work = {segments = {}, segments_by_cell = {}, entities = {}, entity_by_segment = {},
        endpoint_by_id = {src = {x = 12, y = 24, port_id = "src"}, dst = {x = 10, y = 23, port_id = "dst"}}}
    local function put(x, y, s) work.segments[#work.segments + 1] = s; work.segments_by_cell[key(x, y)] = s; return s end
    put(12, 24, belt(N)); put(12, 23, belt(second_dir)); put(11, 23, belt(W)); put(10, 23, belt(W))
    local anchor = put(13, 23, belt(N))
    work.bindings = {{flow_id = "ore", source_port_id = "src", sink_port_id = "dst", segment_id = "s1"}}
    return work, anchor
end

H.test("MS1 turning a tile a binding rides flags it, and its path is then gone", function()
    local work, anchor = world(W)
    H.equal(reach(work, work.bindings[1]) ~= nil, true)
    H.equal(merge(work, anchor, key(12, 23), {flow_id = "ore"}), anchor)
    H.equal(#(work._turned_merge_risk or {}), 1)
    H.equal(work._turned_merge_anchor, anchor)  --the refusal names this anchor so the caller blocks it and searches again
    H.equal(reach(work, work._turned_merge_risk[1]), nil)
    io.write("MS1\n")
end)
H.test("MS2 an aligned second tile flags nothing", function()
    local work, anchor = world(N)
    H.equal(merge(work, anchor, key(12, 23), {flow_id = "ore"}), anchor)
    H.equal(work._turned_merge_risk, nil)
    io.write("MS2\n")
end)
H.done("test_route_splitter_second_tile")
