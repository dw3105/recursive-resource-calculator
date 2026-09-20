--Every engine member the harness mocks exists in the pinned runtime API, with the right kind (attribute or method)
--Round 8 shipped two invented members in a plan revision (get_logistic_radius, max_connection_distance); this file
--is what makes that class of mistake impossible to repeat. It checks names and kinds only: parameter types, subtype
--gating and physical behaviour stay the job of the strict mocks and the in-game tier.
local H = require "tests.harness"

local PINNED = {["2.0"] = "docs/api/2.0.77.members.json", ["2.1"] = "docs/api/2.1.19.members.json"}

--Reads the extract without a JSON library: the mod's own helpers mock is available once a world exists
local function pinned_spec(shape)
    local file = assert(io.open(PINNED[shape]), "missing pinned API extract for " .. shape)
    local text = file:read("*a")
    file:close()
    return assert(helpers.json_to_table(text), "pinned extract is not JSON: " .. PINNED[shape])
end

--The core style names, pinned from wube/factorio-data. A style the game has not got crashes add{} at once.
local function pinned_styles()
    local file = assert(io.open("docs/api/2.0.77.styles.json"), "missing pinned style list")
    local text = file:read("*a")
    file:close()
    return assert(helpers.json_to_table(text), "pinned style list is not JSON")
end

