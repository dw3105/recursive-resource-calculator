--Network-level route proofs: the emitted graph must describe what the product can physically travel.
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
    H.equal(state.done, true, "network route reaches a terminal state")
    return state
end

local function pipe_pair_input(extra)
    local input = {
        grid = Grid.new(10, 3),
        catalog = {pipe = {pipe = "pipe", underground = "pipe-to-ground", throughput_per_second = 100,
            underground_max_distance = 6}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 1, w = 1, h = 1, ports = {{
                port_id = "source-fluid", role = "out", kind = "fluid", flow_id = "fluid/water", rate_per_second = 2,
                attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
                connection = {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 6},
            }}},
            {block_id = "sink", machines = {{step_id = "sink"}}, x = 7, y = 1, w = 1, h = 1, ports = {{
                port_id = "sink-fluid", role = "in", kind = "fluid", flow_id = "fluid/water", rate_per_second = 2,
                attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
                connection = {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 6},
            }}},
        },
        flows = {{flow_id = "fluid/water", is_fluid = true,
            producers = {{step_id = "source", share_per_second = 2}},
            consumers = {{step_id = "sink", share_per_second = 2}}}},
    }
    for key, value in pairs(extra or {}) do input[key] = value end
    return input
end

local function belt_pair_input()
    local input = pipe_pair_input()
    input.catalog = {belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 20,
        underground_max_distance = 6}}
    input.blocks[1].ports[1].kind = "item"
    input.blocks[1].ports[1].flow_id = "item/ore"
    input.blocks[1].ports[1].connection = {connection_type = "underground", direction = Grid.EAST,
        max_underground_distance = 6}
    input.blocks[2].ports[1].kind = "item"
    input.blocks[2].ports[1].flow_id = "item/ore"
    input.blocks[2].ports[1].connection = {connection_type = "underground", direction = Grid.WEST,
        max_underground_distance = 6}
    input.flows[1] = {flow_id = "item/ore", is_fluid = false,
        producers = {{step_id = "source", share_per_second = 2}},
        consumers = {{step_id = "sink", share_per_second = 2}}}
    return input
end

