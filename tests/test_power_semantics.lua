--Power semantics that are easy to get subtly wrong: overlap, quality, entity-sized consumers and bounded relays.
local H = require "tests.harness"
local Power = require "logic.bp.power"

local function rect(x, y, w, h) return {x = x, y = y, w = w, h = h} end

local function finish(input)
    local state = Power.begin(input)
    for _ = 1, 20000 do
        if state.done then break end
        Power.step(state, {ops = 1})
    end
    H.equal(state.done, true, "power semantics fixture terminates")
    H.equal(state.result ~= nil, true, "power semantics fixture publishes a result")
    return state.result
end

local function has_error(result, code)
    for _, error in ipairs(result.errors or {}) do
        if error.code == code then return true end
    end
    return false
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " overlap covers a whole machine without containing it", function()
        local result = finish({
            grid_w = 14, grid_h = 14,
            occupied = {{rect = rect(4, 4, 5, 5)}},
            consumers = {{id = "machine", rect = rect(4, 4, 5, 5)}},
            pole = {name = "small-electric-pole", tile_w = 1, tile_h = 1,
                supply_w = 2.5, supply_h = 2.5, wire_reach = 7.5},
        })
        H.equal(result.pole_count, 1, "one pole overlaps the large machine")
        H.equal(#result.uncovered, 0, "the large machine is covered")
        H.equal(result.components, 1, "the covering pole is connected")
    end)

    H.test(shape .. " an obstacle can require an off-lattice relay", function()
        local result = finish({
            grid_w = 22, grid_h = 3,
            occupied = {
                {rect = rect(0, 0, 22, 1)}, {rect = rect(0, 2, 22, 1)},
                {rect = rect(1, 1, 1, 1)}, {rect = rect(19, 1, 1, 1)},
            },
            consumers = {{id = "a", rect = rect(1, 1, 1, 1)}, {id = "b", rect = rect(19, 1, 1, 1)}},
            pole = {name = "test-pole", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 9},
        })
        H.equal(result.pole_count, 3, "the relay is retained")
        H.equal(result.components, 1, "the off-lattice relay joins both poles")
        H.equal(#result.uncovered, 0, "both machines are covered")
        H.equal(result.entities[2].x, 9, "the relay is at the only legal middle tile")
        H.equal(result.entities[2].y, 1, "the relay is in the only free row")
    end)

    H.test(shape .. " overlap handles a rotated non-square consumer rectangle", function()
        local result = finish({
            grid_w = 10, grid_h = 10,
            occupied = {{rect = rect(4, 3, 2, 4)}},
            consumers = {{id = "rotated-machine", rect = rect(4, 3, 2, 4), direction = 4}},
            pole = {name = "small-electric-pole", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 8},
        })
        H.equal(#result.uncovered, 0, "the pole overlaps the rotated footprint")
    end)

    H.test(shape .. " a one-tile miss remains uncovered", function()
        local result = finish({
            grid_w = 8, grid_h = 5,
            occupied = {{rect = rect(5, 2, 1, 1)}},
            consumers = {{id = "missed", rect = rect(5, 2, 1, 1)}},
            pole = {name = "small-electric-pole", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 8, x = 2, y = 2},
        })
        H.equal(#result.uncovered, 1, "the missed consumer stays uncovered")
        H.equal(result.uncovered[1], "missed", "the uncovered id is preserved")
        H.equal(has_error(result, "BP_PW_UNCOVERED"), true, "the miss has an uncovered error")
    end)

    H.test(shape .. " a quality-specific supply distance changes coverage", function()
        local input = {
            grid_w = 12, grid_h = 5,
            occupied = {{rect = rect(2, 2, 1, 1)}, {rect = rect(8, 2, 1, 1)}},
            consumers = {{id = "a", rect = rect(2, 2, 1, 1)}, {id = "b", rect = rect(8, 2, 1, 1)}},
            limits = {max_poles = 4},
        }
        input.pole = {name = "quality-pole", quality = "normal", tile_w = 1, tile_h = 1,
            supply_area_distance_by_quality = {normal = 2, rare = 4}, wire_reach = 20}
        local normal = finish(input)
        input.pole.quality = "rare"
        local rare = finish(input)
        H.equal(normal.pole_count, 2, "normal quality needs two poles")
        H.equal(rare.pole_count, 1, "the larger rare supply distance needs one pole")
    end)

    H.test(shape .. " a distant beacon needs its own electrical coverage", function()
        local result = finish({
            grid_w = 12, grid_h = 5,
            occupied = {{rect = rect(1, 2, 1, 1)}, {rect = rect(8, 2, 1, 1)}},
            consumers = {
                {id = "machine", rect = rect(1, 2, 1, 1)},
                {id = "beacon", rect = rect(8, 2, 1, 1)},
            },
            pole = {name = "small-electric-pole", tile_w = 1, tile_h = 1,
                supply_w = 2, supply_h = 2, wire_reach = 20},
            limits = {max_poles = 4},
        })
        H.equal(#result.uncovered, 0, "the beacon is covered")
        H.equal(result.pole_count, 2, "the beacon forces another pole")
    end)

    H.test(shape .. " a disconnected layout terminates inside the relay bound", function()
        local result = finish({
            grid_w = 18, grid_h = 4,
            occupied = {{rect = rect(1, 1, 1, 1)}, {rect = rect(15, 1, 1, 1)}},
            consumers = {{id = "left", rect = rect(1, 1, 1, 1)}, {id = "right", rect = rect(15, 1, 1, 1)}},
            pole = {name = "short-pole", tile_w = 1, tile_h = 1,
                supply_w = 1.5, supply_h = 1.5, wire_reach = 5},
            limits = {max_poles = 3, max_off_lattice_candidates = 8, max_off_lattice_checks = 64},
        })
        H.equal(#result.uncovered, 0, "both distant consumers are covered")
        H.equal(result.components > 1, true, "the genuinely disconnected layout stays disconnected")
        H.equal(has_error(result, "BP_PW_DISCONNECTED"), true, "disconnection is reported")
    end)
end

H.done("test_power_semantics")
