--A neighbouring port's reservation is not evidence that this port is blocked.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function catalog()
    return {belt = {belt = "basic-belt", items_per_second = 10}}
end

local function run(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 1000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route finishes within the test bound")
    return state
end

local function error_code(state)
    return state.errors and state.errors[1] and state.errors[1].code
end

local function neighbouring_ports_input()
    return {
        grid = Grid.new(8, 6),
        catalog = catalog(),
        blocks = {{block_id = "pair", machines = {{step_id = "pair"}}, x = 2, y = 3, w = 2, h = 1, dir = Grid.EAST,
            ports = {
                {port_id = "in:item/a", role = "in", kind = "item", flow_id = "item/a", rate_per_second = 1,
                    _block_w = 2, _block_h = 1, attach_dx = 0, attach_dy = -1,
                    normal_dir = Grid.SOUTH, travel_dir = Grid.SOUTH},
                {port_id = "in:item/b", role = "in", kind = "item", flow_id = "item/b", rate_per_second = 1,
                    _block_w = 2, _block_h = 1, attach_dx = 1, attach_dy = -1,
                    normal_dir = Grid.SOUTH, travel_dir = Grid.SOUTH},
            }}},
        perimeter_ports = {
            {port_id = "source-a", role = "in", kind = "item", flow_id = "item/a", rate_per_second = 1,
                x = 6, y = 3, travel_dir = Grid.WEST},
            {port_id = "source-b", role = "in", kind = "item", flow_id = "item/b", rate_per_second = 1,
                x = 6, y = 4, travel_dir = Grid.WEST},
        },
        flows = {
            {flow_id = "item/a", producers = {{step_id = "$external", port_id = "source-a", share_per_second = 1}},
                consumers = {{step_id = "pair", share_per_second = 1}}},
            {flow_id = "item/b", producers = {{step_id = "$external", port_id = "source-b", share_per_second = 1}},
                consumers = {{step_id = "pair", share_per_second = 1}}},
        },
    }
end

local function foreign_belt_on_port_input()
    return {
        grid = Grid.new(6, 4),
        catalog = catalog(),
        obstacles = {{x = 3, y = 1, w = 1, h = 1, owner = "foreign-belt"}},
        blocks = {{block_id = "sink", machines = {{step_id = "sink"}}, x = 3, y = 2, w = 1, h = 1,
            ports = {{
                port_id = "sink-port", role = "in", kind = "item", flow_id = "item/sink", rate_per_second = 1,
                _block_w = 1, _block_h = 1, attach_dx = 0, attach_dy = -1,
                normal_dir = Grid.SOUTH, travel_dir = Grid.SOUTH,
            }}}},
        perimeter_ports = {{port_id = "source", role = "in", kind = "item", flow_id = "item/sink", rate_per_second = 1,
            x = 0, y = 1, travel_dir = Grid.EAST}},
        flows = {{flow_id = "item/sink", producers = {{step_id = "$external", port_id = "source", share_per_second = 1}},
            consumers = {{step_id = "sink", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " neighbouring ports of different flows are both routable", function()
        local state = run(neighbouring_ports_input())
        H.equal(state.ok, true, "neighbouring ports do not block one another")
        H.equal(#state.result.port_bindings, 2, "both neighbouring port demands are bound")
    end)

    H.test(shape .. " a neighbour's port tile may be this port's approach", function()
        local state = run(neighbouring_ports_input())
        local reserved = state.work.port_cells["3:3"]
        H.equal(reserved ~= nil and reserved["in:item/a"] == true, true,
            "the first port owns its tile")
        H.equal(reserved ~= nil and reserved["in:item/b"] == true, true,
            "the neighbour owns the first port tile as its approach")
        H.equal(state.ok, true, "the approach reservation does not block the port: " .. tostring(error_code(state)))
    end)

    H.test(shape .. " a foreign belt standing on a port tile still blocks it", function()
        local state = run(foreign_belt_on_port_input())
        H.equal(state.ok, false, "a genuinely occupied port tile is blocked")
        H.equal(error_code(state), "BP_R_PORT_BLOCKED", "the occupied port has the blocked result")
    end)
end

H.done("test_port_not_self_blocked")
