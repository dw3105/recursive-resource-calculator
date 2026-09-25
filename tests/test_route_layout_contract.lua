--Hand-written route layouts prove that validation does not trust the router's occupancy decisions.
local H = require "tests.harness"

local Grid = require "logic.bp.grid"
local Validate = require "logic.bp.validate"

local function box(left, top, right, bottom)
    return {left_top = {x = left, y = top}, right_bottom = {x = right, y = bottom}}
end

local function catalog()
    return {
        entity = {
            belt = {name = "belt", etype = "transport-belt", tile_w = 1, tile_h = 1,
                collision_box = box(-0.4, -0.4, 0.4, 0.4), collision_mask = {"belt-layer"}, needs_power = false},
            ug = {name = "ug", etype = "underground-belt", tile_w = 1, tile_h = 1,
                collision_box = box(-0.4, -0.4, 0.4, 0.4), collision_mask = {"belt-layer"}, needs_power = false},
            pipe = {name = "pipe", etype = "pipe", tile_w = 1, tile_h = 1,
                collision_box = box(-0.4, -0.4, 0.4, 0.4), collision_mask = {"pipe-layer"}, needs_power = false},
            asym = {name = "asym", etype = "assembling-machine", tile_w = 2, tile_h = 1,
                collision_box = box(-1, -0.2, 1, 0.2), collision_mask = {"object-layer"}, needs_power = false},
            tiny = {name = "tiny", etype = "assembling-machine", tile_w = 1, tile_h = 1,
                collision_box = box(-0.4, -0.4, 0.4, 0.4), collision_mask = {"object-layer"}, needs_power = false},
        },
        belt = {items_per_second = 10, underground_max_distance = 3},
        pipe = {throughput_per_second = 100, underground_max_distance = 3},
    }
end

local function finish(input)
    input.catalog = input.catalog or catalog()
    local state = Validate.begin(input)
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        H.equal(ticks < 1000, true, "validator finishes")
        Validate.step(state, {ops = 1})
    end
    return state
end

--Round 37: these fragments are a bare crossing or approach belt with nothing feeding them, so the round-37 rule
--BP_V_BELT_NO_SOURCE (a belt run nothing feeds) fires on every one of them. The contract here is about crossings
--and approaches, so a fragment passes when that is its only complaint.
local function ok_but_unfed(state)
    for _, error in ipairs(state.errors or {}) do
        if error.code ~= "BP_V_BELT_NO_SOURCE" then return false end
    end
    return true
end

local function has_code(state, code)
    for _, error in ipairs(state.errors or {}) do
        if error.code == code then return true end
    end
    return false
end

local function endpoint(id, x, y, direction, kind, extra)
    local result = {id = id, name = kind == "pipe" and "pipe" or "ug", kind = kind == "pipe" and "pipe" or "belt",
        position = {x = x + 0.5, y = y + 0.5}, direction = direction,
        type = extra and extra.type or (id:find("in", 1, true) and "input" or "output"),
        ug_role = extra and extra.ug_role or (id:find("in", 1, true) and "input" or "output"),
        ug_pair_id = extra and extra.ug_pair_id, flow_id = extra and extra.flow_id or "item/cross"}
    return result
end

