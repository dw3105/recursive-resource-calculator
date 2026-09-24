--Tick-sized routing work must preserve the exact entity decisions of a large-budget run.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function input()
    local value = {grid = Grid.new(22, 24), catalog = {belt = {belt = "basic-belt", underground = "basic-underground",
        items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 5}}, blocks = {}, flows = {}}
    for group = 1, 5 do
        local sy, cy = 1 + (group - 1) * 4, 1 + (group - 1) * 4
        local source_ports, consumer_ports = {}, {}
        local source_id, consumer_id = "s" .. group, "c" .. group
        for lane = 0, 3 do
            local flow = "item/" .. ((group - 1) * 4 + lane + 1)
            source_ports[#source_ports + 1] = {port_id = "so" .. flow, role = "out", kind = "item", flow_id = flow,
                rate_per_second = 1, attach_dx = 1, attach_dy = lane, normal_dir = Grid.WEST, travel_dir = Grid.EAST}
            consumer_ports[#consumer_ports + 1] = {port_id = "ci" .. flow, role = "in", kind = "item", flow_id = flow,
                rate_per_second = 1, attach_dx = -1, attach_dy = lane, normal_dir = Grid.EAST, travel_dir = Grid.EAST}
            value.flows[#value.flows + 1] = {flow_id = flow, producers = {{step_id = source_id, share_per_second = 1}},
                consumers = {{step_id = consumer_id, share_per_second = 1}}}
        end
        value.blocks[#value.blocks + 1] = {block_id = source_id, machines = {{step_id = source_id}}, x = 1, y = sy,
            w = 1, h = 4, ports = source_ports}
        value.blocks[#value.blocks + 1] = {block_id = consumer_id, machines = {{step_id = consumer_id}}, x = 5, y = cy,
            w = 1, h = 4, ports = consumer_ports}
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
        local elapsed = os.clock() - tick
        H.equal(elapsed < 0.03, true, "Route.step remains under 30 ms (" .. tostring(elapsed) .. "s, "
            .. tostring(state.progress.phase) .. ", build flow " .. tostring(state.cursor.flow_index) .. ")")
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
