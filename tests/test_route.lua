--Routing proves deterministic transport geometry, underground pairing and simultaneous segment capacity.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function belt_input(extra)
    local input = {
        grid = Grid.new(12, 5),
        catalog = {
            belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 10,
                lane_items_per_second = 5, underground_max_distance = 5},
            pipe = {pipe = "pipe", underground = "pipe-to-ground", throughput_per_second = 100,
                underground_max_distance = 5},
        },
        blocks = {
            {block_id = "source", x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/plate", rate_per_second = 10,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "consumer", x = 8, y = 2, w = 1, h = 1, ports = {
                {port_id = "consumer-in", role = "in", kind = "item", flow_id = "item/plate", rate_per_second = 10,
                    attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
            }},
        },
        flows = {{flow_id = "item/plate", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 10}},
            consumers = {{step_id = "consumer", share_per_second = 10}}}},
    }
    for key, value in pairs(extra or {}) do input[key] = value end
    return input
end

local function run(input, ops)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        H.equal(ticks < 10000, true, "route finishes")
        Route.step(state, {ops = ops or 100000})
    end
    return state
end

local function error_code(state)
    return state.errors and state.errors[1] and state.errors[1].code
end

local function narrow_row()
    return {
        {x = 0, y = 0, w = 12, h = 2, owner = "wall"},
        {x = 0, y = 3, w = 4, h = 1, owner = "wall"},
        {x = 5, y = 3, w = 7, h = 1, owner = "wall"},
    }
end

local function shared_capacity_input(total)
    local input = {
        grid = Grid.new(12, 5),
        catalog = {belt = {belt = "basic-belt", splitter = "basic-splitter", items_per_second = 10, lane_items_per_second = 5}},
        obstacles = narrow_row(),
        blocks = {
            {block_id = "source", x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/shared", rate_per_second = total,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "intermediate", x = 4, y = 4, w = 1, h = 1, ports = {
                {port_id = "intermediate-in", role = "in", kind = "item", flow_id = "item/shared", rate_per_second = total / 2,
                    attach_dx = 0, attach_dy = -1, normal_dir = Grid.SOUTH, travel_dir = Grid.SOUTH},
            }},
        },
        perimeter_ports = {{port_id = "out:item/shared", role = "out", kind = "item", flow_id = "item/shared",
            rate_per_second = total / 2, x = 6, y = 2, travel_dir = Grid.EAST}},
        flows = {{flow_id = "item/shared", is_fluid = false,
            producers = {{step_id = "source", share_per_second = total}},
            consumers = {{step_id = "intermediate", share_per_second = total / 2},
                {step_id = "$external", share_per_second = total / 2}}}},
    }
    return input
end

