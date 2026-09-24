--The catalog freezes requested prototypes into quality-aware plain data, including infrastructure geometry and diagnostics.
local H = require "tests.harness"

local Catalog

local function world_with_catalog_fixtures(shape, quality_fixtures)
    quality_fixtures = quality_fixtures or {}
    local world = H.new_world(shape)
    Catalog = require "logic.catalog"
    world.add_item("plate")
    world.add_fluid("water")
    world.add_module("speed-module", "speed", {speed = 0.2}, {legendary = {speed = 0.8}})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1,
        speeds_by_quality = {normal = 1, legendary = 2.5}, module_slots = 2,
        quality_affects_module_slots = true})
    world.add_beacon({name = "beacon", module_slots = 2, quality_affects_module_slots = true})
    if quality_fixtures.beacon_supply then
        local supply = quality_fixtures.beacon_supply
        prototypes.entity.beacon.quality_affects_supply_area_distance = true
        prototypes.entity.beacon.get_supply_area_distance = function(quality)
            local level = prototypes.quality[quality].level
            return supply.normal + level * supply.bonus_per_level
        end
    end
    world.add_default_infrastructure()
    if quality_fixtures.pole_wire_bonus then
        world.add_electric_pole({name = "quality-pole", supply_area = 2.5, wire_distance = 8,
            quality_affects_supply_area = true, supply_bonus_per_level = 0.25,
            wire_bonus_per_level = quality_fixtures.pole_wire_bonus})
    end
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

