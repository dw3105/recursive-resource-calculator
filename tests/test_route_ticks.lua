--Tick-sized routing work must preserve the exact entity decisions of a large-budget run.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    local value = {grid = Grid.new(22, 24), catalog = {belt = {belt = "basic-belt", underground = "basic-underground",
        items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}}, blocks = {}, flows = {}}
    for i = 1, 10 do
        local y = 1 + (i - 1) * 2
        local flow = "item/" .. i
        value.blocks[#value.blocks + 1] = {block_id = "s" .. i, machines = {{step_id = "s" .. i}}, x = 1, y = y,
            w = 1, h = 1, ports = {{port_id = "so" .. i, role = "out", kind = "item", flow_id = flow,
                rate_per_second = 1, attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST}}}
        value.blocks[#value.blocks + 1] = {block_id = "c" .. i, machines = {{step_id = "c" .. i}}, x = 8, y = y,
            w = 1, h = 1, ports = {{port_id = "ci" .. i, role = "in", kind = "item", flow_id = flow,
                rate_per_second = 1, attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST}}}
        value.flows[#value.flows + 1] = {flow_id = flow, producers = {{step_id = "s" .. i, share_per_second = 1}},
            consumers = {{step_id = "c" .. i, share_per_second = 1}}}
    end
    return value
end

local function timed_run(slice)
    local started = os.clock()
    local state = Route.begin(input())
    local begin_time = os.clock() - started
    H.equal(begin_time < 0.03, true, "Route.begin remains under 30 ms")
    while not state.done do
        local tick = os.clock()
        Route.step(state, {ops = slice})
        H.equal(os.clock() - tick < 0.03, true, "Route.step remains under 30 ms")
    end
    H.equal(state.ok, true, "synthetic route completes")
    if state.tidy then
        local tidy = Route.tidy_begin(state)
        while not tidy.done do
            local tick = os.clock()
            Route.tidy_step(tidy, {ops = slice})
            H.equal(os.clock() - tick < 0.03, true, "Route.tidy_step remains under 30 ms")
        end
        return tidy.result
    end
    return state.result
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RT1 route ticks preserve entities and stay under 30 ms", function()
        local sliced = timed_run(2000)
        local large = timed_run(100000000)
        H.deep_equal(sliced.entities, large.entities, "tick budget preserves routed entities")
    end)
end
H.done("test_route_ticks")
