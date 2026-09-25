local H = require "tests.harness"
local Catalog

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " A1 vanilla inserter throughput comes from game facts", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_default_infrastructure()
        world.add_player(1)
        world.init()
        local normal = Catalog.build(1, {inserter = "inserter"})
        local fast = Catalog.build(1, {inserter = "fast-inserter"})
        local long = Catalog.build(1, {inserter = "long-handed-inserter"})
        H.equal(math.abs(normal.inserter.items_per_second - 0.83) <= 0.03, true, "yellow inserter")
        H.equal(math.abs(fast.inserter.items_per_second - 2.31) <= 0.05, true, "fast inserter")
        H.equal(math.abs(long.inserter.items_per_second - 1.15) <= 0.05, true, "long inserter")
        H.equal(type(fast.inserter.rotation_speed), "number", "rotation speed captured")
        H.equal(type(fast.inserter.extension_speed), "number", "extension speed captured")
        H.equal(fast.inserter.bulk, false, "bulk fact captured")
    end)

    H.test(shape .. " A1 stack bonuses and quality rotation affect throughput", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_default_infrastructure()
        world.inserter_stack_size_bonus = 1
        world.add_player(1)
        world.init()
        local force = game.players[1].force
        H.equal(force.inserter_stack_size_bonus, 1, "force bonus initialized")
        local fast = Catalog.build(1, {inserter = "fast-inserter"})
        H.equal(math.abs(fast.inserter.items_per_second - 4.62) <= 0.1, true, "fast stack 2 got " .. tostring(fast.inserter.items_per_second) .. " bonus " .. tostring(fast.inserter.inserter_stack_size_bonus))
        world.add_unlinked_quality("higher", 1)
        world.add_inserter({name = "quality-inserter", speeds_by_quality = {
            normal = {rotation_speed = 0.02515, extension_speed = 0.0343},
            higher = {rotation_speed = 0.1, extension_speed = 0.04}}})
        local quality = Catalog.build(1, {inserter = {base = "quality-inserter", quality = "higher"}})
        H.equal(quality.inserter.items_per_second > fast.inserter.items_per_second, true, "higher quality faster")
    end)

    H.test(shape .. " A1 bulk inserters use the bulk force capacity bonus", function()
        local world = H.new_world(shape)
        Catalog = require "logic.catalog"
        world.add_default_infrastructure()
        world.add_inserter({name = "bulk-inserter", bulk = true, rotation_speed = 0.07})
        world.bulk_inserter_capacity_bonus = 2
        world.add_player(1)
        world.init()
        local catalog = Catalog.build(1, {inserter = "bulk-inserter"})
        H.equal(math.abs(catalog.inserter.items_per_second - 12.13) <= 0.1, true, "bulk capacity bonus got " .. tostring(catalog.inserter.items_per_second))
    end)

    H.test(shape .. " A1 unavailable speed facts use the documented fallback", function()
        local world = H.new_world(shape)
        world.add_inserter({name = "unknown-speed", no_speed = true})
        world.add_player(1)
        world.init()
        local catalog, diagnostics = Catalog.build(1, {inserter = "unknown-speed"})
        H.equal(catalog.inserter.items_per_second, 4.62, "fallback throughput")
        local found = false
        for _, item in ipairs(diagnostics) do
            if item.code == "CATALOG_INSERTER_SPEED_DEFAULT" then found = true end
        end
        H.equal(found, true, "fallback diagnostic")
    end)
end

H.done("test_catalog_inserter_speed")
