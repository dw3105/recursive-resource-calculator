--Prototype facts as plain data, read once, so everything downstream can be pure.
--
--Owned by lane W1-catalog. Only this module and logic/bp/plan.lua touch prototypes; every geometry, routing,
--power and serialization module takes a catalog and returns plain data, which is what lets those lanes be
--written and tested with no game at all.
--
--Two geometry models live here, and they are not the same thing:
--  tile_w/tile_h      the north footprint, integer. A conservative bound the packer uses.
--  collision_box      the exact box in tiles relative to the entity centre, with its mask. What the validator
--                     uses. A packer and a validator sharing one model cannot catch each other's mistake.
--
--Quality is never assumed: reach, supply area, crafting speed and module slots are read at the selected quality
--through the prototype's own accessors, never from a normal-quality constant.
--
--  entity[name] = {name, etype, tile_w, tile_h, collision_box = {left_top = {x, y}, right_bottom = {x, y}},
--                  collision_mask, module_slots, energy_usage_w, pollution_per_min, needs_power,
--                  fluid_boxes = {{index, production_type, filter, connections = {
--                      {positions = {4 x {x, y}}, direction, connection_type, flow_direction, max_underground_distance}}}},
--                  beacon = {supply_w, supply_h, distribution_effectivity, profile, counter} | nil}
--  belt = {belt, underground, splitter, quality, items_per_second, lane_items_per_second, underground_max_distance}
--  pipe = {pipe, underground, quality, underground_max_distance, throughput_per_second}
--  inserter = {name, quality, items_per_second, pickup_offset, drop_offset, drop_position}
--  pole = {name, quality, tile_w, tile_h, supply_w, supply_h, wire_reach}
--  robo = {name, quality, tile_w, tile_h, logistic_radius, construction_radius, connection_distance}
--
--An identity that no longer resolves is reported, never guessed and never crashed on.
local Catalog = {}

Catalog.SCHEMA_VERSION = 1

local Utils = require "logic.utils"

local MISSING_PROTOTYPE = "CATALOG_MISSING_PROTOTYPE"
local MISSING_QUALITY = "CATALOG_MISSING_QUALITY"

local function copy_plain(value, seen)
    local value_type = type(value)
    if value_type == "userdata" then
        return Utils.id_name(value)
    end
    if value_type ~= "table" then
        if value_type == "function" then return nil end
        return value
    end

    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        local copied_key = copy_plain(key, seen)
        local copied_child = copy_plain(child, seen)
        if copied_key ~= nil and copied_child ~= nil then
            result[copied_key] = copied_child
        end
    end
    return result
end

local function copy_position(position)
    if not position then return nil end
    return {x = position.x, y = position.y}
end

local function copy_box(box)
    if not box then return nil end
    return {left_top = copy_position(box.left_top), right_bottom = copy_position(box.right_bottom)}
end

local function copy_positions(positions)
    local result = {}
    for index, position in ipairs(positions or {}) do
        result[index] = copy_position(position)
    end
    return result
end

local function name_of(value)
    if value == nil then return nil end
    if type(value) == "table" then
        return value.name or value.prototype or value.id
    end
    return Utils.id_name(value)
end

local function quality_of(value, fallback)
    local name = name_of(value)
    return name == nil and fallback or name
end

