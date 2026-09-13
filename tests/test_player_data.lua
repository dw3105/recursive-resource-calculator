--Player data kept across configuration changes
local H = require "tests.harness"

local EFFECTS = {"consumption", "speed", "productivity", "pollution", "quality"}

local GEAR = {name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}}

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

--Stored machine modules as "name@quality" in slot order, or nil when the recipe has no setup
local function stored(recipe_name)
    local setup = storage[1].module_setups_by_recipe_name[recipe_name]
    if not setup then return nil end
    local names = {}
    for _, module in ipairs(setup.modules) do
        names[#names + 1] = module.name .. (module.quality and ("@" .. module.quality) or "")
    end
    return table.concat(names, ",")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B2 modules from a removed mod are dropped and effects recomputed from the rest", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe(GEAR)
        world.add_module("gone-speed", "speed", {speed = 0.5, consumption = 0.7})
        world.add_module("kept-productivity", "productivity", {productivity = 0.1, speed = -0.05, consumption = 0.4})
        world.add_module("gone-efficiency", "efficiency", {consumption = -0.3})
        world.add_player(1)
        world.init()
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "gone-speed"}, {name = "kept-productivity"}, {name = "gone-efficiency"}, {name = "kept-productivity"}}

        world.remove_module("gone-speed")
        world.remove_module("gone-efficiency")
        reconfigure()

        H.equal(stored("gear"), "kept-productivity,kept-productivity", "remaining modules in order")
        local expected = {consumption = 2 * 0.4, speed = -2 * 0.05, productivity = 2 * 0.1, pollution = 0, quality = 0}
        local effects = require("logic.utils").recipe_effects(1, "gear")
        for _, effect in ipairs(EFFECTS) do
            H.near(effects[effect], expected[effect], effect .. " effect")
        end
    end)

    H.test(shape .. " B2 preferences without removed modules are left untouched", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe(GEAR)
        world.add_module("kept-productivity", "productivity", {productivity = 0.1})
        world.add_player(1)
        world.init()
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "kept-productivity", quality = "rare"}, {name = "kept-productivity"}}

        reconfigure()

        H.equal(stored("gear"), "kept-productivity@rare,kept-productivity", "modules")
        H.near(require("logic.utils").recipe_effects(1, "gear").productivity, 0.2, "productivity effect")
    end)

    local function swap_world()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "swapped", categories = {"crafting"}, speed = 2})
        world.add_recipe(GEAR)
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

    --Gear on a 4-slot assembler with control.lua loaded; machine_spec and recipe_spec fields override the defaults
    local function control_world(machine_spec, recipe_spec)
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_item("hand-made")
        world.add_module("speed-module", "speed", {speed = 0.2, consumption = 0.5})
        world.add_module("productivity-module", "productivity", {productivity = 0.1, speed = -0.05, consumption = 0.4})
        world.add_module("efficiency-module", "efficiency", {consumption = -0.3})
        world.add_module("gone-module", "speed", {speed = 1})
        local machine = {name = "assembler", categories = {"crafting"}, speed = 1}
        for key, value in pairs(machine_spec or {}) do machine[key] = value end
        world.add_machine(machine)
        local recipe = {}
        for key, value in pairs(GEAR) do recipe[key] = value end
        for key, value in pairs(recipe_spec or {}) do recipe[key] = value end
        world.add_recipe(recipe)
        world.add_recipe({name = "hand-made", category = "handcraft", ingredients = {{name = "raw", amount = 1}}, products = {{name = "hand-made", amount = 1}}})
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()
        return world
    end

    --Turns the player's module data into what 1.1.14 saved for gear: names at positive indexes, counts at negative ones, summed effects, no setups
    local function old_save(modules)
        local preferences = {effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0, quality = 0}}
        for index, module in ipairs(modules) do
            preferences[index], preferences[-index] = module[1], module[2]
            for effect, value in pairs(prototypes.item[module[1]].module_effects) do
                preferences.effects[effect] = preferences.effects[effect] + module[2] * value
            end
        end
        storage[1].module_preferences_by_recipe_name = {gear = preferences}
        storage[1].module_setups_by_recipe_name = nil
    end

    H.test(shape .. " U1 an old save's module counts become whole slots in stored order", function()
        local world = control_world({allowed_module_categories = {"speed", "productivity"}})
        old_save({{"speed-module", 2.5}, {"efficiency-module", 1}, {"gone-module", 1}, {"productivity-module", 3}})
        world.remove_module("gone-module")
        world.handlers.on_configuration_changed({mod_changes = {}})

        local report = H.run_sheet({{item = "gear", rate = 10, unit = "/s"}})
        --two speed modules and two productivity modules: speed +40% -10% = +30%, productivity +20%
        H.near(report.rows["item/gear"].machines, 10 / 1.2 / 1.3, "machines")
        H.equal(stored("gear"), "speed-module,speed-module,productivity-module,productivity-module", "slots")
        H.equal(storage[1].module_preferences_by_recipe_name, nil, "old module data removed")
    end)

    H.test(shape .. " U2 a second configuration change does not convert old module data again", function()
        local world = control_world()
        old_save({{"speed-module", 1}})
        world.handlers.on_configuration_changed({mod_changes = {}})
        world.handlers.on_configuration_changed({mod_changes = {}})
        H.equal(stored("gear"), "speed-module", "slots after two configuration changes")
    end)

    H.test(shape .. " U3 a hand-crafted recipe keeps an empty setup and a removed recipe's setup goes", function()
        local world = control_world()
        storage[1].module_setups_by_recipe_name["hand-made"].modules = {{name = "speed-module"}}
        world.remove_recipe("gear")
        reconfigure()
        H.equal(stored("hand-made"), "", "hand-crafted recipe")
        H.equal(stored("gear"), nil, "removed recipe")
    end)

    H.test(shape .. " U4 old counts convert to whole modules within the machine's slots", function()
        for _, case in ipairs({
            {module = "speed-module", count = 0.9, slots = ""},
            {module = "speed-module", count = 0, slots = ""},
            {module = "speed-module", count = -1, slots = ""},
            {module = "speed-module", count = 1e9, slots = "speed-module,speed-module,speed-module,speed-module"},
            {module = "efficiency-module", count = 1e9, slots = ""},
        }) do
            control_world({allowed_module_categories = {"speed", "productivity"}})
            old_save({{case.module, case.count}})
            reconfigure()
            H.equal(stored("gear"), case.slots, case.module .. " x " .. tostring(case.count))
        end
    end)

    H.test(shape .. " U5 a slot module whose quality was removed stays at normal quality", function()
        local world = control_world()
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module", quality = "rare"}}
        world.remove_quality("rare")
        reconfigure()
        H.equal(stored("gear"), "speed-module", "module kept without quality")
    end)

    H.test(shape .. " U6 slot modules raising an effect the recipe disallows are dropped", function()
        control_world(nil, {allowed_effects = {"consumption", "speed", "pollution", "quality"}})
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "productivity-module"}, {name = "speed-module"}}
        reconfigure()
        H.equal(stored("gear"), "speed-module", "kept modules")
    end)

    H.test(shape .. " G5d a slot module turned into a plain item by a mod is dropped without reading it", function()
        local world = control_world()
        storage[1].module_setups_by_recipe_name.gear.modules = {{name = "speed-module"}, {name = "productivity-module"}}
        world.replace_module_with_item("speed-module")
        reconfigure()
        H.equal(stored("gear"), "productivity-module", "remaining modules")
    end)
end

H.done("test_player_data")
