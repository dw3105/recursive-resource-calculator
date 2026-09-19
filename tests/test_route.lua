--Routing proves deterministic transport geometry, underground pairing and simultaneous segment capacity.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Groups = require "logic.bp.groups"
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
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/plate", rate_per_second = 10,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "consumer", machines = {{step_id = "consumer"}}, x = 8, y = 2, w = 1, h = 1, ports = {
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
    while not state.done and ticks < 600 do
        ticks = ticks + 1
        Route.step(state, {ops = ops or 100000})
    end
    H.equal(state.done, true, "route finishes within 600 iterations; stopped in phase "
        .. tostring(state.progress and state.progress.phase))
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
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 2, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/shared", rate_per_second = total,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "intermediate", machines = {{step_id = "intermediate"}}, x = 4, y = 4, w = 1, h = 1, ports = {
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
            {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 1, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/ore", rate_per_second = 4,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST, connection = connection_a},
            }},
            {block_id = "consumer", machines = {{step_id = "consumer"}}, x = distance + 1, y = 1, w = 1, h = 1, ports = {
                {port_id = "consumer-in", role = "in", kind = "item", flow_id = "item/ore", rate_per_second = 4,
                    attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST, connection = connection_b},
            }},
        },
        flows = {{flow_id = "item/ore", is_fluid = false,
            producers = {{step_id = "source", share_per_second = 4}},
            consumers = {{step_id = "consumer", share_per_second = 4}}}},
    }
end

local function perimeter_input(edge, role)
    local sides = {
        top = {attach_dx = 0, attach_dy = -1, x = 2, y = 0, outward = Grid.NORTH, inward = Grid.SOUTH},
        right = {attach_dx = 1, attach_dy = 0, x = 4, y = 2, outward = Grid.EAST, inward = Grid.WEST},
        bottom = {attach_dx = 0, attach_dy = 1, x = 2, y = 4, outward = Grid.SOUTH, inward = Grid.NORTH},
        left = {attach_dx = -1, attach_dy = 0, x = 0, y = 2, outward = Grid.WEST, inward = Grid.EAST},
    }
    local side = sides[edge]
    local block_role = role == "out" and "out" or "in"
    local flow_id = "item/perimeter/" .. edge .. "/" .. role
    local block_id = role == "out" and "source" or "sink"
    local block_port_id = block_id .. "-port"
    local perimeter_port_id = "perimeter-port"
    local block_port = {
        port_id = block_port_id, role = block_role, kind = "item", flow_id = flow_id, rate_per_second = 1,
        attach_dx = side.attach_dx, attach_dy = side.attach_dy, normal_dir = side.inward,
        travel_dir = role == "out" and side.outward or side.inward,
    }
    return {
        grid = Grid.new(5, 5), catalog = {belt = {belt = "basic-belt", items_per_second = 10}},
        blocks = {{block_id = block_id, machines = {{step_id = block_id}}, x = 2, y = 2, w = 1, h = 1, ports = {block_port}}},
        perimeter_ports = {{port_id = perimeter_port_id, role = role, kind = "item", flow_id = flow_id,
            rate_per_second = 1, x = side.x, y = side.y, travel_dir = role == "out" and side.outward or side.inward}},
        flows = {{flow_id = flow_id, producers = role == "out"
                and {{step_id = block_id, share_per_second = 1}}
                or {{step_id = "$external", port_id = perimeter_port_id, share_per_second = 1}},
            consumers = role == "out"
                and {{step_id = "$external", port_id = perimeter_port_id, share_per_second = 1}}
                or {{step_id = block_id, share_per_second = 1}}}},
    }
end

local function entity_at(result, x, y)
    for _, entity in ipairs(result.entities or {}) do
        local position = entity.position or {}
        if math.floor(position.x) == x and math.floor(position.y) == y then return entity end
    end
end

