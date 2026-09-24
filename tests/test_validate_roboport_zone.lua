--Roboports must remain outside every machine buffer ring, including retry bumps.
local H = require "tests.harness"
local Validate = require "logic.bp.validate"

local function box(radius)
    return {left_top = {x = -radius, y = -radius}, right_bottom = {x = radius, y = radius}}
end

local function catalog()
    return {
        entity = {
            assembler = {name = "assembler", etype = "assembling-machine", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
            belt = {name = "belt", etype = "transport-belt", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
            inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
            pole = {name = "pole", etype = "electric-pole", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false},
            roboport = {name = "roboport", etype = "roboport", tile_w = 2, tile_h = 2,
                collision_box = box(0.9), collision_mask = {"object-layer"}, needs_power = false},
            beacon = {name = "beacon", etype = "beacon", tile_w = 1, tile_h = 1,
                collision_box = box(0.4), collision_mask = {"object-layer"}, needs_power = false,
                beacon = {supply_w = 5, supply_h = 5}},
        },
        recipe = {
            first = {ingredients = {{name = "iron"}}},
            second = {ingredients = {{name = "copper"}, {name = "iron"}}},
        },
        inserter = {items_per_second = 5},
    }
end

local function finish(entities, steps, ring_bump)
    local state = Validate.begin({catalog = catalog(), plan = {steps = steps or {}}, entities = entities, ring_bump = ring_bump})
    local ticks = 0
    while not state.done do
        ticks = ticks + 1
        H.equal(ticks < 1000, true, "validator finishes")
        Validate.step(state, {ops = 1})
    end
    return state
end

local function machine(id, x, y, step_id, recipe)
    return {id = id, kind = "machine", name = "assembler", x = x, y = y, w = 1, h = 1,
        step_id = step_id, recipe = recipe}
end

local function buffer_record(state)
    for _, record in ipairs(state.errors or {}) do
        if record.code == "BP_V_BUFFER_ZONE" then return record end
    end
end

local function contains(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end

H.test("VB1 different-recipe assemblers three tiles apart name both machines and rectangles", function()
    local state = finish({machine("a", 2, 2, "one"), machine("b", 5, 2, "two")}, {
        {step_id = "one", recipe = "first"}, {step_id = "two", recipe = "second"},
    })
    local record = buffer_record(state)
    H.equal(record ~= nil, true, "overlapping buffer rings are refused")
    H.equal(contains(record and record.ids, "a"), true, "first machine is named")
    H.equal(contains(record and record.ids, "b"), true, "second machine is named")
    H.deep_equal(record and record.detail, {rect_a = {x = 2, y = 2, w = 1, h = 1},
        rect_b = {x = 5, y = 2, w = 1, h = 1}}, "both machine rectangles are included")
end)

H.test("VB2 different-recipe assemblers five tiles apart have clear rings", function()
    local state = finish({machine("a", 2, 2, "one"), machine("b", 7, 2, "two")}, {
        {step_id = "one", recipe = "first"}, {step_id = "two", recipe = "second"},
    })
    H.equal(buffer_record(state), nil, "rings separated by a tile do not conflict")
end)

H.test("VB3 same-recipe machines share a column but not a shifted column", function()
    local shared = finish({machine("a", 2, 2, "one"), machine("b", 2, 3, "two")}, {
        {step_id = "one", recipe = "first"}, {step_id = "two", recipe = "first"},
    })
    H.equal(buffer_record(shared), nil, "same-recipe machines in one column may share")
    local shifted = finish({machine("a", 2, 2, "one"), machine("b", 3, 3, "two")}, {
        {step_id = "one", recipe = "first"}, {step_id = "two", recipe = "first"},
    })
    H.equal(buffer_record(shifted) ~= nil, true, "moving one machine to another column conflicts")
end)

H.test("VB4 belt, inserter, pole and beacon may occupy a machine ring", function()
    local entities = {machine("machine", 5, 5, "one"),
        {id = "belt", kind = "belt", name = "belt", x = 3, y = 4, w = 1, h = 1},
        {id = "inserter", kind = "inserter", name = "inserter", x = 4, y = 3, w = 1, h = 1},
        {id = "pole", kind = "pole", name = "pole", x = 6, y = 3, w = 1, h = 1},
        {id = "beacon", kind = "beacon", name = "beacon", x = 7, y = 4, w = 1, h = 1}}
    local state = finish(entities, {{step_id = "one", recipe = "first"}})
    H.equal(buffer_record(state), nil, "non-machine entities inside a ring are allowed")
end)

local function robo_record(state)
    for _, record in ipairs(state.errors or {}) do
        if record.code == "BP_V_BUFFER_ROBOPORT" then return record end
    end
end

H.test("RZ1 a roboport footprint intersecting a machine ring is refused with its zone and rect", function()
    local state = finish({machine("m", 5, 5, "one"),
        {id = "r", kind = "roboport", name = "roboport", x = 3, y = 4, w = 2, h = 2}},
        {{step_id = "one", recipe = "first"}})
    local record = robo_record(state)
    H.equal(record ~= nil, true, "roboport in ring rejected")
    H.deep_equal(record and record.detail, {machine_id = "m", roboport_id = "r",
        zone = {x = 3, y = 3, w = 5, h = 5}, rect = {x = 3, y = 4, w = 2, h = 2}}, "details identify both rectangles")
end)

H.test("RZ2 a roboport one tile beyond the ring is clean", function()
    local state = finish({machine("m", 5, 5, "one"),
        {id = "r", kind = "roboport", name = "roboport", x = 8, y = 5, w = 2, h = 2}},
        {{step_id = "one", recipe = "first"}})
    H.equal(robo_record(state), nil, "separated roboport is allowed")
end)

H.test("RZ3 ring_bump widens a formerly clear layout", function()
    local entities = {machine("m", 5, 5, "one"),
        {id = "r", kind = "roboport", name = "roboport", x = 8, y = 5, w = 2, h = 2}}
    local steps = {{step_id = "one", recipe = "first"}}
    H.equal(robo_record(finish(entities, steps)), nil, "base ring leaves one tile gap")
    H.equal(robo_record(finish(entities, steps, 1)) ~= nil, true, "bumped ring catches roboport")
end)

H.done("test_validate_roboport_zone")
