--Blueprint serialization assigns stable entity numbers and canonicalizes only representation noise.
local H = require "tests.harness"
local Serialize = require "logic.bp.serialize"

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function fixture(offset_x, offset_y)
    offset_x, offset_y = offset_x or 0, offset_y or 0
    return {
        label = "iron line",
        target_rates = { ["item/iron-plate"] = 2.5 },
        external_ports = {
            {port_id = "in:item/iron-ore", role = "in", full_name = "item/iron-ore", rate_per_second = 3},
            {port_id = "out:item/iron-plate", role = "out", full_name = "item/iron-plate", rate_per_second = 2.5},
        },
        infrastructure = {belt = "transport-belt", pole = "medium-electric-pole"},
        entities = {
            {id = "m:machine", name = "assembling-machine-2", position = {x = 4.5 + offset_x, y = 2.5 + offset_y},
                entity_number = 91, direction = 4, recipe = "iron-plate", recipe_quality = "normal",
                modules = {{name = "speed-module", quality = "rare"}, {name = "productivity-module", quality = "normal"}},
                drop_position = {1.25, 0}},
            {id = "r:belt", name = "transport-belt", position = {x = 3.5 + offset_x, y = 2.5 + offset_y},
                entity_number = 17, direction = 4},
            {id = "u:input", name = "underground-belt", position = {x = 0.5 + offset_x, y = 0.5 + offset_y},
                entity_number = 44, direction = 4, type = "input", ug_pair_id = "u:output"},
            {id = "u:output", name = "underground-belt", position = {x = 2.5 + offset_x, y = 0.5 + offset_y},
                entity_number = 12, direction = 4, type = "output", ug_pair_id = "u:input"},
            {id = "p:pole", name = "medium-electric-pole", position = {x = 4.5 + offset_x, y = 0.5 + offset_y},
                entity_number = 3, quality = "legendary"},
            {id = "k:beacon", name = "beacon", position = {x = 6.5 + offset_x, y = 2.5 + offset_y},
                entity_number = 5, modules = {{name = "speed-module", quality = "normal"}}},
        },
        wires = {{a_id = "p:pole", a_connector = 1, b_id = "m:machine", b_connector = 2}},
    }
end

local function serialize(candidate, operations)
    local state = Serialize.begin(candidate)
    for _ = 1, 1000 do
        if state.done then break end
        Serialize.step(state, {ops = operations or 1})
    end
    H.equal(state.done, true, "serialization finishes")
    H.equal(state.ok, true, "serialization succeeds")
    H.equal(state.result ~= nil, true, "serialization has a blueprint result")
    return state.result
end

local function json(value)
    return helpers.table_to_json(value)
end

local function by_name(blueprint, name)
    for _, entity in ipairs(blueprint.entities or {}) do
        if entity.name == name then return entity end
    end
end