local function outside_perimeter_input()
    return {
        grid = Grid.new(5, 5), catalog = {belt = {belt = "basic-belt", items_per_second = 10}},
        blocks = {{block_id = "source", machines = {{step_id = "source"}}, x = 2, y = 2, w = 1, h = 1, ports = {{
            port_id = "source-port", role = "out", kind = "item", flow_id = "item/outside", rate_per_second = 1,
            attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.WEST,
        }}}},
        perimeter_ports = {{port_id = "outside-port", role = "out", kind = "item", flow_id = "item/outside",
            rate_per_second = 1, x = -1, y = 2, travel_dir = Grid.WEST}},
        flows = {{flow_id = "item/outside", producers = {{step_id = "source", share_per_second = 1}},
            consumers = {{step_id = "$external", port_id = "outside-port", share_per_second = 1}}}},
    }
end

local function real_one_step_plan()
    return {
        steps = {{step_id = "gear", recipe = "gear", machine = "assembler", machine_count = 1,
            inputs = {{flow_id = "item/raw", rate_per_second = 0.1}},
            outputs = {{flow_id = "item/gear", rate_per_second = 0.1}}}},
        flows = {
            {flow_id = "item/raw", producers = {{step_id = "$external", share_per_second = 0.1}},
                consumers = {{step_id = "gear", share_per_second = 0.1}}},
            {flow_id = "item/gear", producers = {{step_id = "gear", share_per_second = 0.1}},
                consumers = {{step_id = "$external", share_per_second = 0.1}}},
        },
        ports = {
            {port_id = "in:item/raw", role = "in", full_name = "item/raw", is_fluid = false,
                rate_per_second = 0.1, kind = "item", min_lanes = 1},
            {port_id = "out:item/gear", role = "out", full_name = "item/gear", is_fluid = false,
                rate_per_second = 0.1, kind = "item", min_lanes = 1},
        },
    }
end

local function real_plan_route_input()
    local plan = real_one_step_plan()
    local grouping = Groups.begin({plan = plan, catalog = {entity = {
        assembler = {name = "assembler", tile_w = 3, tile_h = 3},
    }}})
    local iterations = 0
    while not grouping.done and iterations < 600 do
        iterations = iterations + 1
        Groups.step(grouping, {ops = 1})
    end
    H.equal(grouping.done, true, "grouping finishes within 600 iterations; stopped in phase "
        .. tostring(grouping.progress and grouping.progress.phase))
    local block = grouping.result.candidates[1].blocks[1]
    block.x, block.y = 4, 3
    return {
        grid = Grid.new(14, 12),
        catalog = {belt = {belt = "basic-belt", items_per_second = 10}},
        blocks = {block},
        perimeter_ports = {
            {port_id = "in:item/raw", role = "in", kind = "item", flow_id = "item/raw",
                rate_per_second = 0.1, x = 0, y = 2, travel_dir = Grid.EAST},
            {port_id = "out:item/gear", role = "out", kind = "item", flow_id = "item/gear",
                rate_per_second = 0.1, x = 13, y = 8, travel_dir = Grid.EAST},
        },
        flows = plan.flows,
    }
end