local function crossing(direction, middle_flow)
    local locations = {
        [Grid.NORTH] = {{x = 2, y = 4}, {x = 2, y = 2}},
        [Grid.EAST] = {{x = 1, y = 2}, {x = 3, y = 2}},
        [Grid.SOUTH] = {{x = 2, y = 1}, {x = 2, y = 3}},
        [Grid.WEST] = {{x = 3, y = 2}, {x = 1, y = 2}},
    }
    local pair = locations[direction]
    local first = endpoint("cross-in", pair[1].x, pair[1].y, direction, "belt",
        {type = "input", ug_role = "input", ug_pair_id = "cross-out"})
    local second = endpoint("cross-out", pair[2].x, pair[2].y, direction, "belt",
        {type = "output", ug_role = "output", ug_pair_id = "cross-in"})
    local entities = {first, second}
    if middle_flow then
        local middle_x = (pair[1].x + pair[2].x) / 2
        local middle_y = (pair[1].y + pair[2].y) / 2
        entities[#entities + 1] = {id = "cross-middle", name = "belt", kind = "belt", flow_id = middle_flow,
            position = {x = middle_x + 0.5, y = middle_y + 0.5}, direction = direction}
    end
    return {grid = {w = 7, h = 7}, entities = entities}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " L1 all cardinal underground crossings with an opposing middle flow are legal", function()
        for _, direction in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local state = finish(crossing(direction, "item/other"))
            H.equal(ok_but_unfed(state), true, "cardinal crossing is accepted")
        end
    end)

    H.test(shape .. " L2 underground endpoint types and direction are verified", function()
        local wrong_type = crossing(Grid.EAST)
        wrong_type.entities[2].type, wrong_type.entities[2].ug_role = "input", "input"
        local type_state = finish(wrong_type)
        H.equal(type_state.ok, false, "two input endpoints are rejected")
        H.equal(has_code(type_state, "BP_V_UNDERGROUND_UNPAIRED"), true, "endpoint type has a reason")

        local wrong_direction = crossing(Grid.EAST)
        wrong_direction.entities[2].direction = Grid.WEST
        local direction_state = finish(wrong_direction)
        H.equal(direction_state.ok, false, "a reversed endpoint is rejected")
        H.equal(has_code(direction_state, "BP_V_UNDERGROUND_UNPAIRED"), true, "endpoint direction has a reason")
    end)

    H.test(shape .. " L3 underground range and middle segment violations have named reasons", function()
        local over = crossing(Grid.EAST)
        over.entities[2].position.x = 5.5
        local range_state = finish(over)
        H.equal(range_state.ok, false, "an over-range pair is rejected")
        H.equal(has_code(range_state, "BP_V_UNDERGROUND_RANGE"), true, "range has a reason")

        local middle_state = finish(crossing(Grid.EAST, "item/cross"))
        H.equal(middle_state.ok, false, "a segment on the underground middle tile is rejected")
        H.equal(has_code(middle_state, "BP_V_UNDERGROUND_UNPAIRED"), true, "middle occupancy has a reason")
    end)

    H.test(shape .. " L4 a foreign flow cannot occupy a port or its approach", function()
        local state = finish({grid = {w = 5, h = 3}, ports = {
            {port_id = "in:item/a", role = "in", flow_id = "item/a", x = 2, y = 1, travel_dir = Grid.EAST},
        }, entities = {{id = "foreign", name = "belt", kind = "belt", flow_id = "item/b",
            position = {x = 1.5, y = 1.5}, direction = Grid.EAST}}})
        H.equal(state.ok, false, "foreign approach belt is rejected")
        H.equal(has_code(state, "BP_V_PORT_EDGE_WRONG"), true, "foreign approach has a reason")

        local legal = finish({grid = {w = 5, h = 3}, ports = {
            {port_id = "in:item/a", role = "in", flow_id = "item/a", x = 2, y = 1, travel_dir = Grid.EAST},
        }, entities = {{id = "same-flow", name = "belt", kind = "belt", flow_id = "item/a",
            position = {x = 1.5, y = 1.5}, direction = Grid.EAST}}})
        H.equal(ok_but_unfed(legal), true, "same-flow approach belt remains legal")
    end)

    H.test(shape .. " L5 one item trunk may serve two consumers but fluids may not mix", function()
        local shared = finish({flows = {{flow_id = "item/shared", producers = {{step_id = "source", share_per_second = 10}},
            consumers = {{step_id = "one", share_per_second = 5}, {step_id = "two", share_per_second = 5}}}},
            segments = {{segment_id = "trunk", kind = "belt", capacity_per_second = 10, flow_id = "item/shared",
                allocations = {{flow_id = "item/shared", sink = "step:one", rate_per_second = 5},
                    {flow_id = "item/shared", sink = "step:two", rate_per_second = 5}}}}})
        H.equal(shared.ok, true, "shared item trunk is legal")

        local mixed = finish({flows = {
            {flow_id = "fluid/water", producers = {{step_id = "source", share_per_second = 5}}, consumers = {{step_id = "water", share_per_second = 5}}},
            {flow_id = "fluid/steam", producers = {{step_id = "source", share_per_second = 5}}, consumers = {{step_id = "steam", share_per_second = 5}}},
        }, segments = {{segment_id = "pipe", kind = "pipe", capacity_per_second = 100,
            allocations = {{flow_id = "fluid/water", sink = "step:water", rate_per_second = 5},
                {flow_id = "fluid/steam", sink = "step:steam", rate_per_second = 5}}}}})
        H.equal(mixed.ok, false, "different fluids on one pipe are rejected")
        H.equal(has_code(mixed, "BP_V_FLUID_MIXING"), true, "fluid mixing has a reason")
    end)

    H.test(shape .. " L6 rotated asymmetric block occupancy is checked from placed geometry", function()
        local invalid = finish({grid = {w = 9, h = 6}, placements = {{block_id = "rotated", x = 3, y = 1, dir = Grid.EAST}},
            blocks = {{block_id = "rotated", w = 2, h = 3, members = {{id = "member", name = "asym", kind = "machine",
                x = 0, y = 0, w = 2, h = 1, dir = Grid.NORTH}}}}, entities = {
            {id = "occupier", name = "tiny", kind = "machine", x = 5, y = 1, w = 1, h = 1},
        }})
        H.equal(invalid.ok, false, "rotated asymmetric occupancy collision is rejected")
        H.equal(has_code(invalid, "BP_V_COLLISION"), true, "rotated occupancy has a collision reason")

        local legal = finish({grid = {w = 9, h = 6}, placements = {{block_id = "rotated", x = 3, y = 1, dir = Grid.EAST}},
            blocks = {{block_id = "rotated", w = 2, h = 3, members = {{id = "member", name = "asym", kind = "machine",
                x = 0, y = 0, w = 2, h = 1, dir = Grid.NORTH}}}}})
        H.equal(legal.ok, true, "legal rotated asymmetric occupancy remains accepted")
    end)
end

H.done("test_route_layout_contract")
