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
    H.test(shape .. " recipe_category reads the member that exists", function()
        local world = H.new_world(shape)
        world.add_recipe({name = "r", category = "chemistry", ingredients = {}, products = {{name = "x", amount = 1}}})
        H.equal(require("logic.utils").recipe_category(prototypes.recipe.r), "chemistry", "category")
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
