--A plan entry names a step, but a block may publish one transport port for every hand serving that step.
--Every published port must receive its own binding and its share of the step's obligation.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function run(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 10000 do
        ticks = ticks + 1
        Route.step(state, {ops = 10000})
    end
    H.equal(state.done, true, "per-hand route reaches a terminal state")
    return state
end

local function base()
    return {
        grid = Grid.new(14, 7),
        catalog = {belt = {belt = "basic-belt", splitter = "basic-splitter", items_per_second = 20}},
        blocks = {},
        flows = {{flow_id = "item/hand-fed", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 10}},
            consumers = {{step_id = "sink", share_per_second = 10}}}},
    }
end

local function consumer_ports(rates)
    local input = base()
    input.blocks = {
        {block_id = "source", machines = {{step_id = "source"}}, x = 2, y = 3, w = 1, h = 1, ports = {{
            port_id = "source-out", role = "out", kind = "item", flow_id = "item/hand-fed", rate_per_second = 10,
            x = 3, y = 3, travel_dir = Grid.EAST,
        }}},
        {block_id = "sink", machines = {{step_id = "sink"}}, x = 11, y = 1, w = 1, h = 3, ports = {
            {port_id = "sink-hand-1", role = "in", kind = "item", flow_id = "item/hand-fed",
                rate_per_second = rates[1], x = 10, y = 1, travel_dir = Grid.EAST},
            {port_id = "sink-hand-2", role = "in", kind = "item", flow_id = "item/hand-fed",
                rate_per_second = rates[2], x = 10, y = 3, travel_dir = Grid.EAST},
        }},
    }
    return input
end

local function producer_ports(rates)
    local input = base()
    input.blocks = {
        {block_id = "source", machines = {{step_id = "source"}}, x = 2, y = 1, w = 1, h = 3, ports = {
            {port_id = "source-hand-1", role = "out", kind = "item", flow_id = "item/hand-fed",
                rate_per_second = rates[1], x = 3, y = 1, travel_dir = Grid.EAST},
            {port_id = "source-hand-2", role = "out", kind = "item", flow_id = "item/hand-fed",
                rate_per_second = rates[2], x = 3, y = 3, travel_dir = Grid.EAST},
        }},
        {block_id = "sink", machines = {{step_id = "sink"}}, x = 11, y = 2, w = 1, h = 1, ports = {{
            port_id = "sink-in", role = "in", kind = "item", flow_id = "item/hand-fed", rate_per_second = 10,
            x = 10, y = 2, travel_dir = Grid.EAST,
        }}},
    }
    return input
end

local function binding_rates(state, field)
    local result = {}
    for _, binding in ipairs(state.result and state.result.bindings or {}) do
        local port_id = binding[field]
        if port_id ~= nil then result[port_id] = (result[port_id] or 0) + binding.rate_per_second end
    end
    return result
end

local function assert_port_rates(state, field, expected, label)
    H.equal(state.ok, true, label .. " route succeeds")
    local actual = binding_rates(state, field)
    for port_id, rate in pairs(expected) do
        H.near(actual[port_id], rate, label .. " binds " .. port_id)
    end
    local count = 0
    for _, _ in pairs(actual) do count = count + 1 end
    H.equal(count, 2, label .. " binds both published ports")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BH1 one consumer binding per weighted hand port", function()
        local state = run(consumer_ports({3, 7}))
        assert_port_rates(state, "sink_port_id", {['sink-hand-1'] = 3, ['sink-hand-2'] = 7}, "weighted consumer")
    end)

    H.test(shape .. " BH2 one producer binding per weighted hand port", function()
        local state = run(producer_ports({3, 7}))
        assert_port_rates(state, "source_port_id", {['source-hand-1'] = 3, ['source-hand-2'] = 7}, "weighted producer")
    end)

    H.test(shape .. " BH3 missing port rates divide a plan entry evenly", function()
        local state = run(consumer_ports({nil, nil}))
        assert_port_rates(state, "sink_port_id", {['sink-hand-1'] = 5, ['sink-hand-2'] = 5}, "even consumer")
    end)

    H.test(shape .. " BH4 a zero-share port fails by port id", function()
        local input = consumer_ports({5, 5})
        input.flows[1].producers[1].share_per_second = 0
        input.flows[1].consumers[1].share_per_second = 0
        local state = run(input)
        H.equal(state.ok, false, "a port with no demand rejects the candidate")
        H.equal(state.errors[1].code, "BP_R_PORT_BLOCKED", "zero-share port uses the route port error")
        H.equal(state.errors[1].port_id, "sink-hand-1", "zero-share failure names the first port")
    end)
end

H.done("test_bindings_per_hand")
