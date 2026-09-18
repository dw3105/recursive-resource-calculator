--The catalog freezes requested prototypes into quality-aware plain data, including infrastructure geometry and diagnostics.
local H = require "tests.harness"

local Catalog

local function world_with_catalog_fixtures(shape)
    local world = H.new_world(shape)
    Catalog = require "logic.catalog"
    world.add_item("plate")
    world.add_fluid("water")
    world.add_module("speed-module", "speed", {speed = 0.2}, {legendary = {speed = 0.8}})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1,
        speeds_by_quality = {normal = 1, legendary = 2.5}, module_slots = 2,
        quality_affects_module_slots = true})
    world.add_beacon({name = "beacon", module_slots = 2, quality_affects_module_slots = true})
    world.add_default_infrastructure()
    world.set_fluid_boxes("assembler", {
        world.fluid_box({connections = {
            {offset = {x = 0, y = -1}, direction = defines.direction.north},
            {offset = {x = 1, y = 0}, direction = defines.direction.east},
        }}),
    })
    world.add_player(1)
    world.init()
    return world
end

local function collision_width(box)
    return box.right_bottom.x - box.left_top.x
end

local function walk_plain(value, seen, path)
    H.equal(type(value) ~= "userdata", true, "catalog has no LuaObject at " .. path)
    H.equal(type(value) ~= "function", true, "catalog has no function at " .. path)
    if type(value) ~= "table" then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        walk_plain(key, seen, path .. ".<key>")
        walk_plain(child, seen, path .. "." .. tostring(key))
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " C1 tile footprint and exact collision box are separate geometry models", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {entities = {"splitter"}})
        local splitter = catalog.entity.splitter
        H.equal(splitter.tile_w, 2, "splitter tile footprint width")
        H.equal(splitter.tile_h, 1, "splitter tile footprint height")
        H.near(collision_width(splitter.collision_box), 1.9, "splitter exact collision width")
        H.equal(splitter.tile_w ~= collision_width(splitter.collision_box), true, "packing and physical widths differ")
        H.deep_equal(splitter.collision_mask, {layers = {object = true, player = true, water_tile = true}}, "collision mask is copied")
    end)

    H.test(shape .. " C2 quality accessors supply the selected pole reach", function()
        world_with_catalog_fixtures(shape)
        local normal = Catalog.build(1, {quality = "normal", pole = "medium-electric-pole"})
        local legendary = Catalog.build(1, {quality = "legendary", pole = "medium-electric-pole"})
        H.near(normal.pole.supply_w, 3.5, "normal supply area")
        H.near(legendary.pole.supply_w, 6, "legendary supply area")
        H.near(normal.pole.wire_reach, 9, "normal wire reach")
        H.near(legendary.pole.wire_reach, 9, "legendary wire reach")
        H.equal(normal.pole.supply_w ~= legendary.pole.supply_w, true, "quality changes supply area")
    end)

    H.test(shape .. " C3 roboport radii and connection distance come from the prototype", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "custom-robo", tile_width = 6, logistic_radius = 31,
            construction_radius = 67, connection_distance = 43})
        local catalog = Catalog.build(1, {quality = "legendary", robo = "custom-robo"})
        H.equal(catalog.robo.tile_w, 6, "roboport tile width")
        H.equal(catalog.robo.logistic_radius, 31, "logistic radius")
        H.equal(catalog.robo.construction_radius, 67, "construction radius")
        H.equal(catalog.robo.connection_distance, 43, "connection distance")
    end)

    H.test(shape .. " C4 belt speed becomes total and per-lane item throughput", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {belt = {belt = "transport-belt", underground = "underground-belt", splitter = "splitter"}})
        H.near(catalog.belt.items_per_second, 15, "belt throughput")
        H.near(catalog.belt.lane_items_per_second, 7.5, "lane throughput")
    end)

    H.test(shape .. " C5 underground belt and pipe-to-ground retain their own range", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {
            belt = {belt = "transport-belt", underground = "underground-belt", splitter = "splitter"},
            pipe = {pipe = "pipe", underground = "pipe-to-ground"},
        })
        H.equal(catalog.belt.underground_max_distance, 5, "underground belt range")
        H.equal(catalog.pipe.underground_max_distance, 10, "pipe-to-ground range")
        local connections = catalog.entity["pipe-to-ground"].fluid_boxes[1].connections
        H.equal(connections[1].connection_type, "normal", "exposed connection is normal")
        H.equal(connections[1].direction, defines.direction.north, "exposed connection faces north")
        H.equal(connections[2].connection_type, "underground", "buried connection is underground")
        H.equal(connections[2].direction, defines.direction.south, "buried connection faces away from exposed connection")
        H.equal(connections[2].max_underground_distance, 10, "connection range is carried on its own connection")
    end)

    H.test(shape .. " C6 fluid connections retain four cardinal runtime positions", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {entities = {"assembler"}})
        local connections = catalog.entity.assembler.fluid_boxes[1].connections
        H.equal(#connections, 2, "two fluid connections")
        for index, connection in ipairs(connections) do
            H.equal(#connection.positions, 4, "connection " .. index .. " has four positions")
            H.equal(connection.positions[1].x ~= nil and connection.positions[1].y ~= nil, true,
                "connection " .. index .. " position is plain data")
        end
    end)

    H.test(shape .. " C7 version-specific fluid box fields do not crash the projection", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {entities = {"assembler"}})
        local box = catalog.entity.assembler.fluid_boxes[1]
        if shape == "2.0" then
            H.equal(box.volume, 100, "2.0 fluid box volume")
        else
            H.equal(box.volume, nil, "2.1 fluid box has no volume")
        end
    end)

    H.test(shape .. " C8 module slots, crafting speed and module effects use the selected quality", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {quality = "legendary", entities = {"assembler"}, modules = {"speed-module"}})
        H.equal(catalog.entity.assembler.module_slots, 7, "quality-aware module slots")
        H.near(catalog.entity.assembler.crafting_speed, 2.5, "quality-aware crafting speed")
        H.near(catalog.module["speed-module"].effects.speed, 0.8, "quality-aware module effect")
    end)

    H.test(shape .. " C9 a missing prototype is a diagnostic and not a crash", function()
        world_with_catalog_fixtures(shape)
        local catalog, diagnostics = Catalog.build(1, {entities = {"removed-machine"}})
        H.equal(catalog.entity["removed-machine"], nil, "missing entity is not guessed")
        H.equal(#diagnostics, 1, "one missing-prototype diagnostic")
        H.equal(diagnostics[1].code, "CATALOG_MISSING_PROTOTYPE", "diagnostic code")
        H.equal(diagnostics[1].subject, "entity/removed-machine", "diagnostic subject")
        H.equal(type(diagnostics[1].detail), "string", "diagnostic detail")
    end)

    H.test(shape .. " C10 export contains only referenced dependencies", function()
        world_with_catalog_fixtures(shape)
        local export = Catalog.for_export(1, {quality = "legendary", entities = {"splitter"}})
        H.equal(export.entity.splitter ~= nil, true, "referenced entity is exported")
        H.equal(export.entity.assembler, nil, "unreferenced machine is omitted")
        H.equal(export.entity["transport-belt"], nil, "unreferenced infrastructure is omitted")
        H.equal(export.item.plate, nil, "unreferenced item is omitted")
    end)

    H.test(shape .. " C11 the complete catalog is engine-object free", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {
            quality = "legendary", entities = {"assembler", "beacon"}, items = {"plate"},
            modules = {"speed-module"}, fluids = {"water"},
            belt = {belt = "transport-belt", underground = "underground-belt", splitter = "splitter"},
            pipe = {pipe = "pipe", underground = "pipe-to-ground"}, inserter = "inserter",
            pole = "medium-electric-pole", robo = "roboport",
        })
        walk_plain(catalog, nil, "catalog")
    end)
end

H.done("test_catalog")
