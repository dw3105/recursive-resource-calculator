--Sheet inputs: empty sheets and the same item entered in several rows
local H = require "tests.harness"

local function gear_world(shape)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    world.add_player(1)
    world.init()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B5 a sheet with no targets clears its output", function()
        gear_world(shape)
        local report = H.run_sheet({})
        H.equal(report, nil, "report on empty sheet")
    end)

    H.test(shape .. " B13 V9 the same item in two rows is summed across time units", function()
        gear_world(shape)
        local report = H.run_sheet({{item = "gear", rate = 60, unit = "/m"}, {item = "gear", rate = 2, unit = "/s"}})
        H.near(report.rows["item/gear"].rate, 3, "gear rate")
        H.near(report.rows["item/raw"].rate, 3, "raw demand")
    end)
end

H.done("test_input")
