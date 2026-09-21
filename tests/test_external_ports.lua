--External inputs get one deterministic perimeter slot per demand-sized supply network, while routing may still share one trunk.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Power = require "logic.bp.power"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"
local Serialize = require "logic.bp.serialize"
local Validate = require "logic.bp.validate"

local function stage(result)
    return {done = false, ok = nil, result = result, cursor = {}, progress = {}}
end

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function run_route(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 10000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "external-port route finishes within the test bound")
    return state
end

local function external_three_consumer_input()
    local blocks = {}
    for index, y in ipairs({1, 4, 7}) do
        blocks[#blocks + 1] = {block_id = "consumer-" .. tostring(index),
            machines = {{step_id = "consumer-" .. tostring(index)}}, x = 10, y = y, w = 1, h = 1,
            ports = {{port_id = "consumer-" .. tostring(index) .. "-in", role = "in", kind = "item",
                flow_id = "item/sheet", rate_per_second = 1, attach_dx = -1, attach_dy = 0,
                normal_dir = Grid.EAST, travel_dir = Grid.EAST}}}
    end
    return {
        grid = Grid.new(12, 9),
        catalog = {belt = {belt = "basic-belt", splitter = "basic-splitter", items_per_second = 10,
            lane_items_per_second = 5}},
        --The three rooms are deliberately disconnected. Each consumer therefore needs the perimeter
        --port in its own room; no block or port footprint is enlarged to make the case pass.
        obstacles = {{x = 1, y = 2, w = 11, h = 1, owner = "wall-a"},
            {x = 1, y = 5, w = 11, h = 1, owner = "wall-b"}},
        perimeter_ports = {
            {port_id = "source-a", role = "in", kind = "item", flow_id = "item/sheet", rate_per_second = 3,
                x = 0, y = 1, travel_dir = Grid.EAST},
            {port_id = "source-b", role = "in", kind = "item", flow_id = "item/sheet", rate_per_second = 3,
                x = 0, y = 4, travel_dir = Grid.EAST},
            {port_id = "source-c", role = "in", kind = "item", flow_id = "item/sheet", rate_per_second = 3,
                x = 0, y = 7, travel_dir = Grid.EAST},
        },
        flows = {{flow_id = "item/sheet", producers = {{step_id = "$external", share_per_second = 3}},
            consumers = {{step_id = "consumer-1", share_per_second = 1},
                {step_id = "consumer-2", share_per_second = 1},
                {step_id = "consumer-3", share_per_second = 1}}}},
        blocks = blocks,
    }
end

local function shared_trunk_input()
    local input = external_three_consumer_input()
    input.obstacles = nil
    input.perimeter_ports = {{port_id = "shared-source", role = "in", kind = "item", flow_id = "item/sheet",
        rate_per_second = 3, x = 0, y = 4, travel_dir = Grid.EAST}}
    return input
end

local function external_plan()
    return {
        steps = {{step_id = "one", machine = "assembler", machine_count = 1}},
        ports = {{port_id = "in:item/sheet", role = "in", kind = "item", flow_id = "item/sheet",
            rate_per_second = 3}},
        flows = {{flow_id = "item/sheet", producers = {{step_id = "$external", share_per_second = 3}},
            consumers = {{step_id = "one-a", share_per_second = 1}, {step_id = "one-b", share_per_second = 1},
                {step_id = "one-c", share_per_second = 1}}}},
    }
end

