--The runtime adapter is the game-facing implementation.  These tests use the
--strict harness object model and call Scenario.runtime_adapter() itself; the
--candidate below only supplies a bounded generation result.
local H = require "tests.harness"

package.path = "tests/golden/engine/mod/?.lua;" .. package.path
local Scenario = require "scenario"

local PINNED = { ["2.0"] = "docs/api/2.0.77.members.json", ["2.1"] = "docs/api/2.1.19.members.json" }

local function read_pinned(shape)
    local file = assert(io.open(PINNED[shape]), "missing pinned API extract for " .. shape)
    local text = file:read("*a")
    file:close()
    return assert(helpers.json_to_table(text), "invalid pinned API extract for " .. shape)
end

local function set_of(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[value] = true end
    return result
end

local function members(attributes, methods)
    local result = {}
    for _, name in ipairs(attributes or {}) do result[#result + 1] = name end
    for _, name in ipairs(methods or {}) do result[#result + 1] = name end
    return result
end

local function assert_pinned(spec, class_name, member, kind)
    local class = spec.classes[class_name]
    H.equal(class ~= nil, true, class_name .. " is present in the pinned API")
    H.equal(set_of(class[kind])[member] == true, true,
        class_name .. "." .. member .. " is a pinned " .. kind:sub(1, -2))
end

--The pinned extract intentionally contains the classes used by the adapter's
--game/surface/inventory boundary.  Every one is checked before a test invokes
--the adapter.  Created runtime entities are strict local LuaObjects below as
--the extract has no LuaEntity class; their exact member set is explicit rather
--than discovered with pcall or by reading a permissive mock.
local function assert_adapter_api(shape)
    local spec = read_pinned(shape)
    local attributes = {
        {"LuaGameScript", "tick"}, {"LuaGameScript", "surfaces"}, {"LuaGameScript", "forces"},
        {"LuaGameScript", "speed"},
        {"LuaSurface", "valid"}, {"LuaForce", "technologies"}, {"LuaBootstrap", "active_mods"},
    }
    local methods = {
        {"LuaGameScript", "print"}, {"LuaGameScript", "delete_surface"},
        {"LuaGameScript", "create_surface"}, {"LuaGameScript", "create_force"},
        {"LuaSurface", "create_entities_from_blueprint_string"}, {"LuaSurface", "create_entity"},
        {"LuaInventory", "insert"}, {"LuaInventory", "remove"},
        {"LuaHelpers", "decode_string"}, {"LuaHelpers", "json_to_table"},
        {"LuaHelpers", "table_to_json"}, {"LuaHelpers", "encode_string"},
        {"LuaHelpers", "write_file"},
    }
    for _, entry in ipairs(attributes) do assert_pinned(spec, entry[1], entry[2], "attributes") end
    for _, entry in ipairs(methods) do assert_pinned(spec, entry[1], entry[2], "methods") end

    for _, member in ipairs({"name", "type", "valid", "position", "quality", "power_production",
        "inserter_stack_size_override", "power_usage"}) do
        assert_pinned(spec, "LuaEntity", member, "attributes")
    end
    for _, member in ipairs({"get_inventory", "destroy", "get_wire_connector", "revive"}) do
        assert_pinned(spec, "LuaEntity", member, "methods")
    end
    if shape == "2.0" then
        assert_pinned(spec, "LuaEntity", "fluidbox", "attributes")
    else
        for _, member in ipairs({"get_fluid", "add_fluid", "remove_fluid"}) do
            assert_pinned(spec, "LuaEntity", member, "methods")
        end
    end

    local blueprint_entity = spec.concepts.BlueprintEntity
    H.equal(blueprint_entity ~= nil, true, "BlueprintEntity is pinned")
    local fields = set_of(blueprint_entity.parameters)
    for _, name in ipairs({"name", "position", "entity_number", "quality", "items", "wires"}) do
        H.equal(fields[name] == true, true, "BlueprintEntity." .. name .. " is pinned")
    end
end

local function entity_members(shape)
    local attributes = {
        "name", "type", "valid", "position", "force", "direction", "recipe", "items", "quality", "wires",
        "power_production", "power_usage", "inserter_stack_size_override", "network_id",
    }
    if shape == "2.0" then attributes[#attributes + 1] = "fluidbox" end
    local methods = {"get_inventory", "get_wire_connector", "destroy", "revive"}
    if shape == "2.1" then
        for _, name in ipairs({"get_fluid", "add_fluid", "remove_fluid"}) do methods[#methods + 1] = name end
    end
    return members(attributes, methods)
end

local function blueprint_entities(two_poles)
    local result = {
        {entity_number = 1, name = "assembling-machine-1", position = {x = 0, y = 0},
            recipe = "iron-gear-wheel", quality = "rare",
            items = {{name = "speed-module", quality = "uncommon", count = 2}},
            wires = {{2, 5, 1, 1}}},
        {entity_number = 2, name = "medium-electric-pole", position = {x = 1, y = 0},
            quality = "uncommon", wires = {{1, 5, 2, 1}}},
    }
    if two_poles then
        result[#result + 1] = {entity_number = 3, name = "medium-electric-pole", position = {x = 2, y = 0},
            quality = "rare", wires = {{2, 5, 3, 1}}}
    end
    return result
end

local function encoded_blueprint(two_poles)
    local payload = {blueprint = {entities = blueprint_entities(two_poles)}}
    return "0" .. helpers.encode_string(helpers.table_to_json(payload))
end

local function runtime_world(shape)
    local world = H.new_world(shape)
    world.add_item("iron-plate")
    world.add_item("iron-gear-wheel")
    world.add_item("speed-module")
    world.add_machine({name = "assembling-machine-1", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "iron-gear-wheel", category = "crafting", ingredients = {{name = "iron-plate", amount = 2}},
        products = {{name = "iron-gear-wheel", amount = 1}}})
    world.add_default_infrastructure()

    local spec = read_pinned(shape)
    local surface_attributes = spec.classes.LuaSurface.attributes
    local surface_methods = spec.classes.LuaSurface.methods
    local force_attributes = spec.classes.LuaForce.attributes
    local force_methods = spec.classes.LuaForce.methods
    local game_attributes = spec.classes.LuaGameScript.attributes
    local game_methods = spec.classes.LuaGameScript.methods
    local inventory_attributes = spec.classes.LuaInventory.attributes
    local inventory_methods = spec.classes.LuaInventory.methods
    local records, files, printed, created_surfaces = {}, {}, {}, {}
    local revived_count = 0
    local helper_attributes = spec.classes.LuaHelpers.attributes
    local helper_methods = spec.classes.LuaHelpers.methods

    local original_helpers = helpers
    local helper_fields = {
        compare_versions = original_helpers.compare_versions,
        is_valid_sprite_path = original_helpers.is_valid_sprite_path,
        table_to_json = original_helpers.table_to_json,
        json_to_table = original_helpers.json_to_table,
        encode_string = original_helpers.encode_string,
        decode_string = original_helpers.decode_string,
        write_file = function(path, text, append)
            files[path] = (append and files[path] or "") .. text
        end,
    }
    _G.helpers = H.lua_object("LuaHelpers", helper_fields,
        members(helper_attributes, helper_methods), nil, nil)

    local function position_copy(position)
        return {x = position.x, y = position.y}
    end

    local function make_inventory(entity, initial)
        local available = {default = initial or 0}
        local inserted = {}
        local removed = {}
        local function stack_key(stack)
            return stack.name .. ":" .. (stack.quality or "normal")
        end
        local inventory = H.lua_object("LuaInventory", {valid = true, index = 1, name = "chest"},
            members(inventory_attributes, inventory_methods), nil, {
                insert = {read = function()
                    return function(stack)
                        local count = stack.count or 0
                        local key = stack_key(stack)
                        available[key] = (available[key] or 0) + count
                        inserted[#inserted + 1] = {name = stack.name, quality = stack.quality, count = count}
                        return count
                    end
                end},
                remove = {read = function()
                    return function(stack)
                        local key = stack_key(stack)
                        local count = math.min(available[key] or 0, stack.count or 0)
                        local used_default = false
                        if count == 0 and (stack.quality == nil or stack.quality == "normal") then
                            count = math.min(available.default or 0, stack.count or 0)
                            available.default = (available.default or 0) - count
                            used_default = true
                        end
                        if not used_default then available[key] = (available[key] or 0) - count end
                        removed[#removed + 1] = {name = stack.name, quality = stack.quality, count = count}
                        return count
                    end
                end},
            })
        return inventory, inserted, removed, function() return available end
    end

    local function make_entity(params)
        local entity_type = params.type
        local record = {name = params.name, type = entity_type, position = position_copy(params.position), destroyed = false}
        local initial = params.name == "iron-chest" and 100000 or 0
        local inventory, inserted, removed, available = make_inventory(record, initial)
        local fluid
        local fluidbox = {[1] = nil}
        local entity
        local connectors = {}
        local fields
        fields = {
            name = params.name, type = entity_type, valid = true, position = position_copy(params.position),
            force = params.force, direction = params.direction, recipe = params.recipe, items = params.items,
            quality = params.quality, wires = params.wires, power_production = params.power_production,
            power_usage = params.power_usage, inserter_stack_size_override = params.inserter_stack_size_override,
            network_id = params.name == "medium-electric-pole" and "factory-network"
                or (entity_type == "assembling-machine" and "factory-consumer-unpowered" or params.network_id),
            get_inventory = function() return inventory end,
            get_wire_connector = function(id)
                return connectors[id]
            end,
            revive = function()
                fields.type = params.revive_type or entity_type
                record.type = fields.type
                if fields.type == "assembling-machine" then fields.network_id = "factory-consumer-unpowered" end
                record.revived = true
                revived_count = revived_count + 1
                return {}, entity
            end,
            destroy = function()
                fields.valid = false
                record.destroyed = true
            end,
        }
        if shape == "2.0" then
            fields.fluidbox = fluidbox
        else
            fields.get_fluid = function(index)
                return index == 1 and fluid or nil
            end
            fields.add_fluid = function(index, value)
                if index ~= 1 or (fluid and fluid.name ~= value.name) then return 0 end
                local amount = value.amount or 0
                fluid = {name = value.name, amount = (fluid and fluid.amount or 0) + amount}
                return amount
            end
            fields.remove_fluid = function(index, amount)
                if index ~= 1 or not fluid then return nil end
                local removed = math.min(fluid.amount, amount or 0)
                if removed <= 0 then return nil end
                local result = {name = fluid.name, amount = removed}
                fluid.amount = fluid.amount - removed
                if fluid.amount <= 0 then fluid = nil end
                return result
            end
        end
        entity = H.lua_object("LuaEntity", fields, entity_members(shape), nil, nil)
        local connector_members = {"connect_to", "disconnect_from", "is_connected_to", "can_wire_reach",
            "owner", "wire_type", "wire_connector_id", "valid", "object_name", "connection_count",
            "connections", "real_connection_count", "real_connections", "network_id"}
        if entity_type == "electric-pole" or entity_type == "electric-energy-interface" then
            connectors[defines.wire_connector_id.pole_copper] = H.lua_object("LuaWireConnector", {
                owner = entity, wire_type = defines.wire_type.copper,
                wire_connector_id = defines.wire_connector_id.pole_copper, valid = true,
                connect_to = function(target)
                    record.connection = {wire = defines.wire_type.copper, target_entity = target.owner}
                    fields.network_id = target.owner.network_id or "factory-network"
                    return true
                end,
            }, connector_members, nil, nil)
        end
        record.entity, record.inserted, record.removed, record.available = entity, inserted, removed, available
        records[#records + 1] = record
        return entity
    end

    local function decode_blueprint(value)
        local encoded = value:sub(1, 1) == "0" and value:sub(2) or value
        return helpers.json_to_table(helpers.decode_string(encoded))
    end

    local function entity_type(name)
        if name == "medium-electric-pole" then return "electric-pole" end
        if name == "assembling-machine-1" then return "assembling-machine" end
        if name == "electric-energy-interface" then return "electric-energy-interface" end
        if name == "wooden-chest" or name == "iron-chest" then return "container" end
        if name == "storage-tank" then return "storage-tank" end
        if name == "pipe" then return "pipe" end
        if name == "inserter" then return "inserter" end
        return "simple-entity"
    end

    local function make_surface(name)
        local surface
        local function create_entity(params)
            return make_entity({name = params.name, type = entity_type(params.name), position = params.position,
                force = params.force, direction = params.direction})
        end
        local fields = {name = name, valid = true,
            create_entity = create_entity,
            create_entities_from_blueprint_string = function(params)
                local decoded = decode_blueprint(params.string)
                local root = decoded.blueprint or decoded
                local created = {}
                for _, blueprint_entity in ipairs(root.entities or {}) do
                    local position = {x = blueprint_entity.position.x + params.position.x,
                        y = blueprint_entity.position.y + params.position.y}
                    local is_first = #created == 0
                    created[#created + 1] = make_entity({name = blueprint_entity.name,
                        type = is_first and "entity-ghost" or entity_type(blueprint_entity.name),
                        revive_type = entity_type(blueprint_entity.name), position = position, force = params.force,
                        recipe = blueprint_entity.recipe, items = blueprint_entity.items,
                        quality = blueprint_entity.quality, wires = blueprint_entity.wires})
                end
                return created
            end,
        }
        surface = H.lua_object("LuaSurface", fields, members(surface_attributes, surface_methods), nil, nil)
        return surface
    end

    local force = H.lua_object("LuaForce", {name = "player", valid = true, technologies = {}},
        members(force_attributes, force_methods), nil, nil)
    local surface = make_surface("nauvis")
    local surfaces, forces = {nauvis = surface}, {player = force}
    local game = H.lua_object("LuaGameScript", {tick = 0, speed = 1, surfaces = surfaces, forces = forces},
        members(game_attributes, game_methods), nil, nil)
    game.create_surface = function(name)
        local value = make_surface(name)
        surfaces[name] = value
        created_surfaces[#created_surfaces + 1] = value
        return value
    end
    game.create_force = function(name)
        local value = H.lua_object("LuaForce", {name = name, valid = true, technologies = {}},
            members(force_attributes, force_methods), nil, nil)
        forces[name] = value
        return value
    end
    game.delete_surface = function(name) surfaces[name] = nil end
    game.print = function(line) printed[#printed + 1] = line end
    _G.game = game

    return {
        world = world, game = game, force = force, surface = surface, records = records,
        files = files, printed = printed, created_surfaces = created_surfaces, revived_count = function()
            return revived_count
        end,
    }
end

local function adapter_case()
    local supply, drain = {}, {}
    local positions = {
        {x = -5, y = -5, direction = 0}, {x = 5, y = -5, direction = 4},
        {x = 5, y = 5, direction = 8}, {x = -5, y = 5, direction = 12},
    }
    for index, position in ipairs(positions) do
        supply[index] = {full_name = "item/iron-plate", rate_per_second = 120,
            position = {x = position.x, y = position.y}, travel_dir = position.direction,
            port_id = "supply-" .. index}
        drain[index] = {full_name = "item/iron-gear-wheel", rate_per_second = 120,
            position = {x = position.x, y = position.y}, travel_dir = position.direction,
            port_id = "drain-" .. index}
    end
    return {
        case_id = "adapter-runtime",
        sheet_id = "sheet-runtime",
        player_index = 1,
        expected_candidate_sha = "candidate-sha",
        prepared_input = {source_kind = "harness", marker = "captured-prepared-input",
            snapshot = {schema_version = 1, sheet_id = "sheet-runtime"},
            solver_result = {result = "fixture"}, catalog = {items = {"iron-plate"}},
            settings = {precision = 3}, options = {quality = "rare"}, revisions = {sheet = 4, config = 2}},
        setup = {settings = {current = {precision = 3}}, options = {quality = "rare"}},
        engine_scenario = {
            initial_state = {surface = "nauvis", force = "player"}, build_position = {x = 100, y = 100},
            warm_up_ticks = 1, sampling_window_ticks = 2, timeout_seconds = 10,
            supply = supply, drain = drain, factory_demand_per_second = 1,
        },
    }
end

local function fluid_adapter_case()
    local result = adapter_case()
    result.case_id = "adapter-fluid-runtime"
    result.engine_scenario.supply = {{full_name = "fluid/water", rate_per_second = 120,
        position = {x = -5, y = -5}, travel_dir = 0, port_id = "fluid-supply"}}
    result.engine_scenario.drain = {{full_name = "fluid/water", rate_per_second = 120,
        position = {x = 5, y = 5}, travel_dir = 8, port_id = "fluid-drain"}}
    return result
end

local function quality_key(item_name, quality)
    return "item-quality:" .. #item_name .. ":" .. item_name .. #quality .. ":" .. quality
end

local function record_for(fixture, entity)
    for _, record in ipairs(fixture.records) do
        if record.entity == entity then return record end
    end
    return nil
end

local function assert_shape(actual, exemplar, path)
    path = path or "observation"
    H.equal(actual ~= nil, true, path .. " is present")
    if type(exemplar) ~= "table" then return end
    H.equal(type(actual), "table", path .. " is an object")
    if #exemplar > 0 then
        H.equal(#actual >= #exemplar, true, path .. " has the example array shape")
        for index, value in ipairs(exemplar) do assert_shape(actual[index], value, path .. "[" .. index .. "]") end
        return
    end
    for key, value in pairs(exemplar) do
        if key ~= "note" and key ~= "wall_clock_seconds" then
            assert_shape(actual[key], value, path .. "." .. key)
        end
    end
end

local function example(name)
    local file = assert(io.open("docs/engine-evidence/examples/" .. name .. ".json"))
    local text = file:read("*a")
    file:close()
    return assert(helpers.json_to_table(text), "invalid " .. name .. " example")
end

local function production_candidate(blueprint)
    local status_calls = 0
    return {
        build_id = function()
            return {candidate_sha = "candidate-sha", packaged = true, factorio_branch = "2.0",
                factorio_version = "2.0.77"}
        end,
        start_generation = function(context)
            H.equal(context.prepared_input.marker, "captured-prepared-input", "service sees nested prepared input")
            H.equal(context.snapshot, nil, "prepared fields are not flattened into the context")
            return "job-runtime"
        end,
        generation_status = function()
            status_calls = status_calls + 1
            if status_calls == 1 then return {state = "pending", phase = "preparing"} end
            return {state = "success", phase = "complete", blueprint_string = blueprint,
                canonical_sha256 = string.rep("a", 64), canonical_version = 1}
        end,
        cancel_generation = function() return {state = "cancelled"} end,
        canonical = function() return {canonical_sha256 = string.rep("a", 64), canonical_version = 1} end,
    }
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " RA1 checks adapter members against the pinned API before use", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        H.equal(type(fixture.game), "userdata", "game is a strict LuaObject")
        H.equal(type(prototypes), "userdata", "prototypes keeps engine userdata shape")
    end)

    H.test(shape .. " RA2 passes captured prepared input nested to the service", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter = Scenario.runtime_adapter()
        local context = adapter.generation_context(adapter_case(), {surface_name = "nauvis", force_name = "player"},
            {factorio_branch = shape, factorio_version = shape})
        H.equal(context.prepared_input.marker, "captured-prepared-input", "prepared marker is nested")
        H.equal(context.marker, nil, "prepared marker is not flat")
        H.equal(context.prepared_input.source_kind, "harness", "prepared provenance survives")
        H.equal(context.deliver, false, "engine generation never delivers to the cursor")
        H.equal(fixture.files["unused"], nil, "context construction has no side effects")
    end)

    H.test(shape .. " RA3 builds real machines with recipe modules quality and wires", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter = Scenario.runtime_adapter()
        local case = adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), adapter.generation_context(case, environment, {}), environment, case)
        H.equal(#built.entities, 2, "blueprint created two real entities")
        H.equal(type(built.entities[1]), "userdata", "built result contains LuaEntity objects")
        H.equal(built.entities[1].name, "assembling-machine-1", "machine name")
        H.equal(built.entities[1].recipe, "iron-gear-wheel", "machine recipe")
        H.equal(built.entities[1].items[1].name, "speed-module", "machine module")
        H.equal(built.entities[1].items[1].quality, "uncommon", "module quality")
        H.equal(built.entities[1].quality, "rare", "machine quality")
        H.equal(#built.entities[1].wires, 1, "machine wire data")
        H.equal(fixture.revived_count(), 1, "ghost entity was revived")
        H.equal(built.entities[2].type, "electric-pole", "pole is a real electric pole")
        H.equal(#fixture.records, 2, "the strict surface created the two entities")
    end)

    H.test(shape .. " RA4 puts source and sink buffers on all four perimeter edges", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        local drains = adapter.prepare_drain(built, case, environment)
        H.equal(#supplies, 4, "four source ports")
        H.equal(#drains, 4, "four sink ports")
        local seen_supply, seen_drain = {}, {}
        for _, port in ipairs(supplies) do
            seen_supply[port.entry.travel_dir] = true
            H.equal(port.buffer.name, "wooden-chest", "source buffer is a chest")
            H.equal(port.inserter.name, "inserter", "source has an inserter")
        end
        for _, port in ipairs(drains) do
            seen_drain[port.entry.travel_dir] = true
            H.equal(port.buffer.name, "iron-chest", "sink buffer is a chest")
            H.equal(port.inserter.name, "inserter", "sink has an inserter")
        end
        local function check_edge(port, side)
            local direction = port.entry.travel_dir
            local dx, dy = 0, -1
            if direction == 4 then dx, dy = 1, 0 end
            if direction == 8 then dx, dy = 0, 1 end
            if direction == 12 then dx, dy = -1, 0 end
            local anchor = {x = 100 + port.entry.position.x, y = 100 + port.entry.position.y}
            local distance = side == "supply" and -2 or 2
            H.equal(port.buffer.position.x, anchor.x + dx * distance, side .. " buffer x at edge " .. direction)
            H.equal(port.buffer.position.y, anchor.y + dy * distance, side .. " buffer y at edge " .. direction)
        end
        for _, port in ipairs(supplies) do check_edge(port, "supply") end
        for _, port in ipairs(drains) do check_edge(port, "drain") end
        for _, direction in ipairs({0, 4, 8, 12}) do
            H.equal(seen_supply[direction], true, "source reaches edge direction " .. direction)
            H.equal(seen_drain[direction], true, "sink reaches edge direction " .. direction)
        end
        H.equal(#built.perimeter, 8, "all source and sink perimeter entities are attached")
        H.equal(#fixture.records, 18, "strict surface saw factory plus sixteen perimeter entities")
    end)

    H.test(shape .. " RA5 supply and drain keep feed counts separate and exceed factory demand", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        local drains = adapter.prepare_drain(built, case, environment)
        for _, port in ipairs(supplies) do H.equal(port.entry.rate_per_second > case.engine_scenario.factory_demand_per_second, true, "supply exceeds factory demand") end
        for _, port in ipairs(drains) do H.equal(port.entry.rate_per_second > case.engine_scenario.factory_demand_per_second, true, "drain exceeds factory demand") end
        local accepted = adapter.supply(supplies)
        local drained = adapter.drain(drains)
        H.equal(accepted["item/iron-plate"] > 0, true, "source accepted declared feed")
        H.equal(drained["item/iron-gear-wheel"] > 0, true, "sink released factory output")
        H.equal(drained["item/iron-plate"], nil, "measurement cannot count the feed as output")
        H.equal(#fixture.records, 18, "feed and drain used real perimeter entities")
    end)

    H.test(shape .. " RA5b uses the pinned branch-specific fluid boundary", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), fluid_adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        local drains = adapter.prepare_drain(built, case, environment)
        local accepted = adapter.supply(supplies)
        adapter.supply(drains)
        local drained = adapter.drain(drains)
        H.equal(accepted["fluid/water"] > 0, true, "fluid source accepted water")
        H.equal(drained["fluid/water"] > 0, true, "fluid sink released water")
        H.equal(#fixture.records, 6, "fluid perimeter uses only its buffer and pipe entities")
    end)

    H.test(shape .. " QS1 legendary item supplied through the perimeter keeps its quality", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        case.engine_scenario.supply = {{full_name = "item/iron-plate", quality = "legendary", rate_per_second = 60,
            position = {x = -5, y = -5}, travel_dir = 0, port_id = "legendary-supply"}}
        case.engine_scenario.drain = {}
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        local accepted = adapter.supply(supplies)
        local inserted = record_for(fixture, supplies[1].buffer).inserted[1]
        H.equal(inserted ~= nil, true, "supply inserted a stack")
        H.equal(inserted.quality, "legendary", "supply stack keeps legendary quality")
        H.equal(accepted[quality_key("iron-plate", "legendary")], 1, "supply measurement keeps quality key")
        H.equal(accepted["item/iron-plate"], nil, "quality supply is not measured as normal")
    end)

    H.test(shape .. " QD1 legendary item drained through the perimeter keeps its quality and qualities never collapse", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        case.engine_scenario.supply = {}
        case.engine_scenario.drain = {
            {full_name = "item/iron-plate", quality = "rare", rate_per_second = 60,
                position = {x = 5, y = -5}, travel_dir = 4, port_id = "rare-drain"},
            {full_name = "item/iron-plate", quality = "legendary", rate_per_second = 60,
                position = {x = 5, y = 5}, travel_dir = 8, port_id = "legendary-drain"},
        }
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local drains = adapter.prepare_drain(built, case, environment)
        for _, port in ipairs(drains) do
            port.buffer.get_inventory(defines.inventory.chest).insert({name = port.name, quality = port.quality, count = 1})
        end
        local drained = adapter.drain(drains)
        H.equal(drains[2].quality, "legendary", "drain perimeter object keeps legendary quality")
        H.equal(record_for(fixture, drains[2].buffer).removed[1].quality, "legendary",
            "drain removes a legendary stack")
        H.equal(drained[quality_key("iron-plate", "rare")], 1, "rare output has its own measurement key")
        H.equal(drained[quality_key("iron-plate", "legendary")], 1, "legendary output has its own measurement key")
        H.equal(drained["item/iron-plate"], nil, "two qualities never collapse into normal output")
    end)

    H.test(shape .. " QC1 a perimeter device carries the declared load with measured headroom including the high-load external item endpoint", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        case.engine_scenario.supply = {{full_name = "item/iron-plate", rate_per_second = 600,
            position = {x = -5, y = -5}, travel_dir = 0, port_id = "incident-high-load"}}
        case.engine_scenario.drain = {}
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        adapter.provide_power(built, case, environment)
        local port = supplies[1]
        H.equal(port.inserter.inserter_stack_size_override > 1, true, "high-load endpoint derives stack capacity")
        H.equal(port.capacity_per_second > port.entry.rate_per_second, true, "capacity has measured headroom")
        H.equal(port.capacity_headroom_per_second > 0, true, "headroom is recorded")
        H.equal(port.power_pole ~= nil, true, "perimeter inserter has a dedicated power pole")
        H.equal(port.buffer.position.x ~= port.inserter.position.x or port.buffer.position.y ~= port.inserter.position.y,
            true, "buffer and inserter occupy legal distinct positions")
        local accepted = {}
        for _ = 1, 60 do
            local counts = adapter.supply(supplies)
            accepted["item/iron-plate"] = (accepted["item/iron-plate"] or 0) + (counts["item/iron-plate"] or 0)
        end
        H.equal(Scenario.rate_per_second(accepted["item/iron-plate"], 60) >= 600, true,
            "measured endpoint rate carries the incident load")
        H.equal(port.measured_rate_per_second >= port.entry.rate_per_second, true,
            "perimeter device records its measured declared rate")
        H.equal(port.measured_rate_per_second < port.capacity_per_second, true,
            "measured rate retains headroom")
    end)

    H.test(shape .. " QP1 harness-only power never covers a deliberately unpowered factory consumer", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        H.equal(adapter.provide_power(built, case, environment), true, "harness perimeter power setup succeeds")
        H.equal(built.entities[1].network_id, "factory-consumer-unpowered", "factory consumer starts unpowered")
        H.equal(built.power.network_id == built.entities[1].network_id, false,
            "harness-only power does not repair the factory consumer")
        for _, port in ipairs(supplies) do
            H.equal(port.power_pole ~= built.entities[2], true, "perimeter power is not the factory pole")
        end
        H.equal(#fixture.records > #built.entities, true, "power setup created perimeter-only fixtures")
    end)

    H.test(shape .. " RA6 connects power production to dedicated perimeter poles", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local adapter, case = Scenario.runtime_adapter(), adapter_case()
        local environment = adapter.setup_environment(case, {factorio_branch = shape})
        local built = adapter.build_blueprint(encoded_blueprint(true), {}, environment, case)
        local supplies = adapter.prepare_supply(built, case, environment)
        H.equal(adapter.provide_power(built, case, environment), true, "power setup succeeds")
        H.equal(built.power.power_production, "100MW", "power source produces energy")
        H.equal(built.power.network_id, supplies[1].power_pole.network_id, "power source joins the perimeter network")
        local connected = false
        for _, record in ipairs(fixture.records) do
            if record.entity == built.power and record.connection and record.connection.wire == defines.wire_type.copper then
                connected = record.connection.target_entity.type == "electric-pole"
                    and record.connection.target_entity ~= built.entities[2]
                    and record.connection.target_entity ~= built.entities[3]
            end
        end
        H.equal(connected, true, "copper wire reaches the blueprint pole")
        local first_pole, second_pole = built.entities[2], built.entities[3]
        local first_connector = first_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        local second_connector = second_pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
        H.equal(first_connector.connect_to(second_connector), true, "copper wire connects the two poles")
        local poles_connected = false
        for _, record in ipairs(fixture.records) do
            if record.entity == first_pole and record.connection
                and record.connection.target_entity == second_pole then
                poles_connected = true
            end
        end
        H.equal(poles_connected, true, "two poles share the electrical connection")
    end)

    H.test(shape .. " RA7 production observation follows the frozen example shape", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local blueprint = encoded_blueprint()
        local adapter = Scenario.runtime_adapter()
        local controller = Scenario.new({candidate = production_candidate(blueprint), adapter = adapter})
        local accepted = controller:submit(adapter_case())
        H.equal(accepted, true, "runtime adapter controller accepts the case")
        for tick = 1, 10 do fixture.game.tick = tick; controller:tick(tick) end
        local observation = controller:status().observation
        H.equal(observation.production ~= nil, true, "runtime adapter reaches production")
        assert_shape(observation, example("production"))
        H.equal(observation.outcome_kind, "production", "production outcome kind")
        H.equal(observation.production.accepted_supply.counts["item/iron-plate"] > 0, true, "feed was accepted")
        H.equal(observation.production.drained_outputs.counts["item/iron-gear-wheel"] > 0, true, "output was drained")
        H.equal(observation.production.drained_outputs.counts["item/iron-plate"], nil, "feed is absent from output")
        H.equal(fixture.files["rrc-engine-evidence/adapter-runtime.observation.json"] ~= nil, true,
            "runtime adapter wrote the captured observation")
        H.equal(helpers.json_to_table(fixture.files["rrc-engine-evidence/adapter-runtime.observation.json"]).outcome_kind,
            "production", "observation file contains the terminal outcome")
    end)

    H.test(shape .. " RA8 rejection and export observations follow their example shapes", function()
        local fixture = runtime_world(shape)
        assert_adapter_api(shape)
        local rejected = Scenario.new({adapter = Scenario.runtime_adapter(), candidate = {
            build_id = function() return {candidate_sha = "candidate-sha", packaged = false,
                factorio_branch = shape, factorio_version = shape} end,
        }})
        rejected:submit(adapter_case())
        local rejection = rejected:status().observation
        assert_shape(rejection, example("rejection"))
        H.equal(rejection.outcome_kind, "rejection", "rejection outcome kind")

        local export_payload = {format = "rrc-sheet-debug", schema_version = 1}
        local export_candidate = production_candidate(encoded_blueprint())
        export_candidate.export = function()
            return helpers.encode_string(helpers.table_to_json(export_payload))
        end
        local exporting = Scenario.new({adapter = Scenario.runtime_adapter(), candidate = export_candidate})
        local export_case = adapter_case()
        export_case.expected_outcome = "export"
        H.equal(exporting:submit(export_case), true, "export case accepted")
        fixture.game.tick = 1; exporting:tick(1)
        fixture.game.tick = 2; exporting:tick(2)
        local exported = exporting:status().observation
        assert_shape(exported, example("export"))
        H.equal(exported.outcome_kind, "export", "export outcome kind")
        H.equal(exported.export.format, "rrc-sheet-debug", "decoded export envelope")
        H.equal(exported.export.content_sha256 ~= nil, true, "export content digest")
    end)
end

H.done("test_engine_runtime_adapter")
