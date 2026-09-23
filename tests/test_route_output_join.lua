--A machine output whose port tile sits right beside a laid run of its own flow joins that run with ONE belt.
--The player's fix, 2026-09-23 on legalcopilot-dev: science machine 4 drops at (16,1) with its port heading
--NORTH; the router forced that heading and walked a 9-entity loop round (18,0)..(18,2) and under
--(17,2)->(15,2), where one belt at (16,1) facing WEST into the trunk at (15,1) does the job
--(~/share/RRC/player-red-science-1s-20260923-fixed.txt, 249 entities against our 257).
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    return {
        grid = Grid.new(10, 8),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", splitter = "basic-splitter",
            items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}},
        blocks = {
            --Producer A: port tile (4,5), heading NORTH, straight up column x=4 to the door.
            {block_id = "a", machines = {{step_id = "a"}}, x = 4, y = 6, w = 1, h = 1, ports = {
                {port_id = "a-out", role = "out", kind = "item", flow_id = "item/pack", rate_per_second = 1,
                    attach_dx = 0, attach_dy = -1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH},
            }},
            --Producer B: port tile (5,2) right beside that column, heading NORTH like science machine 4.
            {block_id = "b", machines = {{step_id = "b"}}, x = 6, y = 2, w = 1, h = 1, ports = {
                {port_id = "b-out", role = "out", kind = "item", flow_id = "item/pack", rate_per_second = 1,
                    attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.NORTH},
            }},
        },
        perimeter_ports = {{port_id = "out:item/pack", role = "out", kind = "item", flow_id = "item/pack",
            rate_per_second = 2, x = 4, y = 0, travel_dir = Grid.NORTH}},
        flows = {{flow_id = "item/pack", is_fluid = false,
            producers = {{step_id = "a", share_per_second = 1}, {step_id = "b", share_per_second = 1}},
            consumers = {{step_id = "$external", share_per_second = 2}}}},
    }
end

local function run()
    local state = Route.begin(input())
    local ticks = 0
    while not state.done and ticks < 600 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route finishes")
    return state
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " OJ1 an output beside its own trunk joins it with one belt", function()
        local state = run()
        H.equal(state.ok, true, "both producers reach the door")
        if not state.ok then return end
        local off_column, at_port = 0, nil
        for _, entity in ipairs(state.result.entities or {}) do
            local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
            if x ~= 4 then off_column = off_column + 1 end
            if x == 5 and y == 2 then at_port = entity end
            print(string.format("%s OJ1 %s (%d,%d) dir=%s", shape, tostring(entity.name), x, y, tostring(entity.direction)))
        end
        H.equal(off_column, 1, "producer B adds exactly one belt beside the column")
        H.equal(at_port and at_port.direction, Grid.WEST, "that belt faces WEST into the trunk")
    end)

    H.test(shape .. " OJ2 a door keeps its own heading", function()
        local state = run()
        if not state.ok then return end
        for _, entity in ipairs(state.result.entities or {}) do
            if math.floor(entity.position.x) == 4 and math.floor(entity.position.y) == 0 then
                H.equal(entity.direction, Grid.NORTH, "the drain belt points off the edge")
            end
        end
    end)
end

H.done("test_route_output_join")