local function belt_network_input()
    local input = {
        grid = Grid.new(12, 7),
        catalog = {belt = {belt = "basic-belt", splitter = "basic-splitter", items_per_second = 10,
            underground = "basic-underground", underground_max_distance = 5}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 3, w = 1, h = 1, ports = {{
                port_id = "source-out", role = "out", kind = "item", flow_id = "item/shared", rate_per_second = 8,
                attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
            }}},
            {block_id = "near", machines = {{step_id = "near"}}, x = 8, y = 2, w = 1, h = 1, ports = {{
                port_id = "near-in", role = "in", kind = "item", flow_id = "item/shared", rate_per_second = 4,
                attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
            }}},
            {block_id = "far", machines = {{step_id = "far"}}, x = 10, y = 5, w = 1, h = 1, ports = {{
                port_id = "far-in", role = "in", kind = "item", flow_id = "item/shared", rate_per_second = 4,
                attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
            }}},
        },
        flows = {{flow_id = "item/shared", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 8}},
            consumers = {{step_id = "near", share_per_second = 4}, {step_id = "far", share_per_second = 4}}}},
    }
    return input
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RN1 pipe-to-ground endpoints face opposite ways and carry no type", function()
        local state = run(pipe_pair_input())
        H.equal(state.ok, true, "the facing pipe pair routes")
        H.equal(#state.result.entities, 2, "the pipe route emits one pair")
        local entrance, exit = state.result.entities[1], state.result.entities[2]
        H.equal(entrance.ug_role, "input", "the source is the pipe entrance")
        H.equal(exit.ug_role, "output", "the sink is the pipe exit")
        H.equal(entrance.direction, Grid.EAST, "the entrance points downstream")
        H.equal(exit.direction, Grid.WEST, "the exit points upstream")
        H.equal(entrance.type, nil, "pipe entrance has no belt type")
        H.equal(exit.type, nil, "pipe exit has no belt type")
        H.equal(entrance.ug_pair_id, exit.id, "pipe pair points forward")
        H.equal(exit.ug_pair_id, entrance.id, "pipe pair points back")
    end)

    H.test(shape .. " RN2 underground belts keep travel direction and input/output types", function()
        local state = run(belt_pair_input())
        H.equal(state.ok, true, "the belt pair routes")
        local entrance, exit = state.result.entities[1], state.result.entities[2]
        H.equal(entrance.direction, Grid.EAST, "belt entrance travels downstream")
        H.equal(exit.direction, Grid.EAST, "belt exit keeps travel direction")
        H.equal(entrance.type, "input", "belt entrance has input type")
        H.equal(exit.type, "output", "belt exit has output type")
    end)

    H.test(shape .. " RN3 direction-aware budget publishes the full frontier state model", function()
        local state = Route.begin(belt_pair_input())
        H.equal(state.work.expansion_state_space.directions, 4, "frontier tracks arrival heading")
        H.equal(state.work.expansion_state_space.kinds, 2, "frontier tracks transport kind")
        H.equal(state.work.expansion_state_space.underground_modes, 2, "frontier tracks underground mode")
        H.equal(state.work.expansion_state_space.direction_orders, 4, "frontier keeps deterministic orders")
        H.equal(state.work.max_expansions, math.max(4096, 10 * 3 * 4 * 2 * 2 * 4),
            "budget is derived from the expanded state space")
    end)

    H.test(shape .. " RN4 same-flow routing seeks a shared trunk and counts both allocations", function()
        local state = run(belt_network_input())
        H.equal(state.ok, true, "the shared network routes")
        local shared, allocation_total = false, 0
        for _, segment in ipairs(state.result.segments) do
            if #segment.allocations > 1 then shared = true end
            for _, allocation in ipairs(segment.allocations) do allocation_total = allocation_total + allocation.rate_per_second end
        end
        H.equal(shared, true, "at least one segment is reused by the same flow")
        H.equal(allocation_total > 0, true, "shared allocations carry real demand")
    end)

    H.test(shape .. " RN5 route audit leaves every entity attached to a live obligation", function()
        local state = run(belt_network_input())
        H.equal(state.ok, true, "audited network routes")
        local live = {}
        for _, segment in ipairs(state.result.segments) do
            H.equal(#segment.allocations > 0, true, "every published segment has an allocation")
            live[segment.segment_id] = true
        end
        for _, entity in ipairs(state.result.entities) do
            H.equal(live[entity.segment_id], true, "every entity serves a published segment")
        end
        H.equal(state.counters.discarded_geometry, 0, "successful completion has zero abandoned geometry")
    end)

    H.test(shape .. " RN6 reversed underground connections are rejected without loose geometry", function()
        local input = pipe_pair_input()
        input.blocks[1].ports[1].connection.direction = Grid.WEST
        input.blocks[2].ports[1].connection.direction = Grid.EAST
        local state = run(input)
        H.equal(state.ok, false, "reversed pipe connections do not route")
        H.equal(state.errors[1].code, "BP_R_NO_PATH", "reversed pipe reports no path")
        H.equal(#state.work.entities, 0, "failed pipe route leaves no geometry")
    end)

    H.test(shape .. " RN7 a boundary attachment is blocked instead of silently mirrored", function()
        local input = belt_pair_input()
        input.blocks[1].x = 0
        input.blocks[1].ports[1].attach_dx = -1
        input.blocks[1].ports[1].normal_dir = Grid.EAST
        input.blocks[1].ports[1].travel_dir = Grid.WEST
        local state = run(input)
        H.equal(state.ok, false, "an outside real attachment is rejected")
        H.equal(state.errors[1].code, "BP_R_PORT_BLOCKED", "the boundary failure names the blocked port")
    end)
end

H.done("test_route_network")
