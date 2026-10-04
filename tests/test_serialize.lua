--Blueprint serialization assigns stable entity numbers and canonicalizes only representation noise.
local H = require "tests.harness"
local Serialize = require "logic.bp.serialize"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

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

local function fluid_identity_catalog()
    return {entity = {
        ["mod-assembler"] = {name = "mod-assembler", etype = "assembling-machine", tile_w = 3, tile_h = 3,
            fluid_boxes = {
                {production_type = "input", index = 1,
                    pipe_connections = {{position = {x = -2, y = 0}, direction = Grid.WEST}}},
                {production_type = "output", index = 2,
                    pipe_connections = {{position = {x = 2, y = 0}, direction = Grid.EAST}}},
            }},
        ["mod-furnace"] = {name = "mod-furnace", etype = "furnace", tile_w = 3, tile_h = 3},
        inserter = {name = "inserter", etype = "inserter", tile_w = 1, tile_h = 1},
    }}
end

local function fluid_identity_plan()
    return {steps = {{step_id = "mixed", machine = "mod-assembler", machine_count = 1,
        recipe = "mixed-recipe", recipe_quality = "rare", modules = {{name = "speed-module", quality = "epic", slot = 2}},
        inputs = {{flow_id = "fluid/water", kind = "fluid", is_fluid = true, rate_per_second = 10},
            {flow_id = "item/ore", kind = "item", rate_per_second = 1}},
        outputs = {{flow_id = "fluid/steam", kind = "fluid", is_fluid = true, rate_per_second = 5},
            {flow_id = "item/product", kind = "item", rate_per_second = 1}}}}}
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

    H.test(shape .. " S8 grouped mixed-fluid machines serialize identity and no fluid inserters in all rotations", function()
        local catalog = fluid_identity_catalog()
        local state = Groups.begin({plan = fluid_identity_plan(), catalog = catalog})
        for _ = 1, 100 do
            if state.done then break end
            Groups.step(state, {ops = 1000})
        end
        H.equal(state.done and state.ok, true, "grouping mixed-fluid identity plan finishes")
        local block = state.result and state.result.candidates[1] and state.result.candidates[1].blocks[1]
        H.equal(block ~= nil, true, "grouped mixed-fluid block exists")
        if not block then return end
        for _, dir in ipairs({Grid.NORTH, Grid.EAST, Grid.SOUTH, Grid.WEST}) do
            local placed = Groups.materialize(block, {x = 20, y = 30, dir = dir})
            local serialized = serialize({candidate = {entities = placed.entities}, catalog = catalog})
            local machine, inserters = nil, 0
            for _, entity in ipairs(serialized.entities) do
                if entity.name == "mod-assembler" then machine = entity end
                if entity.name == "inserter" then
                    inserters = inserters + 1
                    H.equal(tostring(entity.flow_id or ""):sub(1, 6) == "fluid/", false,
                        "serialized inserter never serves a fluid flow")
                end
            end
            H.equal(machine ~= nil, true, "serialized machine exists")
            H.equal(machine and machine.recipe, "mixed-recipe", "serialized recipe survives rotation")
            H.equal(machine and machine.recipe_quality, "rare", "serialized recipe quality survives rotation")
            H.equal(machine and machine.items[1].items.in_inventory[1].stack, 2,
                "serialized module slot survives rotation")
            H.equal(inserters, 2, "serialized item transfers retain both inserters")
        end
    end)

    H.test(shape .. " S9 serializer uses etype for a modded furnace and assembler", function()
        local catalog = fluid_identity_catalog()
        local blueprint = serialize({catalog = catalog, entities = {
            {id = "assembler", name = "mod-assembler", etype = "assembling-machine", recipe = "r",
                recipe_quality = "rare", position = {x = 0.5, y = 0.5}},
            {id = "furnace", name = "mod-furnace", etype = "furnace", recipe = "must-not-be-written",
                recipe_quality = "legendary", position = {x = 4.5, y = 0.5}},
        }})
        local assembler, furnace = by_name(blueprint, "mod-assembler"), by_name(blueprint, "mod-furnace")
        H.equal(assembler.recipe, "r", "etype assembler receives recipe")
        H.equal(assembler.recipe_quality, "rare", "etype assembler receives recipe quality")
        H.equal(furnace.recipe, nil, "etype furnace receives no recipe")
        H.equal(furnace.recipe_quality, nil, "etype furnace receives no recipe quality")
    end)
end

H.test("SR-NOMUT serialize never writes into its input (it keeps the input, copies only the entities it numbers)", function()
    --Round 56 gate: Serialize.begin no longer copies the whole input (blue success tick 108 -> 41 ms).
    local input = {
        blocks = {{id = "b1", members = {{name = "assembling-machine-2", x = 1, y = 2, w = 3, h = 3}}}},
        placements = {b1 = {x = 4, y = 5}},
        route = {entities = {{id = "r1", name = "transport-belt", position = {x = 0.5, y = 0.5}, direction = 4}}},
        power = {entities = {{id = "p1", name = "small-electric-pole", position = {x = 9.5, y = 9.5}}}},
    }
    local function dump(value, out)
        out = out or {}
        if type(value) ~= "table" then out[#out + 1] = tostring(value); return out end
        local keys = {}; for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "="; dump(value[k], out) end
        out[#out + 1] = "}"
        return out
    end
    local before = table.concat(dump(input))
    local state = Serialize.begin(input)
    while not state.done do Serialize.step(state, {ops = 1}) end
    H.equal(table.concat(dump(input)), before, "input unchanged after a full serialize")
    H.equal(#state.result.entities, 3, "all three entities serialized")
end)

H.done("test_serialize")
