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
H.test("EU3 an end pointing into the side of another flow's underground exit turns away; from behind it stays", function()
    --Round 54 integrator: EM x1 Turn 12 Flip, holmium-ore end (5,13) faced east into the stone exit (6,13) heading
    --south; the engine side-loads onto the exit's open half (holmium onto the stone line).
    local S = Grid.SOUTH
    local head = belt(5, 13, E, "holmium")
    local exit = {name = "underground-belt", position = {x = 6.5, y = 13.5}, dir = S, flow_id = "stone", ug_role = "output", type = "output"}
    local r = {entities = {head, exit, {name = "inserter", position = {x = 5.5, y = 12.5}, dir = S}}}
    H.equal(Ends.turn_heads(r), 1)
    H.equal(head.dir, S)
    local behind = belt(6, 12, S, "holmium")
    local exit2 = {name = "underground-belt", position = {x = 6.5, y = 13.5}, dir = S, flow_id = "stone", ug_role = "output", type = "output"}
    H.equal(Ends.turn_heads({entities = {behind, exit2}}), 0)
    local dead = belt(40, 27, S, "plate")
    local ptg = {name = "pipe-to-ground", position = {x = 40.5, y = 28.5}, dir = E, ug_role = "output"}
    H.equal(Ends.turn_heads({entities = {dead, ptg}}), 0, "a pipe-to-ground exit takes no belt items")
    io.write("EU3\n")
end)
H.done("test_ends_underground_side")
