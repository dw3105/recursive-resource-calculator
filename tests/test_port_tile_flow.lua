--A route result never puts a different flow on a port's own tile or its approach tile.
--This predicate is deliberately independent of Route's working reservation table.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"

local function run(input)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "route finishes within the port-tile test bound")
    H.equal(state.ok, true, "route succeeds for the port-tile test")
    return state
end

local function number(value)
    return type(value) == "number" and value or nil
end

local function port_tile(port, block)
    --This is the same public coordinate authority consumed by validation: an explicit placed x/y wins over
    --any auxiliary position object. The router must reserve the tile the validator will inspect.
    local x, y = number(port.x), number(port.y)
    if x ~= nil and y ~= nil then return math.floor(x), math.floor(y) end
    if not block then return nil, nil end
    local frame = {w = number(port._block_w) or number(block.w) or 1,
        h = number(port._block_h) or number(block.h) or 1}
    local placement = {x = number(block.x) or 0, y = number(block.y) or 0, dir = number(block.dir) or Grid.NORTH}
    local placed = Grid.place_port(frame, placement, port)
    return placed.x, placed.y
end

local function owned_tiles(input)
    local owners = {}
    local function claim(port, block)
        local x, y = port_tile(port, block)
        local direction = port.travel_dir or port.dir or port.normal_dir
        local dx, dy
        if direction then dx, dy = Grid.dir_vector(direction) end
        if x == nil or y == nil or dx == nil or dy == nil then return end
        local flow = port.flow_id or port.full_name or port.flow
        if flow == nil then return end
        local function add(px, py)
            local key = tostring(px) .. ":" .. tostring(py)
            owners[key] = owners[key] or {}
            owners[key][flow] = true
        end
        add(x, y)
        if port.role == "in" then add(x - dx, y - dy)
        elseif port.role == "out" then add(x + dx, y + dy) end
    end
    for _, block in ipairs(input.blocks or {}) do
        for _, port in ipairs(block.ports or block.block_ports or {}) do claim(port, block) end
    end
    for _, port in ipairs(input.perimeter_ports or input.perimeter or {}) do claim(port) end
    return owners
end

local function entity_tiles(entity)
    local position = entity.position or entity
    local x, y = math.floor(position.x), math.floor(position.y)
    local result = {{x = x, y = y}}
    if entity.splitter or tostring(entity.name or ""):find("splitter", 1, true) then
        local side = Grid.rotate_dir(Grid.EAST, entity.direction or entity.dir or Grid.NORTH)
        local dx, dy = Grid.dir_vector(side)
        if dx ~= 0 then
            x, y = math.floor(position.x - 0.5), math.floor(position.y)
        else
            x, y = math.floor(position.x), math.floor(position.y - 0.5)
        end
        result = {{x = x, y = y}, {x = x + dx, y = y + dy}}
    end
    --Both ends of a crossing are published as separate entities. Keeping every entity in the walk here is
    --intentional: an underground exit must be checked just like its entry, not only through its pair id.
    return result
end

local function splitter_port_input()
    return {
        grid = Grid.new(8, 6),
        catalog = {belt = {belt = "transport-belt", splitter = "splitter", items_per_second = 10,
            lane_items_per_second = 5, underground_max_distance = 0}},
        obstacles = {{x = 0, y = 2, w = 5, h = 1, owner = "wall"}},
        perimeter_ports = {{port_id = "owner-port", role = "out", kind = "item", flow_id = "item/owner",
            rate_per_second = 0, x = 6, y = 3, position = {x = 100, y = 3}, travel_dir = Grid.NORTH}},
        blocks = {
            {block_id = "source", machines = {{step_id = "source"}}, x = 0, y = 3, w = 1, h = 1, ports = {
                {port_id = "source-out", role = "out", kind = "item", flow_id = "item/branch", rate_per_second = 2,
                    attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST},
            }},
            {block_id = "straight", machines = {{step_id = "straight"}}, x = 7, y = 3, w = 1, h = 1, ports = {
                {port_id = "straight-in", role = "in", kind = "item", flow_id = "item/branch", rate_per_second = 1,
                    x = 5, y = 3, travel_dir = Grid.EAST},
            }},
            {block_id = "branch", machines = {{step_id = "branch"}}, x = 5, y = 0, w = 1, h = 1, ports = {
                {port_id = "branch-in", role = "in", kind = "item", flow_id = "item/branch", rate_per_second = 1,
                    attach_dx = 0, attach_dy = 1, normal_dir = Grid.SOUTH, travel_dir = Grid.NORTH},
            }},
        },
        flows = {{flow_id = "item/branch", producers = {{step_id = "source", share_per_second = 2}},
            consumers = {{step_id = "straight", share_per_second = 1}, {step_id = "branch", share_per_second = 1}}}},
    }
