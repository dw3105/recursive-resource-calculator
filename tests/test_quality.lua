--Crafting machine quality: speed and the machine button in the report
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B8 M1 a legendary machine's speed counts and its quality stays on the button", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speeds_by_quality = {normal = 1, legendary = 2.5}})
        world.add_recipe({name = "gear", category = "crafting", energy = 5, ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.gear = {name = "assembler", quality = "legendary"}

        local report = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].machines, 2 * 5 / 2.5, "legendary machines")
        H.equal(report.rows["item/gear"].machine.name, "assembler", "button machine")
        H.equal(report.rows["item/gear"].machine.quality, "legendary", "button quality")
    end)

    H.test(shape .. " B8 a machine chosen without quality uses normal speed", function()
        local world = H.new_world(shape)
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speeds_by_quality = {normal = 1, legendary = 2.5}})
        world.add_recipe({name = "gear", category = "crafting", energy = 5, ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()

        local report = H.run_sheet({{item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].machines, 2 * 5, "normal machines")
    end)
end

H.done("test_quality")