local function sorted_keys(values)
    local keys = {}
    for key, _ in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function is_array(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then return false end
    end
    return true
end

local function add_request(result, value, default_quality, key_quality)
    if value == nil then return end
    local value_type = type(value)
    if value_type == "string" or value_type == "userdata" then
        result[#result + 1] = {name = name_of(value), quality = key_quality or default_quality}
        return
    end
    if value_type ~= "table" then return end

    local direct_name = value.name or value.prototype or value.id
    if direct_name ~= nil then
        result[#result + 1] = {name = name_of(direct_name), quality = quality_of(value.quality, key_quality or default_quality)}
        return
    end
    if is_array(value) then
        for _, child in ipairs(value) do
            add_request(result, child, default_quality, key_quality)
        end
        return
    end

    for _, key in ipairs(sorted_keys(value)) do
        local child = value[key]
        if child == true then
            result[#result + 1] = {name = key, quality = key_quality or default_quality}
        elseif type(child) == "string" then
            -- A map such as {assembler = "legendary"} is a convenient compact request.
            result[#result + 1] = {name = key, quality = child}
        elseif type(child) == "table" then
            local child_name = child.name or child.prototype or child.id or key
            result[#result + 1] = {name = name_of(child_name), quality = quality_of(child.quality, key_quality or default_quality)}
        elseif child == nil then
            result[#result + 1] = {name = key, quality = key_quality or default_quality}
        end
    end
end

local function unique_requests(requests)
    local result, seen = {}, {}
    for _, request in ipairs(requests) do
        if request.name ~= nil and request.name ~= "" then
            local key = tostring(request.name) .. "\0" .. tostring(request.quality or "normal")
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = request
            end
        end
    end
    table.sort(result, function(a, b)
        if a.name == b.name then return tostring(a.quality) < tostring(b.quality) end
        return a.name < b.name
    end)
    return result
end

local function split_full_name(value, expected_type)
    if type(value) ~= "string" then return value end
    local prefix, name = value:match("^([^/]+)/(.+)$")
    if prefix == expected_type then return name end
    return value
end

local function diagnostic(diagnostics, code, subject, detail)
    diagnostics[#diagnostics + 1] = {code = code, subject = subject, detail = detail}
end

local function resolve(diagnostics, kind, name)
    local prototypes_of_kind = prototypes[kind]
    local prototype = prototypes_of_kind and prototypes_of_kind[name]
    if not prototype or (prototype.valid ~= nil and not prototype.valid) then
        diagnostic(diagnostics, MISSING_PROTOTYPE, kind .. "/" .. tostring(name),
            "prototype " .. kind .. "/" .. tostring(name) .. " no longer resolves")
        return nil
    end
    return prototype
end

local function selected_quality(name, diagnostics, quality_cache)
    name = quality_of(name, "normal")
    if quality_cache[name] ~= nil then return quality_cache[name], name end
    local prototype = prototypes.quality[name]
    if not prototype or (prototype.valid ~= nil and not prototype.valid) then
        diagnostic(diagnostics, MISSING_QUALITY, "quality/" .. tostring(name),
            "quality " .. tostring(name) .. " no longer resolves")
        quality_cache[name] = false
        return false, name
    end
    local projected = {name = prototype.name, level = prototype.level}
    quality_cache[name] = projected
    return projected, name
end

local function project_quality(catalog, quality, quality_name)
    if not catalog.quality[quality_name] then
        catalog.quality[quality_name] = quality
        catalog.quality_level[quality_name] = quality.level
    end
end

local function source_for(entity)
    return entity.electric_energy_source_prototype or entity.burner_prototype
        or entity.heat_energy_source_prototype or entity.fluid_energy_source_prototype
        or entity.void_energy_source_prototype
end

local function max_energy_per_tick(entity, quality_name, quality_valid)
    if not quality_valid then return nil end
    if quality_valid and type(entity.get_max_energy_usage) == "function" then
        return entity.get_max_energy_usage(quality_name)
    end
    return entity.energy_usage
end

local function project_fluid_boxes(entity)
    local boxes = {}
    for index, box in ipairs(entity.fluidbox_prototypes or {}) do
        local projected = {
            index = box.index,
            production_type = box.production_type,
            filter = Utils.id_name(box.filter),
            connections = {},
        }
        -- volume was removed in Factorio 2.1. The version branch is deliberate:
        -- reading an absent LuaObject member is an error in the real engine.
        if not Utils.IS_2_1 then projected.volume = box.volume end
        for connection_index, connection in ipairs(box.pipe_connections or {}) do
            local projected_connection = {
                positions = copy_positions(connection.positions),
                direction = connection.direction,
                connection_type = connection.connection_type,
                flow_direction = connection.flow_direction,
                max_underground_distance = connection.max_underground_distance,
            }
            if Utils.IS_2_1 then
                projected_connection.alt_direction = connection.alt_direction
                projected_connection.alt_position = copy_position(connection.alt_position)
            end
            projected.connections[connection_index] = projected_connection
        end
        boxes[#boxes + 1] = projected
    end
    return boxes
end

local function project_entity(catalog, diagnostics, entity, quality_name, quality_valid)
    local energy_per_tick = max_energy_per_tick(entity, quality_name, quality_valid)
    local source = source_for(entity)
    local emissions = source and source.emissions_per_joule
    local pollution = 0
    if energy_per_tick and emissions then
        pollution = energy_per_tick * (emissions.pollution or 0) * 60
    end

    local projected = {
        name = entity.name,
        etype = entity.type,
        quality = quality_name,
        tile_w = entity.tile_width,
        tile_h = entity.tile_height,
        collision_box = copy_box(entity.collision_box),
        collision_mask = copy_plain(entity.collision_mask),
        flags = copy_plain(entity.flags),
        module_slots = nil,
        crafting_speed = nil,
        energy_usage_w = energy_per_tick and energy_per_tick * 60 or nil,
        pollution_per_min = pollution,
        needs_power = source ~= nil or (energy_per_tick ~= nil and energy_per_tick > 0),
        fluid_boxes = project_fluid_boxes(entity),
        beacon = nil,
    }

    if quality_valid and (entity.type == "assembling-machine" or entity.type == "furnace"
        or entity.type == "rocket-silo" or entity.type == "mining-drill" or entity.type == "lab")
        and type(entity.get_crafting_speed) == "function" then
        projected.crafting_speed = entity.get_crafting_speed(quality_name)
    end
    if quality_valid and type(entity.get_inventory_size) == "function" then
        if entity.type == "beacon" then
            projected.module_slots = entity.get_inventory_size(defines.inventory.beacon_modules, quality_name)
        elseif entity.type == "assembling-machine" or entity.type == "furnace" or entity.type == "rocket-silo"
            or entity.type == "mining-drill" or entity.type == "lab" then
            projected.module_slots = entity.get_inventory_size(defines.inventory.crafter_modules, quality_name)
        end
    end
    if projected.module_slots == nil and quality_valid then projected.module_slots = entity.module_inventory_size end

    if entity.type == "beacon" then
        local supply
        if quality_valid and type(entity.get_supply_area_distance) == "function" then
            supply = entity.get_supply_area_distance(quality_name)
        end
        local level = quality_valid and (prototypes.quality[quality_name].level or 0) or 0
        projected.beacon = {
            supply_w = supply,
            supply_h = supply,
            distribution_effectivity = (entity.distribution_effectivity or 0)
                + (entity.distribution_effectivity_bonus_per_quality_level or 0) * level,
            profile = copy_plain(entity.profile),
            counter = entity.beacon_counter,
        }
    end
    catalog.entity[entity.name] = projected
    if entity.type == "beacon" then catalog.beacon[entity.name] = copy_plain(projected.beacon) end
    return projected
end

local function project_item(catalog, diagnostics, request, quality_name, quality_valid)
    local name = split_full_name(request.name, "item")
    local item = resolve(diagnostics, "item", name)
    if not item then return end
    local projected = {
        name = item.name,
        type = item.type,
        quality = quality_name,
        fuel_value = item.fuel_value,
        fuel_category = Utils.id_name(item.fuel_category),
        fuel_emissions_multiplier = item.fuel_emissions_multiplier,
        burnt_result = Utils.id_name(item.burnt_result),
    }
    if item.type == "module" and quality_valid and type(item.get_module_effects) == "function" then
        projected.module_effects = copy_plain(item.get_module_effects(quality_name) or {})
        projected.module = true
        catalog.module[item.name] = {
            name = item.name,
            category = item.category,
            quality = quality_name,
            effects = copy_plain(projected.module_effects),
        }
    end
    catalog.item[item.name] = projected
end

local function project_fluid(catalog, diagnostics, request, quality_name)
    local name = split_full_name(request.name, "fluid")
    local fluid = resolve(diagnostics, "fluid", name)
    if not fluid then return end
    local projected = {
        name = fluid.name,
        type = "fluid",
        quality = quality_name,
        fuel_value = fluid.fuel_value,
        emissions_multiplier = fluid.emissions_multiplier,
    }
    if Utils.IS_2_1 then projected.spent_fluid = Utils.id_name(fluid.spent_fluid) end
    catalog.fluid[fluid.name] = projected
end

local function project_entities(catalog, diagnostics, requests, quality_cache)
    for _, request in ipairs(unique_requests(requests)) do
        local entity = resolve(diagnostics, "entity", request.name)
        if entity then
            local quality, quality_name = selected_quality(request.quality, diagnostics, quality_cache)
            if quality then project_quality(catalog, quality, quality_name) end
            project_entity(catalog, diagnostics, entity, quality_name, quality ~= false)
        end
    end
end

local function family_source(options, name)
    local infrastructure = options.infrastructure
    if type(infrastructure) == "table" and infrastructure[name] ~= nil then return infrastructure[name] end
    return options[name] or options[name .. "_family"]
end

local function family_piece(descriptor, key, fallback)
    if type(descriptor) == "string" or type(descriptor) == "userdata" then
        return key == "base" and descriptor or fallback
    end
    if type(descriptor) ~= "table" then return fallback end
    return descriptor[key] or descriptor[key == "base" and "name" or key .. "_name"] or fallback
end

local function family_quality(descriptor, fallback)
    return type(descriptor) == "table" and quality_of(descriptor.quality, fallback) or fallback
end

local function add_family_requests(requests, descriptor, names)
    for _, name in ipairs(names) do
        if name then requests[#requests + 1] = {name = name, quality = family_quality(descriptor, "normal")} end
    end
end

local function build_belt(catalog, diagnostics, options, requests)
    local descriptor = family_source(options, "belt")
    if not descriptor then return end
    local base_name = family_piece(descriptor, "base", nil)
    local underground_name = family_piece(descriptor, "underground", options.underground_belt)
    local splitter_name = family_piece(descriptor, "splitter", options.splitter)
    if not base_name then base_name = family_piece(descriptor, "belt", nil) end
    local quality_name = family_quality(descriptor, options.quality or "normal")
    add_family_requests(requests, {quality = quality_name}, {base_name, underground_name, splitter_name})
    local base = base_name and resolve(diagnostics, "entity", base_name)
    local underground = underground_name and resolve(diagnostics, "entity", underground_name)
    local splitter = splitter_name and resolve(diagnostics, "entity", splitter_name)
    if not base then return end
    local quality = selected_quality(quality_name, diagnostics, catalog._quality_cache)
    local valid = quality ~= false
    if quality then project_quality(catalog, quality, quality_name) end
    local speed = base.belt_speed
    local items_per_second = speed and speed * 480 or nil
    catalog.belt = {
        belt = base.name,
        underground = underground and underground.name or nil,
        splitter = splitter and splitter.name or nil,
        quality = quality_name,
        items_per_second = items_per_second,
        lane_items_per_second = items_per_second and items_per_second / 2 or nil,
        underground_max_distance = underground and underground.max_underground_distance or nil,
    }
end

local function build_pipe(catalog, diagnostics, options, requests)
    local descriptor = family_source(options, "pipe")
    if not descriptor then return end
    local base_name = family_piece(descriptor, "base", nil)
    local underground_name = family_piece(descriptor, "underground", options.underground_pipe)
    if not base_name then base_name = family_piece(descriptor, "pipe", nil) end
    local quality_name = family_quality(descriptor, options.quality or "normal")
    add_family_requests(requests, {quality = quality_name}, {base_name, underground_name})
    local base = base_name and resolve(diagnostics, "entity", base_name)
    local underground = underground_name and resolve(diagnostics, "entity", underground_name)
    if not base then return end
    local quality = selected_quality(quality_name, diagnostics, catalog._quality_cache)
    if quality then project_quality(catalog, quality, quality_name) end
    local throughput = type(descriptor) == "table" and descriptor.throughput_per_second
    catalog.pipe = {
        pipe = base.name,
        underground = underground and underground.name or nil,
        quality = quality_name,
        underground_max_distance = underground and underground.max_underground_distance or nil,
        throughput_per_second = throughput or options.pipe_throughput_per_second or 1200,
    }
end

local function build_inserter(catalog, diagnostics, options, requests)
    local descriptor = family_source(options, "inserter")
    if not descriptor then return end
    local name = family_piece(descriptor, "base", nil)
    if not name then name = family_piece(descriptor, "inserter", nil) end
    if not name then return end
    local quality_name = family_quality(descriptor, options.quality or "normal")
    add_family_requests(requests, {quality = quality_name}, {name})
    local entity = resolve(diagnostics, "entity", name)
    if not entity then return end
    local quality = selected_quality(quality_name, diagnostics, catalog._quality_cache)
    if quality then project_quality(catalog, quality, quality_name) end
    local items_per_second = type(descriptor) == "table" and descriptor.items_per_second
    catalog.inserter = {
        name = entity.name,
        quality = quality_name,
        items_per_second = items_per_second or 4.62,
        pickup_offset = copy_position(entity.inserter_pickup_position),
        drop_offset = copy_position(entity.inserter_drop_position),
        drop_position = copy_position(entity.inserter_drop_position),
    }
end

local function build_pole(catalog, diagnostics, options, requests)
    local descriptor = family_source(options, "pole")
    if not descriptor then return end
    local name = family_piece(descriptor, "base", nil)
    if not name then name = family_piece(descriptor, "pole", nil) end
    if not name then return end
    local quality_name = family_quality(descriptor, options.quality or "normal")
    add_family_requests(requests, {quality = quality_name}, {name})
    local entity = resolve(diagnostics, "entity", name)
    if not entity then return end
    local quality = selected_quality(quality_name, diagnostics, catalog._quality_cache)
    if quality then project_quality(catalog, quality, quality_name) end
    local supply, wire
    if quality then
        if type(entity.get_supply_area_distance) == "function" then supply = entity.get_supply_area_distance(quality_name) end
        if type(entity.get_max_wire_distance) == "function" then wire = entity.get_max_wire_distance(quality_name) end
    end
    catalog.pole = {
        name = entity.name,
        quality = quality_name,
        tile_w = entity.tile_width,
        tile_h = entity.tile_height,
        supply_w = supply,
        supply_h = supply,
        wire_reach = wire,
    }
end

local function build_robo(catalog, diagnostics, options, requests)
    local descriptor = family_source(options, "robo") or family_source(options, "roboport")
    if not descriptor then return end
    local name = family_piece(descriptor, "base", nil)
    if not name then name = family_piece(descriptor, "robo", nil) end
    if not name then name = family_piece(descriptor, "roboport", nil) end
    if not name then return end
    local quality_name = family_quality(descriptor, options.quality or "normal")
    add_family_requests(requests, {quality = quality_name}, {name})
    local entity = resolve(diagnostics, "entity", name)
    if not entity then return end
    local quality = selected_quality(quality_name, diagnostics, catalog._quality_cache)
    if quality then project_quality(catalog, quality, quality_name) end
    catalog.robo = {
        name = entity.name,
        quality = quality_name,
        tile_w = entity.tile_width,
        tile_h = entity.tile_height,
        logistic_radius = entity.logistic_radius,
        construction_radius = entity.construction_radius,
        connection_distance = entity.connection_distance,
    }
end

local function all_names(collection)
    local result = {}
    for name, _ in pairs(collection or {}) do result[#result + 1] = name end
    table.sort(result)
    return result
end

local function requests_from_options(options, names, aliases, quality)
    local requests = {}
    for _, key in ipairs(aliases) do add_request(requests, options[key], quality) end
    for _, key in ipairs(names or {}) do add_request(requests, options[key], quality) end
    return requests
end

local function catalog_template()
    return {
        schema_version = Catalog.SCHEMA_VERSION,
        entity = {}, item = {}, fluid = {}, quality = {}, quality_level = {}, module = {}, beacon = {},
        belt = nil, pipe = nil, inserter = nil, pole = nil, robo = nil,
    }
end

--Builds the projection for one generation request. Returns catalog, diagnostics (a list of {code, subject, detail}).
function Catalog.build(player_index, options)
    options = options or {}
    local catalog, diagnostics = catalog_template(), {}
    local quality_cache = {}
    local default_quality = quality_of(options.quality or options.selected_quality, "normal")
    local selected, selected_name = selected_quality(default_quality, diagnostics, quality_cache)
    if selected then project_quality(catalog, selected, selected_name) end

    -- The private cache never crosses the API boundary; it is removed before returning.
    catalog._quality_cache = quality_cache
    local entity_requests = {}
    add_request(entity_requests, options.entities, default_quality)
    add_request(entity_requests, options.entity, default_quality)
    add_request(entity_requests, options.machines, default_quality)
    add_request(entity_requests, options.machine, default_quality)
    add_request(entity_requests, options.beacons, default_quality)
    add_request(entity_requests, options.beacon, default_quality)

    local item_requests = requests_from_options(options, {"item_names"}, {"items", "item"}, default_quality)
    local fluid_requests = requests_from_options(options, {"fluid_names"}, {"fluids", "fluid"}, default_quality)
    local module_requests = requests_from_options(options, {"module_names"}, {"modules", "module"}, default_quality)
    local quality_requests = requests_from_options(options, {"quality_names"}, {"qualities", "quality"}, default_quality)
    -- quality is also the selected default above; a list can add other qualities referenced by a calculation.
    for _, request in ipairs(quality_requests) do
        local quality, quality_name = selected_quality(request.name, diagnostics, quality_cache)
        if quality then project_quality(catalog, quality, quality_name) end
    end

    build_belt(catalog, diagnostics, options, entity_requests)
    build_pipe(catalog, diagnostics, options, entity_requests)
    build_inserter(catalog, diagnostics, options, entity_requests)
    build_pole(catalog, diagnostics, options, entity_requests)
    build_robo(catalog, diagnostics, options, entity_requests)

    project_entities(catalog, diagnostics, entity_requests, quality_cache)
    for _, request in ipairs(unique_requests(item_requests)) do
        local quality, quality_name = selected_quality(request.quality, diagnostics, quality_cache)
        project_item(catalog, diagnostics, request, quality_name, quality ~= false)
        if quality then project_quality(catalog, quality, quality_name) end
    end
    for _, request in ipairs(unique_requests(module_requests)) do
        local quality, quality_name = selected_quality(request.quality, diagnostics, quality_cache)
        project_item(catalog, diagnostics, request, quality_name, quality ~= false)
        if quality then project_quality(catalog, quality, quality_name) end
    end
    for _, request in ipairs(unique_requests(fluid_requests)) do
        local _, quality_name = selected_quality(request.quality, diagnostics, quality_cache)
        project_fluid(catalog, diagnostics, request, quality_name)
    end

    catalog._quality_cache = nil
    return catalog, diagnostics
end

--The subset the debug export carries: only prototypes the calculation actually referenced, never every prototype
function Catalog.for_export(player_index, referenced)
    -- Referenced is intentionally passed as the request object, not as a prototype table. Build's
    -- normalizer accepts both the calculation's grouped form and compact name maps.
    local empty = true
    for _, _ in pairs(referenced or {}) do empty = false break end
    if empty then return catalog_template(), {} end
    return Catalog.build(player_index, referenced or {})
end

return Catalog
