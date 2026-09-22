--The route's binding is a promise about a directed transport chain, not merely about a visited target tile.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"

local function run()
    local state = Route.begin(dofile(FROZEN))
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "the frozen route reaches a terminal state")
    return state
end

local function tile(entity)
    local position = entity.position or entity
    return math.floor(position.x + 1e-9), math.floor(position.y + 1e-9)
end

local function flow_of(entity)
    return entity.flow_id or entity.full_name
end

local function reaches(binding, result, ports)
    local source, sink = ports[binding.source_port_id], ports[binding.sink_port_id]
    if not source or not sink then return false end
    local by_tile, by_id = {}, {}
    for _, entity in ipairs(result.entities or {}) do
        local x, y = tile(entity)
        by_tile[x .. ":" .. y] = by_tile[x .. ":" .. y] or {}
        by_tile[x .. ":" .. y][#by_tile[x .. ":" .. y] + 1] = entity
        by_id[tostring(entity.id)] = entity
    end
    local function successors(entity)
        local result = {}
        local pair_id = entity.ug_pair_id or entity.underground_pair_id
        if pair_id and by_id[tostring(pair_id)] then result[#result + 1] = by_id[tostring(pair_id)] end
        local x, y = tile(entity)
        local direction = entity.direction or entity.dir
        local dx, dy = Grid.dir_vector(direction or Grid.NORTH)
        local function add_at(px, py)
            for _, next_entity in ipairs(by_tile[px .. ":" .. py] or {}) do
                if next_entity ~= entity and (flow_of(next_entity) == nil or flow_of(next_entity) == binding.flow_id) then
                    result[#result + 1] = next_entity
                end
            end
        end
        if dx ~= nil then add_at(x + dx, y + dy) end
        if entity.splitter or entity.type == "splitter" then
            local sx, sy = Grid.dir_vector(Grid.rotate_dir(direction or Grid.NORTH, Grid.EAST))
            if sx ~= nil then add_at(x + sx, y + sy) end
        end
        return result
    end
    local start_x, start_y = source.x, source.y
    local target_x, target_y = sink.x, sink.y
    local queue, head, seen = {}, 1, {}
    for _, entity in ipairs(by_tile[start_x .. ":" .. start_y] or {}) do
        if flow_of(entity) == nil or flow_of(entity) == binding.flow_id then
            queue[#queue + 1] = entity
            seen[tostring(entity.id)] = true
        end
    end
    while queue[head] do
        local entity = queue[head]
        head = head + 1
        local x, y = tile(entity)
        if x == target_x and y == target_y then return true end
        for _, next_entity in ipairs(successors(entity)) do
            if not seen[tostring(next_entity.id)] then
                seen[tostring(next_entity.id)] = true
                queue[#queue + 1] = next_entity
            end
        end
    end
    return false
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RC1 every recorded binding reaches its own sink", function()
        local state = run()
        H.equal(state.ok, true, "the candidate routes")
        if not state.ok then return end
        local ports = state.work.endpoint_by_id or {}
        local broken = 0
        for _, binding in ipairs(state.result.bindings or {}) do
            if not reaches(binding, state.result, ports) then broken = broken + 1 end
        end
        --Round-16 baseline: 7 bindings, 1 broken chain.  This assertion is the red characterization at the
        --lane boundary; S3 closes the one measured fault instead of deleting the binding.
        H.equal(broken, 0, "every binding has a directed same-flow chain")
    end)

    H.test(shape .. " RC2 the frozen candidate keeps its transport budget while chains close", function()
        local state = run()
        H.equal(state.ok, true, "the candidate routes")
        if not state.ok then return end
        local belts = 0
        for _, entity in ipairs(state.result.entities or {}) do
            if entity.ug_role or entity.splitter or tostring(entity.name or ""):find("belt", 1, true) then
                belts = belts + 1
            end
        end
        H.equal(belts <= 85, true, "the frozen characterization stays at or below 85 belts")
    end)
end

H.done("test_route_chain")
