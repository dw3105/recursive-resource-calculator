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
    local base_belts, routed_belts = 139, 0
    local foundries = {
        ["item/iron-gear-wheel"] = {{20, 25}, {20, 26}},
        ["item/copper-plate"] = {{8, 25}, {8, 26}},
    }
    local flow_tiles = {}
    for _, segment in ipairs(work.segments or {}) do
        local is_belt = segment.kind == "belt"
        if is_belt then
            routed_belts = routed_belts + 1
            for flow_id in pairs(foundries) do
                for _, allocation in ipairs(segment.allocations or {}) do
                    if allocation.flow_id == flow_id then
                        local key = flow_id
                        flow_tiles[key] = flow_tiles[key] or {}
                        flow_tiles[key][tostring(segment.x) .. "," .. tostring(segment.y)] = true
                    end
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
    for _, segment in ipairs(work.segments or {}) do
        if segment.kind == "belt" and segment.y < 3 and segment.y ~= 3 then
            H.equal(true, false, "no routed belt above the row feed: " .. tostring(segment.x) .. "," .. tostring(segment.y))
        end
    end
    print("collector belt cells: base=" .. base_belts .. " routed=" .. routed_belts)
    H.equal(routed_belts < base_belts, true, "collector lowers total belt cells")
end)

H.done("test_route_collector")