for _, shape in ipairs(H.shapes()) do
    H.new_world(shape)
    H.test(shape .. " S1 entity numbers sort by y, x, id and remap references", function()
        local blueprint = serialize(fixture())
        H.equal(blueprint.entities[1].entity_number, 1, "first entity number")
        H.equal(blueprint.entities[1].type, "input", "input endpoint keeps its type")
        local input = by_name(blueprint, "underground-belt")
        H.equal(input.ug_pair_id ~= nil, true, "underground endpoint keeps its partner")
        H.equal(blueprint.wires[1][1] ~= blueprint.wires[1][3], true, "wire endpoints are distinct numbers")
        H.equal(type(blueprint.wires[1][1]), "number", "wire endpoint is renumbered")
        H.equal(type(input.ug_pair_id), "number", "underground partner is renumbered")
    end)

    H.test(shape .. " S2 translation and input renumbering do not change canonical form", function()
        local first = fixture()
        local translated = fixture(100, -40)
        for index, entity in ipairs(translated.entities) do entity.entity_number = index * 101 end
        local canonical_a = Serialize.canonical(serialize(first))
        local canonical_b = Serialize.canonical(serialize(translated))
        H.equal(json(canonical_a), json(canonical_b), "translated layout has the same canonical JSON")
    end)

    H.test(shape .. " S3 direction, module quality and machine position change canonical form", function()
        local baseline = Serialize.canonical(serialize(fixture()))
        local direction = fixture()
        direction.entities[2].direction = 8
        local quality = fixture()
        quality.entities[1].modules[1].quality = "epic"
        local position = fixture()
        position.entities[1].position.x = position.entities[1].position.x + 0.25
        H.equal(json(Serialize.canonical(serialize(direction))) ~= json(baseline) and true or false, true,
            "belt direction is canonical")
        H.equal(json(Serialize.canonical(serialize(quality))) ~= json(baseline) and true or false, true,
            "module quality is canonical")
        H.equal(json(Serialize.canonical(serialize(position))) ~= json(baseline) and true or false, true,
            "machine position is canonical")
    end)

    H.test(shape .. " S4 modules use the entity inventory and retain slots and quality", function()
        local blueprint = serialize(fixture())
        local machine = by_name(blueprint, "assembling-machine-2")
        local beacon = by_name(blueprint, "beacon")
        H.equal(machine.items[1].items.in_inventory[1].inventory, 4, "machine module inventory")
        H.equal(machine.items[1].items.in_inventory[1].stack, 0, "first machine module slot")
        H.equal(machine.items[1].id.quality, "rare", "module quality is retained")
        H.equal(machine.items[2].items.in_inventory[1].stack, 1, "second machine module slot")
        H.equal(beacon.items[1].items.in_inventory[1].inventory, 1, "beacon module inventory")
    end)

    H.test(shape .. " S5 recipes, underground type, drop position and entity quality are blueprint fields", function()
        local blueprint = serialize(fixture())
        local machine = by_name(blueprint, "assembling-machine-2")
        local pole = by_name(blueprint, "medium-electric-pole")
        H.equal(machine.recipe, "iron-plate", "recipe")
        H.equal(machine.recipe_quality, "normal", "recipe quality")
        H.deep_equal(machine.drop_position, {x = 1.25, y = 0}, "drop position is an object")
        H.equal(pole.quality, "legendary", "non-normal entity quality")
        H.equal(machine.quality, nil, "normal entity quality is omitted")
        local array_form = fixture()
        array_form.entities[1].drop_position = {x = 1.25, y = 0}
        H.equal(json(Serialize.canonical(serialize(fixture()))) == json(Serialize.canonical(serialize(array_form))), true,
            "array and object drop positions canonicalize alike")
    end)

    H.test(shape .. " S6 two runs produce byte-identical canonical JSON and metadata", function()
        local first = serialize(fixture(), 1)
        local second = serialize(fixture(), 100)
        H.equal(json(Serialize.canonical(first)), json(Serialize.canonical(second)), "canonical JSON is deterministic")
        H.equal(first.label, "iron line", "label")
        H.equal(type(first.description), "string", "description")
        H.equal(first.description:find("item/iron%-plate", 1, false) ~= nil, true, "description target rate")
        H.equal(first.description:find("in:item/iron%-ore", 1, false) ~= nil, true, "description external port")
        H.equal(first.description:find("transport%-belt", 1, false) ~= nil, true, "description infrastructure")
    end)

    H.test(shape .. " S7 route fields survive entity and global wire serialization", function()
        local candidate = {entities = {
            {id = "left", name = "underground-belt", position = {x = 0.5, y = 0.5}, dir = 12,
                ug_role = "input", ug_pair_id = "right", quality = {name = "rare"},
                wires = {{a_id = "left", a_connector = 1, b_id = "right", b_connector = 2}}},
            {id = "right", name = "underground-belt", position = {x = 2.5, y = 0.5}, direction = 12,
                type = "output", ug_role = "output", ug_pair_id = "left"},
        }}
        local blueprint = serialize(candidate)
        local left, right = blueprint.entities[1], blueprint.entities[2]
        H.equal(left.direction, 12, "dir is written as the verified blueprint direction")
        H.equal(left.type, "input", "underground role supplies the endpoint type")
        H.equal(left.quality, "rare", "entity quality is retained")
        H.equal(type(left.wires[1][1]), "number", "entity wire endpoint is remapped")
        H.equal(#blueprint.wires, 1, "entity wire is also retained at the blueprint boundary")
        H.equal(blueprint.wires[1][1] ~= blueprint.wires[1][3], true, "global wire endpoints remain distinct")
        H.equal(right.type, "output", "explicit endpoint type is retained")
    end)
end

H.done("test_serialize")
