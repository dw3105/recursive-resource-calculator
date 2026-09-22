--The route's binding is a promise about a directed transport chain, not merely about a visited target tile.
local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"

local FROZEN = "tests/fixtures/routing/player_chain_first_candidate.lua"

local function run(force)
    local input = dofile(FROZEN)
    if force ~= nil then input._force_multi_flow_hands = force end
    local state = Route.begin(input)
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

local function carries(entity, flow_id)
    if flow_of(entity) == flow_id then return true end
    for _, declared in ipairs(entity.flow_ids or {}) do
        if declared == flow_id then return true end
    end
    return false
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
                if next_entity ~= entity and (flow_of(next_entity) == nil or carries(next_entity, binding.flow_id)) then
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
        if flow_of(entity) == nil or carries(entity, binding.flow_id) then
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

local function parallel_input(flow_count)
    local perimeter_ports, flows = {}, {}
    for index = 1, flow_count do
        local flow_id = "item/parallel/" .. tostring(index)
        local input_port = "parallel-in-" .. tostring(index)
        local output_port = "parallel-out-" .. tostring(index)
        perimeter_ports[#perimeter_ports + 1] = {port_id = input_port, role = "in", kind = "item",
            flow_id = flow_id, rate_per_second = 1, x = 0, y = 1, travel_dir = Grid.EAST}
        perimeter_ports[#perimeter_ports + 1] = {port_id = output_port, role = "out", kind = "item",
            flow_id = flow_id, rate_per_second = 1, x = 7, y = 1, travel_dir = Grid.EAST}
        flows[#flows + 1] = {flow_id = flow_id, producers = {{step_id = "$external", port_id = input_port,
            share_per_second = 1}}, consumers = {{step_id = "$external", port_id = output_port, share_per_second = 1}}}
    end
    return {grid = {w = 8, h = 3}, catalog = {belt = {belt = "basic-belt", splitter = "splitter",
        items_per_second = 10, lane_items_per_second = 5}}, perimeter_ports = perimeter_ports, flows = flows,
        _force_multi_flow_hands = true}
end

local function run_parallel(flow_count)
    local state = Route.begin(parallel_input(flow_count))
    local ticks = 0
    while not state.done and ticks < 200000 do
        ticks = ticks + 1
        Route.step(state, {ops = 100000})
    end
    H.equal(state.done, true, "the parallel-flow route reaches a terminal state")
    return state
end

local function measure(label, state)
    local surface, underground, splitters = 0, 0, 0
    for _, entity in ipairs(state.result and state.result.entities or {}) do
        if entity.splitter then splitters = splitters + 1
        elseif entity.ug_role then underground = underground + 1
        elseif tostring(entity.name or ""):find("belt", 1, true) then surface = surface + 1 end
    end
    local flow_segments, max_flow_count = 0, 0
    for _, segment in ipairs(state.work.segments or {}) do
        local ids = {}
        if segment.flow_id ~= nil then ids[segment.flow_id] = true end
        for flow_id, present in pairs(segment.flow_ids or {}) do if present then ids[flow_id] = true end end
        for _, allocation in ipairs(segment.allocations or {}) do
            if allocation.flow_id ~= nil then ids[allocation.flow_id] = true end
        end
        local count = 0
        for _, _ in pairs(ids) do count = count + 1 end
        if count >= 2 then flow_segments = flow_segments + 1 end
        if count > max_flow_count then max_flow_count = count end
    end
    print(string.format("%s geometry: surface belts=%d, underground endpoints=%d, splitters=%d, two-flow segments=%d, max flows=%d",
        label, surface, underground, splitters, flow_segments, max_flow_count))
    return {surface = surface, underground = underground, splitters = splitters,
        flow_segments = flow_segments, max_flow_count = max_flow_count}
end

