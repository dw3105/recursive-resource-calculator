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

--One recipe makes a fluid, another eats it to make the target item
local function fluid_chain_world(shape, made, eaten)
    local world = H.new_world(shape)
    world.add_item("target")
    world.add_fluid("bulk")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "target", category = "crafting", ingredients = {{type = "fluid", name = "bulk", amount = eaten}}, products = {{name = "target", amount = 1}}})
    world.add_recipe({name = "bulk", category = "crafting", ingredients = {}, products = {{type = "fluid", name = "bulk", amount = made}}})
    world.add_player(1)
    world.init()
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " F1a a recipe making and eating 1e9 of a fluid is solvable", function()
        local world = fluid_chain_world(shape, 1e9, 1e9)
        local report = report_or_fail(H.run_sheet({{item = "target", rate = 1, unit = "/s"}}), world)
        H.near(report.rows["item/target"].machines, 1, "target crafts")
        H.near(report.rows["fluid/bulk"].machines, 1, "bulk crafts")
    end)

    H.test(shape .. " F1b the fluid's unit scale does not change solvability", function()
        for _, amount in ipairs({1e-3, 1e3}) do
            local world = fluid_chain_world(shape, amount, amount)
            local report = report_or_fail(H.run_sheet({{item = "target", rate = 1, unit = "/s"}}), world)
            H.near(report.rows["item/target"].machines, 1, "target crafts at amount " .. amount)
            H.near(report.rows["fluid/bulk"].machines, 1, "bulk crafts at amount " .. amount)
        end
    end)

    H.test(shape .. " F1c a near-singular system is rejected, not solved from rounding noise", function()
        local world = H.new_world(shape)
        world.add_item("p")
        world.add_item("q")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "low", category = "crafting", ingredients = {},
            products = {{name = "p", amount = 1, p = 0.1}, {name = "q", amount = 1, p = 0.3}}})
        world.add_recipe({name = "high", category = "crafting", ingredients = {},
            products = {{name = "p", amount = 1, p = 0.3}, {name = "q", amount = 1, p = 0.9}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "low")
        world.bind("item/q", "high")
        local report = H.run_sheet({{item = "p", rate = 1, unit = "/s"}, {item = "q", rate = 3, unit = "/s"}})
        H.equal(report, nil, "report")
        H.equal(world.flying_texts[1] and world.flying_texts[1][1], "hxrrc.system_with_no_solution_error", "flying text")
    end)

    H.test(shape .. " F1e a small yield eaten a billion times over is solvable", function()
        local world = fluid_chain_world(shape, 1, 1e9)
        local report = report_or_fail(H.run_sheet({{item = "target", rate = 1, unit = "/s"}}), world)
        H.near(report.rows["item/target"].machines, 1, "target crafts")
        H.near_relative(report.rows["fluid/bulk"].machines, 1e9, "bulk crafts")
    end)

    H.test(shape .. " F1f a product with probability 1e-5 eaten 65535 per craft is solvable", function()
        local world = H.new_world(shape)
        world.add_item("trace")
        world.add_item("target")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "trace", category = "crafting", ingredients = {}, products = {{name = "trace", amount = 1, p = 1e-5}}})
        world.add_recipe({name = "target", category = "crafting", ingredients = {{name = "trace", amount = 65535}}, products = {{name = "target", amount = 1}}})
        world.add_player(1)
        world.init()
        local report = report_or_fail(H.run_sheet({{item = "target", rate = 1, unit = "/s"}}), world)
        H.near(report.rows["item/target"].machines, 1, "target crafts")
        H.near_relative(report.rows["item/trace"].machines, 65535 / 1e-5, "trace crafts")
    end)

    H.test(shape .. " F1g a small but meaningful off-diagonal coefficient is kept", function()
        local e = 2 ^ -15
        local world = H.new_world(shape)
        for _, item in ipairs({"p", "q", "r"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "r1", category = "crafting", ingredients = {}, products = {{name = "p", amount = 1}, {name = "q", amount = 1}}})
        world.add_recipe({name = "r2", category = "crafting", ingredients = {}, products = {{name = "q", amount = 1, p = e}}})
        world.add_recipe({name = "r3", category = "crafting", ingredients = {}, products = {
            {name = "p", amount = 65535}, {name = "p", amount = 1},
            {name = "q", amount = 65535}, {name = "q", amount = 1}, {name = "q", amount = 1, p = e},
            {name = "r", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "r1")
        world.bind("item/q", "r2")
        world.bind("item/r", "r3")
        local report = report_or_fail(H.run_sheet({{item = "p", rate = 65537, unit = "/s"}, {item = "q", rate = 65537 + 2 * e, unit = "/s"}, {item = "r", rate = 1, unit = "/s"}}), world)
        H.near(report.rows["item/p"].machines, 1, "r1 crafts")
        H.near(report.rows["item/q"].machines, 1, "r2 crafts")
        H.near(report.rows["item/r"].machines, 1, "r3 crafts")
    end)
end

--Matrices for the solver hook: line i holds product i's coefficients per recipe column, column N+1 the demand
local function gauss(rows)
    H.new_world("2.0")
    local A = {}
    for i, row in ipairs(rows) do
        A[i] = {}
        for column, value in ipairs(row) do
            if value ~= 0 or column == #row then A[i][column] = value end
        end
    end
    return require("logic.solver")._gauss_solve(A)
end

H.test("F1h the review 6 matrix solves to 1 in every row and column order", function()
    local e = 2 ^ -15
    local matrix = {{1, 0, 65536, 65537}, {1, e, 65536 + e, 65537 + 2 * e}, {0, 0, 1, 1}}
    for _, order in ipairs({{1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1}}) do
        local permuted = {}
        for new_line, old_line in ipairs(order) do
            permuted[new_line] = {}
            for new_column, old_column in ipairs(order) do permuted[new_line][new_column] = matrix[old_line][old_column] end
            permuted[new_line][4] = matrix[old_line][4]
        end
        local solution = gauss(permuted)
        assert(solution, "order " .. table.concat(order) .. " rejected")
        for i = 1, 3 do H.near(solution[i], 1, "order " .. table.concat(order) .. " rate " .. i) end
    end
end)

H.test("F1i noise reaching a pivot through two elimination steps is rejected", function()
    H.equal(gauss({{0.1, 0.3, 1, 1.4}, {0.3, 1, -1, 0.3}, {0.4, 1.3, 0, 1.7}}), nil, "solution of a singular system")
end)

H.done("test_solver")
