-- This regression fails before the collector grouping fix: the frozen candidate routes each
-- adjacent output hand independently and sends copper over the top of the feed row.
local H = require "tests.harness"
local Route = require "logic.bp.route"

H.test("adjacent output hands share a collector on the frozen red science route", function()
    H.new_world(H.shapes()[1])
    local file = assert(io.open("tests/fixtures/route_red10s_final.json"))
    local root = helpers.json_to_table(file:read("*a")); file:close()
    local state = Route.begin(root)
    while not state.done do Route.step(state, {ops = 100000}) end
    H.equal(state.ok, true, "frozen route completes")
    local work = state.work or state._work
    local demand_counts = {}
    for _, demand in ipairs(work.demands or {}) do
        if foundries[demand.flow_id] then demand_counts[demand.flow_id] = (demand_counts[demand.flow_id] or 0) + 1 end
    end
    for flow_id in pairs(foundries) do H.equal(demand_counts[flow_id], 1, flow_id .. " has one collector demand") end
    local base_belts, routed_belts = 139, 0
    local foundries = {
        ["item/iron-gear-wheel"] = {{20, 25}, {20, 26}},
        ["item/copper-plate"] = {{8, 25}, {8, 26}},
    }
    local flow_tiles = {}
    local coordinates = {}
    for key, segment in pairs(work.segments_by_cell or {}) do
        if segment.kind == "belt" then
            routed_belts = routed_belts + 1
            local x, y = key:match("^(-?%d+):(-?%d+)$")
            x, y = tonumber(x), tonumber(y)
            coordinates[key] = {x = x, y = y, segment = segment}
            local x, y = coordinates[key].x, coordinates[key].y
            for flow_id, drops in pairs(foundries) do
                local has_flow = false
                for _, allocation in ipairs(segment.allocations or {}) do
                    if allocation.flow_id == flow_id then has_flow = true end
                end
                if has_flow then
                    flow_tiles[flow_id] = flow_tiles[flow_id] or {}
                    flow_tiles[flow_id][x .. "," .. y] = true
                end
            end
        end
    end
    for flow_id, drops in pairs(foundries) do
        local tiles = flow_tiles[flow_id] or {}
        for _, point in ipairs(drops) do
            H.equal(tiles[point[1] .. "," .. point[2]], true, flow_id .. " belt touches drop tile")
        end
        local seen, queue = {}, {{drops[1][1], drops[1][2]}}
        while #queue > 0 do
            local point = table.remove(queue)
            local key = point[1] .. "," .. point[2]
            if tiles[key] and not seen[key] then
                seen[key] = true
                for _, delta in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
                    queue[#queue + 1] = {point[1] + delta[1], point[2] + delta[2]}
                end
            end
        end
        H.equal(seen[drops[2][1] .. "," .. drops[2][2]], true, flow_id .. " drops join one connected run")
    end
    for _, cell in pairs(coordinates) do
        if cell.y < 3 then
            H.equal(true, false, "no routed belt above the row feed: " .. tostring(cell.x) .. "," .. tostring(cell.y))
        end
    end
    print("collector belt cells: base=" .. base_belts .. " routed=" .. routed_belts)
    H.equal(routed_belts < base_belts, true, "collector lowers total belt cells")
end)

H.done("test_route_collector")
