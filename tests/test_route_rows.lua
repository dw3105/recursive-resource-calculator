local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Route = require "logic.bp.route"
local Row = require "tests.fixtures.row_block"

local function make_input(dir)
    local row = Row.science_row(dir, 12, 12)
    local runs, ports, machines = row.belt_runs, {}, {}
    local step = "automation-science-pack"
    for i, p in ipairs(row.ports) do
        local copy = {}
        for k, v in pairs(p) do copy[k] = v end
        copy.step_id = step
        copy.kind, copy.rate_per_second = "item", 1
        ports[#ports + 1] = copy
    end
    for _, m in ipairs(row.machines) do machines[#machines + 1] = m end
    local input_ports, source_points = {}, {}
    for index, feed in ipairs(runs[1].feeds) do
        local x, y = feed.side_tile.x, feed.side_tile.y
        local dx, dy = Grid.dir_vector(Grid.dir_opposite(feed.travel_dir))
        local id = "source:" .. feed.flow_id
        input_ports[#input_ports + 1] = {port_id = id, role = "in", flow_id = feed.flow_id,
            x = x + dx * 7, y = y + dy * 7, travel_dir = feed.travel_dir, rate_per_second = 1}
        source_points[index] = {port_id = id, step_id = "$external", share_per_second = 1}
    end
    local out = runs[2].port
    local dx, dy = Grid.dir_vector(out.travel_dir)
    local sink_id = "sink:packs"
    input_ports[#input_ports + 1] = {port_id = sink_id, role = "out", flow_id = Row.PACK,
        x = out.x + dx * 7, y = out.y + dy * 7, travel_dir = out.travel_dir, rate_per_second = 1}
    local flows = {}
    for i, feed in ipairs(runs[1].feeds) do
        flows[#flows + 1] = {flow_id = feed.flow_id, producers = {source_points[i]},
            consumers = {{step_id = step, share_per_second = 1}}}
    end
    flows[#flows + 1] = {flow_id = Row.PACK,
        producers = {{step_id = step, share_per_second = 1}},
        consumers = {{step_id = "$external", port_id = sink_id, share_per_second = 1}}}
    return {grid = {w = 40, h = 40}, blocks = {{block_id = step, step_id = step,
        x = 0, y = 0, w = 1, h = 1, entities = machines, ports = ports}},
        perimeter_ports = input_ports, flows = flows, belt_runs = runs, multi_flow_hands = true,
        catalog = {belt = {belt = "basic-belt", items_per_second = 10}}}
end

local function finish(input, before_improve)
    local state = Route.begin(input)
    local ticks = 0
    while not state.done and ticks < 10000 do
        ticks = ticks + 1
        Route.step(state, {ops = 1})
        if before_improve and not state.work.improved and not state.work.improve_state
            and state.cursor.demand_index > #state.work.demands then
            before_improve(state)
            before_improve = nil
        end
    end
    return state, ticks
end

for _, shape in ipairs(H.shapes()) do
    for _, dir in ipairs({Grid.NORTH, Grid.EAST}) do
        H.test(shape .. " RR fixed science row runs and feeds", function()
            local run = make_input(dir).belt_runs
            local before = {}
            local state = finish(make_input(dir), function(current)
                for _, belt_run in ipairs(run) do
                    for _, tile in ipairs(belt_run.tiles) do
                        local seg = current.work.segments_by_cell[tostring(tile.x) .. ":" .. tostring(tile.y)]
                        before[tostring(tile.x) .. ":" .. tostring(tile.y)] = seg and seg.segment_id
                    end
                end
            end)
            H.equal(state.ok, true, "row route succeeds")
            if not state.ok then return end
            local by_tile = {}
            for key, segment in pairs(state.work.segments_by_cell) do by_tile[key] = segment end
            local function key(p) return tostring(p.x) .. ":" .. tostring(p.y) end
            local row = run
            for _, tile in ipairs(row[1].tiles) do
                local s = by_tile[key(tile)]
                H.equal(s ~= nil and s.fixed and s.direction == row[1].dir, true, "input tile remains fixed")
                H.equal(s ~= nil and s.flow_ids[Row.COPPER] and s.flow_ids[Row.GEAR], true, "both input flows use run")
                H.equal(s ~= nil and #s.allocations >= 2, true, "input run allocates both hand flows")
            end
            for _, tile in ipairs(row[2].tiles) do
                local s = by_tile[key(tile)]
                H.equal(s ~= nil and s.fixed and s.flow_ids[Row.PACK], true, "output tile carries packs")
            end
            local hdx, hdy = Grid.dir_vector(row[1].dir)
            local behind = {x = row[1].head.x - hdx, y = row[1].head.y - hdy}
            H.equal(by_tile[key(behind)] == nil, true, "head has no belt feeding from behind")
            for _, feed in ipairs(row[1].feeds) do
                local binding
                for _, b in ipairs(state.result.bindings or {}) do
                    if b.flow_id == feed.flow_id then binding = b end
                end
                H.equal(binding ~= nil, true, "feed flow has a binding")
                if binding then
                    local sink = state.work.endpoint_by_id[binding.sink_port_id]
                    H.equal(key(sink), key(feed.side_tile), "demand ends at feed side")
                    H.equal(sink.travel_dir, feed.travel_dir, "feed heads into row head")
                end
            end
            for tile_key, segment_id in pairs(before) do
                H.equal(by_tile[tile_key] and by_tile[tile_key].segment_id, segment_id, "improve keeps fixed run")
            end
        end)
    end
end

H.done("test_route_rows")
