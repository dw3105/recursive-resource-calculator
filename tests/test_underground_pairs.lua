--The route must publish complete underground pairs even when a retry rebuilds the working layout.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"
local EPSILON = 1e-9

local function tile_of(entity)
    local position = entity.position or entity
    return math.floor(position.x), math.floor(position.y)
end

local function expected_direction(source, sink)
    local sx, sy = tile_of(source)
    local tx, ty = tile_of(sink)
    local dx, dy = tx - sx, ty - sy
    if dx ~= 0 and dy ~= 0 then return nil end
    if dx == 0 and dy == 0 then return nil end
    return Grid.dir_from_vector(dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1))
end

local function underground_limit(input, entity)
    local connection = entity.connection or entity.underground_connection or entity.pipe_connection
    if connection and connection.max_underground_distance ~= nil then
        return connection.max_underground_distance
    end
    local belt = input.catalog and input.catalog.belt or {}
    local pipe = input.catalog and input.catalog.pipe or {}
    if entity.name == pipe.underground or entity.name == pipe.pipe then
        return pipe.underground_max_distance
    end
    return belt.underground_max_distance
end

local function assert_pairs(input, result)
    local entities = result and result.entities or {}
    local by_id = {}
    for _, entity in ipairs(entities) do
        H.equal(entity.id ~= nil, true, "every route entity has an id")
        H.equal(by_id[tostring(entity.id)] == nil, true, "route entity ids are unique")
        by_id[tostring(entity.id)] = entity
    end

    local underground_count = 0
    for _, entity in ipairs(entities) do
        if entity.ug_pair_id ~= nil then
            underground_count = underground_count + 1
            local partner = by_id[tostring(entity.ug_pair_id)]
            H.equal(partner ~= nil, true, "underground endpoint has a partner in this result")
            if partner then
                H.equal(partner.ug_pair_id, entity.id, "underground partner points back")

                local role = entity.ug_role or entity.type
                local partner_role = partner.ug_role or partner.type
                H.equal(role == "input" or role == "output", true, "underground endpoint has a known role")
                H.equal(partner_role == "input" or partner_role == "output", true,
                    "underground partner has a known role")
                H.equal(role ~= partner_role, true, "underground roles differ")
                H.equal(entity.ug_role == nil or entity.type == nil or entity.ug_role == entity.type, true,
                    "underground role and type agree")
                H.equal(partner.ug_role == nil or partner.type == nil or partner.ug_role == partner.type, true,
                    "underground partner role and type agree")

                local source, sink = role == "input" and entity or partner, role == "input" and partner or entity
                local direction = expected_direction(source, sink)
                H.equal(direction ~= nil, true, "underground endpoints are cardinally aligned")
                H.equal(source.direction, direction, "underground source carries its travel direction")
                H.equal(sink.direction, direction, "underground sink carries its travel direction")

                local x1, y1 = tile_of(entity)
                local x2, y2 = tile_of(partner)
                local distance = math.abs(x1 - x2) + math.abs(y1 - y2)
                local own_limit = underground_limit(input, entity)
                local partner_limit = underground_limit(input, partner)
                H.equal(type(own_limit) == "number", true, "underground endpoint has a distance limit")
                H.equal(type(partner_limit) == "number", true, "underground partner has a distance limit")
                H.equal(distance <= own_limit + EPSILON, true, "pair is inside the endpoint's distance limit")
                H.equal(distance <= partner_limit + EPSILON, true, "pair is inside the partner's distance limit")
            end
        end
    end
    H.equal(underground_count > 0, true, "route exercises underground pairs")
    H.equal(underground_count % 2, 0, "underground endpoints occur in complete pairs")
end

local function run_with_restart_observation(input)
    local state = Route.begin(input)
    local saw_restart = false
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        local restarts = state.counters.restarts
        Route.step(state, {ops = 1})
        if state.counters.restarts > restarts then
            saw_restart = true
            H.equal(#state.work.entities, 0, "a rip-up removes both ends of every working pair")
            H.equal(#state.work.segments, 0, "a rip-up removes the working segments with the pairs")
        end
    end
    H.equal(state.done, true, "route finishes while observing retries")
    H.equal(state.ok, true, "route reroutes successfully")
    H.equal(saw_restart, true, "pair check exercises a rip-up and reroute")
    return state
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " underground route results contain only complete, aligned pairs", function()
        local input = dofile(FROZEN)
        local state = run_with_restart_observation(input)
        assert_pairs(input, state.result)
    end)
end

H.done("test_underground_pairs")
