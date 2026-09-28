--PS1 is red on e0a883f: gray + magenta grid 9, legalcopilot-dev 2026-09-28 - the iron-ore edge belt (0,73) fed a
--splitter at (1,73)/(1,74); prune asked whether the tile BEHIND the splitter was fed, found the edge source unfed,
--deleted the splitter and then both branches (8 + 25 belts), and four molten-iron blocks lost their ore.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local E = Grid.EAST
local prune = Route._test.prune_dead_route_segments

local function edge_splitter_work()
    local work = {segments = {}, segments_by_cell = {}, entities = {}, entity_by_segment = {}, counters = {},
        bindings = {}, endpoint_by_id = {}, demands = {}}
    local n = 0
    local function add(segment, cells)
        n = n + 1; segment.segment_id = "s" .. n; segment.flow_id = "ore"; segment.flow_ids = {ore = true}
        segment.allocations = {{flow_id = "ore", sink = "step:m", rate_per_second = 5}}
        work.segments[#work.segments + 1] = segment
        for _, c in ipairs(cells) do work.segments_by_cell[key(c[1], c[2])] = segment end
        local entity = {segment_id = segment.segment_id}
        work.entities[#work.entities + 1] = entity; work.entity_by_segment[segment.segment_id] = entity
        return segment
    end
    add({kind = "belt", direction = E}, {{0, 0}})
    add({kind = "belt", splitter = true, splitter_direction = E, direction = E, splitter_anchor_x = 1, splitter_anchor_y = 0,
        splitter_anchor_key = key(1, 0), splitter_second_key = key(1, 1)}, {{1, 0}, {1, 1}})
    for x = 2, 3 do add({kind = "belt", direction = E}, {{x, 0}}); add({kind = "belt", direction = E}, {{x, 1}}) end
    work.demands = {{flow_id = "ore", source = {x = 0, y = 0}, sink = {x = 3, y = 0}},
        {flow_id = "ore", source = {x = 0, y = 0}, sink = {x = 3, y = 1}}}
    return work
end

H.test("PS1 splitter fed straight from an edge source belt survives prune with both branches", function()
    local work = edge_splitter_work()
    prune(work)
    H.equal(#work.segments, 6)
    H.equal(work.segments_by_cell[key(1, 0)] ~= nil, true)
    H.equal(work.segments_by_cell[key(2, 1)] ~= nil, true)
    io.write("PS1\n")
end)
H.test("PS2 splitter nothing points into is still pruned", function()
    local work = edge_splitter_work()
    local first = work.segments[1]
    work.segments_by_cell[key(0, 0)] = nil; table.remove(work.segments, 1); table.remove(work.entities, 1)
    work.entity_by_segment[first.segment_id] = nil; work.demands = {}
    prune(work)
    H.equal(#work.segments, 0)
    io.write("PS2\n")
end)
H.done("test_route_prune_splitter")
