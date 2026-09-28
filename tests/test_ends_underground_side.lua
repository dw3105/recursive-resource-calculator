--EU1 is red on 0875ac9: gray + magenta grid 9 layered, legalcopilot-dev 2026-09-28 - iron-ore sink tile (13,22) ended
--facing a calcite belt; the turner took the first free side, west, into the side of the same flow's underground
--entrance (12,22): one lane blocked (BP_V_UNDERGROUND_SIDELOAD_BLOCKED). East faces the inserter and simply ends.
package.path = "./?.lua;" .. package.path
local H = require "tests.harness"
local Ends = require "logic.bp.ends"
local Grid = require "logic.bp.grid"
local N, E, W = Grid.NORTH, Grid.EAST, Grid.WEST  --inserter heading as published on the sheet (dir 4)

local function belt(x, y, dir, flow) return {name = "turbo-transport-belt", position = {x = x + 0.5, y = y + 0.5}, dir = dir, flow_id = flow} end

H.test("EU1 a turned end never side-loads an underground entrance, even of its own flow", function()
    local head = belt(13, 22, N, "ore")
    local ug = {name = "turbo-underground-belt", position = {x = 12.5, y = 22.5}, dir = N, flow_id = "ore", ug_role = "input", type = "input"}
    local r = {entities = {head, belt(13, 21, E, "calcite"), ug,
        {name = "bulk-inserter", position = {x = 14.5, y = 22.5}, dir = E}}}
    H.equal(Ends.turn_heads(r), 1)
    H.equal(head.dir, E)
    io.write("EU1\n")
end)
H.test("EU2 an underground entrance straight ahead of the turned heading is fine", function()
    local head = belt(13, 22, N, "ore")
    local ug = {name = "turbo-underground-belt", position = {x = 12.5, y = 22.5}, dir = W, flow_id = "ore", ug_role = "input", type = "input"}
    local r = {entities = {head, belt(13, 21, E, "calcite"), ug}}
    H.equal(Ends.turn_heads(r), 1)
    H.equal(head.dir, W)
    io.write("EU2\n")
end)
H.done("test_ends_underground_side")
