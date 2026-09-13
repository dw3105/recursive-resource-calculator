--Productivity bonuses from machine, research and modules
local H = require "tests.harness"

--Gear recipe on a machine with the given base productivity; module and research bonuses applied through the player's data
local function gear_world(shape, spec)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "foundry", categories = {"crafting"}, speed = 1, base_productivity = spec.base})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}},
        maximum_productivity = spec.maximum})
    if spec.module then world.add_module("bonus-module", "productivity", {productivity = spec.module}) end
    world.add_player(1, {gear = spec.research})
    world.init()
    if spec.module then storage[1].module_setups_by_recipe_name.gear.modules = {{name = "bonus-module"}} end
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B7 machine, research and module productivity are added", function()
        gear_world(shape, {base = 0.5, research = 0.2, module = 0.1})
        local report = H.run_sheet({{item = "gear", rate = 9, unit = "/s"}})
        H.near(report.rows["item/raw"].rate, 9 / 1.8, "raw demand at +80%")
        H.near(report.rows["item/gear"].machines, 9 / 1.8, "machines at +80%")
    end)

    H.test(shape .. " B7 total productivity is capped at the recipe maximum", function()
        gear_world(shape, {base = 0.5, research = 3, module = 1, maximum = 3})
        local report = H.run_sheet({{item = "gear", rate = 8, unit = "/s"}})
        H.near(report.rows["item/raw"].rate, 8 / 4, "raw demand at the +300% cap")
    end)
end

H.done("test_productivity")
