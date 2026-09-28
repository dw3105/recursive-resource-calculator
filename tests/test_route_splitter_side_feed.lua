--SP1 is red on c743751: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-28 - the foundry-2 copper-cable path
--came south out of an underground at (42,95) and turned west at (42,96); a later branch made (42,96) a west-facing
--splitter because (43,96) fed it straight from behind. The underground now pointed into the splitter's side, and
--47 belts from foundry 2 fed nothing.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"
local key = Route._coordinate_key
local S, W = Grid.SOUTH, Grid.WEST
local fed = Route._test.splitter_straight_fed

local function belt(dir) return {kind = "belt", flow_id = "cable", flow_ids = {cable = true}, direction = dir, allocations = {}} end
local function world(side)
    local work = {segments_by_cell = {}}
    local cell = belt(W)
    work.segments_by_cell[key(2, 1)] = cell
    work.segments_by_cell[key(3, 1)] = belt(W)
    if side then work.segments_by_cell[key(2, 0)] = side end
    return work, cell
end

H.test("SP1 a turn cell fed from its side cannot become a splitter", function()
    local work, cell = world(belt(S))
    H.equal(fed(work, 2, 1, cell, "cable"), false)
    local exit = belt(S); exit.underground = true; exit.underground_exit_key = key(2, 0); exit.underground_entry_key = key(2, -4)
    work.segments_by_cell[key(2, 0)] = exit
    H.equal(fed(work, 2, 1, cell, "cable"), false)
    io.write("SP1\n")
end)
H.test("SP2 a straight-fed cell with no side feed may become a splitter; a side belt running past does not count", function()
    local work, cell = world(nil)
    H.equal(fed(work, 2, 1, cell, "cable"), true)
    local past = world(belt(W))
    H.equal(fed(past, 2, 1, past.segments_by_cell[key(2, 1)], "cable"), true)
    io.write("SP2\n")
end)
H.done("test_route_splitter_side_feed")
