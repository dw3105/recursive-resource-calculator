--One code base on Factorio 2.0 and 2.1: version branch instead of member probing
local H = require "tests.harness"

H.test("IS_2_1 follows the base mod version", function()
    for _, case in ipairs({{"2.0", false}, {"2.1", true}}) do
        H.new_world(case[1])
        H.equal(require("logic.utils").IS_2_1, case[2], "IS_2_1 for shape " .. case[1])
    end
    H.new_world("2.0")
    script.active_mods.base = "2.1.0"
    H.equal(require("logic.utils").IS_2_1, true, "IS_2_1 at the 2.1.0 boundary")
end)

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " recipe_categories reads the members that exist", function()
        local world = H.new_world(shape)
        world.add_recipe({name = "r", category = "chemistry", additional_categories = {"metallurgy"}, ingredients = {}, products = {{name = "x", amount = 1}}})
        local categories = require("logic.utils").recipe_categories(prototypes.recipe.r)
        H.equal(#categories, 2, "category count")
        H.equal(categories[1], "chemistry", "primary category")
        H.equal(categories[2], "metallurgy", "additional category")
    end)

    local function gear_with_extra_category_world(machines)
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        for _, machine in ipairs(machines) do world.add_machine(machine) end
        world.add_recipe({name = "gear", category = "crafting", additional_categories = {"metallurgy"},
            ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        return world
    end

    local function find_named(element, name)
        if element.name == name then return element end
        for _, child in ipairs(element.children) do
            local found = find_named(child, name)
            if found then return found end
        end
    end

    H.test(shape .. " G2a a recipe whose only machine has its additional category is machine-crafted", function()
        gear_with_extra_category_world({{name = "foundry", categories = {"metallurgy"}, speed = 1}})
        local report = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        assert(report, "no report")
        H.equal(report.rows["item/gear"].kind, "solved", "gear row kind")
        H.near(report.rows["item/gear"].machines, 1, "machines")
        assert(report.energy_mw > 0, "energy should count the foundry, got " .. tostring(report.energy_mw))
    end)

    H.test(shape .. " G2b a machine chosen through an additional category is kept and offered", function()
        gear_with_extra_category_world({{name = "assembler", categories = {"crafting"}, speed = 1}, {name = "foundry", categories = {"metallurgy"}, speed = 2}})
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "foundry"}
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "foundry", "chosen machine after reinitialize")
        local _, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        local button = find_named(sheet_pane, "hxrrc_choose_crafting_machine_button")
        assert(button, "no machine button")
        local filtered_categories = {}
        for _, filter in ipairs(button.elem_filters) do
            H.equal(filter.filter, "crafting-category", "filter kind")
            filtered_categories[filter.crafting_category] = true
        end
        H.equal(filtered_categories.crafting, true, "primary category offered")
        H.equal(filtered_categories.metallurgy, true, "additional category offered")
        H.equal(button.enabled, true, "button enabled with two machines")
    end)

    H.test(shape .. " init, sheet and configuration change run on the strict shape", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 0.5})
        world.add_recipe({name = "gear", category = "crafting", energy = 2, ingredients = {{name = "raw", amount = 2}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "assembler", "chosen machine")
        local report = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].machines, 2 * 2 / 0.5, "machines")
        H.near(report.rows["item/raw"].rate, 4, "raw demand")
        require("logic.player_data_updater").reinitialize(1)
        H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear.name, "assembler", "machine kept after reinitialize")
    end)
end

H.test("product_probability on 2.0 reads probability", function()
    H.new_world("2.0")
    H.near(require("logic.utils").product_probability(H.product("2.0", {name = "x", amount = 1, p = 0.25})), 0.25, "probability")
end)

H.test("product_probability on 2.1 multiplies independent by the shared range", function()
    H.new_world("2.1")
    local Utils = require "logic.utils"
    H.near(Utils.product_probability(H.product("2.1", {name = "x", amount = 1, p = 0.5, shared = {min = 0.2, max = 0.6}})), 0.2, "independent x shared")
    H.near(Utils.product_probability(H.product("2.1", {name = "x", amount = 1, p = 0.5, no_shared = true})), 0.5, "V1b 2.1.7 shape without shared_probability")
end)

H.done("test_compat")