--Search doubles keep these assertions on perimeter allocation. Route receives the generated input, so this
--also checks the hand-off without coupling the test to grouping, power coverage or serialization policy.
local function capture_generated_ports(grid)
    local route_input
    local originals = {
        groups_begin = Groups.begin, groups_step = Groups.step, materialize = Groups.materialize,
        pack_begin = Pack.begin, pack_step = Pack.step, route_begin = Route.begin, route_step = Route.step,
        power_begin = Power.begin, power_step = Power.step, validate_begin = Validate.begin,
        validate_step = Validate.step, serialize_begin = Serialize.begin, serialize_step = Serialize.step,
    }
    local candidate = {id = "candidate", blocks = {{id = "block", block_id = "block", w = 1, h = 1}}}
    local function complete(result)
        local result_stage = stage(result)
        result_stage.result = result
        return result_stage
    end
    local function finish_stage(result, ok)
        return function(state, budget)
            if budget.ops > 0 then
                budget.ops = budget.ops - 1
                state.result, state.done, state.ok = result, true, ok ~= false
            end
            return state
        end
    end

    Groups.begin = function() return stage() end
    Groups.step = function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result, state.done, state.ok = {candidates = {clone(candidate)}}, true, true
        end
        return state
    end
    Groups.materialize = function(block, placement)
        return {envelope = {x = placement.x, y = placement.y, w = block.w, h = block.h, dir = Grid.NORTH},
            entities = {}, ports = {}}
    end
    Pack.begin = function(input)
        local result = stage()
        result.placement = {block_id = input.blocks[1].block_id, x = 3, y = 3, w = 1, h = 1}
        return result
    end
    Pack.step = function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {placements = {state.placement}}
            state.done, state.ok = true, true
        end
        return state
    end
    Route.begin = function(input)
        route_input = clone(input)
        return complete({entities = {}, segments = {}, bindings = {}})
    end
    Route.step = finish_stage({entities = {}, segments = {}, bindings = {}}, true)
    Power.begin = function() return complete({entities = {}, wires = {}}) end
    Power.step = finish_stage({entities = {}, wires = {}}, true)
    Validate.begin = function() return complete({score = {beacon_count = 0, footprint_area = 1}}) end
    Validate.step = finish_stage({score = {beacon_count = 0, footprint_area = 1}, metrics = {}}, true)
    Serialize.begin = function(candidate_value) return complete(candidate_value) end
    Serialize.step = finish_stage(route_input and {candidate = route_input} or {}, true)

    local input = {plan_result = external_plan(), grids = {grid}, include_roboports = false,
        catalog = {}, settings = {input_edge = "left", output_edge = "top"}, port_pitch = 1}
    local ok, state_or_error = pcall(function()
        local state = Search.begin(input)
        local ticks = 0
        while not state.done and ticks < 1000 do
            ticks = ticks + 1
            Search.step(state, {ops = 1000})
        end
        H.equal(state.done, true, "generated-port search finishes within the test bound")
        return state
    end)

    Groups.begin, Groups.step, Groups.materialize = originals.groups_begin, originals.groups_step, originals.materialize
    Pack.begin, Pack.step = originals.pack_begin, originals.pack_step
    Route.begin, Route.step = originals.route_begin, originals.route_step
    Power.begin, Power.step = originals.power_begin, originals.power_step
    Validate.begin, Validate.step = originals.validate_begin, originals.validate_step
    Serialize.begin, Serialize.step = originals.serialize_begin, originals.serialize_step
    if not ok then error(state_or_error, 0) end
    return state_or_error, route_input
end

local function distinct_cells(ports)
    local seen = {}
    for _, port in ipairs(ports or {}) do
        local key = tostring(port.x) .. ":" .. tostring(port.y)
        if seen[key] then return false end
        seen[key] = true
    end
    return true
end

