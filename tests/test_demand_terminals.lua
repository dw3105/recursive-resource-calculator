--Demand-sized external terminals.  Rates decide capacity; entry count matters only when a legal branching
--limit is explicitly supplied.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Power = require "logic.bp.power"
local Route = require "logic.bp.route"
local Search = require "logic.bp.search"
local Serialize = require "logic.bp.serialize"
local Validate = require "logic.bp.validate"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function plan_network(port, flow)
    return {work = {input = {}, plan_result = {ports = {port}, flows = {flow}}}}
end

local function input_port(rate, capacity, role)
    return {port_id = "terminal", role = role or "in", kind = "item", flow_id = "item/ore",
        rate_per_second = rate, capacity_per_second = capacity}
end

local function input_flow(rate, role, branches)
    local consumers, producers = {}, {}
    if role == "out" then
        for index = 1, branches or 1 do producers[#producers + 1] = {step_id = "producer-" .. index, share_per_second = rate / (branches or 1)} end
        consumers = {{step_id = "$external", share_per_second = rate}}
    else
        producers = {{step_id = "$external", share_per_second = rate}}
        for index = 1, branches or 1 do consumers[#consumers + 1] = {step_id = "consumer-" .. index, share_per_second = rate / (branches or 1)} end
    end
    return {flow_id = "item/ore", producers = producers, consumers = consumers}
end

local function sizing(port, flow, input)
    local state = plan_network(port, flow)
    state.work.input = input or {}
    local network = {port = port, ports = {port}, flow = flow, role = port.role}
    return Search.terminals_for_demand(state, network)
end

local function stage(result, ok)
    return {done = true, ok = ok ~= false, result = result or {}, progress = {phase = "done", done_units = 1, total_units = 1}}
end

--Exercise the private generated-port path through Search.  This is deliberately the first case: the lane's
--named mutation replaces the production sizing call, and must make this assertion fail.
local function generated(rate, capacity)
    local originals = {
        groups_begin = Groups.begin, groups_step = Groups.step, materialize = Groups.materialize,
        pack_begin = Pack.begin, pack_step = Pack.step, route_begin = Route.begin, route_step = Route.step,
        power_begin = Power.begin, power_step = Power.step, validate_begin = Validate.begin,
        validate_step = Validate.step, serialize_begin = Serialize.begin, serialize_step = Serialize.step,
    }
    local seen_ports
    local candidate = {id = "candidate", blocks = {{id = "block", block_id = "block", w = 1, h = 1}}}
    Groups.begin = function() return {done = false, ok = nil, result = nil, cursor = {}, progress = {}} end
    Groups.step = function(state, budget)
        budget.ops = budget.ops - 1
        state.result, state.done, state.ok = {candidates = {clone(candidate)}}, true, true
        return state
    end
    Groups.materialize = function(block, placement)
        return {envelope = {x = placement.x, y = placement.y, w = block.w, h = block.h, dir = Grid.NORTH}, entities = {}, ports = {}}
    end
    Pack.begin = function(input)
        return {done = false, ok = nil, result = nil, cursor = {}, progress = {}, placement = {
            block_id = input.blocks[1].block_id, x = 2, y = 2, w = 1, h = 1}}
    end
    Pack.step = function(state, budget)
        budget.ops = budget.ops - 1
        state.result, state.done, state.ok = {placements = {state.placement}}, true, true
        return state
    end
    Route.begin = function(input)
        seen_ports = clone(input.perimeter_ports)
        return stage({entities = {}, segments = {}, bindings = {}})
    end
    Route.step = function() end
    Power.begin = function() return stage({entities = {}, wires = {}}) end
    Power.step = function() end
    Validate.begin = function() return stage({score = {beacon_count = 0, production_area = 1}}) end
    Validate.step = function() end
    Serialize.begin = function() return stage({entities = {}}) end
    Serialize.step = function() end

    local port = input_port(rate, capacity)
    local state = Search.begin({plan_result = {ports = {port}, flows = {input_flow(rate, "in", 1)}},
        grids = {{w = 8, h = 8}}, include_roboports = false, settings = {input_edge = "left", output_edge = "top"}})
    local ticks = 0
    while not state.done and ticks < 100 do
        ticks = ticks + 1
        Search.step(state, {ops = 1000})
    end

    Groups.begin, Groups.step, Groups.materialize = originals.groups_begin, originals.groups_step, originals.materialize
    Pack.begin, Pack.step = originals.pack_begin, originals.pack_step
    Route.begin, Route.step = originals.route_begin, originals.route_step
    Power.begin, Power.step = originals.power_begin, originals.power_step
    Validate.begin, Validate.step = originals.validate_begin, originals.validate_step
    Serialize.begin, Serialize.step = originals.serialize_begin, originals.serialize_step
    return state, seen_ports
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " DT1 aggregate rate sizes generated terminals", function()
        local state, ports = generated(25, 10)
        H.equal(state.done, true, "generated terminal search reaches a terminal state")
        H.equal(state.ok, true, "generated terminal search succeeds")
        H.equal(#ports, 3, "25 per second at capacity 10 needs three terminals")
        H.equal(ports[2].terminal_reason, "capacity", "the second terminal names capacity as its reason")
        H.equal(ports[3].terminal_reason_record.capacity_per_second, 10, "the extra terminal records its capacity")
    end)

    H.test(shape .. " DT2 many consumers below capacity stay one terminal", function()
        local value = sizing(input_port(10, 20), input_flow(10, "in", 10))
        H.equal(value.count, 1, "headcount never inflates a terminal below capacity")
        H.equal(value.demand_per_second, 10, "aggregate demand is the sum of rates")
    end)

    H.test(shape .. " DT3 capacity boundary rounds up only when crossed", function()
        H.equal(sizing(input_port(20, 10), input_flow(20, "in", 1)).count, 2, "exactly two capacity units are required")
        H.equal(sizing(input_port(19.999, 10), input_flow(19.999, "in", 1)).count, 2,
            "a fractional demand still rounds to two terminals")
    end)

    H.test(shape .. " DT4 output terminals use aggregate producer demand", function()
        local value = sizing(input_port(21, 10, "out"), input_flow(21, "out", 3))
        H.equal(value.count, 3, "output demand uses producers rather than consumer headcount")
        H.equal(value.demand_per_second, 21, "output producer rates aggregate to demand")
    end)

    H.test(shape .. " DT5 explicit legal branching can require terminals", function()
        local value = sizing(input_port(5, 100), input_flow(5, "in", 5), {max_branches_per_terminal = 2})
        H.equal(value.count, 3, "five branches at two per terminal need three terminals")
        H.equal(value.reasons[1].kind, "feasibility", "branching is recorded as feasibility")
    end)

    H.test(shape .. " DT6 capacity and branching reasons are both retained", function()
        local value = sizing(input_port(25, 10), input_flow(25, "in", 5), {max_branches_per_terminal = 2})
        H.equal(value.count, 3, "the larger of capacity and branching requirements wins")
        H.equal(#value.reasons, 2, "both independent reasons remain recorded")
    end)

    H.test(shape .. " DT7 compatible network starts at one terminal", function()
        local value = sizing(input_port(1, 1), input_flow(1, "in", 50))
        H.equal(value.count, 1, "a compatible supply network starts with one terminal")
        H.equal(value.reasons[1], nil, "no extra terminal has an invented reason")
    end)

    H.test(shape .. " DT8 absent capacity never becomes headcount sizing", function()
        local value = sizing(input_port(100, nil), input_flow(100, "in", 100))
        H.equal(value.count, 1, "unknown capacity keeps one terminal instead of guessing from headcount")
        H.equal(value.capacity_source, "unbounded", "the missing capacity is named")
    end)

    H.test(shape .. " DT9 every extra terminal carries a recorded reason", function()
        local state, ports = generated(31, 10)
        H.equal(state.ok, true, "the reason-recording search succeeds")
        H.equal(#ports, 4, "31 per second at capacity 10 needs four terminals")
        for index = 2, #ports do
            H.equal(type(ports[index].terminal_reason_record), "table", "terminal " .. index .. " carries a reason record")
        end
    end)
end

H.done("test_demand_terminals")
