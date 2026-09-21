--Wire publication is checked as a physical graph, not just as an internal
--component count.  The validator consumes the sorted entity list, so these
--tests deliberately put selection order and world order at odds.
local H = require "tests.harness"
local Power = require "logic.bp.power"

local function rect(x, y, w, h)
    return {x = x, y = y, w = w, h = h}
end

local function finish(input, limit)
    local state = Power.begin(input)
    local ticks = 0
    while not state.done and ticks < (limit or 100000) do
        Power.step(state, {ops = 1})
        ticks = ticks + 1
    end
    H.equal(state.done, true, "wire fixture terminates")
    H.equal(state.result ~= nil, true, "wire fixture publishes")
    return state.result
end

local function error_with_code(result, code)
    for _, entry in ipairs(result.errors or {}) do
        if entry.code == code then return entry end
    end
    return nil
end

local function pole(name, quality, x, y, reach)
    return {name = name, quality = quality, x = x, y = y, tile_w = 1, tile_h = 1,
        supply_w = 0.5, supply_h = 0.5, wire_reach = reach, max_count = 1}
end

local function wire_endpoints(result, edge)
    local by_id = {}
    for _, entity in ipairs(result.entities) do by_id[entity.id] = entity end
    return by_id[edge.a_id], by_id[edge.b_id]
end

local function wire_distance(a, b)
    local ax, ay = a.x + a.w / 2, a.y + a.h / 2
    local bx, by = b.x + b.w / 2, b.y + b.h / 2
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function assert_legal_edges(result, message)
    for _, edge in ipairs(result.wires) do
        local a, b = wire_endpoints(result, edge)
        H.equal(a ~= nil and b ~= nil, true, message .. " endpoints exist")
        --pole_copper is 5, measured from the player's own 2.0.77 blueprint on 2026-09-21, not guessed from
        --the position of the field. logic/bp/power.lua, logic/bp/validate.lua and tests/harness.lua all say 5.
        H.equal(edge.a_connector, 5, message .. " starts on copper")
        H.equal(edge.b_connector, 5, message .. " ends on copper")
        H.equal(wire_distance(a, b) <= math.min(a.wire_reach, b.wire_reach) + 1e-9,
            true, message .. " is inside both endpoint reaches")
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " W1 an edge exactly at the smaller reach boundary is legal", function()
        local result = finish({
            grid_w = 8, grid_h = 2,
            consumers = {{id = "left", rect = rect(0, 0, 1, 1)}, {id = "right", rect = rect(5, 0, 1, 1)}},
            poles = {pole("left", "normal", 0, 0, 5), pole("right", "normal", 5, 0, 5)},
            limits = {max_poles = 2},
        })
        H.equal(#result.wires, 1, "the boundary edge is emitted")
        H.equal(result.components, 1, "the boundary edge joins the poles")
        assert_legal_edges(result, "the boundary edge")
    end)

    H.test(shape .. " W2 an edge one unit beyond reach is never emitted", function()
        local result = finish({
            grid_w = 9, grid_h = 2,
            consumers = {{id = "left", rect = rect(0, 0, 1, 1)}, {id = "right", rect = rect(6, 0, 1, 1)}},
            poles = {pole("left", "normal", 0, 0, 5), pole("right", "normal", 6, 0, 5)},
            limits = {max_poles = 2, max_relay_candidates = 0, max_relay_checks = 0},
        })
        H.equal(#result.wires, 0, "the over-range edge is not emitted")
        H.equal(result.components, 2, "the poles remain separate")
        H.equal(error_with_code(result, "BP_PW_DISCONNECTED") ~= nil, true,
            "the unconnected result is reported")
        assert_legal_edges(result, "the over-range result")
    end)

    H.test(shape .. " W3 mixed-quality reaches are applied at each pole", function()
        local result = finish({
            grid_w = 8, grid_h = 2,
            consumers = {{id = "normal", rect = rect(0, 0, 1, 1)}, {id = "rare", rect = rect(5, 0, 1, 1)}},
            poles = {pole("normal-pole", "normal", 0, 0, 4), pole("rare-pole", "rare", 5, 0, 6)},
            limits = {max_poles = 2},
        })
        H.equal(result.entities[1].quality, "normal", "the first pole keeps its quality")
        H.equal(result.entities[1].wire_reach, 4, "the normal pole keeps its reach")
        H.equal(result.entities[2].quality, "rare", "the second pole keeps its quality")
        H.equal(result.entities[2].wire_reach, 6, "the rare pole keeps its reach")
        H.equal(#result.wires, 0, "the smaller normal reach controls the edge")
        H.equal(result.components, 2, "mixed-quality poles do not overconnect")
        assert_legal_edges(result, "the mixed-quality result")
    end)

    H.test(shape .. " W4 pruning removes only a pole whose coverage and graph survive", function()
        local result = finish({
            grid_w = 18, grid_h = 4,
            consumers = {
                {id = "left", rect = rect(0, 0, 1, 1)},
                {id = "middle", rect = rect(5, 1, 1, 1)},
                {id = "right", rect = rect(10, 0, 1, 1)},
            },
            --All three poles are required for coverage.  The pruning pass must
            --therefore retain the complete connected graph rather than
            --orphaning one while trying to remove it.
            poles = {
                pole("left", "a", 0, 0, 20), pole("middle", "b", 5, 1, 20),
                pole("right", "c", 10, 0, 20),
            },
            limits = {max_poles = 3, prune = true},
        })
        H.equal(result.pole_count, 3, "coverage poles remain present")
        H.equal(result.components, 1, "pruning leaves one component")
        H.equal(#result.wires, 2, "the connected spanning edges survive pruning")
        assert_legal_edges(result, "the pruned result")
    end)

    H.test(shape .. " W5 a bounded failed connection is not proof of impossibility", function()
        local result = finish({
            grid_w = 12, grid_h = 2,
            consumers = {{id = "left", rect = rect(0, 0, 1, 1)}, {id = "right", rect = rect(10, 0, 1, 1)}},
            pole = {name = "short-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 0.5, supply_h = 0.5, wire_reach = 2},
            limits = {max_poles = 2, max_relay_candidates = 1, max_relay_checks = 1},
        })
        H.equal(result.components > 1, true, "the genuinely unconnectable fixture stays disconnected")
        H.equal(error_with_code(result, "BP_PW_SEARCH_BOUND") ~= nil, true,
            "bound exhaustion is reported as a search-bound failure")
        H.equal(error_with_code(result, "BP_PW_DISCONNECTED") ~= nil, true,
            "the partial graph still explains the failed connection")
        assert_legal_edges(result, "the bounded failure")
    end)

    H.test(shape .. " W6 sorted publication preserves the legal candidate graph", function()
        local result = finish({
            grid_w = 12, grid_h = 8,
            consumers = {
                {id = "b", rect = rect(0, 0, 1, 1)},
                {id = "a", rect = rect(5, 1, 1, 1)},
                {id = "c", rect = rect(10, 0, 1, 1)},
            },
            --Selection order is b, a, c; publication order is b, c, a.
            --The two legal edges go through a, while b-c is over range.
            poles = {pole("b", "a", 0, 0, 6), pole("a", "b", 5, 1, 6), pole("c", "c", 10, 0, 6)},
            limits = {max_poles = 3},
        })
        H.equal(result.components, 1, "the internal candidate graph is connected")
        H.equal(#result.wires, 2, "the spanning edges are published")
        assert_legal_edges(result, "the sorted publication")
    end)
end

H.done("test_power_wires")
