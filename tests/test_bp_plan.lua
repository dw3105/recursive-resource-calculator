--The blueprint plan freezes full-precision machine counts, setup slots, beacon coverage, and balanced plain-data flows.
local H = require "tests.harness"

local Plan = require "logic.bp.plan"

local function run(input)
    local state = Plan.begin(input)
    for _ = 1, 100 do
        if state.done then break end
        Plan.step(state, {ops = 1})
    end
    H.equal(state.done, true, "plan completes within the test bound")
    H.equal(state.result ~= nil, true, "completed plan publishes an IR")
    return state.result
end

local function column(recipe_name, rate, per_machine, amounts)
    return {
        recipe_name = recipe_name,
        net_amounts = amounts or {},
        crafts_per_second_per_machine = per_machine,
    }
end

local function input(round_up, columns, rates, selections, catalog)
    return {
        snapshot = {options = {round_up = round_up}, selection = selections or {}},
        solver_result = {status = "ok", columns = columns, recipe_rates = rates},
        catalog = catalog or {},
    }
end

local function item_port(rate, lane_items_per_second)
    local result = run(input(false,
        {column("make", rate, 1, {['item/output'] = 1})}, {make = rate},
        {{recipe_name = "make", machine = {name = "assembler"}}},
        {belt = {lane_items_per_second = lane_items_per_second}}))
    local port = result.ports[1]
    H.equal(port ~= nil, true, "item output port exists")
    return port
end