local function incomplete_diagnostic(diagnostics, entity_name, field)
    for _, item in ipairs(diagnostics or {}) do
        if item.code == "BP_CAP_INCOMPLETE" and item.subject == "entity/" .. entity_name
            and item.field == field then
            return item
        end
    end
    return nil
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CG1 an empty vector is REFUSED, never published as geometry", function()
        world_with_catalog_fixtures(shape)
        prototypes.entity.inserter.inserter_pickup_position = {}
        local catalog, diagnostics = Catalog.build(1, {inserter = "inserter"})
        H.equal(catalog.inserter, nil, "empty pickup offset is not published")
        H.equal(catalog.entity.inserter, nil, "the incomplete inserter entity is not published")
        local item = incomplete_diagnostic(diagnostics, "inserter", "inserter.pickup_offset")
        H.equal(item ~= nil, true, "empty pickup offset has a capture refusal")
        if item then H.equal(item.detail:find("inserter", 1, true) ~= nil, true, "diagnostic names entity") end
    end)

    H.test(shape .. " CG2 an unsupported representation is REFUSED with an entity and field diagnostic", function()
        world_with_catalog_fixtures(shape)
        prototypes.entity.inserter.inserter_pickup_position = "not-a-vector"
        local catalog, diagnostics = Catalog.build(1, {inserter = "inserter"})
        H.equal(catalog.inserter, nil, "unsupported pickup representation is not published")
        local item = incomplete_diagnostic(diagnostics, "inserter", "inserter.pickup_offset")
        H.equal(item ~= nil, true, "unsupported representation has a capture refusal")
        if item then
            H.equal(item.detail:find("inserter", 1, true) ~= nil, true, "unsupported diagnostic names entity")
            H.equal(item.detail:find("pickup_offset", 1, true) ~= nil, true, "unsupported diagnostic names field")
        end
    end)

    H.test(shape .. " CG3 a keyed vector and an array vector both normalize where the boundary supports them", function()
        local world = world_with_catalog_fixtures(shape)
        world.add_inserter({name = "array-inserter", pickup = {1.25, 2.5}, drop = {-3.5, 4.75}})
        local keyed = Catalog.build(1, {inserter = "inserter"})
        local array = Catalog.build(1, {inserter = "array-inserter"})
        H.deep_equal(keyed.inserter.pickup_offset, {x = 0, y = 1}, "keyed pickup vector")
        H.deep_equal(keyed.inserter.drop_offset, {x = 0, y = -1.203125}, "keyed drop vector")
        H.deep_equal(array.inserter.pickup_offset, {x = 1.25, y = 2.5}, "array pickup vector")
        H.deep_equal(array.inserter.drop_offset, {x = -3.5, y = 4.75}, "array drop vector")
    end)

    H.test(shape .. " CG-long captures selected long inserter geometry as plain facts", function()
        local world = world_with_catalog_fixtures(shape)
        world.add_inserter({name = "long-handed-inserter", pickup = {x = 0, y = 2}, drop = {x = 0, y = -2}})
        local catalog = Catalog.build(1, {long_inserter = "long-handed-inserter"})
        H.equal(catalog.long_inserter.name, "long-handed-inserter", "selected prototype")
        H.deep_equal(catalog.long_inserter.pickup_offset, {x = 0, y = 2}, "pickup fact")
        H.deep_equal(catalog.long_inserter.drop_offset, {x = 0, y = -2}, "drop fact")
        H.deep_equal(catalog.long_inserter.drop_position, {x = 0, y = -2}, "compatibility drop fact")
    end)

    H.test(shape .. " CG4 a complete capture still round-trips unchanged", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {inserter = "inserter", entities = {"assembler"}})
        local encoded = helpers.encode_string(helpers.table_to_json(catalog))
        local decoded = helpers.json_to_table(helpers.decode_string(encoded))
        H.deep_equal(decoded.inserter, catalog.inserter, "complete inserter geometry round trip")
        H.deep_equal(decoded.entity.assembler.fluid_boxes, catalog.entity.assembler.fluid_boxes,
            "complete fluid geometry round trip")
    end)

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

    H.test(shape .. " C3 roboport radii come from the prototype", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "custom-robo", tile_width = 6, logistic_radius = 31,
            construction_radius = 67})
        local catalog = Catalog.build(1, {quality = "legendary", robo = "custom-robo"})
        H.equal(catalog.robo.tile_w, 6, "roboport tile width")
        H.equal(catalog.robo.logistic_radius, 31, "logistic radius")
        H.equal(catalog.robo.construction_radius, 67, "construction radius")
    end)

    --LuaEntityPrototype::connection_distance is subclasses ["RollingStock"] in the pinned 2.0.77 and 2.1.19
    --runtime API, so a roboport never answers it. Reading it anyway is what left the planner deriving a
    --one-tile roboport gap on the real engine, which no test could see while the mock fabricated a value.
    --Reintroducing that read makes Catalog.build raise, and this case names it.
    H.test(shape .. " C3b the roboport catalog never reads the rolling-stock connection distance", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "gap-robo", logistic_radius = 25, construction_radius = 55})
        local ok, catalog = pcall(Catalog.build, 1, {robo = "gap-robo"})
        H.equal(ok, true, "building a roboport catalog reads no rolling-stock member: " .. tostring(catalog))
        H.equal(catalog.robo.connection_distance, nil, "no connection distance is recorded for a roboport")
        H.equal(catalog.robo.logistic_radius, 25, "the roboport keeps its logistic radius")
        H.equal(catalog.robo.construction_radius, 55, "the roboport keeps its construction radius")
    end)

    H.test(shape .. " RF1 the roboport catalog names a missing engine fact", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "missing-logistic", construction_radius = 55})
        local entity = prototypes.entity["missing-logistic"]
        entity.logistic_radius = nil
        local catalog = Catalog.build(1, {robo = "missing-logistic"})
        H.equal(type(catalog.robo.facts), "table", "roboport facts exist")
        if type(catalog.robo.facts) ~= "table" then return end
        H.equal(catalog.robo.facts.missing[1], "logistic_radius", "missing logistic radius is named")
    end)

    H.test(shape .. " RF2 connection_distance is never named as a missing roboport fact", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "compat-robo", logistic_radius = 25, construction_radius = 55})
        local catalog = Catalog.build(1, {robo = {name = "compat-robo", connection_distance = 7}})
        H.equal(type(catalog.robo.facts), "table", "roboport facts exist")
        if type(catalog.robo.facts) ~= "table" then return end
        local named = false
        for _, fact in ipairs(catalog.robo.facts.missing or {}) do
            if fact == "connection_distance" then named = true end
        end
        H.equal(named, false, "connection distance is not an engine fact")
    end)

    H.test(shape .. " RF3 a default-infrastructure roboport reports an empty facts.missing", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_default_infrastructure()
        local catalog = Catalog.build(1, {robo = "roboport"})
        H.equal(catalog.robo.logistic_radius, 25, "default logistic radius")
        H.equal(catalog.robo.construction_radius, 55, "default construction radius")
        H.equal(type(catalog.robo.facts), "table", "roboport facts exist")
        if type(catalog.robo.facts) ~= "table" then return end
        H.equal(#catalog.robo.facts.missing, 0, "default roboport has no missing engine facts")
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

    H.test(shape .. " C12 a pole's wire reach uses the selected quality", function()
        world_with_catalog_fixtures(shape, {pole_wire_bonus = 2})
        local normal = Catalog.build(1, {quality = "normal", pole = "quality-pole"})
        local legendary = Catalog.build(1, {quality = "legendary", pole = "quality-pole"})
        H.equal(normal.pole ~= nil, true, "normal pole is projected")
        H.equal(legendary.pole ~= nil, true, "legendary pole is projected")
        H.near(normal.pole.wire_reach, 8, "normal pole wire reach")
        H.near(legendary.pole.wire_reach, 18, "legendary pole wire reach")
    end)

    H.test(shape .. " C13 crafting speed uses the selected quality", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {quality = "legendary", entities = {"assembler"}})
        H.equal(catalog.entity.assembler ~= nil, true, "assembler is projected")
        H.near(catalog.entity.assembler.crafting_speed, 2.5, "legendary crafting speed")
    end)

    H.test(shape .. " C14 machine and beacon module slots use the selected quality", function()
        world_with_catalog_fixtures(shape)
        local catalog = Catalog.build(1, {quality = "legendary", entities = {"assembler", "beacon"}})
        H.equal(catalog.entity.assembler ~= nil, true, "assembler is projected")
        H.equal(catalog.entity.beacon ~= nil, true, "beacon is projected")
        H.equal(catalog.entity.assembler.module_slots, 7, "legendary machine module slots")
        H.equal(catalog.entity.beacon.module_slots, 7, "legendary beacon module slots")
    end)

    H.test(shape .. " C15 beacon supply area uses the selected quality", function()
        world_with_catalog_fixtures(shape, {beacon_supply = {normal = 10, bonus_per_level = 1.5}})
        local catalog = Catalog.build(1, {quality = "legendary", entities = {"beacon"}})
        H.equal(catalog.entity.beacon ~= nil, true, "beacon is projected")
        H.equal(catalog.entity.beacon.beacon ~= nil, true, "beacon data is projected")
        H.near(catalog.entity.beacon.beacon.supply_w, 17.5, "legendary beacon supply area")
        H.near(catalog.entity.beacon.beacon.supply_h, 17.5, "legendary beacon supply area height")
    end)

    H.test(shape .. " C16 selected quality retains all roboport prototype radii", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_roboport({name = "quality-robo", tile_width = 6, logistic_radius = 31,
            construction_radius = 67})
        local normal = Catalog.build(1, {quality = "normal", robo = "quality-robo"})
        local legendary = Catalog.build(1, {quality = "legendary", robo = "quality-robo"})
        H.equal(normal.robo ~= nil, true, "normal roboport is projected")
        H.equal(legendary.robo ~= nil, true, "legendary roboport is projected")
        H.equal(normal.robo.quality, "normal", "normal roboport quality")
        H.equal(legendary.robo.quality, "legendary", "legendary roboport quality")
        H.deep_equal({normal.robo.logistic_radius, normal.robo.construction_radius},
            {31, 67}, "normal roboport radii")
        H.deep_equal({legendary.robo.logistic_radius, legendary.robo.construction_radius},
            {31, 67}, "legendary roboport radii")
    end)
end

H.done("test_catalog")