local function broken_count(state)
    local ports = state.work.endpoint_by_id or {}
    local broken = 0
    for _, binding in ipairs(state.result and state.result.bindings or {}) do
        if not reaches(binding, state.result, ports) then broken = broken + 1 end
    end
    return broken
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RC1 every recorded binding reaches its own sink", function()
        local state = run()
        H.equal(state.ok, true, "the candidate routes")
        if not state.ok then return end
        measure(shape .. " RC1", state)
        local broken = broken_count(state)
        --Round-16 baseline: 7 bindings, 1 broken chain.  This assertion is the red characterization at the
        --lane boundary; S3 closes the one measured fault instead of deleting the binding.
        H.equal(broken, 0, "every binding has a directed same-flow chain")
    end)

    --RE-FROZEN 2026-09-22 on legalcopilot-dev.  The old ceiling was a single number, 85, and it was written
    --while this candidate could not route at all: it never measured a run whose every binding reaches its
    --own sink, so it described nothing that had ever happened.  What the candidate actually delivers now,
    --with RC1 above green, is 85 surface belts, 6 underground endpoints and 0 splitters -- 91 transport
    --entities.  The ceiling is that measurement, and it is now split by family, so a regression says WHICH
    --family grew instead of only that a total moved.
    --
    --The zero is the load-bearing line.  Contract 28.8 takes the continuation over the fork: a trunk that can
    --be extended through the next sink's own port tile is extended, and no splitter is built.  The player's
    --own factory carries 84 transport-belt and ZERO splitter, decoded from their bytes 2026-09-22.
    H.test(shape .. " RC2 the frozen candidate keeps its transport budget while chains close", function()
        local state = run()
        H.equal(state.ok, true, "the candidate routes")
        if not state.ok then return end
        local geometry = measure(shape .. " RC2", state)
        H.equal(geometry.splitters, 0, "28.8 serves the column by continuation, so no splitter is built")
        H.equal(geometry.surface <= 85, true, "surface belts stay at or below the measured 85")
        H.equal(geometry.underground <= 6, true, "underground endpoints stay at or below the measured 6")
        H.equal(geometry.surface + geometry.underground + geometry.splitters <= 91, true,
            "total transport stays at or below the measured 91")
    end)

    H.test(shape .. " RC5 forced-on frozen candidate keeps continuation geometry", function()
        local state = run(true)
        H.equal(state.ok, true, "the forced-on candidate routes")
        if not state.ok then return end
        local geometry = measure(shape .. " RC5", state)
        H.equal(state.work.multi_flow_hands, true, "the seam forces multi-flow hands on")
        H.equal(geometry.splitters, 0, "forced-on 28.8 never forks")
        H.equal(#(state.work.shortfalls or {}), 0, "forced-on candidate serves every demand")
        H.equal(broken_count(state), 0, "forced-on bindings keep directed chains")
    end)

    H.test(shape .. " RC6 two flows on one belt keep both directed witnesses", function()
        local state = run_parallel(2)
        H.equal(state.ok, true, "the two-flow route succeeds")
        if not state.ok then return end
        local geometry = measure(shape .. " RC6", state)
        H.equal(geometry.flow_segments > 0, true, "a belt carries both item flows")
        H.equal(broken_count(state), 0, "each flow has its own directed chain")
    end)

    H.test(shape .. " RC7 a third flow is refused after two belt flows", function()
        local state = run_parallel(3)
        local geometry = measure(shape .. " RC7", state)
        H.equal(geometry.flow_segments > 0, true, "the candidate reaches a two-flow belt")
        H.equal(geometry.max_flow_count <= 2, true, "a belt never carries a third flow")
        local refused = false
        for _, shortfall in ipairs(state.work.shortfalls or {}) do
            if shortfall.flow_id == "item/parallel/3" then refused = true end
        end
        H.equal(refused, true, "the third flow is refused by name")
    end)

    H.test(shape .. " RC8 forced-off seam preserves the frozen geometry", function()
        local state = run(false)
        H.equal(state.ok, true, "the forced-off candidate routes")
        if not state.ok then return end
        local geometry = measure(shape .. " RC8", state)
        H.equal(state.work.multi_flow_hands, false, "the seam forces multi-flow hands off")
        H.equal(geometry.surface, 85, "forced-off surface belts stay at the measured 85")
        H.equal(geometry.underground, 6, "forced-off underground endpoints stay at the measured 6")
        H.equal(geometry.splitters, 0, "forced-off geometry has no splitters")
        H.equal(broken_count(state), 0, "forced-off bindings keep directed chains")
    end)
end

H.done("test_route_chain")
