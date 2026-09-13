--Gaussian elimination on systems with small but valid coefficients
local H = require "tests.harness"

local function report_or_fail(report, world)
    if report then return report end
    local texts = {}
    for _, text in ipairs(world.flying_texts) do texts[#texts + 1] = type(text) == "table" and text[1] or tostring(text) end
    error("no report; flying texts: " .. table.concat(texts, ", "), 2)
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B3 small off-diagonal coefficients are eliminated, not left behind", function()
        local world = H.new_world(shape)
        world.add_item("p")
        world.add_item("q")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "p-maker", category = "crafting", ingredients = {},
            products = {{name = "p", amount = 1}, {name = "q", amount = 1, p = 0.0005}}})
        world.add_recipe({name = "q-maker", category = "crafting", ingredients = {},
            products = {{name = "q", amount = 1}, {name = "p", amount = 1, p = 0.0005}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "p-maker")
        world.bind("item/q", "q-maker")
        local report = report_or_fail(H.run_sheet({{item = "p", rate = 1, unit = "/s"}, {item = "q", rate = 1, unit = "/s"}}), world)
        local crafts = 1 / 1.0005
        H.near(report.rows["item/p"].machines, crafts, "p-maker machines")
        H.near(report.rows["item/q"].machines, crafts, "q-maker machines")
    end)

    H.test(shape .. " B3 a recipe giving a small amount of its own product is solvable", function()
        local world = H.new_world(shape)
        world.add_item("rare")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "rare", category = "crafting", ingredients = {}, products = {{name = "rare", amount = 1, p = 0.0005}}})
        world.add_player(1)
        world.init()
        local report = report_or_fail(H.run_sheet({{item = "rare", rate = 0.03, unit = "/m"}}), world)
        H.near(report.rows["item/rare"].machines, 1, "machines at 1 craft/s")
    end)
end

H.done("test_solver")
