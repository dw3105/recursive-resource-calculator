--Power placement covers consumers and emits only legal copper wire edges.
local H = require "tests.harness"

local Power = require "logic.bp.power"

local function rect(x, y, w, h)
    return {x = x, y = y, w = w, h = h}
end

local function consumer(id, shape)
    return {id = id, rect = shape}
end

local function occupied(shape, owner)
    return {{rect = shape, owner = owner}}
end

local function finish(input)
    local state = Power.begin(input)
    local ticks = 0
    while not state.done and ticks < 10000 do
        Power.step(state, {ops = 1})
        ticks = ticks + 1
    end
    H.equal(state.done, true, "power search completes")
    H.equal(state.result ~= nil, true, "power publishes a result")
    return state.result
end

local function error_with_code(result, code)
    for _, error in ipairs(result.errors or {}) do
        if error.code == code then return error end
    end
    return nil
end

--The fallback matches logic/bp/power.lua's: pole_copper is 5, measured from the player's own 2.0.77 blueprint
--on 2026-09-21, not guessed from the position of the field.
local function copper_id()
    if type(defines) == "table" and type(defines.wire_connector_id) == "table" then
        return defines.wire_connector_id.pole_copper
    end
    return 5
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " BP9 publishes pole position at the rect center", function()
        local result = finish({
            grid_w = 12, grid_h = 6,
            occupied = occupied(rect(4, 2, 1, 1), "assembler"),
            consumers = {consumer("assembler", rect(4, 2, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
            limits = {max_poles = 4},
        })
        local pole = result.entities[1]
        local expected_x, expected_y = pole.rect.x + pole.rect.w / 2, pole.rect.y + pole.rect.h / 2
        local actual = pole.position and (tostring(pole.position.x) .. "," .. tostring(pole.position.y)) or "missing"
        local expected = tostring(expected_x) .. "," .. tostring(expected_y)
        H.equal(actual, expected,
            "pole position " .. actual .. " matches rect center " .. expected)
    end)

    H.test(shape .. " BP1 covers every consumer and reports the pole count", function()
        local result = finish({
            grid_w = 12, grid_h = 6,
            occupied = occupied(rect(4, 2, 2, 1), "assembler"),
            consumers = {consumer("assembler", rect(4, 2, 2, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
            limits = {max_poles = 4},
        })
        H.equal(#result.uncovered, 0, "every consumer is covered")
        H.equal(result.pole_count, #result.entities, "pole count matches entities")
        H.equal(result.pole_count, 1, "one pole covers the fixture")
        H.equal(result.components, 1, "the one pole is one component")
        H.equal(result.connection_point ~= nil, true, "an external connection point is exposed")
    end)

    H.test(shape .. " BP2 does not require coverage for a roboport", function()
        local result = finish({
            grid_w = 12, grid_h = 6,
            occupied = {
                {rect = rect(2, 2, 2, 2), owner = "roboport"},
                {rect = rect(7, 2, 1, 1), owner = "assembler"},
            },
            --The roboport is intentionally absent from consumers.
            consumers = {consumer("assembler", rect(7, 2, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 3.5, supply_h = 3.5, wire_reach = 9},
            limits = {max_poles = 4},
        })
        H.equal(#result.uncovered, 0, "the roboport does not become an uncovered consumer")
        H.equal(error_with_code(result, "BP_PW_UNCOVERED"), nil, "no uncovered error is emitted for the roboport")
    end)

    H.test(shape .. " BP3 reports disconnected clusters instead of wiring beyond reach", function()
        local result = finish({
            grid_w = 18, grid_h = 4,
            occupied = {
                {rect = rect(1, 1, 1, 1), owner = "left"},
                {rect = rect(15, 1, 1, 1), owner = "right"},
            },
            consumers = {consumer("left", rect(1, 1, 1, 1)), consumer("right", rect(15, 1, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 5},
            limits = {max_poles = 2},
        })
        H.equal(#result.uncovered, 0, "both distant consumers are covered")
        H.equal(result.pole_count, 2, "one pole is placed for each cluster")
        H.equal(result.components, 2, "the clusters remain two components")
        H.equal(#result.wires, 0, "no illegal long wire is returned")
        H.equal(error_with_code(result, "BP_PW_DISCONNECTED") ~= nil, true, "disconnection is reported")
    end)

    H.test(shape .. " BP4 uses the smaller reach for a mixed-quality edge", function()
        local result = finish({
            grid_w = 10, grid_h = 3,
            occupied = {
                {rect = rect(1, 1, 1, 1), owner = "left"},
                {rect = rect(9, 1, 1, 1), owner = "right"},
            },
            consumers = {consumer("left", rect(1, 1, 1, 1)), consumer("right", rect(9, 1, 1, 1))},
            --Each quality is available once.  The deterministic output order
            --puts the higher-quality pole first at the left-hand position.
            poles = {
                {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                    supply_w = 1.5, supply_h = 1.5, wire_reach = 5, max_count = 1},
                {name = "medium-electric-pole", quality = "legendary", tile_w = 1, tile_h = 1,
                    supply_w = 1.5, supply_h = 1.5, wire_reach = 10, max_count = 1},
            },
            limits = {max_poles = 2},
        })
        H.equal(result.pole_count, 2, "the mixed fixture has two poles")
        H.equal(result.entities[1].quality, "legendary", "the first pole is the high-quality pole")
        H.equal(result.entities[2].quality, "normal", "the second pole is the low-quality pole")
        H.equal(result.components, 2, "seven tiles exceeds the normal pole's reach")
        H.equal(#result.wires, 0, "the mixed-quality pair is not wired illegally")
        H.equal(error_with_code(result, "BP_PW_DISCONNECTED") ~= nil, true, "the mixed-quality gap is reported")
    end)

    H.test(shape .. " BP5 higher quality supply area needs fewer poles", function()
        local input = {
            grid_w = 11, grid_h = 4,
            occupied = {
                {rect = rect(1, 1, 1, 1), owner = "a"},
                {rect = rect(5, 1, 1, 1), owner = "b"},
                {rect = rect(9, 1, 1, 1), owner = "c"},
            },
            consumers = {
                consumer("a", rect(1, 1, 1, 1)), consumer("b", rect(5, 1, 1, 1)),
                consumer("c", rect(9, 1, 1, 1)),
            },
            limits = {max_poles = 8},
        }
        input.pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
            supply_w = 2, supply_h = 2, wire_reach = 20}
        local normal = finish(input)
        input.pole = {name = "medium-electric-pole", quality = "legendary", tile_w = 1, tile_h = 1,
            supply_w = 5.5, supply_h = 5.5, wire_reach = 20}
        local legendary = finish(input)
        H.equal(normal.pole_count, 2, "normal supply area overlaps the three consumers with two poles")
        H.equal(legendary.pole_count, 1, "higher quality supply area needs one pole")
    end)

    H.test(shape .. " BP6 returned edges are copper and within both endpoint reaches", function()
        local result = finish({
            grid_w = 9, grid_h = 3,
            occupied = {
                {rect = rect(1, 1, 1, 1), owner = "left"},
                {rect = rect(8, 1, 1, 1), owner = "right"},
            },
            consumers = {consumer("left", rect(1, 1, 1, 1)), consumer("right", rect(8, 1, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 10},
            limits = {max_poles = 2},
        })
        H.equal(result.components, 1, "the legal edge makes one component")
        H.equal(#result.wires, 1, "one legal edge joins two poles")
        local by_id = {}
        for _, entity in ipairs(result.entities) do by_id[entity.id] = entity end
        for _, edge in ipairs(result.wires) do
            H.equal(edge.a_connector, copper_id(), "edge starts on a copper connector")
            H.equal(edge.b_connector, copper_id(), "edge ends on a copper connector")
            H.equal(edge.a_connector == (defines and defines.wire_connector_id.circuit_red or 3), false,
                "edge does not use circuit red")
            H.equal(edge.b_connector == (defines and defines.wire_connector_id.circuit_green or 4), false,
                "edge does not use circuit green")
            local a, b = by_id[edge.a_id], by_id[edge.b_id]
            local ax, ay = a.x + a.w / 2, a.y + a.h / 2
            local bx, by = b.x + b.w / 2, b.y + b.h / 2
            local distance = math.sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by))
            H.equal(distance <= math.min(a.wire_reach, b.wire_reach) + 1e-9, true,
                "edge is within the smaller endpoint reach")
        end
    end)

    H.test(shape .. " BP7 same input gives identical poles and edges", function()
        local input = {
            grid_w = 10, grid_h = 4,
            occupied = {
                {rect = rect(1, 1, 1, 1), owner = "a"},
                {rect = rect(8, 1, 1, 1), owner = "b"},
            },
            consumers = {consumer("b", rect(8, 1, 1, 1)), consumer("a", rect(1, 1, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 10},
            limits = {max_poles = 2},
        }
        local first, second = finish(input), finish(input)
        H.deep_equal(first.entities, second.entities, "pole placement is deterministic")
        H.deep_equal(first.wires, second.wires, "wire selection is deterministic")
    end)

    H.test(shape .. " BP8 names a consumer with no covering pole position", function()
        local result = finish({
            grid_w = 4, grid_h = 4,
            consumers = {consumer("impossible-machine", rect(1, 1, 1, 1))},
            pole = {name = "medium-electric-pole", quality = "normal", tile_w = 1, tile_h = 1,
                supply_w = 0, supply_h = 0, wire_reach = 9},
            limits = {max_poles = 4},
        })
        H.equal(#result.uncovered, 1, "one consumer remains uncovered")
        H.equal(result.uncovered[1], "impossible-machine", "the uncovered id is preserved")
        local error = error_with_code(result, "BP_PW_UNCOVERED")
        H.equal(error ~= nil, true, "the uncovered reason is emitted")
        H.equal(error.ids[1], "impossible-machine", "the reason names the consumer")
    end)
end

H.done("test_power")
