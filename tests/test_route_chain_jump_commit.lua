--This synthetic regression fails on round-45-w5b: one source already reaches the sink,
--so the second source's chained underground jumps used to be committed without a retry.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local function run(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 1000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "routing finishes")
    return state
end

local function chain_jump_input()
    local flow = "item/chain-jump"
    local function output(id, x, y, vertical)
        return {block_id = id, machines = {{step_id = id}}, x = x, y = y, w = 1, h = 1, ports = {{
            port_id = id .. "-out", role = "out", kind = "item", flow_id = flow, rate_per_second = 1,
            attach_dx = vertical and 0 or 1, attach_dy = vertical and 1 or 0,
            normal_dir = vertical and Grid.NORTH or Grid.WEST, travel_dir = vertical and Grid.SOUTH or Grid.EAST,
        }}}
    end
    return {
        grid = Grid.new(15, 13),
        catalog = {belt = {belt = "basic-belt", underground = "basic-underground", items_per_second = 10,
            underground_max_distance = 3}},
        obstacles = {{x = 0, y = 4, w = 15, h = 1, owner = "wall"},
            {x = 0, y = 6, w = 15, h = 1, owner = "wall"}},
        blocks = {
            output("source-1", 9, 8), output("source-2", 7, 1, true),
            {block_id = "sink", machines = {{step_id = "sink"}}, x = 12, y = 8, w = 1, h = 1, ports = {{
                port_id = "sink-in", role = "in", kind = "item", flow_id = flow, rate_per_second = 2,
                attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST,
            }}},
        },
        flows = {{flow_id = flow, is_fluid = false,
            producers = {{step_id = "source-1", share_per_second = 1}, {step_id = "source-2", share_per_second = 1}},
            consumers = {{step_id = "sink", share_per_second = 2}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CJ1 committed underground exits continue into same-flow transport", function()
        local state = run(chain_jump_input())
        H.equal(state.ok, true, "both source branches reach the sink")
        local flow_cells, exits = {}, {}
        for _, entity in ipairs(state.result.entities or {}) do
            if entity.flow_id == "item/chain-jump" then
                local p = entity.position or {}
                flow_cells[math.floor(p.x) .. ":" .. math.floor(p.y)] = entity
                if entity.ug_role == "output" then
                    exits[#exits + 1] = entity
                end
            end
        end
        for _, entity in ipairs(exits) do
            local p = entity.position or {}
            local d = entity.direction
            local delta = d == Grid.NORTH and {0, -1} or d == Grid.EAST and {1, 0}
                or d == Grid.SOUTH and {0, 1} or {-1, 0}
            local x, y = math.floor(p.x) + delta[1], math.floor(p.y) + delta[2]
            H.equal(flow_cells[x .. ":" .. y] ~= nil, true,
                "underground exit at " .. tostring(p.x) .. ":" .. tostring(p.y) .. " continues on same flow")
        end
        H.equal(#exits >= 1, true, "the source behind the parallel walls uses underground crossings")
    end)
end

H.done("test_route_chain_jump_commit")
