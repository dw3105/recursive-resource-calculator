--Recipes listing one product several times, catalysts, and the report's solved/unsolved row contract
local H = require "tests.harness"

--Muluna's Diffused plastic bar: 20 spoilage variants of one item at 5% each, plus carbon dioxide given back
local function diffused_plastic_world(shape)
    local world = H.new_world(shape)
    world.add_item("plastic-bar")
    world.add_item("diffused-plastic-bar")
    world.add_fluid("carbon-dioxide")
    world.add_machine({name = "chemical-plant", categories = {"chemistry"}, speed = 1, energy_kw = 210, pollution_per_minute = 4})
    local products = {}
    for i = 0, 19 do
        local variant = {name = "diffused-plastic-bar", amount = 1, percent_spoiled = i * 0.05}
        if shape == "2.1" then
            variant.shared = {min = i * 0.05, max = (i + 1) * 0.05}
        else
            variant.p = 0.05
        end
        products[#products + 1] = variant
    end
    products[#products + 1] = {type = "fluid", name = "carbon-dioxide", amount = 25}
    world.add_recipe({name = "diffused-plastic-bar", category = "chemistry", energy = 10, products = products,
        ingredients = {{name = "plastic-bar", amount = 1}, {type = "fluid", name = "carbon-dioxide", amount = 100}}})
    world.add_player(1)
    world.init()
    world.bind("item/diffused-plastic-bar", "diffused-plastic-bar")
    return world
end

local function kovarex_world(shape, productivity_module_bonus)
    local world = H.new_world(shape)
    world.add_item("uranium-235")
    world.add_item("uranium-238")
    world.add_machine({name = "centrifuge", categories = {"centrifuging"}, speed = 1})
    world.add_recipe({name = "kovarex-enrichment-process", category = "centrifuging", energy = 60,
        ingredients = {{name = "uranium-235", amount = 40}, {name = "uranium-238", amount = 5}},
        products = {{name = "uranium-235", amount = 41, ignored = 40}, {name = "uranium-238", amount = 2, ignored = 2}}})
    world.add_player(1)
    world.init()
    world.bind("item/uranium-235", "kovarex-enrichment-process")
    storage[1].module_preferences_by_recipe_name["kovarex-enrichment-process"].effects.productivity = productivity_module_bonus or 0
    return world
end

local function report_or_fail(report, world)
    if not report then error("no report; flying texts: " .. table.concat((function()
        local texts = {}
        for _, text in ipairs(world.flying_texts) do texts[#texts + 1] = type(text) == "table" and text[1] or tostring(text) end
        return texts
    end)(), ", "), 2) end
    return report
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " V2 diffused plastic bar at 8 /s matches the recipe, not its 20 entries", function()
        local world = diffused_plastic_world(shape)
        local report = report_or_fail(H.run_sheet({{item = "diffused-plastic-bar", rate = 8, unit = "/s"}}), world)
        H.near(report.rows["item/diffused-plastic-bar"].rate, 8, "bar row rate")
        H.near(report.rows["item/diffused-plastic-bar"].machines, 80, "machines")
        H.near(report.rows["item/plastic-bar"].rate, 8, "plastic row rate")
        H.near(report.rows["fluid/carbon-dioxide"].rate, 600, "carbon dioxide net of the 25 given back")
        H.near(report.energy_mw, 16.8, "energy MW")
        H.near(report.pollution_per_minute, 320, "pollution /m")
        H.equal(report.row_count, 3, "row count")
    end)

    H.test(shape .. " V5 Kovarex nets the catalyst on both sides", function()
        local world = kovarex_world(shape)
        local report = report_or_fail(H.run_sheet({{item = "uranium-235", rate = 8, unit = "/s"}}), world)
        H.near(report.rows["item/uranium-235"].rate, 8, "U-235 row rate")
        H.near(report.rows["item/uranium-235"].machines, 8 * 60, "centrifuges at 8 crafts/s")
        H.near(report.rows["item/uranium-238"].rate, 24, "U-238 demand, 5 in and 2 out per craft")
        H.equal(report.row_count, 2, "row count")
    end)

    H.test(shape .. " V5 Kovarex with +10% productivity only multiplies the net gain", function()
        local world = kovarex_world(shape, 0.1)
        local report = report_or_fail(H.run_sheet({{item = "uranium-235", rate = 8, unit = "/s"}}), world)
        H.near(report.rows["item/uranium-235"].rate, 8, "U-235 row rate")
        H.near(report.rows["item/uranium-235"].machines, 8 / 1.1 * 60, "centrifuges at 8/1.1 crafts/s")
        H.near(report.rows["item/uranium-238"].rate, 3 * 8 / 1.1, "U-238 demand")
    end)

    H.test(shape .. " V11 intermediate rows show their recipe's output, not the zero global balance", function()
        local world = H.new_world(shape)
        for _, item in ipairs({"raw", "a", "b"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "a", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "a", amount = 1}}})
        world.add_recipe({name = "b", category = "crafting", ingredients = {{name = "a", amount = 1}}, products = {{name = "b", amount = 1}}})
        world.add_player(1)
        world.init()
        local report = report_or_fail(H.run_sheet({{item = "b", rate = 8, unit = "/s"}}), world)
        H.near(report.rows["item/b"].rate, 8, "b row")
        H.near(report.rows["item/a"].rate, 8, "a row")
        H.equal(report.rows["item/a"].kind, "solved", "a row kind")
        H.near(report.rows["item/raw"].rate, 8, "raw row")
        H.equal(report.row_count, 3, "row count")
    end)

    H.test(shape .. " V12 byproduct with a bound but unused recipe still gets a row", function()
        local world = H.new_world(shape)
        for _, item in ipairs({"raw", "t", "x"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "t-and-x", category = "crafting", ingredients = {{name = "raw", amount = 1}},
            products = {{name = "t", amount = 1}, {name = "x", amount = 1}}})
        world.add_recipe({name = "x-maker", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "x", amount = 1}}})
        world.add_player(1)
        world.init()
        world.bind("item/t", "t-and-x")
        world.bind("item/x", "x-maker")
        local report = report_or_fail(H.run_sheet({{item = "t", rate = 8, unit = "/s"}}), world)
        assert(report.rows["item/x"], "byproduct x has no row")
        H.near(report.rows["item/x"].rate, -8, "x byproduct rate")
        H.equal(report.rows["item/x"].kind, "hxrrc.byproduct", "x row kind")
    end)

    local function amount(product_spec, bonus)
        H.new_world(shape)
        return require("logic.utils").product_amount(H.product(shape, product_spec), bonus)
    end

    H.test(shape .. " V10 extra count fraction is weighted by probability", function()
        H.near(amount({name = "coin", amount = 1, p = 0.9, e = 0.3}, 0), 1.17, "amount 1")
        H.near(amount({name = "coin", amount = 2, p = 0.9, e = 0.3}, 0), 2.07, "amount 2")
    end)

    H.test(shape .. " V5/V7c catalyst amount ignored by productivity, falling back to ignored_by_stats", function()
        H.near(amount({name = "uranium-235", amount = 41, ignored = 40}, 0.1), 41.1, "ignored_by_productivity")
        H.near(amount({name = "uranium-235", amount = 41, ignored_by_stats = 40}, 0.1), 41.1, "ignored_by_stats only")
    end)

    H.test(shape .. " V7 item range clamps each outcome before averaging", function()
        H.near(amount({name = "x", min = 0, max = 2, ignored = 1}, 1), 4 / 3, "0..2 ignoring 1 at +100%")
    end)

    H.test(shape .. " V7b fluid range uses the continuous distribution", function()
        H.near(amount({type = "fluid", name = "steam", min = 0, max = 2, ignored = 1}, 1), 1.25, "0..2 ignoring 1 at +100%")
    end)

    H.test(shape .. " V13 staff case: 0..100 ignoring 50 at +50%, 2 crafts/s", function()
        local spec = {name = "x", min = 0, max = 100, ignored = 50}
        H.near(2 * (amount(spec, 0.5) - amount(spec, 0)), 1275 / 101, "bonus output per second")
    end)
end

H.done("test_multi_entry_products")
