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

local function entity(id, name, x, extra)
    local result = {id = id, kind = "machine", name = name, x = x, y = 0, w = 1, h = 1}
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

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
        }, wires = {{a_id = "p-left", a_connector = 0, b_id = "p-right", b_connector = 0}}})
        H.equal(state.ok, false, "over-range wire is rejected")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), true, "over-range wire is illegal")
        H.equal(state.errors[1].code, "BP_V_WIRE_ILLEGAL", "legality is recorded before connectivity")
    end)

    H.test(shape .. " V7 circuit connectors cannot bridge power poles", function()
        local state = finish({grid = {w = 4, h = 2}, catalog = catalog(), entities = {
            {id = "p-left", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1},
            {id = "p-right", kind = "pole", name = "pole", x = 1, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-left", a_connector = 3, b_id = "p-right", b_connector = 0}}})
        H.equal(state.ok, false, "circuit bridge is rejected")
        H.equal(has_code(state, "BP_V_WIRE_ILLEGAL"), true, "circuit bridge is illegal")
    end)

    H.test(shape .. " V8 poles connected only through an illegal edge stay disconnected", function()
        local state = finish({grid = {w = 8, h = 2}, catalog = catalog(), entities = {
            {id = "p-left", kind = "pole", name = "pole", x = 0, y = 0, w = 1, h = 1},
            {id = "p-right", kind = "pole", name = "pole", x = 5, y = 0, w = 1, h = 1},
        }, wires = {{a_id = "p-left", a_connector = 0, b_id = "p-right", b_connector = 0}}})
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

    H.test(shape .. " V13 compare is beacon first then footprint then poles", function()
        H.equal(Validate.compare({beacon_count = 1, footprint_area = 1, pole_count = 1}, {beacon_count = 2, footprint_area = 0, pole_count = 0}), -1,
            "beacon count is first")
        H.equal(Validate.compare({beacon_count = 2, footprint_area = 1, pole_count = 3}, {beacon_count = 2, footprint_area = 2, pole_count = 0}), -1,
            "footprint is second")
        H.equal(Validate.compare({beacon_count = 2, footprint_area = 2, pole_count = 1}, {beacon_count = 2, footprint_area = 2, pole_count = 2}), -1,
            "pole count is third")
    end)
end

H.done("test_validate")