--Every Lua file the release script copies, so a style named in any of them is checked
local function shipped_lua_files()
    local paths = {"control.lua"}
    local listing = io.popen("ls gui/*.lua logic/*.lua logic/bp/*.lua 2>/dev/null")
    for line in listing:lines() do paths[#paths + 1] = line end
    listing:close()
    return paths
end

local function set_of(list)
    local set = {}
    for _, name in ipairs(list or {}) do set[name] = true end
    return set
end

--The members the harness serves per class, and whether the mock serves each as a value or as a function
local function harness_members(world, shape)
    local pole = prototypes.entity["medium-electric-pole"]
    local roboport = prototypes.entity["roboport"]
    local belt = prototypes.entity["transport-belt"]
    local underground = prototypes.entity["underground-belt"]
    local inserter = prototypes.entity["inserter"]
    local pipe_to_ground = prototypes.entity["pipe-to-ground"]
    local machine = prototypes.entity["assembler"]
    local plate = prototypes.item["plate"]
    local recipe = prototypes.recipe["plate"]
    local beacon = prototypes.entity["beacon"]
    return {
        LuaEntityPrototype = {
            attributes = {
                {"collision_box", machine.collision_box}, {"collision_mask", machine.collision_mask},
                {"tile_width", machine.tile_width}, {"tile_height", machine.tile_height}, {"flags", machine.flags},
                {"fluidbox_prototypes", pipe_to_ground.fluidbox_prototypes},
                {"belt_speed", belt.belt_speed}, {"max_underground_distance", underground.max_underground_distance},
                {"related_underground_belt", underground.related_underground_belt},
                {"inserter_pickup_position", inserter.inserter_pickup_position},
                {"inserter_drop_position", inserter.inserter_drop_position},
                {"inserter_stack_size_bonus", inserter.inserter_stack_size_bonus},
                {"inserter_max_belt_stack_size", inserter.inserter_max_belt_stack_size},
                {"logistic_radius", roboport.logistic_radius}, {"construction_radius", roboport.construction_radius},
                --connection_distance is deliberately absent from this list. It is subclasses ["RollingStock"],
                --so probing it on a roboport is exactly the invalid read this round removed from production.
                --Its existence and its owning subclass are pinned in tests/tools/test_api_applicability.py,
                --which also checks the harness gate against the same pinned extracts.
                {"quality_affects_supply_area_distance", pole.quality_affects_supply_area_distance},
                {"energy_usage", machine.energy_usage}, {"distribution_effectivity", beacon.distribution_effectivity},
                --round 9: the quality policy reads the receiver, the capacity model reads inserter speeds
                {"effect_receiver", machine.effect_receiver},
                {"allowed_effects", machine.allowed_effects},
            },
            methods = {
                {"get_supply_area_distance", pole.get_supply_area_distance},
                {"get_max_wire_distance", pole.get_max_wire_distance},
                {"get_crafting_speed", machine.get_crafting_speed},
                {"get_max_energy_usage", machine.get_max_energy_usage},
                {"get_inserter_rotation_speed", inserter.get_inserter_rotation_speed},
                {"get_inserter_extension_speed", inserter.get_inserter_extension_speed},
            },
        },
        LuaItemPrototype = {
            attributes = {{"spoil_result", plate.spoil_result}, {"fuel_value", plate.fuel_value}},
            methods = {{"get_spoil_ticks", plate.get_spoil_ticks}},
        },
        LuaRecipePrototype = {
            attributes = {{"energy", recipe.energy}, {"allowed_effects", recipe.allowed_effects},
                {"ingredients", recipe.ingredients}, {"products", recipe.products}},
            methods = {},
        },
        LuaHelpers = {
            attributes = {},
            methods = {{"table_to_json", helpers.table_to_json}, {"json_to_table", helpers.json_to_table},
                {"encode_string", helpers.encode_string}, {"decode_string", helpers.decode_string},
                {"compare_versions", helpers.compare_versions}, {"is_valid_sprite_path", helpers.is_valid_sprite_path}},
        },
        LuaFluidBoxPrototype = {
            attributes = {{"pipe_connections", pipe_to_ground.fluidbox_prototypes[1].pipe_connections},
                {"index", pipe_to_ground.fluidbox_prototypes[1].index},
                {"production_type", pipe_to_ground.fluidbox_prototypes[1].production_type},
                {"minimum_temperature", pipe_to_ground.fluidbox_prototypes[1].minimum_temperature}},
            methods = {},
        },
    }
end

local function world_with_infrastructure(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate", nil, {result = "ore", ticks = 600})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "plate", category = "crafting", ingredients = {{name = "ore", amount = 1}},
        products = {{name = "plate", amount = 1}}})
    world.add_beacon({name = "beacon"})
    world.add_default_infrastructure()
    world.add_blueprint_item()
    world.add_player(1)
    world.init()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " A0 the extract identifies its pinned source", function()
        H.new_world(shape)
        local spec = pinned_spec(shape)
        H.equal(spec.source_url, "https://lua-api.factorio.com/" .. (shape == "2.0" and "2.0.77" or "2.1.19") .. "/runtime-api.json",
            "source URL is pinned")
        H.equal(spec.api_version, 6, "runtime API version is pinned")
        H.equal(type(spec.description_sha256), "string", "download digest is recorded")
        H.equal(#spec.description_sha256, 64, "download digest is SHA-256")
    end)

    H.test(shape .. " A1 every mocked member exists in the pinned runtime API, as the right kind", function()
        local world = world_with_infrastructure(shape)
        local spec = pinned_spec(shape)
        for class_name, served in pairs(harness_members(world, shape)) do
            local pinned = spec.classes[class_name]
            H.equal(pinned ~= nil, true, class_name .. " is in the pinned extract")
            local attributes, methods = set_of(pinned.attributes), set_of(pinned.methods)
            for _, entry in ipairs(served.attributes) do
                H.equal(attributes[entry[1]] == true, true, class_name .. "." .. entry[1] .. " is a pinned attribute")
                H.equal(type(entry[2]) ~= "function", true, class_name .. "." .. entry[1] .. " is served as a value")
            end
            for _, entry in ipairs(served.methods) do
                H.equal(methods[entry[1]] == true, true, class_name .. "." .. entry[1] .. " is a pinned method")
                H.equal(type(entry[2]), "function", class_name .. "." .. entry[1] .. " is served as a function")
            end
        end
    end)

    H.test(shape .. " A2 blueprint stack members come from the inherited class, not an invented one", function()
        local world = world_with_infrastructure(shape)
        local spec = pinned_spec(shape)
        local stack = spec.classes.LuaItemStack
        H.equal(stack.parent, "LuaItemCommon", "LuaItemStack inherits LuaItemCommon")
        for _, name in ipairs({"set_stack", "clear", "set_blueprint_entities", "get_blueprint_entities", "is_blueprint_setup"}) do
            H.equal(set_of(stack.methods)[name] == true, true, "LuaItemStack." .. name .. " is pinned (through its parent)")
        end
        for _, name in ipairs({"label", "preview_icons", "is_blueprint", "blueprint_description"}) do
            H.equal(set_of(stack.attributes)[name] == true, true, "LuaItemStack." .. name .. " is a pinned attribute")
        end
    end)

    H.test(shape .. " A3 names the plan once invented are absent from the pinned API", function()
        H.new_world(shape)
        local spec = pinned_spec(shape)
        local attributes, methods = set_of(spec.classes.LuaEntityPrototype.attributes), set_of(spec.classes.LuaEntityPrototype.methods)
        H.equal(methods.get_logistic_radius, nil, "no get_logistic_radius method")
        H.equal(attributes.get_logistic_radius, nil, "no get_logistic_radius attribute")
        H.equal(attributes.max_connection_distance, nil, "no max_connection_distance attribute")
        H.equal(attributes.logistic_radius, true, "logistic_radius is the real name")
        H.equal(attributes.connection_distance, true, "connection_distance is the real name")
    end)

    --A class member check proves the receiver attribute exists; it says nothing about the table behind it.
    --The quality policy reads that table field by field, so its keys are pinned against the concept itself,
    --and the two branches genuinely differ: 2.1 adds quality_limits and uses_local_effects, 2.0 has neither.
    H.test(shape .. " A5 the effect receiver the harness builds matches the pinned concept", function()
        local world = world_with_infrastructure(shape)
        local spec = pinned_spec(shape)
        local concept = spec.concepts.EffectReceiver
        H.equal(concept ~= nil, true, "EffectReceiver is in the pinned extract")
        local parameters = set_of(concept.parameters)
        local receiver = prototypes.entity["assembler"].effect_receiver
        H.equal(type(receiver), "table", "the harness builds a receiver")
        for key in pairs(receiver) do
            H.equal(parameters[key] == true, true, "EffectReceiver." .. key .. " is a pinned parameter")
        end
        H.equal(parameters.base_effect, true, "base_effect is pinned on both branches")
        H.equal(parameters.uses_module_effects, true, "uses_module_effects is pinned on both branches")
        if shape == "2.1" then
            H.equal(parameters.quality_limits, true, "2.1 exposes quality_limits")
            H.equal(parameters.uses_local_effects, true, "2.1 exposes uses_local_effects")
            H.equal(receiver.uses_local_effects ~= nil, true, "the 2.1 harness carries uses_local_effects")
        else
            H.equal(parameters.quality_limits, nil, "2.0 has no quality_limits")
            H.equal(parameters.uses_local_effects, nil, "2.0 has no uses_local_effects")
            H.equal(receiver.quality_limits, nil, "the 2.0 harness never invents quality_limits")
        end
    end)

    H.test(shape .. " A4 the runtime pipe connection carries positions, never a single position", function()
        H.new_world(shape)
        local spec = pinned_spec(shape)
        local parameters = set_of(spec.concepts.PipeConnectionDefinition.parameters)
        H.equal(parameters.positions, true, "positions is the runtime shape")
        H.equal(parameters.position, nil, "singular position is the data stage, not runtime")
        for _, name in ipairs({"direction", "connection_type", "flow_direction", "max_underground_distance"}) do
            H.equal(parameters[name], true, "PipeConnectionDefinition." .. name)
        end
        if shape == "2.1" then
            H.equal(parameters.alt_direction, true, "2.1 adds alt_direction")
            H.equal(parameters.alt_position, true, "2.1 adds alt_position")
        end
    end)

    H.test(shape .. " A5 the mocked pipe connection matches that shape", function()
        local world = world_with_infrastructure(shape)
        local connection = prototypes.entity["pipe-to-ground"].fluidbox_prototypes[1].pipe_connections[2]
        H.equal(#connection.positions, 4, "one position per cardinal orientation")
        H.equal(connection.connection_type, "underground", "the buried end is the underground connection")
        H.equal(connection.direction, defines.direction.south, "vanilla buries to the south while its open end faces north")
        H.equal(connection.position, nil, "no data-stage position field")
    end)

    H.test(shape .. " A6 blueprint wires are the pinned tuple of entity and connector ids", function()
        H.new_world(shape)
        local spec = pinned_spec(shape)
        H.equal(spec.concepts.BlueprintEntity ~= nil, true, "BlueprintEntity is pinned")
        H.equal(set_of(spec.concepts.BlueprintEntity.parameters).wires, true, "BlueprintEntity.wires exists")
        local connectors = set_of(spec.defines.wire_connector_id)
        H.equal(connectors.pole_copper, true, "pole_copper carries power")
        H.equal(connectors.circuit_red, true, "circuit_red exists and never carries power")
        H.equal(defines.wire_connector_id.pole_copper ~= nil, true, "the harness serves the same define")
    end)
    H.test(shape .. " A7 every style the mod names exists in the pinned core styles", function()
        H.new_world(shape)
        local pinned = set_of(pinned_styles().styles)
        H.equal(pinned.frame_action_button, true, "the pin carries the vanilla title bar button style")
        local checked = 0
        for _, path in ipairs(shipped_lua_files()) do
            local file = assert(io.open(path))
            local source = file:read("*a")
            file:close()
            for name in source:gmatch('style%s*=%s*"([A-Za-z_0-9]+)"') do
                --1.1.47 crashed on open with "Unknown style draggable_space_with_no_left_margin": the mock took
                --any string, so an invented style reached the game. The pin is what refuses one here.
                H.equal(pinned[name], true, path .. " names style " .. name)
                checked = checked + 1
            end
        end
        H.equal(checked > 0, true, "at least one style name was checked")
    end)
end

H.done("test_api_shapes")