local function underground_input(connection_a, connection_b, distance)
    return {
        grid = Grid.new(14, 4),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 10,
            underground_max_distance = 5}},
        blocks = {
            {block_id = "source", x = 1, y = 1, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/ore", rate_per_second = 4,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST, connection = connection_a},
            }},
            {block_id = "consumer", x = distance + 1, y = 1, w = 1, h = 1, ports = {
                {port_id = "consumer-in", role = "in", kind = "item", flow_id = "item/ore", rate_per_second = 4,
                    attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST, connection = connection_b},
            }},
        },
        flows = {{flow_id = "item/ore", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 4}},
            consumers = {{step_id = "consumer", share_per_second = 4}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " R1 a single producer reaches a consumer with belt travel direction", function()
        local state = run(belt_input())
        H.equal(state.ok, true, "route succeeds")
        H.equal(#state.result.entities > 0, true, "belt entities are placed")
        for _, entity in ipairs(state.result.entities) do
            H.equal(entity.flow_id, "item/plate", "entity carries its flow")
            H.equal(entity.direction, Grid.EAST, "belt follows transport travel")
        end
    end)

    H.test(shape .. " R2 rotated underground connections face each other and keep paired roles", function()
        local state = run(underground_input(
            {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 5},
            {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 5}, 4))
        H.equal(state.ok, true, "underground route succeeds")
        H.equal(#state.result.entities, 2, "one underground pair is placed")
        H.equal(state.result.entities[1].ug_role, "output", "source endpoint is output")
        H.equal(state.result.entities[2].ug_role, "input", "consumer endpoint is input")
        H.equal(state.result.entities[1].ug_pair_id, state.result.entities[2].id, "pair points forward")
        H.equal(state.result.entities[2].ug_pair_id, state.result.entities[1].id, "pair points back")
        H.equal(state.result.entities[1].direction, Grid.EAST, "underground travel is east")
        H.equal(state.result.entities[2].direction, Grid.EAST, "both endpoint directions are travel")
    end)

    H.test(shape .. " R2 rotation applies to both connection faces before pairing", function()
        local state = run({
            grid = Grid.new(5, 10),
            catalog = {belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 10}},
            blocks = {
                {block_id = "source", x = 1, y = 1, w = 2, h = 1, dir = Grid.EAST, ports = {
                    {port_id = "source-out", role = "out", kind = "item", flow_id = "item/rotated", rate_per_second = 4,
                        attach_dx = 2, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
                        connection = {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 5}},
                }},
                {block_id = "consumer", x = 1, y = 7, w = 2, h = 1, dir = Grid.EAST, ports = {
                    {port_id = "consumer-in", role = "in", kind = "item", flow_id = "item/rotated", rate_per_second = 4,
                        attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
                        connection = {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 5}},
                }},
            },
            flows = {{flow_id = "item/rotated", producers = {{step_id = "source", share_per_second = 4}},
                consumers = {{step_id = "consumer", share_per_second = 4}}}},
        })
        H.equal(state.ok, true, "rotated pair succeeds")
        H.equal(state.result.entities[1].direction, Grid.SOUTH, "rotated output travels south")
        H.equal(state.result.entities[2].direction, Grid.SOUTH, "rotated input carries southward travel")
    end)

    H.test(shape .. " R3 reversed underground connections are refused", function()
        local state = run(underground_input(
            {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 5},
            {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 5}, 4))
        H.equal(state.ok, false, "reversed pair fails")
        H.equal(error_code(state), "BP_R_NO_PATH", "reversed pair has no path")
        H.equal(#(state.result and state.result.entities or {}), 0, "reversed pair places nothing")
    end)

    H.test(shape .. " R4 underground distance uses each connection's own limit", function()
        local state = run(underground_input(
            {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 3},
            {connection_type = "underground", direction = Grid.WEST, max_underground_distance = 3}, 6))
        H.equal(state.ok, false, "over-range pair fails")
        H.equal(error_code(state), "BP_R_NO_PATH", "over-range pair has no path")
    end)

    H.test(shape .. " R5 different fluids never share a pipe segment", function()
        local common = {
            grid = Grid.new(8, 3), catalog = {pipe = {pipe = "pipe", throughput_per_second = 100}},
            obstacles = {{x = 0, y = 0, w = 8, h = 1, owner = "wall"}, {x = 0, y = 2, w = 8, h = 1, owner = "wall"}},
            blocks = {
                {block_id = "source", x = 1, y = 1, w = 1, h = 1, ports = {
                    {port_id = "water-out", role = "out", kind = "fluid", flow_id = "fluid/water", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
                    {port_id = "steam-out", role = "out", kind = "fluid", flow_id = "fluid/steam", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
                }},
                {block_id = "sink", x = 6, y = 1, w = 1, h = 1, ports = {
                    {port_id = "water-in", role = "in", kind = "fluid", flow_id = "fluid/water", rate_per_second = 5,
                        attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
                    {port_id = "steam-in", role = "in", kind = "fluid", flow_id = "fluid/steam", rate_per_second = 5,
                        attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
                }},
            },
            flows = {
                {flow_id = "fluid/water", is_fluid = true, producers = {{step_id = "source", share_per_second = 5}}, consumers = {{step_id = "sink", share_per_second = 5}}},
                {flow_id = "fluid/steam", is_fluid = true, producers = {{step_id = "source", share_per_second = 5}}, consumers = {{step_id = "sink", share_per_second = 5}}},
            },
        }
        local state = run(common)
        H.equal(state.ok, false, "mixed-fluid route fails")
        H.equal(error_code(state), "BP_R_FLUID_MIX", "mixed-fluid reason is explicit")
    end)

    H.test(shape .. " R6 a shared belt allocates both sinks and rejects an over-capacity pair", function()
        local accepted = run(shared_capacity_input(10))
        H.equal(accepted.ok, true, "two consumers fit exactly")
        local shared
        for _, segment in ipairs(accepted.result.segments) do
            if #segment.allocations == 2 then shared = segment; break end
        end
        H.equal(shared ~= nil, true, "a segment records both sinks")
        local allocated = 0
        for _, allocation in ipairs(shared.allocations) do allocated = allocated + allocation.rate_per_second end
        H.near(allocated, shared.capacity_per_second, "allocations fill but do not exceed the belt")
        local refused = run(shared_capacity_input(12))
        H.equal(refused.ok, false, "two six-per-second demands do not fit one ten-per-second belt")
        H.equal(error_code(refused), "BP_R_CAPACITY", "over-capacity is not a silent shortfall")
    end)

    H.test(shape .. " R7 a blocked port is reported before expansion", function()
        local input = belt_input({obstacles = {{x = 2, y = 2, w = 1, h = 1, owner = "stone"}}})
        local state = run(input)
        H.equal(state.ok, false, "blocked port fails")
        H.equal(error_code(state), "BP_R_PORT_BLOCKED", "blocked port reason")
    end)

    H.test(shape .. " R8 the same input and a tiny budget produce the same route", function()
        local input = belt_input()
        local fast = run(input, 100000)
        local repeated = run(input, 100000)
        local sliced = run(input, 1)
        H.deep_equal(repeated.result, fast.result, "repeated input stays unchanged")
        H.deep_equal(sliced.result, fast.result, "budget does not change the route")
    end)

    H.test(shape .. " R9 routing never overlaps a machine or a roboport", function()
        local input = belt_input({roboports = {{x = 4, y = 1, w = 2, h = 3}}})
        local state = run(input)
        H.equal(state.ok, true, "router finds a detour")
        for _, entity in ipairs(state.result.entities) do
            local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
            H.equal(x == 1 and y == 2, false, "route avoids source machine")
            H.equal(x == 8 and y == 2, false, "route avoids consumer machine")
            H.equal(x >= 4 and x < 6 and y >= 1 and y < 4, false, "route avoids roboport")
        end
    end)
end

H.done("test_route")
