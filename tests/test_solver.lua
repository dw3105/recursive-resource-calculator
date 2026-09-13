--Gaussian elimination on systems with small but valid coefficients, rows needing a swap, and orders that disagree
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

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " G3a recipes whose own product nets zero are solved by reordering rows", function()
        local world = H.new_world(shape)
        world.add_item("p")
        world.add_item("q")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "p-loop", category = "crafting", ingredients = {{name = "p", amount = 1}}, products = {{name = "p", amount = 1}, {name = "q", amount = 1}}})
        world.add_recipe({name = "q-loop", category = "crafting", ingredients = {{name = "q", amount = 1}}, products = {{name = "q", amount = 1}, {name = "p", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "p-loop")
        world.bind("item/q", "q-loop")
        local report = report_or_fail(H.run_sheet({{item = "p", rate = 1, unit = "/s"}, {item = "q", rate = 2, unit = "/s"}}), world)
        H.near(report.rows["item/p"].machines, 2, "p-loop crafts")
        H.near(report.rows["item/q"].machines, 1, "q-loop crafts")
    end)

    --Guard: which row order pairs() produces varies per process, and some orders already solve this at 08ee516
    H.test(shape .. " G3f a tiny probability next to a huge amount solves in whatever order the recipes come", function()
        local e, B = 1e-8, 1e9
        local world = H.new_world(shape)
        for _, item in ipairs({"p", "q", "r"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "r1", category = "crafting", ingredients = {{name = "p", amount = 1}},
            products = {{name = "p", amount = 1}, {name = "q", amount = 1, p = e}, {name = "r", amount = 1}}})
        world.add_recipe({name = "r2", category = "crafting", ingredients = {}, products = {{name = "p", amount = 1}, {name = "q", amount = B}, {name = "r", amount = 1}}})
        world.add_recipe({name = "r3", category = "crafting", ingredients = {}, products = {{name = "p", amount = 1}, {name = "r", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/p", "r1")
        world.bind("item/q", "r2")
        world.bind("item/r", "r3")
        local report = report_or_fail(H.run_sheet({{item = "p", rate = 2, unit = "/s"}, {item = "q", rate = B + e, unit = "/s"}, {item = "r", rate = 3, unit = "/s"}}), world)
        H.near(report.rows["item/p"].machines, 1, "r1 crafts")
        H.near(report.rows["item/q"].machines, 1, "r2 crafts")
        H.near(report.rows["item/r"].machines, 1, "r3 crafts")
    end)
end

local ORDERS = {{1, 2, 3}, {1, 3, 2}, {2, 1, 3}, {2, 3, 1}, {3, 1, 2}, {3, 2, 1}}

local function solver()
    H.new_world("2.0")
    return require("logic.solver")
end

--Rows hold coefficients then the demand; zero coefficients are left out as prepare_matrix does
local function matrix(rows)
    local A = {}
    for i, row in ipairs(rows) do
        A[i] = {}
        for column, value in ipairs(row) do
            if value ~= 0 or column == #row then A[i][column] = value end
        end
    end
    return A
end

--Appends each row's demand for the given answer (all 1 by default), summed left to right
local function with_demands(rows, answer)
    local result = {}
    for i, row in ipairs(rows) do
        result[i] = {}
        local demand = 0
        for column, value in ipairs(row) do
            result[i][column] = value
            demand = demand + value * (answer and answer[column] or 1)
        end
        result[i][#row + 1] = demand
    end
    return result
end

--Same permutation of lines and recipe columns, as a different pairs() order would produce
local function symmetric(rows, order)
    local permuted = {}
    for new_line, old_line in ipairs(order) do
        permuted[new_line] = {}
        for new_column, old_column in ipairs(order) do permuted[new_line][new_column] = rows[old_line][old_column] end
        permuted[new_line][#order + 1] = rows[old_line][#order + 1]
    end
    return permuted
end

local function assert_all_one(solution, what)
    assert(solution, what .. " rejected")
    for i, value in ipairs(solution) do H.near(value, 1, what .. " rate " .. i) end
end

local function assert_same_bits(actual, expected, what)
    assert(actual and expected, what .. ": missing solution")
    H.equal(#actual, #expected, what .. " size")
    for i = 1, #expected do
        H.equal(actual[i], expected[i], what .. " rate " .. i .. string.format(" (%.17g vs %.17g)", actual[i], expected[i]))
    end
end

local FOUR = with_demands({{0.1, 0.3, 1, 0}, {0.3, 0.9, 0, 1}, {0.4, 1.2, 1, 0}, {1, 1, 0, 0}})

local function review_1_matrix(e, B)
    return {{0, 1, 1, 2}, {e, B, 0, B + e}, {1, 1, 1, 3}}
end

H.test("G3b rows are swapped when stuck, and overflowing candidates are rejected", function()
    local Solver = solver()
    assert_all_one(Solver._gauss_solve(matrix({{0, 1, 1}, {1, 0, 1}})), "zero diagonal")
    assert_all_one(Solver._gauss_solve(matrix(FOUR)), "4x4 order 1234")
    H.equal(Solver._worst_residual({{1, 1}}, {math.huge}), nil, "infinite candidate")
    H.equal(Solver._worst_residual({{1e308, 1e308}}, {2}), nil, "candidate whose product overflows")
    H.equal(Solver._worst_residual({{1e308, 1e308}}, {1}), 0, "exact candidate")
end)

H.test("G3c a stuck pivot takes the row that went through the least cancellation", function()
    local Solver = solver()
    assert_all_one((Solver._solve_once(matrix({FOUR[1], FOUR[3], FOUR[2], FOUR[4]}), "today")), "4x4 order 1324")
end)

H.test("G3d equally untouched candidates prefer the larger pivot", function()
    local Solver = solver()
    assert_all_one((Solver._solve_once(matrix(review_1_matrix(1e-8, 1e9)), "today")), "e=1e-8")
    assert_all_one((Solver._solve_once(matrix(review_1_matrix(1e-5, 65535)), "today")), "e=1e-5")
end)

H.test("G3e a tiny untouched pivot is outvoted by the largest-pivot order in every row order", function()
    local Solver = solver()
    for _, parameters in ipairs({{1e-8, 1e9}, {1e-5, 65535}}) do
        for _, order in ipairs(ORDERS) do
            assert_all_one(Solver._gauss_solve(matrix(symmetric(review_1_matrix(parameters[1], parameters[2]), order))),
                "e=" .. parameters[1] .. " order " .. table.concat(order))
        end
    end
end)

H.test("G3g an answer that fits the equations but not the machine count loses to the better-fitting order", function()
    local Solver = solver()
    local rows = {{0, 1, 1, 2}, {1e-5, 65535, 0, 65535 + 1e-5}, {1, 1000, 1000, 2001}}
    for _, order in ipairs(ORDERS) do
        local what = "order " .. table.concat(order)
        local solution = Solver._gauss_solve(matrix(symmetric(rows, order)))
        assert_all_one(solution, what)
        for position, recipe in ipairs(order) do
            if recipe == 1 then
                H.near(solution[position] * 0.3 / 0.1, 3, what .. " machines at energy 0.3 and speed 0.1")
            end
        end
    end
end)

H.test("G3h equally fitting answers that differ keep the current order's numbers", function()
    local Solver = solver()
    local rows = with_demands({{-2e-5, 0, 1}, {0, -1e-5, 0}, {1e-5, 65535, 0}}, {3, 3, 1})
    assert_same_bits(Solver._gauss_solve(matrix(rows)), (Solver._solve_once(matrix(rows), "today")), "tie")
end)

H.test("G3i agreeing orders return the current order's exact numbers", function()
    local Solver = solver()
    assert_same_bits(Solver._gauss_solve(matrix(FOUR)), (Solver._solve_once(matrix(FOUR), "today")), "4x4 order 1234")
end)

H.done("test_solver")