local function tiny_many_demands_input()
    return {
        grid = Grid.new(2, 2),
        catalog = {belt = {belt = "basic-belt", items_per_second = 10, lane_items_per_second = 10}},
        obstacles = {{x = 1, y = 0, w = 1, h = 2, owner = "wall"}},
        blocks = {{block_id = "consumers", x = 1, y = 1, w = 1, h = 1, ports = {
            {port_id = "consumer-1-in", step_id = "consumer-1", role = "in", kind = "item",
                flow_id = "item/tiny", rate_per_second = 1, x = 0, y = 1, travel_dir = Grid.SOUTH},
            {port_id = "consumer-2-in", step_id = "consumer-2", role = "in", kind = "item",
                flow_id = "item/tiny", rate_per_second = 1, x = 0, y = 1, travel_dir = Grid.SOUTH},
            {port_id = "consumer-3-in", step_id = "consumer-3", role = "in", kind = "item",
                flow_id = "item/tiny", rate_per_second = 1, x = 0, y = 1, travel_dir = Grid.SOUTH},
        }}},
        perimeter_ports = {{port_id = "tiny-source", role = "in", kind = "item", flow_id = "item/tiny",
            rate_per_second = 3, x = 0, y = 0, travel_dir = Grid.SOUTH}},
        flows = {{flow_id = "item/tiny", producers = {{step_id = "$external", share_per_second = 3}},
            consumers = {{step_id = "consumer-1", share_per_second = 1},
                {step_id = "consumer-2", share_per_second = 1},
                {step_id = "consumer-3", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " three consumers receive one demand-sized external port", function()
        local state, route_input = capture_generated_ports({w = 8, h = 8})
        local ports = route_input and route_input.perimeter_ports or {}
        H.equal(state.ok, true, "enough perimeter slots publish a candidate")
        H.equal(#ports, 1, "one external flow starts with one terminal, not one per consumer")
        H.equal(distinct_cells(ports), true, "generated external ports never stack")
        H.equal(ports[1].port_id, "in:item/sheet", "the first generated port keeps the plan id")
        H.equal(ports[1].terminal_reason, "base supply network", "the base terminal records its network role")
    end)

    H.test(shape .. " one reachable external port remains the shared trunk", function()
        local state = run_route(shared_trunk_input())
        H.equal(state.ok, true, "one external port reaches all consumers")
        H.equal(#state.result.port_bindings, 3, "all three consumer demands are bound")
        for _, binding in ipairs(state.result.port_bindings) do
            H.equal(binding.source_port_id, "shared-source", "the shared source is preferred")
        end
        local shared
        for _, segment in ipairs(state.result.segments) do
            if #segment.allocations >= 2 then shared = segment break end
        end
        H.equal(shared ~= nil, true, "the shared source uses an allocated trunk")
    end)

    H.test(shape .. " three separated consumers select the reachable external port", function()
        local state = run_route(external_three_consumer_input())
        H.equal(state.ok, true, "three perimeter ports route three consumers")
        local used = {}
        for _, binding in ipairs(state.result.port_bindings) do used[binding.source_port_id] = true end
        H.equal(used["source-a"] and used["source-b"] and used["source-c"], true,
            "each separated room selects its own source port")
    end)

    H.test(shape .. " one demand-sized terminal fits the small edge", function()
        local state, route_input = capture_generated_ports({w = 2, h = 2})
        local ports = route_input and route_input.perimeter_ports or (state.work and state.work.perimeter_ports) or {}
        H.equal(state.ok, true, "one demand-sized terminal fits the available edge")
        H.equal(#ports, 1, "only one terminal is requested for aggregate demand")
        H.equal(distinct_cells(ports), true, "generated external ports never stack")
    end)

    H.test(shape .. " generated external ports are deterministic", function()
        local _, first = capture_generated_ports({w = 8, h = 8})
        local _, second = capture_generated_ports({w = 8, h = 8})
        H.deep_equal(first and first.perimeter_ports, second and second.perimeter_ports,
            "the same input produces the same generated ports")
    end)

    H.test(shape .. " more demands than one reachable component's cells retain a usable share", function()
        local state = run_route(tiny_many_demands_input())
        H.equal(#state.work.demands > 2, true, "the run has more demands than its two-cell reachable component")
        H.equal(state.work.max_expansions, 4096 * #state.work.demands,
            "the default budget gives every demand a derived sweep allowance")
        H.equal(state.ok, true, "all tiny shared demands finish inside the cumulative budget")
        H.equal(#state.result.port_bindings, 3, "every tiny demand receives its share")
    end)

    H.test(shape .. " a hopeless many-demand run remains bounded", function()
        local input = tiny_many_demands_input()
        input.max_expansions = 25
        input.grid = Grid.new(8, 8)
        input.obstacles = {{x = 0, y = 4, w = 8, h = 1, owner = "wall"}}
        input.blocks[1].x, input.blocks[1].y = 7, 6
        for _, port in ipairs(input.blocks[1].ports) do port.x, port.y = 7, 7 end
        input.perimeter_ports[1].x, input.perimeter_ports[1].y = 0, 0
        local state = run_route(input)
        H.equal(state.ok, false, "the isolated sink is rejected")
        H.equal(state.errors[1].code, "BP_R_EXPANSIONS", "the explicit cumulative bound is reported")
        H.equal(state.counters.expansions, 25, "the hopeless run consumes only its configured bound")
    end)
end

H.done("test_external_ports")