local function genuinely_unbound_port_input()
    local input = real_plan_route_input()
    input.blocks = {{block_id = "block:orphan", x = 4, y = 3, w = 1, h = 1, ports = {{
        port_id = "orphan-out", role = "out", kind = "item", flow_id = "item/gear", rate_per_second = 0.1,
        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
    }}}}
    return input
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
                {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 1, w = 2, h = 1, dir = Grid.EAST, ports = {
                    {port_id = "source-out", role = "out", kind = "item", flow_id = "item/rotated", rate_per_second = 4,
                        attach_dx = 2, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST,
                        connection = {connection_type = "underground", direction = Grid.EAST, max_underground_distance = 5}},
                }},
                {block_id = "consumer", machines = {{step_id = "consumer"}}, x = 1, y = 7, w = 2, h = 1, dir = Grid.EAST, ports = {
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
                {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 1, w = 1, h = 1, ports = {
                    {port_id = "water-out", role = "out", kind = "fluid", flow_id = "fluid/water", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
                    {port_id = "steam-out", role = "out", kind = "fluid", flow_id = "fluid/steam", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
                }},
                {block_id = "sink", machines = {{step_id = "sink"}}, x = 6, y = 1, w = 1, h = 1, ports = {
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

    H.test(shape .. " R10 perimeter ports on all four edge cells are routable", function()
        local edges = {"top", "right", "bottom", "left"}
        for _, edge in ipairs(edges) do
            for _, role in ipairs({"out", "in"}) do
                local state = run(perimeter_input(edge, role))
                H.equal(state.ok, true, edge .. " " .. role .. " perimeter route succeeds")
                local side = ({
                    top = {x = 2, y = 0, direction = role == "out" and Grid.NORTH or Grid.SOUTH},
                    right = {x = 4, y = 2, direction = role == "out" and Grid.EAST or Grid.WEST},
                    bottom = {x = 2, y = 4, direction = role == "out" and Grid.SOUTH or Grid.NORTH},
                    left = {x = 0, y = 2, direction = role == "out" and Grid.WEST or Grid.EAST},
                })[edge]
                local entity = entity_at(state.result, side.x, side.y)
                H.equal(entity ~= nil, true, edge .. " " .. role .. " has a belt on its perimeter cell")
                if entity then
                    H.equal(entity.direction, side.direction, edge .. " " .. role .. " travel direction")
                end
            end
        end
    end)

    H.test(shape .. " R10 a genuinely outside perimeter cell stays blocked", function()
        local state = run(outside_perimeter_input())
        H.equal(state.ok, false, "outside perimeter route fails")
        H.equal(error_code(state), "BP_R_PORT_BLOCKED", "outside perimeter is blocked")
    end)

    H.test(shape .. " R11 a real one-step plan binds both endpoints of every flow", function()
        local state = run(real_plan_route_input())
        local initial_error = state.work and state.work.initial_error
        H.equal(state.ok, true, "real one-step plan routes; code "
            .. tostring(error_code(state)) .. "; detail " .. tostring(initial_error and initial_error.detail))
        local bindings = {}
        for _, binding in ipairs(state.result and state.result.bindings or {}) do
            bindings[binding.flow_id] = binding
            H.equal(binding.source_port_id ~= nil, true, binding.flow_id .. " has a producer endpoint")
            H.equal(binding.sink_port_id ~= nil, true, binding.flow_id .. " has a consumer endpoint")
        end
        H.equal(bindings["item/raw"] ~= nil, true, "raw flow is bound")
        H.equal(bindings["item/gear"] ~= nil, true, "gear flow is bound")
    end)

    H.test(shape .. " R12 a port with no owning step is still blocked", function()
        local state = run(genuinely_unbound_port_input())
        H.equal(state.ok, false, "an unowned port fails")
        H.equal(error_code(state), "BP_R_PORT_BLOCKED", "an unowned port reports blocked")
    end)
    --A path search visits cells, so a routing run is bounded by its own grid. One million expansions let a single
    --demand burn 1.2 million steps on a 54 by 54 grid without finishing, which the player sees as a frozen
    --Generate.
    H.test(shape .. " R15 the expansion limit follows the grid, never a fixed million", function()
        local state = Route.begin(belt_input({grid = Grid.new(40, 30)}))
        H.equal(state.work.max_expansions, 40 * 30 * 16, "a large grid allows sixteen visits per cell")
        local small = Route.begin(belt_input({grid = Grid.new(4, 4)}))
        H.equal(small.work.max_expansions, 4096, "a tiny grid keeps a floor that still finds a path")
        local explicit = Route.begin(belt_input({grid = Grid.new(40, 30), max_expansions = 25}))
        H.equal(explicit.work.max_expansions, 25, "an explicit limit still wins")
    end)

    --Two belts that must cross cannot both stay on the surface. The second one dives under the first, and the
    --tiles it dives under keep the segment that already owns them.
    H.test(shape .. " R16 a belt that must cross another one goes under it", function()
        local input = {
            grid = Grid.new(11, 11),
            catalog = {belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 10,
                lane_items_per_second = 5, underground_max_distance = 5}},
            blocks = {
                {block_id = "west", machines = {{step_id = "west"}}, x = 0, y = 5, w = 1, h = 1, ports = {
                    {port_id = "a-out", role = "out", kind = "item", flow_id = "item/a", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
                }},
                {block_id = "east", machines = {{step_id = "east"}}, x = 10, y = 5, w = 1, h = 1, ports = {
                    {port_id = "a-in", role = "in", kind = "item", flow_id = "item/a", rate_per_second = 5,
                        attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST},
                }},
                {block_id = "north", machines = {{step_id = "north"}}, x = 5, y = 0, w = 1, h = 1, ports = {
                    {port_id = "b-out", role = "out", kind = "item", flow_id = "item/b", rate_per_second = 5,
                        attach_dx = 0, attach_dy = 1, normal_dir = Grid.NORTH, travel_dir = Grid.SOUTH},
                }},
                {block_id = "south", machines = {{step_id = "south"}}, x = 5, y = 10, w = 1, h = 1, ports = {
                    {port_id = "b-in", role = "in", kind = "item", flow_id = "item/b", rate_per_second = 5,
                        attach_dx = 0, attach_dy = -1, normal_dir = Grid.SOUTH, travel_dir = Grid.SOUTH},
                }},
            },
            flows = {
                {flow_id = "item/a", is_fluid = false, producers = {{step_id = "west", share_per_second = 5}},
                    consumers = {{step_id = "east", share_per_second = 5}}},
                {flow_id = "item/b", is_fluid = false, producers = {{step_id = "north", share_per_second = 5}},
                    consumers = {{step_id = "south", share_per_second = 5}}},
            },
        }
        local state = run(input)
        H.equal(state.ok, true, "both belts route; neither crossing flow is refused")
        local pairs_found, undergrounds = 0, {}
        for _, entity in ipairs(state.result.entities) do
            if entity.ug_pair_id ~= nil then
                pairs_found = pairs_found + 1
                undergrounds[#undergrounds + 1] = entity
                H.equal(entity.name, "basic-underground", "a crossing uses the family's underground belt")
            end
        end
        H.equal(pairs_found, 2, "the crossing is one pair: an entrance and an exit")
        H.equal(undergrounds[1].ug_pair_id, undergrounds[2].id, "the pair points forward")
        H.equal(undergrounds[2].ug_pair_id, undergrounds[1].id, "the pair points back")
        local gap = math.abs(undergrounds[1].position.x - undergrounds[2].position.x)
            + math.abs(undergrounds[1].position.y - undergrounds[2].position.y)
        H.equal(gap >= 2, true, "the pair spans the tile it dives under")
    end)

    --A port is useless without the tile its transport reaches it from. Routing one demand across the approach
    --tile of a port it does not serve leaves that port with no path at all.
    H.test(shape .. " R17 one demand never takes the approach tile of another port", function()
        local input = {
            grid = Grid.new(9, 9),
            catalog = {belt = {belt = "basic-belt", items_per_second = 10, lane_items_per_second = 5}},
            blocks = {
                {block_id = "stack", machines = {{step_id = "stack"}}, x = 0, y = 4, w = 1, h = 2, ports = {
                    {port_id = "top-in", role = "in", kind = "item", flow_id = "item/top", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.WEST},
                    {port_id = "low-in", role = "in", kind = "item", flow_id = "item/low", rate_per_second = 5,
                        attach_dx = 1, attach_dy = 1, normal_dir = Grid.WEST, travel_dir = Grid.WEST},
                }},
            },
            perimeter_ports = {
                {port_id = "top-src", role = "in", kind = "item", flow_id = "item/top", rate_per_second = 5,
                    x = 8, y = 0, travel_dir = Grid.WEST},
                {port_id = "low-src", role = "in", kind = "item", flow_id = "item/low", rate_per_second = 5,
                    x = 8, y = 4, travel_dir = Grid.WEST},
            },
            flows = {
                {flow_id = "item/top", is_fluid = false, producers = {{step_id = "$external", share_per_second = 5}},
                    consumers = {{step_id = "stack", share_per_second = 5}}},
                {flow_id = "item/low", is_fluid = false, producers = {{step_id = "$external", share_per_second = 5}},
                    consumers = {{step_id = "stack", share_per_second = 5}}},
            },
        }
        local state = run(input)
        H.equal(state.ok, true, "both stacked ports keep a path of their own")
        local reserved = state.work.port_cells["2:4"]
        H.equal(reserved ~= nil and reserved["top-in"] == true, true, "the tile the top port is entered from belongs to it")
        H.equal(reserved["low-in"], nil, "the low port never owns the tile the top port needs")
    end)

end

H.done("test_route")
