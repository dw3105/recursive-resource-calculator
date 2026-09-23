--Re-route pass: once every path exists, each is lifted and searched again with a free first heading, and
--the new path is kept only when it lays fewer entities.  The player, 2026-09-23 on legalcopilot-dev, "Why
--this bend?": furnace 4's output at (17,48), port heading SOUTH, walked (17,49)..(13,49) back up into the
--trunk; the straight (17,48)..(14,48) is two belts fewer.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    return {
        grid = Grid.new(10, 6),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
            items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}},
        blocks = {
            --Producer: output port tile (7,2), port heading SOUTH, like the furnace row's outputs.
            {block_id = "p", machines = {{step_id = "p"}}, x = 7, y = 1, w = 1, h = 1, ports = {
                {port_id = "p-out", role = "out", kind = "item", flow_id = "item/plate", rate_per_second = 1,
                    attach_dx = 0, attach_dy = 1, normal_dir = Grid.NORTH, travel_dir = Grid.SOUTH},
            }},
            --Consumer on the same row, its input tile (2,2) entered heading WEST.
            {block_id = "c", machines = {{step_id = "c"}}, x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "c-in", role = "in", kind = "item", flow_id = "item/plate", rate_per_second = 1,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.WEST},
            }},
        },
        flows = {{flow_id = "item/plate", is_fluid = false,
            producers = {{step_id = "p", share_per_second = 1}},
            consumers = {{step_id = "c", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RI1 an output on the consumer's row runs straight along it", function()
        local state = Route.begin(input())
        local ticks = 0
        while not state.done and ticks < 600 do ticks = ticks + 1; Route.step(state, {ops = 100000}) end
        H.equal(state.ok, true, "the route completes")
        if not state.ok then return end
        local off_row, count = 0, 0
        for _, entity in ipairs(state.result.entities or {}) do
            count = count + 1
            local y = math.floor(entity.position.y)
            if y ~= 2 then off_row = off_row + 1 end
            print(string.format("%s RI1 %s (%d,%d) dir=%s", shape, tostring(entity.name),
                math.floor(entity.position.x), y, tostring(entity.direction)))
        end
        H.equal(off_row, 0, "no belt leaves the row")
        H.equal(count, 6, "(7,2) to (2,2) is six belts")
    end)
end

H.done("test_route_improve")
