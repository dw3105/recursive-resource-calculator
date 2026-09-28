--EF1, EF2 and EF4 are red on round-47-w1 (no end-feed guard): gray + magenta grid 54x254, legalcopilot-dev
--2026-09-28 - an iron-stick underground exit faced the rail output belt (98 BP_V_BELT_BLEED) and a stone belt end
--with both sides taken faced an advanced-circuit underground entrance.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local N, E, S, W = Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST

local function world(cells)
    local work = {segments_by_cell = {}, obstacles = {}}
    for _, c in ipairs(cells) do work.segments_by_cell[key(c.x, c.y)] = c.seg end
    return work
end
local function belt(flow, dir) return {kind = "belt", flow_id = flow, flow_ids = {[flow] = true}, direction = dir, allocations = {}} end
local function exit_at(flow, dir, ex, ey)
    local s = belt(flow, dir); s.underground = true; s.underground_exit_key = key(ex, ey); s.underground_entry_key = key(ex, ey - 3)
    return s
end
local guard = Route._test.end_feed_bleeds

H.test("EF1 path ending in an underground exit that faces another flow's belt is refused", function()
    local w = world({{x = 4, y = 121, seg = exit_at("stick", S, 4, 121)}, {x = 4, y = 122, seg = belt("rail", W)}})
    H.equal(guard(w, {flow_id = "stick", kind = "belt"}, {{x = 4, y = 118}, {x = 4, y = 121}}, {}), true)
    io.write("EF1\n")
end)
H.test("EF2 belt end facing another flow's entrance with both sides taken is refused", function()
    local entry = belt("circuit", S); entry.underground = true; entry.underground_exit_key = key(27, 119)
    local w = world({{x = 28, y = 115, seg = belt("stone", W)}, {x = 27, y = 115, seg = entry},
        {x = 28, y = 114, seg = belt("circuit", W)}, {x = 28, y = 116, seg = belt("stick", E)}})
    H.equal(guard(w, {flow_id = "stone", kind = "belt"}, {{x = 29, y = 115}, {x = 28, y = 115}}, {}), true)
    io.write("EF2\n")
end)
H.test("EF3 belt end with a free side is left to Ends.turn_heads", function()
    local w = world({{x = 28, y = 115, seg = belt("stone", W)}, {x = 27, y = 115, seg = belt("circuit", S)}})
    H.equal(guard(w, {flow_id = "stone", kind = "belt"}, {{x = 29, y = 115}, {x = 28, y = 115}}, {}), false)
    io.write("EF3\n")
end)
H.test("EF4 new belt in front of another flow's underground exit is refused; head-on is allowed", function()
    local w = world({{x = 4, y = 121, seg = exit_at("stick", S, 4, 121)}, {x = 4, y = 122, seg = belt("rail", W)}})
    H.equal(guard(w, {flow_id = "rail", kind = "belt"}, {{x = 5, y = 122}, {x = 4, y = 122}}, {}), true)
    local w2 = world({{x = 4, y = 121, seg = exit_at("stick", S, 4, 121)}, {x = 4, y = 122, seg = belt("rail", N)}})
    H.equal(guard(w2, {flow_id = "rail", kind = "belt"}, {{x = 4, y = 123}, {x = 4, y = 122}}, {}), false)
    io.write("EF4\n")
end)
H.done("test_route_end_feed")
