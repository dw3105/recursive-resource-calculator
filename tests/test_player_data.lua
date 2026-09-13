--Player data kept across configuration changes
local H = require "tests.harness"

local EFFECTS = {"consumption", "speed", "productivity", "pollution", "quality"}

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B2 modules from a removed mod are dropped and effects recomputed from the rest", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_module("gone-speed", "speed", {speed = 0.5, consumption = 0.7})
        world.add_module("kept-productivity", "productivity", {productivity = 0.1, speed = -0.05, consumption = 0.4})
        world.add_module("gone-efficiency", "efficiency", {consumption = -0.3})
        world.add_player(1)
        world.init()

        --what ModuleGUI stores: module names at positive indexes, counts at the matching negative indexes, summed effects
        local preferences = storage[1].module_preferences_by_recipe_name.gear
        preferences[1], preferences[-1] = "gone-speed", 2
        preferences[2], preferences[-2] = "kept-productivity", 3
        preferences[3], preferences[-3] = "gone-efficiency", 1
        preferences.effects = {consumption = 2 * 0.7 + 3 * 0.4 - 0.3, speed = 2 * 0.5 - 3 * 0.05, productivity = 3 * 0.1, pollution = 0, quality = 0}

        world.remove_module("gone-speed")
        world.remove_module("gone-efficiency")
        require("logic.player_data_updater").reinitialize(1)

        preferences = storage[1].module_preferences_by_recipe_name.gear
        H.equal(preferences[1], "kept-productivity", "remaining module")
        H.equal(preferences[-1], 3, "remaining module count")
        H.equal(preferences[2], nil, "no second module")
        H.equal(preferences[-2], nil, "no second count")
        H.equal(preferences[3], nil, "no third module")
        local expected = {consumption = 3 * 0.4, speed = -3 * 0.05, productivity = 3 * 0.1, pollution = 0, quality = 0}
        for _, effect in ipairs(EFFECTS) do
            H.near(preferences.effects[effect], expected[effect], effect .. " effect")
        end
    end)

    H.test(shape .. " B2 preferences without removed modules are left untouched", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_module("kept-productivity", "productivity", {productivity = 0.1})
        world.add_player(1)
        world.init()
        local preferences = storage[1].module_preferences_by_recipe_name.gear
        preferences[1], preferences[-1] = "kept-productivity", 4
        preferences.effects.productivity = 0.4

        require("logic.player_data_updater").reinitialize(1)

        H.equal(preferences[1], "kept-productivity", "module")
        H.equal(preferences[-1], 4, "count")
        H.near(preferences.effects.productivity, 0.4, "productivity effect")
    end)

    local function swap_world()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "swapped", categories = {"crafting"}, speed = 2})
        world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "swapped"}
        return world
    end

    H.test(shape .. " G5a a chosen machine turned into another entity type by a mod is replaced without reading it", function()
        local world = swap_world()
        world.replace_machine_with_entity("swapped", "container")
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "assembler", "fallback machine")
    end)

    H.test(shape .. " G5b a chosen machine removed by a mod falls back to an available one", function()
        local world = swap_world()
        world.remove_machine("swapped")
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "assembler", "fallback machine")
    end)
end

H.done("test_player_data")
