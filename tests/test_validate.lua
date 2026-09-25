--The validator rejects physical overlaps and illegal power edges, then checks the finished blueprint claims.
local H = require "tests.harness"

local Validate = require "logic.bp.validate"

local function box(radius)
    return {left_top = {x = -radius, y = -radius}, right_bottom = {x = radius, y = radius}}
end

local function catalog()
    return {
        entity = {
            tight = {name = "tight", etype = "assembling-machine", tile_w = 1, tile_h = 1,
                collision_box = box(0.5), collision_mask = {"object-layer"}, needs_power = false},
            wide = {name = "wide", etype = "assembling-machine", tile_w = 1, tile_h = 1,
                collision_box = box(0.6), collision_mask = {"object-layer"}, needs_power = false},
            assembler = {name = "assembler", etype = "assembling-machine", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false, module_slots = 2},
            beacon = {name = "beacon", etype = "beacon", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false,
                module_slots = 2, beacon = {supply_w = 5, supply_h = 5}},
            pole = {name = "pole", etype = "electric-pole", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
            ug = {name = "ug", etype = "transport-belt", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
        },
        module = { ["speed-module"] = {effects = {speed = 0.5}} },
        pole = {wire_reach = 2, supply_w = 0, supply_h = 0},
        belt = {items_per_second = 10, lane_items_per_second = 5, underground_max_distance = 3},
    }
end

local function finish(input)
    local state = Validate.begin(input)
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        H.equal(ticks < 1000, true, "validator finishes")
        Validate.step(state, {ops = 1})
    end
    return state
end

local function has_code(state, code)
    for _, error in ipairs(state.errors or {}) do
        if error.code == code then return true end
    end
    return false
end

local function error_with_code(state, code)
    for _, error in ipairs(state.errors or {}) do
        if error.code == code then return error end
    end
    return nil
end

local function ids_contain(ids, wanted)
    for _, id in ipairs(ids or {}) do if id == wanted then return true end end
    return false
end

local function entity(id, name, x, extra)
    local result = {id = id, kind = "machine", name = name, x = x, y = 0, w = 1, h = 1}
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function fixture_positions()
    local file = assert(io.open("tests/fixtures/engine/roboport-cell.json", "rb"))
    local text = file:read("*a")
    file:close()
    local section = assert(text:match('"normalised_positions"%s*:%s*%[(.-)%]'), "fixture has normalized positions")
    local result = {}
    for entry in section:gmatch("{(.-)}") do
        result[#result + 1] = {
            name = assert(entry:match('"name"%s*:%s*"([^"]+)"')),
            x = assert(tonumber(entry:match('"x"%s*:%s*(-?[%d%.]+)'))),
            y = assert(tonumber(entry:match('"y"%s*:%s*(-?[%d%.]+)'))),
        }
    end
    return result
end

local function robo_catalog()
    return {robo = {name = "roboport", logistic_radius = 25}}
end

local function robo_entities(positions, translate, right_column_x)
    local result = {}
    for _, position in ipairs(positions) do
        local x = position.x
        if right_column_x ~= nil and x == 50 then x = right_column_x end
        result[#result + 1] = {
            id = (position.x == 50 and "right-" or "left-") .. tostring(position.y),
            kind = "roboport", name = position.name, x = x + translate.x, y = position.y + translate.y, w = 1, h = 1,
        }
    end
    return result
end

H.test("S1 transport waste names the inserter outward cell and the orphan belt", function()
    local test_catalog = catalog()
    test_catalog.inserter = {items_per_second = 5, pickup_offset = {x = 0, y = 1}, drop_offset = {x = 0, y = -1}}
    test_catalog.entity.inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
        collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false, items_per_second = 5}
    local state = finish({grid = {w = 8, h = 8}, catalog = test_catalog,
        plan = {steps = {{step_id = "step", machine = "assembler", machine_count = 1}}}, entities = {
        entity("machine", "assembler", 3, {step_id = "step", y = 2}),
        {id = "support-belt", kind = "belt", name = "ug", x = 1, y = 2, w = 1, h = 1, dir = 4,
            flow_id = "item/in"},
        {id = "orphan-inserter", kind = "inserter", name = "inserter", x = 2, y = 2, w = 1, h = 1, dir = 4,
            flow_id = "item/in", role = "input", machine_id = "machine", pickup_target = "support-belt",
            drop_target = "machine", pickup_position = {x = 1.5, y = 2.5}, drop_position = {x = 3.5, y = 2.5}},
        {id = "orphan-belt", kind = "belt", name = "ug", x = 6, y = 6, w = 1, h = 1, dir = 12,
            flow_id = "item/orphan"},
    }})
    local inserter_record, belt_record
    for _, record in ipairs(state.errors or {}) do
        if record.code == "BP_V_TRANSPORT_UNUSED" and record.ids[1] == "orphan-inserter" then inserter_record = record end
        if record.code == "BP_V_TRANSPORT_UNUSED" and record.ids[1] == "orphan-belt" then belt_record = record end
    end
    H.equal(inserter_record ~= nil, true, "the unused inserter is named")
    H.deep_equal(inserter_record and inserter_record.detail, {reason = "inserter serves no required transfer",
        x = 1, y = 2, flow_id = "item/in", facing = 4}, "the inserter record names its pickup cell and facing")
    H.equal(belt_record ~= nil, true, "the orphan belt is named")
    H.deep_equal(belt_record and belt_record.detail, {reason = "transport entity serves no required transfer",
        x = 6, y = 6, flow_id = "item/orphan", facing = 12}, "the belt record names its tile, flow and facing")
end)

H.test("S2 target shortfall names the consumer sink and both rates", function()
    local state = finish({catalog = catalog(), flows = {{flow_id = "item/plate",
        producers = {{step_id = "source", share_per_second = 4}},
        consumers = {{step_id = "consumer", share_per_second = 4}}}},
        segments = {{segment_id = "short-belt", kind = "belt", capacity_per_second = 10,
            allocations = {{flow_id = "item/plate", sink = "step:consumer", rate_per_second = 1}}}}})
    local record = error_with_code(state, "BP_V_TARGET_SHORTFALL")
    H.equal(record ~= nil, true, "the underfilled consumer emits a target shortfall")
    H.deep_equal(record and record.detail, {required = 4, reached = 1, sink = "step:consumer", step_id = "consumer"},
        "the shortfall says which sink is short and by how much")
end)

local function ids_contain(ids, wanted)
    for _, id in ipairs(ids or {}) do if id == wanted then return true end end
    return false
end

H.test("VS1 a beacon supplies by collision-box overlap, exactly as a pole does", function()
    local test_catalog = catalog()
    test_catalog.entity.beacon.collision_mask = {"beacon-layer"}
    test_catalog.entity.pole.collision_mask = {"pole-layer"}
    local state = finish({grid = {w = 4, h = 4}, catalog = test_catalog,
        plan = {steps = {{step_id = "step", machine_count = 1,
            beacon_groups = {{name = "beacon", count_per_machine = 1}}}}}, entities = {
        entity("machine", "wide", 1.1, {step_id = "step", needs_power = true, y = 0.2}),
        {id = "beacon", kind = "beacon", name = "beacon", x = 0, y = 1.2, w = 1, h = 1, supply_w = 1, supply_h = 1},
        {id = "pole", kind = "pole", name = "pole", x = 0, y = 1.2, w = 1, h = 1, supply_w = 1, supply_h = 1},
    }})
    H.equal(state.ok, true, "the collision-box overlap supplies the machine through both consumers")
    H.equal(has_code(state, "BP_V_BEACON_COVERAGE_SHORT"), false, "the beacon sees the overlapping machine")
    H.equal(has_code(state, "BP_V_POWER_UNCOVERED"), false, "the pole sees the overlapping machine")
end)

H.test("VS2 the fractional-box counterexample is refused by the beacon rule and the pole rule alike", function()
    local test_catalog = catalog()
    test_catalog.entity.assembler.collision_box = {left_top = {x = -0.7, y = -0.7}, right_bottom = {x = 0.7, y = 0.7}}
    test_catalog.entity.beacon.collision_mask = {"beacon-layer"}
    test_catalog.entity.pole.collision_mask = {"pole-layer"}
    local state = finish({grid = {w = 8, h = 8}, catalog = test_catalog,
        plan = {steps = {{step_id = "step", machine_count = 1,
            beacon_groups = {{name = "beacon", count_per_machine = 1}}}}}, entities = {
        entity("machine", "assembler", 3, {step_id = "step", needs_power = true, y = 4, w = 3, h = 3}),
        {id = "beacon", kind = "beacon", name = "beacon", x = 3, y = 0, w = 3, h = 3,
            supply_w = 3, supply_h = 3},
        {id = "pole", kind = "pole", name = "pole", x = 3, y = 0, w = 3, h = 3,
            supply_w = 3, supply_h = 3},
    }})
    H.equal(state.ok, false, "the real fractional collision box is outside both supply decisions")
    --Round 36: a beacon's supply_area_distance counts from its edge (3x3, distance 3 -> y -3..6), so the machine box
    --4.8..6.2 is in reach; only the pole, whose distance counts from its centre, refuses it.
    H.equal(has_code(state, "BP_V_BEACON_COVERAGE_SHORT"), false, "the beacon reaches the machine from its edge")
    H.equal(has_code(state, "BP_V_POWER_UNCOVERED"), true, "the pole rejects the fractional-box counterexample")
end)

H.test("VS3 the player's four-roboport cell validates as connected, before and after translation", function()
    local positions = fixture_positions()
    H.equal(#positions, 4, "the engine fixture supplies four roboport coordinates")
    for _, translate in ipairs({{x = 0, y = 0}, {x = 137.25, y = -44.5}}) do
        local state = finish({catalog = robo_catalog(), entities = robo_entities(positions, translate)})
        H.equal(state.ok, true, "the fixture cell is connected at its translation")
        H.equal(has_code(state, "BP_V_ROBO_DISCONNECTED"), false, "the fixture cell has no disconnected roboports")
    end
end)

--Geometry only: the stated spacing is 50 tiles, so moving the whole right-hand column to x=51 removes every
--cross-column edge. This deliberately asserts nothing about the engine's true rejection boundary.
H.test("VS4 geometry only: a whole column moved past a stated spacing is disconnected and named", function()
    local positions = fixture_positions()
    local state = finish({catalog = robo_catalog(), entities = robo_entities(positions, {x = 0, y = 0}, 51)})
    H.equal(state.ok, false, "the geometry-only wider column is rejected")
    local disconnected = error_with_code(state, "BP_V_ROBO_DISCONNECTED")
    H.equal(disconnected ~= nil, true, "the geometry-only rejection has the roboport reason")
    H.equal(ids_contain(disconnected and disconnected.ids, "right-0"), true, "the upper moved roboport is named")
    H.equal(ids_contain(disconnected and disconnected.ids, "right-50"), true, "the lower moved roboport is named")
    H.equal(ids_contain(disconnected and disconnected.ids, "left-0"), false, "the left column remains the root component")
    H.equal(ids_contain(disconnected and disconnected.ids, "left-50"), false, "the left column remains connected")
end)

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " V1 touching collision boxes do not overlap", function()
        local state = finish({grid = {w = 3, h = 2}, catalog = catalog(), entities = {
            entity("left", "tight", 0), entity("right", "tight", 1),
        }})
        H.equal(state.ok, true, "touching physical boxes are accepted")
    end)

    H.test(shape .. " V2 fractional collision overlap is not integer occupancy", function()
        local state = finish({grid = {w = 3, h = 2}, catalog = catalog(), entities = {
            entity("left", "wide", 0), entity("right", "wide", 1),
        }})
        H.equal(state.ok, false, "fractional physical overlap is rejected")
        H.equal(has_code(state, "BP_V_COLLISION"), true, "fractional overlap has the collision reason")
    end)

    H.test(shape .. " V3 a machine beyond the physical grid fails", function()
        local state = finish({grid = {w = 2, h = 2}, catalog = catalog(), entities = {entity("outside", "tight", 2)}})
        H.equal(state.ok, false, "outside entity is rejected")
        H.equal(has_code(state, "BP_V_OUT_OF_GRID"), true, "grid containment has the reason")
    end)

    H.test(shape .. " V4 a speed beacon cannot influence a quality machine", function()
        local state = finish({grid = {w = 8, h = 3}, catalog = catalog(), entities = {
            entity("machine", "assembler", 4, {step_id = "quality", forbids_speed_beacon = true}),
            {id = "beacon", kind = "beacon", name = "beacon", x = 0, y = 0, w = 1, h = 1,
                modules = {{name = "speed-module", quality = "normal"}}},
        }, plan = {steps = {{step_id = "quality", machine_count = 1}}}})
        H.equal(state.ok, false, "speed beacon on quality machine is rejected")
        H.equal(has_code(state, "BP_V_SPEED_BEACON_ON_QUALITY"), true, "quality isolation has the reason")
    end)

    H.test(shape .. " V5 configured beacon group needs every requested beacon", function()
        local input = {grid = {w = 9, h = 3}, catalog = catalog(), plan = {steps = {{step_id = "grouped", machine_count = 1,
            beacon_groups = {{name = "beacon", quality = "normal", count_per_machine = 2}}}}}, entities = {
            entity("machine", "assembler", 4, {step_id = "grouped"}),
            {id = "beacon-a", kind = "beacon", name = "beacon", quality = "normal", x = 0, y = 0, w = 1, h = 1},
        }}
        local short = finish(input)
        H.equal(short.ok, false, "one beacon is short of the configured group")
        H.equal(has_code(short, "BP_V_BEACON_COVERAGE_SHORT"), true, "short beacon coverage has the reason")
        input.entities[#input.entities + 1] = {id = "beacon-b", kind = "beacon", name = "beacon", quality = "normal", x = 2, y = 0, w = 1, h = 1}
        local extra = finish(input)
        H.equal(extra.ok, true, "extra coverage satisfies the configured group")
    end)

    H.test(shape .. " V6 an over-range copper wire is illegal before connectivity", function()
        local state = finish({grid = {w = 8, h = 2}, catalog = catalog(), entities = {
            {id = "p-left", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1},
            {id = "p-right", kind = "pole", name = "pole", x = 5, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-left", a_connector = 5, b_id = "p-right", b_connector = 5}}})
        H.equal(state.ok, false, "over-range wire is rejected")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), true, "over-range wire is illegal")
        H.equal(state.errors[1].code, "BP_V_WIRE_ILLEGAL", "legality is recorded before connectivity")
    end)

    H.test(shape .. " V7 circuit connectors cannot bridge power poles", function()
        local state = finish({grid = {w = 4, h = 2}, catalog = catalog(), entities = {
            {id = "p-left", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1},
            {id = "p-right", kind = "pole", name = "pole", x = 1, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-left", a_connector = 3, b_id = "p-right", b_connector = 5}}})
        H.equal(state.ok, false, "circuit bridge is rejected")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), true, "circuit bridge is illegal")
    end)

    H.test(shape .. " V8 poles connected only through an illegal edge stay disconnected", function()
        local state = finish({grid = {w = 8, h = 2}, catalog = catalog(), entities = {
            {id = "p-left", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1},
            {id = "p-right", kind = "pole", name = "pole", x = 5, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-left", a_connector = 5, b_id = "p-right", b_connector = 5}}})
        H.equal(has_code(state, "BP_V_WIRE_DISCONNECTED"), true, "illegal edge is excluded from connectivity")
    end)

    H.test(shape .. " V9 a belt cannot promise two consumers beyond its capacity", function()
        local function candidate(total)
            return {catalog = catalog(), flows = {{flow_id = "item/plate", producers = {{step_id = "source", share_per_second = total}},
                consumers = {{step_id = "one", share_per_second = total / 2}, {step_id = "two", share_per_second = total / 2}}}},
                segments = {{segment_id = "belt-1", kind = "belt", capacity_per_second = 10, allocations = {
                    {flow_id = "item/plate", sink = "step:one", rate_per_second = total / 2},
                    {flow_id = "item/plate", sink = "step:two", rate_per_second = total / 2},
                }}}}
        end
        local inside = finish(candidate(10))
        H.equal(inside.ok, true, "simultaneous consumers inside belt capacity pass")
        local shortfall = finish(candidate(12))
        H.equal(shortfall.ok, false, "simultaneous consumers beyond belt capacity fail")
        H.equal(has_code(shortfall, "BP_V_TARGET_SHORTFALL"), true, "capacity breach is also a target shortfall")
    end)

    H.test(shape .. " V10 unbalanced flow shares fail conservation", function()
        local state = finish({catalog = catalog(), flows = {{flow_id = "item/plate",
            producers = {{step_id = "source", share_per_second = 5}}, consumers = {{step_id = "sink", share_per_second = 4}}}},
            segments = {{segment_id = "belt-1", kind = "belt", capacity_per_second = 10,
                allocations = {{flow_id = "item/plate", sink = "step:sink", rate_per_second = 4}}}}})
        H.equal(state.ok, false, "unbalanced flow is rejected")
        H.equal(has_code(state, "BP_V_FLOW_IMBALANCE"), true, "flow imbalance has the reason")
    end)

    H.test(shape .. " V11 an underground pair beyond its own range fails", function()
        local state = finish({grid = {w = 10, h = 2}, catalog = catalog(), entities = {
            {id = "ug-a", kind = "belt", name = "ug", x = 0, y = 0, w = 1, h = 1, flow_id = "item/ore", ug_role = "output", ug_pair_id = "ug-b",
                connection = {connection_type = "underground", direction = 4, max_underground_distance = 3}},
            {id = "ug-b", kind = "belt", name = "ug", x = 5, y = 0, w = 1, h = 1, flow_id = "item/ore", ug_role = "input", ug_pair_id = "ug-a",
                connection = {connection_type = "underground", direction = 12, max_underground_distance = 3}},
        }})
        H.equal(state.ok, false, "over-range underground pair is rejected")
        H.equal(has_code(state, "BP_V_UNDERGROUND_RANGE"), true, "underground range has the reason")
    end)

    H.test(shape .. " V12 placed machine count is compared with the plan", function()
        local state = finish({grid = {w = 3, h = 2}, catalog = catalog(), plan = {steps = {{step_id = "step", machine_count = 2}}},
            entities = {entity("machine", "assembler", 0, {step_id = "step"})}})
        H.equal(state.ok, false, "machine count mismatch is rejected")
        H.equal(has_code(state, "BP_V_MACHINE_COUNT_MISMATCH"), true, "machine count has the reason")
    end)

    H.test(shape .. " V13 compare is beacon first then production area then poles", function()
        H.equal(Validate.compare({beacon_count = 1, production_area = 1, pole_count = 1}, {beacon_count = 2, production_area = 0, pole_count = 0}), -1,
            "beacon count is first")
        H.equal(Validate.compare({beacon_count = 2, production_area = 1, pole_count = 3}, {beacon_count = 2, production_area = 2, pole_count = 0}), -1,
            "production area is second")
        H.equal(Validate.compare({beacon_count = 2, production_area = 2, pole_count = 1}, {beacon_count = 2, production_area = 2, pole_count = 2}), -1,
            "pole count is third")
    end)

    H.test(shape .. " V14 a mixed-reach wire beyond the shorter pole is illegal and disconnected", function()
        local state = finish({grid = {w = 7, h = 2}, catalog = catalog(), entities = {
            {id = "p-long", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1, wire_reach = 5},
            {id = "p-short", kind = "pole", name = "pole", x = 4, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-long", a_connector = 5, b_id = "p-short", b_connector = 5}}})
        H.equal(state.ok, false, "a wire beyond the shorter reach is rejected")
        local illegal = error_with_code(state, "BP_V_WIRE_ILLEGAL")
        H.equal(illegal ~= nil, true, "the mixed-reach edge is illegal")
        local detail = illegal and illegal.detail
        H.equal(detail ~= nil, true, "the illegal edge reports detail")
        H.equal(detail and detail.reason, "over range", "the illegal edge reports the range reason")
        H.equal(has_code(state, "BP_V_WIRE_DISCONNECTED"), true, "the illegal edge is excluded from connectivity")
    end)

    H.test(shape .. " V15 a mixed-reach wire inside the shorter pole reach connects the poles", function()
        local state = finish({grid = {w = 4, h = 2}, catalog = catalog(), entities = {
            {id = "p-long", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1, wire_reach = 5},
            {id = "p-short", kind = "pole", name = "pole", x = 1, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-long", a_connector = 5, b_id = "p-short", b_connector = 5}}})
        H.equal(state.ok, true, "a wire inside the shorter reach is legal")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), false, "the inside-range edge is not illegal")
        H.equal(has_code(state, "BP_V_WIRE_DISCONNECTED"), false, "the poles form one component")
    end)

    H.test(shape .. " V16 a mixed-reach wire at the shorter pole boundary is legal", function()
        local state = finish({grid = {w = 5, h = 2}, catalog = catalog(), entities = {
            {id = "p-long", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1, wire_reach = 5},
            {id = "p-short", kind = "pole", name = "pole", x = 2, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-long", a_connector = 5, b_id = "p-short", b_connector = 5}}})
        H.equal(state.ok, true, "a wire at the shorter reach boundary is legal")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), false, "the boundary edge is not illegal")
        H.equal(has_code(state, "BP_V_WIRE_DISCONNECTED"), false, "the boundary edge connects the poles")
    end)
    -- -----------------------------------------------------------------------------------------------------
    -- Block and perimeter ports use disjoint ids. The perimeter marker is therefore read directly from the
    -- resolved port, while a block-local port with the same role remains a wrong binding endpoint.
    -- -----------------------------------------------------------------------------------------------------

    H.test(shape .. " V17 a disjoint external supply keeps its role", function()
        local state = finish({grid = {w = 6, h = 4}, catalog = catalog(),
            entities = {{id = "p", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1}},
            ports = {{port_id = "block:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                      block_id = "b1", x = 0, y = 1, rate_per_second = 1},
                     {port_id = "sink:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                      block_id = "b2", x = 3, y = 1, rate_per_second = 1}},
            external_ports = {{port_id = "in:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                               perimeter = true, x = 0, y = 1, rate_per_second = 1}},
            bindings = {{source_port_id = "in:item/iron-plate", sink_port_id = "sink:item/iron-plate",
                         flow_id = "item/iron-plate", rate_per_second = 1}},
        })
        H.equal(has_code(state, "BP_V_PORT_EDGE_WRONG"), false,
            "an external supply keeps its role even when a block port shares its id")
    end)

    H.test(shape .. " V18 a block port that is NOT declared external still fails the binding role", function()
        --The positive control for V17. Without it, V17 is satisfied by dropping the rule entirely.
        local state = finish({grid = {w = 6, h = 4}, catalog = catalog(),
            entities = {{id = "p", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1}},
            ports = {{port_id = "in:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                      block_id = "b1", x = 0, y = 1, rate_per_second = 1},
                     {port_id = "sink:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                      block_id = "b2", x = 3, y = 1, rate_per_second = 1}},
            bindings = {{source_port_id = "in:item/iron-plate", sink_port_id = "sink:item/iron-plate",
                         flow_id = "item/iron-plate", rate_per_second = 1}},
        })
        local failure = error_with_code(state, "BP_V_PORT_EDGE_WRONG")
        H.equal(failure ~= nil, true,
            "a block-local source with role in is still rejected when nothing declares it external")
        H.equal(failure and failure.detail and failure.detail.reason, "binding source has role in",
            "the wrong source half is named")
        H.equal(ids_contain(failure and failure.ids, "in:item/iron-plate"), true,
            "the failing source port is named")
    end)

    H.test(shape .. " V19 a binding with a wrong sink role names the sink half", function()
        local state = finish({grid = {w = 6, h = 4}, catalog = catalog(),
            entities = {{id = "p", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1}},
            ports = {{port_id = "block-out:item/iron-plate", flow_id = "item/iron-plate", role = "out",
                      block_id = "b2", x = 3, y = 1, rate_per_second = 1}},
            external_ports = {{port_id = "in:item/iron-plate", flow_id = "item/iron-plate", role = "in",
                               perimeter = true, x = 0, y = 1, rate_per_second = 1}},
            bindings = {{source_port_id = "in:item/iron-plate", sink_port_id = "block-out:item/iron-plate",
                         flow_id = "item/iron-plate", rate_per_second = 1}},
        })
        local failure = error_with_code(state, "BP_V_PORT_EDGE_WRONG")
        H.equal(failure ~= nil, true, "a wrong sink role rejects")
        H.equal(failure and failure.detail and failure.detail.reason, "binding sink has role out",
            "the wrong sink half is named")
        H.equal(ids_contain(failure and failure.ids, "block-out:item/iron-plate"), true,
            "the failing sink port is named")
    end)
end

H.done("test_validate")