end

local function rotated_materialized_port_input()
    return {
        grid = Grid.new(12, 7),
        catalog = {belt = {belt = "transport-belt", items_per_second = 10}},
        perimeter_ports = {
            {port_id = "foreign-source", role = "in", kind = "item", flow_id = "item/foreign", rate_per_second = 1,
                x = 0, y = 4, travel_dir = Grid.EAST},
            {port_id = "foreign-sink", role = "out", kind = "item", flow_id = "item/foreign", rate_per_second = 1,
                x = 11, y = 4, travel_dir = Grid.EAST},
        },
        blocks = {{block_id = "rotated", x = 0, y = 5, w = 10, h = 11, dir = Grid.EAST, ports = {{
            port_id = "owner-port", role = "out", kind = "item", flow_id = "item/owner", rate_per_second = 0,
            _block_w = 11, _block_h = 10, attach_dx = -1, attach_dy = 0,
            normal_dir = Grid.EAST, travel_dir = Grid.WEST,
        }}}},
        flows = {{flow_id = "item/foreign", producers = {{step_id = "$external", port_id = "foreign-source", share_per_second = 1}},
            consumers = {{step_id = "$external", port_id = "foreign-sink", share_per_second = 1}}}},
    }
end

local function assert_no_foreign_flow(input, result)
    local owners = owned_tiles(input)
    for _, entity in ipairs(result.entities or {}) do
        local flow = entity.flow_id or entity.full_name
        for _, tile in ipairs(entity_tiles(entity)) do
            local owner_flows = owners[tostring(tile.x) .. ":" .. tostring(tile.y)]
            if owner_flows and flow ~= nil then
                for owner_flow, _ in pairs(owner_flows) do
                    H.equal(flow == owner_flow, true,
                        "flow " .. tostring(flow) .. " does not occupy " .. tostring(tile.x) .. ":"
                            .. tostring(tile.y) .. " owned by " .. tostring(owner_flow))
                end
            end
        end
    end
end

local function shifted_port_input()
    return {
        grid = Grid.new(7, 3),
        catalog = {belt = {belt = "transport-belt", items_per_second = 10}},
        --The owner port is intentionally not a demand. It still owns its placed tile, exactly as validation
        --does, while the foreign flow is the route that must prove it can go around that tile.
        perimeter_ports = {
            {port_id = "owner-port", role = "out", kind = "item", flow_id = "item/owner", rate_per_second = 0,
                x = 3, y = 1, position = {x = 8, y = 1}, travel_dir = Grid.EAST},
            {port_id = "foreign-source", role = "in", kind = "item", flow_id = "item/foreign", rate_per_second = 1,
                x = 0, y = 1, travel_dir = Grid.EAST},
            {port_id = "foreign-sink", role = "out", kind = "item", flow_id = "item/foreign", rate_per_second = 1,
                x = 6, y = 1, travel_dir = Grid.EAST},
        },
        flows = {{flow_id = "item/foreign", producers = {{step_id = "$external", port_id = "foreign-source", share_per_second = 1}},
            consumers = {{step_id = "$external", port_id = "foreign-sink", share_per_second = 1}}}},
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " a foreign flow never occupies a validator-visible port tile", function()
        local input = shifted_port_input()
        local state = run(input)
        if state.ok then assert_no_foreign_flow(input, state.result) end
    end)

    H.test(shape .. " a splitter's second tile is also owned by its port flow", function()
        local input = splitter_port_input()
        local state = run(input)
        if state.ok then assert_no_foreign_flow(input, state.result) end
    end)

    H.test(shape .. " a rotated materialized port reserves the validator-visible approach", function()
        local input = rotated_materialized_port_input()
        local state = run(input)
        if state.ok then assert_no_foreign_flow(input, state.result) end
    end)

    H.test(shape .. " both ends of the frozen crossing route respect port flows", function()
        local input = dofile(FROZEN)
        local state = run(input)
        if state.ok then assert_no_foreign_flow(input, state.result) end
    end)
end

H.done("test_port_tile_flow")