local function plain(value, seen, path)
    local value_type = type(value)
    H.equal(value_type == "userdata" or value_type == "function", false, path .. " is executable or a LuaObject")
    if value_type ~= "table" then return end
    H.equal(getmetatable(value), nil, path .. " has no metatable")
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        plain(key, seen, path .. ".<key>")
        plain(child, seen, path .. "." .. tostring(key))
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP1 full precision counts ignore the round-up display checkbox", function()
        local columns = {column("make", 6.2, 1, {['item/output'] = 1})}
        local selections = {{recipe_name = "make", machine = {name = "assembler", quality = "normal"}}}
        local down = run(input(false, columns, {make = 6.2}, selections))
        local up = run(input(true, columns, {make = 6.2}, selections))
        H.equal(down.steps[1].machine_count, 7, "6.2 machines round up to seven")
        H.equal(up.steps[1].machine_count, 7, "round-up display setting does not change physical count")
        H.equal(Plan.machine_count(6.2, 1), 7, "machine_count uses the full-precision requirement")
    end)

    H.test(shape .. " BP2 zero work needs no machine and positive work below one needs one", function()
        local result = run(input(false,
            {column("idle", 0, 1), column("tiny", 0.2, 1)},
            {idle = 0, tiny = 0.2},
            {{recipe_name = "idle", machine = {name = "assembler"}}, {recipe_name = "tiny", machine = {name = "assembler"}}}))
        H.equal(result.steps[1].step_id, "idle", "steps are sorted by id")
        H.equal(result.steps[1].machine_count, 0, "zero-rate step needs no machine")
        H.equal(result.steps[2].machine_count, 1, "positive sub-machine work needs one machine")
        H.equal(result.totals.machines, 1, "totals count whole machines")
        H.equal(result.totals.steps, 2, "totals count planned steps")
    end)

    H.test(shape .. " BP3 module slots and beacon minimum coverage survive in order", function()
        local catalog = {
            entity = {
                assembler = {crafting_speed = 1, energy_usage_w = 100, pollution_per_min = 2},
                beacon = {energy_usage_w = 480, beacon = {distribution_effectivity = 1.5, counter = "same_type"}},
            },
            module = {
                speed = {effects = {speed = 0.2}},
                quality = {effects = {quality = 0.1}},
            },
        }
        local selections = {{recipe_name = "make", machine = {name = "assembler", quality = "normal"},
            modules = {{name = "speed", quality = "normal"}, {name = "speed", quality = "normal"},
                {name = "quality", quality = "normal"}, {name = "speed", quality = "normal"}},
            beacons = {{name = "beacon", quality = "normal", count = 2, sharing = 7,
                modules = {{name = "speed", quality = "normal"}}}}}}
        local result = run(input(false, {column("make", 1, 1, {['item/output'] = 1})}, {make = 1}, selections, catalog))
        local step = result.steps[1]
        H.equal(#step.modules, 3, "module runs retain slot order")
        H.equal(step.modules[1].name, "speed", "first module run survives")
        H.equal(step.modules[1].count, 2, "first module run retains two slots")
        H.equal(step.modules[2].name, "quality", "quality module stays between speed runs")
        H.equal(step.modules[3].name, "speed", "last module run survives")
        H.equal(step.has_quality_module, true, "quality module is identified by its effect")
        H.equal(step.forbids_speed_beacon, true, "quality module forbids speed beacon coverage")
        H.equal(step.beacon_groups[1].count_per_machine, 2, "beacon minimum coverage survives")
        H.equal(step.beacon_groups[1].sharing, 7, "beacon sharing remains information only")
        H.equal(step.beacon_groups[1].count, nil, "sharing is not rewritten as a placement count")
    end)

    H.test(shape .. " BP4 shared intermediate has one flow and consumer shares equal production", function()
        local result = run(input(false,
            {column("producer", 4, 1, {['item/intermediate'] = 1}),
                column("consumer-a", 1, 1, {['item/intermediate'] = -1}),
                column("consumer-b", 3, 1, {['item/intermediate'] = -1})},
            {producer = 4, ['consumer-a'] = 1, ['consumer-b'] = 3},
            {{recipe_name = "producer", machine = {name = "assembler"}},
                {recipe_name = "consumer-a", machine = {name = "assembler"}},
                {recipe_name = "consumer-b", machine = {name = "assembler"}}}))
        local flow
        for _, candidate in ipairs(result.flows) do if candidate.full_name == "item/intermediate" then flow = candidate end end
        H.equal(flow ~= nil, true, "shared intermediate is represented once")
        H.equal(#flow.consumers, 2, "shared intermediate has two consumers")
        H.near(flow.producers[1].share_per_second, 4, "producer makes four per second")
        H.near(flow.consumers[1].share_per_second + flow.consumers[2].share_per_second, 4,
            "consumer shares add up to production")
    end)

    H.test(shape .. " BP5 byproducts and fluids expose the world-side flow", function()
        local result = run(input(false, {column("make", 2, 1,
            {['item/byproduct'] = 1, ['fluid/water'] = 3})}, {make = 2},
            {{recipe_name = "make", machine = {name = "assembler"}}}))
        local byproduct, fluid, output_port, fluid_port
        for _, flow in ipairs(result.flows) do
            if flow.full_name == "item/byproduct" then byproduct = flow end
            if flow.full_name == "fluid/water" then fluid = flow end
        end
        for _, port in ipairs(result.ports) do
            if port.full_name == "item/byproduct" then output_port = port end
            if port.full_name == "fluid/water" then fluid_port = port end
        end
        H.equal(byproduct ~= nil, true, "byproduct has a flow")
        H.equal(byproduct.consumers[1].step_id, "$external", "byproduct is removed externally")
        H.equal(fluid.is_fluid, true, "fluid flow is marked fluid")
        H.equal(output_port.role, "out", "byproduct has an output port")
        H.equal(fluid_port.kind, "fluid", "fluid port has fluid kind")
        H.equal(fluid_port.min_lanes, 1, "fluid port needs one lane")
    end)

    H.test(shape .. " BP6 plan IR is sorted and contains no LuaObjects", function()
        local result = run(input(false,
            {column("z-step", 1, 1, {['item/z'] = 1}), column("a-step", 1, 1, {['item/a'] = 1})},
            {['z-step'] = 1, ['a-step'] = 1},
            {{recipe_name = "z-step", machine = {name = "assembler"}}, {recipe_name = "a-step", machine = {name = "assembler"}}}))
        H.equal(result.steps[1].step_id, "a-step", "steps are sorted")
        H.equal(result.flows[1].flow_id, "item/a", "flows are sorted")
        H.equal(result.ports[1].port_id, "out:item/a", "ports are sorted")
        plain(result, nil, "plan")
    end)

    H.test(shape .. " BP7 item port below one belt lane asks for one", function()
        local port = item_port(9.9, 10)
        H.equal(port.min_lanes, 1, "a sub-lane item rate needs one lane")
    end)

    H.test(shape .. " BP8 item port above one belt lane asks for two", function()
        local port = item_port(12, 10)
        H.equal(port.min_lanes, 2, "a 1.2-lane item rate needs two lanes")
    end)

    H.test(shape .. " BP9 item port at one belt lane stays at one within tolerance", function()
        local port = item_port(10 + 1e-10, 10)
        H.equal(port.min_lanes, 1, "a rate within tolerance of one lane needs one lane")
    end)

    H.test(shape .. " BP10 item port needing three belt lanes asks for three", function()
        local port = item_port(30, 10)
        H.equal(port.min_lanes, 3, "a three-lane item rate needs three lanes")
    end)

    H.test(shape .. " BP11 fluid port always asks for one lane", function()
        local result = run(input(false,
            {column("make", 100, 1, {['fluid/water'] = 1})}, {make = 100},
            {{recipe_name = "make", machine = {name = "assembler"}}},
            {belt = {lane_items_per_second = 10}}))
        local port = result.ports[1]
        H.equal(port ~= nil, true, "fluid output port exists")
        H.equal(port.min_lanes, 1, "fluid rate ignores belt lane capacity")
    end)

    H.test(shape .. " BP12 selected faster belt family lowers the item lane count", function()
        local standard = item_port(24, 10)
        local faster = item_port(24, 20)
        H.equal(standard.min_lanes, 3, "the standard belt needs three lanes")
        H.equal(faster.min_lanes, 2, "the faster belt needs two lanes")
        H.equal(faster.min_lanes < standard.min_lanes, true, "a faster belt lowers the lane count")
    end)
end

H.done("test_bp_plan")
