--Excess products consumed by a recipe the player picks: consumer bindings, their checks, and results that cannot be solved or are infeasible
local H = require "tests.harness"

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

--make: raw -> target + x; burn consumes x and makes nothing; cast makes x from ore
local function consumer_world(shape)
    local world = H.new_world(shape)
    for _, item in ipairs({"raw", "target", "x", "ore", "y"}) do world.add_item(item) end
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "make", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "target", amount = 1}, {name = "x", amount = 1}}})
    world.add_recipe({name = "burn", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {}})
    world.add_recipe({name = "cast", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "x", amount = 1}}})
    --burn2 takes one x and gives one back at probability 0.5: net -0.5, zero at +100% productivity, +0.5 at +200%
    world.add_recipe({name = "burn2", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {{name = "x", amount = 1, p = 0.5}}})
    world.add_recipe({name = "dup", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {{name = "x", amount = 2}}}) --net +1
    world.add_recipe({name = "swap", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {{name = "x", amount = 1}}}) --net 0
    world.add_recipe({name = "melt", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {{name = "y", amount = 1}}}) --y's only recipe
    world.add_player(1)
    world.init()
    world.bind("item/target", "make")
    return world
end

local function recompute(sheet_pane)
    require("gui.sheet").calculate(nil, sheet_pane, 1)
    return H.parse_report(sheet_pane.tabs[1].content.output_flow)
end

local function fire_elem_changed(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

--Picks a recipe on a row's recipe button through the registered handler, as a player does
local function pick_recipe(report, product_full_name, recipe_name)
    local button = report.rows[product_full_name].recipe_button
    button.elem_value = recipe_name
    fire_elem_changed(button)
    return button
end

--A consumer world whose report is on screen with its handlers registered; returns world, report, sheet pane
local function consumer_sheet(shape, rate)
    local world = consumer_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    local report, sheet_pane = H.run_sheet({{item = "target", rate = rate or 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    return world, report, sheet_pane
end

local function flying_text_keys(world)
    local keys = {}
    for _, text in ipairs(world.flying_texts) do keys[#keys + 1] = text[1] end
    return table.concat(keys, ",")
end

--craft: plate -> target + scrap; recycle: scrap -> 2 plate; smelt: ore -> plate. Consuming the scrap returns more plate than the craft eats.
local function counterexample_world(shape)
    local world = H.new_world(shape)
    for _, item in ipairs({"target", "scrap", "plate", "ore"}) do world.add_item(item) end
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100})
    world.add_recipe({name = "craft", category = "crafting", ingredients = {{name = "plate", amount = 1}},
        products = {{name = "target", amount = 1}, {name = "scrap", amount = 1}}})
    world.add_recipe({name = "recycle", category = "crafting", ingredients = {{name = "scrap", amount = 1}}, products = {{name = "plate", amount = 2}}})
    world.add_recipe({name = "smelt", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/target", "craft")
    world.bind("item/plate", "smelt")
    world.bind_consumer("item/scrap", "recycle")
    return world
end

H.test("R4-3c a rate is judged against the rounding of its own equation only", function()
    H.new_world("2.0")
    local reasons = require("logic.solver")._backwards_reasons
    local columns = {{recipe_name = "c1"}, {recipe_name = "c2"}, {recipe_name = "c3"}}
    --line c is column c's equation; index 4 is the demand
    local matrix = {
        {[1] = 1, [2] = 1e3, [4] = 0},
        {[2] = 1, [4] = 1},
        {[3] = 1, [4] = 1e15},
    }
    local found = reasons(matrix, columns, {-1e-12, 1, 1e15})
    H.equal(found.c1, nil, "-1e-12 against terms of 1e3 is rounding")
    H.equal(next(found), nil, "no other column is at fault")

    matrix[1] = {[1] = 1, [2] = 1, [4] = 0}
    found = reasons(matrix, columns, {-1e-3, 1, 1e15})
    H.equal(found.c1, "recipe_runs_backwards", "-1e-3 against terms of 1 runs backwards, although c3 runs at 1e15")
    H.equal(found.c3, nil, "the huge rate itself is fine")

    found = reasons(matrix, columns, {0 / 0, 1, 1e15})
    H.equal(found.c1, "rate_not_finite", "nan")
end)

--Every locale key the code names exists in every language, reasons included
H.test("R4 locale has every key the code names, in every language", function()
    local keys = {}
    for _, file in ipairs({"gui/report.lua", "gui/sheet.lua", "gui/modulegui.lua", "gui/input_container.lua", "gui/calculator.lua", "logic/solver.lua"}) do
        local source = io.open(file):read("*a")
        for key in source:gmatch('"hxrrc%.([%w_]+)"') do keys[key] = true end
        for key in source:gmatch('reasons_by_column%[[^\n]-%] = "([%w_]+)"') do keys[key] = true end
        for key in source:gmatch('reason or "([%w_]+)"') do keys[key] = true end
        for key in source:gmatch('%] or "([%w_]+)"%)') do keys[key] = true end
    end
    H.equal(keys.consumer_no_longer_consumes and keys.recipe_runs_backwards and keys.no_rate and true, true, "scan finds the reason keys")
    for _, language in ipairs({"en", "cs", "ro"}) do
        local locale = io.open("locale/" .. language .. "/locale.cfg"):read("*a")
        for key, _ in pairs(keys) do
            if not locale:find("\n" .. key .. "=", 1, true) then
                error(language .. " locale lacks " .. key)
            end
        end
    end
end)

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " R4-3 a producer the bindings drive backwards makes the sheet infeasible, without totals", function()
        counterexample_world(shape)
        local power_calls = 0
        package.loaded["logic.compute_power_and_pollution"] = function() power_calls = power_calls + 1 return 0, 0 end
        local report = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        H.equal(power_calls, 0, "power and pollution never computed")
        H.equal(report.energy_caption, "hxrrc.totals_unavailable", "energy header")
        H.equal(report.pollution_caption, "hxrrc.totals_unavailable", "pollution header")
        H.equal(report.rows["item/plate"].reason, "hxrrc.recipe_runs_backwards", "smelt row names the fault")
        H.near(report.rows["item/plate"].rate, -1, "smelt's rate still shown")
        H.near(report.rows["item/target"].machines, 1, "craft row keeps its count")
        H.near(report.rows["item/scrap"].machines, 1, "recycle row keeps its count")
    end)

    H.test(shape .. " R4-3b a backwards producer stays a fault next to an unrelated column of any scale", function()
        for _, trace_yield in ipairs({1e-12, 1e-6, 1}) do
            local world = H.new_world(shape)
            for _, item in ipairs({"target", "scrap", "plate", "ore", "trace", "trace-ore"}) do world.add_item(item) end
            world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100})
            world.add_recipe({name = "craft", category = "crafting", ingredients = {{name = "plate", amount = 1}, {name = "trace", amount = 1}},
                products = {{name = "target", amount = 1}, {name = "scrap", amount = 1}}})
            world.add_recipe({name = "recycle", category = "crafting", ingredients = {{name = "scrap", amount = 1}}, products = {{name = "plate", amount = 2}}})
            world.add_recipe({name = "smelt", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
            world.add_recipe({name = "trace-make", category = "crafting", ingredients = {{name = "trace-ore", amount = 1}},
                products = {{name = "trace", amount = 1, p = trace_yield}}})
            world.add_player(1)
            world.init()
            world.bind("item/target", "craft")
            world.bind("item/plate", "smelt")
            world.bind_consumer("item/scrap", "recycle")
            local power_calls = 0
            package.loaded["logic.compute_power_and_pollution"] = function() power_calls = power_calls + 1 return 0, 0 end
            local what = "trace yield " .. trace_yield
            local result = require("logic.solver").solve_for({["item/target"] = 1}, 1)
            H.near_relative(result.recipe_rates["trace-make"], 1 / trace_yield, what .. ": trace rate")
            H.near(result.recipe_rates.smelt, -1, what .. ": smelt rate")
            H.equal(result.status, "infeasible", what .. ": status")
            H.equal(result.reasons_by_column.smelt, "recipe_runs_backwards", what .. ": smelt runs backwards")
            H.equal(result.reasons_by_column["trace-make"], nil, what .. ": trace-make is fine")
            local report = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
            H.equal(report.energy_caption, "hxrrc.totals_unavailable", what .. ": no totals")
            H.equal(power_calls, 0, what .. ": power never computed")
        end
    end)

    H.test(shape .. " R4-3 rounding noise below zero on a rate is not a fault", function()
        local solver = require "logic.solver"
        counterexample_world(shape)
        --the ore that smelt needs is covered by target demand alone: with scrap unbound the system is plain
        storage[1].consumer_product_full_names["item/scrap"] = nil
        storage[1].recipes_by_product_full_name["item/scrap"] = nil
        storage[1].product_full_names_by_recipe_name.recycle = nil
        local result = solver.solve_for({["item/target"] = 1}, 1)
        H.equal(result.status, "ok", "status")
        H.near(result.recipe_rates.smelt, 1, "smelt")
    end)

    H.test(shape .. " R4-6 a byproduct bound to a producer is still left out of the system", function()
        local world = consumer_world(shape)
        world.bind("item/x", "cast")
        local report = H.run_sheet({{item = "target", rate = 2, unit = "/s"}})
        H.near(report.rows["item/x"].rate, -2, "x stays a byproduct")
        H.equal(report.rows["item/x"].kind, "hxrrc.byproduct", "kind")
        H.equal(report.rows["item/ore"], nil, "cast is not used, so no ore")
        H.near(report.energy_mw, 0.21 * 2, "totals of make only")
    end)

    H.test(shape .. " R4-5 a consumer that no longer consumes is reported before solving, with its editors", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn2")
        local report, sheet_pane = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        H.equal(report.energy_caption ~= nil and report.energy_mw ~= nil, true, "starts solved with totals")
        H.near(report.rows["item/x"].machines, 2, "two burns eat the one x")

        local force_recipe = game.players[1].force.recipes.burn2
        for _, step in ipairs({{1, "zero"}, {2, "positive"}}) do
            force_recipe.productivity_bonus = step[1]
            report = recompute(sheet_pane)
            H.equal(report.energy_mw, nil, step[2] .. ": old totals gone")
            H.equal(report.energy_caption, "hxrrc.totals_unavailable", step[2] .. ": header")
            H.equal(report.rows["item/x"].reason, "hxrrc.consumer_no_longer_consumes", step[2] .. ": reason on the consumer row")
            H.equal(report.rows["item/x"].rate, nil, step[2] .. ": no rate")
            H.equal(report.rows["item/x"].machine_button ~= nil, true, step[2] .. ": machine editor present")
            H.equal(report.rows["item/x"].recipe_button.elem_value, "burn2", step[2] .. ": recipe editor shows the binding")
            H.equal(report.rows["item/target"].reason, "hxrrc.no_rate", step[2] .. ": other rows carry no number")
        end
        force_recipe.productivity_bonus = 0
        report = recompute(sheet_pane)
        H.near(report.energy_mw, 0.21 * 3, "solved again with totals")
        H.equal(world.flying_texts[1], nil, "no flying text for an infeasible result")
    end)

    H.test(shape .. " R4-11 an unsolvable binding clears the old report, lists the bindings, and undoing it recovers", function()
        local world = H.new_world(shape)
        require "gui.calculator" --registers the event handlers the test fires
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_recipe({name = "a", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        --b gives back the gear it takes: gear's equation is empty and the system has no answer
        world.add_recipe({name = "b", category = "crafting", ingredients = {{name = "gear", amount = 1}}, products = {{name = "gear", amount = 1, ignored = 0}}})
        world.add_player(1)
        world.init()
        world.bind("item/gear", "a")
        local report, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        H.near(report.energy_mw, 0.21, "solved with a")

        pick_recipe(report, "item/gear", "b")
        report = recompute(sheet_pane)
        H.equal(report.energy_caption, "hxrrc.system_with_no_solution_error", "header says why")
        H.equal(report.pollution_caption, "hxrrc.totals_unavailable", "no pollution total")
        H.equal(report.rows["item/raw"], nil, "old rows cleared")
        H.equal(report.row_count, 1, "one row per used recipe")
        H.equal(report.rows["item/gear"].recipe_button.elem_value, "b", "the binding to undo is shown")
        H.equal(world.flying_texts[1] and world.flying_texts[1][1], "hxrrc.system_with_no_solution_error", "flying text")

        pick_recipe(report, "item/gear", "a")
        report = recompute(sheet_pane)
        H.near(report.energy_mw, 0.21, "recovered")
        H.near(report.rows["item/raw"].rate, 1, "raw row back")
    end)

    H.test(shape .. " R4-12 a machine button acts on the recipe in its tags, and refuses once its row is bound elsewhere", function()
        local world = H.new_world(shape)
        require "gui.calculator" --registers the event handlers the test fires
        world.add_item("raw")
        world.add_item("gear")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2})
        world.add_recipe({name = "a", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
        world.add_recipe({name = "b", category = "crafting", ingredients = {{name = "raw", amount = 2}}, products = {{name = "gear", amount = 1}}})
        world.add_player(1)
        world.init()
        local chosen = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
        chosen.a, chosen.b = {name = "assembler"}, {name = "assembler"}
        world.bind("item/gear", "a")
        local report, sheet_pane = H.run_sheet({{item = "gear", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}

        local button = report.rows["item/gear"].machine_button
        H.equal(button.tags.recipe_name, "a", "button tagged with its recipe")
        H.pick_choice(button, {name = "fast-assembler"})
        H.equal(chosen.a.name, "fast-assembler", "change applies to a")
        H.equal(button.tags.recipe_name, "a", "tags keep the row after a change")

        report = recompute(sheet_pane)
        button = report.rows["item/gear"].machine_button
        pick_recipe(report, "item/gear", "b")
        storage.computation_stack = {}
        H.equal(H.pick_choice(button, {name = "assembler"}), false, "stale button opens no picker")
        H.equal(chosen.a.name, "fast-assembler", "a unchanged by the stale button")
        H.equal(chosen.b.name, "assembler", "b unchanged: the neighbour recipe button already shows b")
        H.equal(button.tags.name, "fast-assembler", "stale button still shows its machine")
        H.equal(#storage.computation_stack, 0, "nothing queued")

        report = recompute(sheet_pane)
        local untagged = report.rows["item/gear"].machine_button
        untagged.tags = {name = "assembler"} --a button whose row tags are missing
        H.equal(H.pick_choice(untagged, {name = "fast-assembler"}), false, "untagged button opens no picker")
        H.equal(chosen.b.name, "assembler", "untagged button refused")
    end)

    H.test(shape .. " R4-1 oil byproducts cracked down to the target fluid, picked on their byproduct rows", function()
        local world = H.new_world(shape)
        require "gui.calculator"
        for _, fluid in ipairs({"crude", "water", "heavy", "light", "gas"}) do world.add_fluid(fluid) end
        world.add_machine({name = "refinery", categories = {"oil-processing"}, speed = 1, energy_kw = 420})
        world.add_machine({name = "chemical-plant", categories = {"chemistry"}, speed = 1, energy_kw = 210})
        world.add_recipe({name = "advanced-oil", category = "oil-processing", energy = 5,
            ingredients = {{type = "fluid", name = "crude", amount = 100}, {type = "fluid", name = "water", amount = 50}},
            products = {{type = "fluid", name = "heavy", amount = 25}, {type = "fluid", name = "light", amount = 45}, {type = "fluid", name = "gas", amount = 55}}})
        world.add_recipe({name = "heavy-cracking", category = "chemistry", energy = 2,
            ingredients = {{type = "fluid", name = "heavy", amount = 40}, {type = "fluid", name = "water", amount = 30}},
            products = {{type = "fluid", name = "light", amount = 30}}})
        world.add_recipe({name = "light-cracking", category = "chemistry", energy = 2,
            ingredients = {{type = "fluid", name = "light", amount = 30}, {type = "fluid", name = "water", amount = 30}},
            products = {{type = "fluid", name = "gas", amount = 20}}})
        world.add_player(1)
        world.init()
        world.bind("fluid/gas", "advanced-oil")
        local report, sheet_pane = H.run_sheet({{fluid = "gas", rate = 100, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        H.near(report.rows["fluid/heavy"].rate, -25 * 100 / 55, "heavy excess before cracking")
        H.near(report.rows["fluid/light"].rate, -45 * 100 / 55, "light excess before cracking")
        local heavy_button = report.rows["fluid/heavy"].recipe_button
        H.equal(heavy_button.tags.consumer, true, "byproduct row has a consumer button")
        H.equal(heavy_button.elem_filters[1].filter, "has-ingredient-fluid", "it lists recipes eating heavy oil")
        H.equal(heavy_button.elem_filters[1].elem_filters[1].name, "heavy", "filtered by name")

        pick_recipe(report, "fluid/heavy", "heavy-cracking")
        report = recompute(sheet_pane)
        pick_recipe(report, "fluid/light", "light-cracking")
        report = recompute(sheet_pane)

        --gas: 55a + 20l = 100; heavy: 25a - 40h = 0; light: 45a + 30h - 30l = 0, so h = 0.625a, l = 2.125a, 97.5a = 100
        local a = 100 / 97.5
        local h, l = 0.625 * a, 2.125 * a
        H.equal(report.rows["fluid/heavy"].kind, "solved", "heavy is a consumer row now")
        H.equal(report.rows["fluid/light"].kind, "solved", "light is a consumer row now")
        H.near(report.rows["fluid/heavy"].rate, -40 * h, "heavy consumed (-25.641025641)")
        H.near(report.rows["fluid/light"].rate, -30 * l, "light consumed (-65.3846153846)")
        H.near(report.rows["fluid/gas"].rate, 55 * a, "gas made by advanced oil (56.4102564103)")
        H.near(report.rows["fluid/gas"].machines, 5 * a, "refineries (5.12820512821)")
        H.near(report.rows["fluid/heavy"].machines, 2 * h, "heavy cracking plants (1.28205128205)")
        H.near(report.rows["fluid/light"].machines, 2 * l, "light cracking plants (4.35897435897)")
        H.near(report.rows["fluid/water"].rate, 50 * a + 30 * h + 30 * l, "water (135.897435897)")
        H.near(report.rows["fluid/crude"].rate, 100 * a, "crude (102.564102564)")
        H.equal(report.rows["fluid/heavy"].recipe_button.tags.consumer, true, "solved consumer row keeps a consumer button")
        H.equal(report.rows["fluid/heavy"].recipe_button.elem_value, "heavy-cracking", "showing its binding")
        H.near(report.energy_mw, 0.42 * 5 * a + 0.21 * (2 * h + 2 * l), "MW (3.56666666667)")
        H.equal(report.row_count, 5, "gas, heavy, light, water, crude")
    end)

    H.test(shape .. " R4-2 a recycling recipe picked for an item byproduct gives back part of the ingredient", function()
        local world = H.new_world(shape)
        require "gui.calculator"
        for _, item in ipairs({"ore", "plate", "gear", "widget"}) do world.add_item(item) end
        world.add_machine({name = "furnace", type = "furnace", categories = {"smelting"}, speed = 1})
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 0.5})
        world.add_recipe({name = "smelt", category = "smelting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
        world.add_recipe({name = "widget", category = "crafting", ingredients = {{name = "plate", amount = 2}},
            products = {{name = "widget", amount = 1}, {name = "gear", amount = 1}}})
        world.add_recipe({name = "gear-recycling", category = "recycling", hidden = true, energy = 0.5,
            ingredients = {{name = "gear", amount = 1}}, products = {{name = "plate", amount = 1, p = 0.25}}})
        world.add_player(1)
        world.init()
        world.bind("item/widget", "widget")
        world.bind("item/plate", "smelt")
        local report, sheet_pane = H.run_sheet({{item = "widget", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        H.near(report.rows["item/ore"].rate, 2, "ore before recycling")
        pick_recipe(report, "item/gear", "gear-recycling")
        report = recompute(sheet_pane)
        H.near(report.rows["item/gear"].rate, -1, "every gear recycled")
        H.near(report.rows["item/gear"].machines, 1 * 0.5 / 0.5, "recyclers")
        H.near(report.rows["item/plate"].rate, 1.75, "smelting only what recycling does not return")
        H.near(report.rows["item/ore"].rate, 1.75, "ore drops by the returned quarter plate")
    end)

    H.test(shape .. " R4-4 a consumer pick must consume the product: net below zero is taken, zero and gains are refused", function()
        local world, report = consumer_sheet(shape)
        local button = report.rows["item/x"].recipe_button
        for _, refused in ipairs({"dup", "swap"}) do
            button.elem_value = refused
            fire_elem_changed(button)
            H.equal(button.elem_value, nil, refused .. ": button restored")
            H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, refused .. ": no binding")
            H.equal(storage[1].consumer_product_full_names["item/x"], nil, refused .. ": no flag")
            H.equal(storage[1].product_full_names_by_recipe_name[refused], nil, refused .. ": recipe still free")
            H.equal(#storage.computation_stack, 0, refused .. ": nothing queued")
        end
        H.equal(flying_text_keys(world), "hxrrc.recipe_does_not_consume_error,hxrrc.recipe_does_not_consume_error", "a message per refusal")
        button.elem_value = "burn2"
        fire_elem_changed(button)
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn2", "net -0.5 is taken")
        H.equal(storage[1].consumer_product_full_names["item/x"], true, "flagged")
        H.equal(#storage.computation_stack > 0, true, "recomputation queued")
    end)

    H.test(shape .. " R4-4 clearing a consumer button removes the binding and its flag; clearing an empty one changes nothing", function()
        local _, report, sheet_pane = consumer_sheet(shape)
        local button = report.rows["item/x"].recipe_button
        button.elem_value = nil
        fire_elem_changed(button)
        H.equal(#storage.computation_stack, 0, "empty consumer button cleared: nothing queued")
        pick_recipe(report, "item/x", "burn")
        report = recompute(sheet_pane)
        pick_recipe(report, "item/x", nil)
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding removed")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag removed")
        H.equal(storage[1].product_full_names_by_recipe_name.burn, nil, "burn free again")
        report = recompute(sheet_pane)
        H.equal(report.rows["item/x"].kind, "hxrrc.byproduct", "x is a byproduct again")
    end)

    H.test(shape .. " R4-4 a consumer pick replaces a producer binding the byproduct row does not show, and clearing it leaves the producer", function()
        local world, report, sheet_pane = consumer_sheet(shape)
        world.bind("item/x", "cast")
        report = recompute(sheet_pane)
        local button = report.rows["item/x"].recipe_button
        H.equal(button.elem_value, nil, "consumer button shows no producer")
        button.elem_value = nil
        fire_elem_changed(button)
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "cast", "clearing the empty consumer button keeps cast")
        pick_recipe(report, "item/x", "burn")
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn", "consumer replaces cast")
        H.equal(storage[1].product_full_names_by_recipe_name.cast, nil, "cast released")
    end)

    H.test(shape .. " R4-8 a recipe serving another product is refused on a byproduct row, and a re-raised restore does not loop", function()
        local world, report = consumer_sheet(shape)
        H.equal(storage[1].recipes_by_product_full_name["item/y"].name, "melt", "melt already makes y")
        H.refire_on_script_set = true
        local button = report.rows["item/x"].recipe_button
        button.elem_value = "melt"
        H.equal(button.elem_value, nil, "restored")
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "no binding")
        H.equal(storage[1].product_full_names_by_recipe_name.melt, "item/y", "melt still serves y")
        button.elem_value = "dup"
        H.equal(button.elem_value, nil, "net gain restored without a loop")
        H.equal(flying_text_keys(world), "hxrrc.recipe_already_used_by_another_product_error,hxrrc.recipe_does_not_consume_error", "messages")
    end)

    H.test(shape .. " R4-9 modded consumer through an additional category, with unequal product probabilities", function()
        local world = H.new_world(shape)
        require "gui.calculator"
        for _, item in ipairs({"raw", "target", "scrap", "metal", "dust"}) do world.add_item(item) end
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "mod-sorter", categories = {"sorting"}, speed = 1})
        world.add_machine({name = "mod-grinder", type = "furnace", categories = {"grinding"}, speed = 0.5})
        world.add_recipe({name = "salvage", category = "crafting", ingredients = {{name = "raw", amount = 1}},
            products = {{name = "target", amount = 1}, {name = "scrap", amount = 1}}})
        world.add_recipe({name = "scrap-sort", category = "sorting", additional_categories = {"grinding"},
            ingredients = {{name = "scrap", amount = 2}}, products = {{name = "metal", amount = 1, p = 0.5}, {name = "dust", amount = 3, p = 0.25}}})
        world.add_player(1)
        world.init()
        world.bind("item/target", "salvage")
        local report, sheet_pane = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        pick_recipe(report, "item/scrap", "scrap-sort")
        report = recompute(sheet_pane)
        H.near(report.rows["item/scrap"].rate, -1, "scrap consumed")
        H.near(report.rows["item/metal"].rate, -0.25, "metal left over")
        H.near(report.rows["item/dust"].rate, -0.375, "dust left over")
        H.equal(report.rows["item/scrap"].machine.name, "mod-sorter", "primary category's machine first")
        H.near(report.rows["item/scrap"].machines, 0.5, "sorters")
        local machine_button = report.rows["item/scrap"].machine_button
        require("gui.module_picker").open(machine_button)
        local offered = {}
        for _, flow in ipairs(storage[1].module_picker.frame.picker_scroll.picker_grid.children) do offered[#offered + 1] = flow.children[1].tags.choice end
        H.equal(table.concat(offered, ","), "mod-sorter,mod-grinder", "both categories' machines offered, primary first")
        require("gui.module_picker").close(1, false)
        H.pick_choice(machine_button, {name = "mod-grinder"})
        report = recompute(sheet_pane)
        H.near(report.rows["item/scrap"].machines, 1, "grinders at half speed")
        H.equal(require("logic.utils").can_craft("assembler", prototypes.recipe["scrap-sort"]), false, "assembler cannot sort")
    end)

    H.test(shape .. " R4-10 one sheet through zero and positive net: diagnostic with working consumer controls, then solved again", function()
        local world, report, sheet_pane = consumer_sheet(shape)
        pick_recipe(report, "item/x", "burn2")
        report = recompute(sheet_pane)
        H.near(report.energy_mw, 0.21 * 3, "solved: one make, two burn2")
        local force_recipe = game.players[1].force.recipes.burn2

        force_recipe.productivity_bonus = 1
        report = recompute(sheet_pane)
        H.equal(report.rows["item/x"].reason, "hxrrc.consumer_no_longer_consumes", "zero net: diagnostic")
        H.equal(report.energy_mw, nil, "zero net: old totals gone")
        local button = report.rows["item/x"].recipe_button
        H.equal(button.tags.consumer, true, "diagnostic row keeps the consumer button")
        storage.computation_stack = {}
        button.elem_value = "burn2" --already bound: no change
        fire_elem_changed(button)
        H.equal(#storage.computation_stack, 0, "re-picking the bound recipe does nothing")
        pick_recipe(report, "item/x", "burn")
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn", "another consumer picked from the diagnostic")
        report = recompute(sheet_pane)
        H.near(report.energy_mw, 0.21 * 2, "solved with burn")

        force_recipe.productivity_bonus = 2
        pick_recipe(report, "item/x", "burn2")
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn", "burn2 at net +0.5 refused")
        H.equal(report.rows["item/x"].recipe_button.elem_value, "burn", "button restored to burn")

        force_recipe.productivity_bonus = 0
        pick_recipe(report, "item/x", "burn2")
        report = recompute(sheet_pane)
        H.near(report.energy_mw, 0.21 * 3, "solved with burn2 again")
        H.equal(flying_text_keys(world), "hxrrc.recipe_does_not_consume_error", "one refusal message")
    end)

    H.test(shape .. " R4-12 a consumer row's machine button refuses once the row's consumer changes; machine then module changes both apply", function()
        local world, report, sheet_pane = consumer_sheet(shape)
        world.add_machine({name = "fast-assembler", categories = {"crafting"}, speed = 2})
        world.add_module("speed-module", "speed", {speed = 0.5})
        reconfigure()
        pick_recipe(report, "item/x", "burn")
        report = recompute(sheet_pane)
        local chosen = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
        local old_button = report.rows["item/x"].machine_button
        H.equal(old_button.tags.recipe_name, "burn", "consumer row tagged with its consumer")

        pick_recipe(report, "item/x", "burn2")
        storage.computation_stack = {}
        local shown = old_button.tags.name
        H.equal(H.pick_choice(old_button, {name = shown == "fast-assembler" and "assembler" or "fast-assembler"}), false, "stale consumer machine button opens no picker")
        H.equal(old_button.tags.name, shown, "stale consumer machine button still shows its machine")
        H.equal(#storage.computation_stack, 0, "nothing queued")

        report = recompute(sheet_pane)
        local button = report.rows["item/x"].machine_button
        H.pick_choice(button, {name = "fast-assembler"})
        H.equal(chosen.burn2.name, "fast-assembler", "machine change applies to burn2")
        report = recompute(sheet_pane)
        local slots = {}
        for _, flow in ipairs(report.rows["item/x"].module_cell.hxrrc_module_slots.children) do slots[#slots + 1] = flow.children[1] end
        H.pick_module(slots[1], {name = "speed-module"})
        H.equal(storage[1].module_setups_by_recipe_name.burn2.modules[4].name, "speed-module", "module change applies to burn2, filling its empty row")
        report = recompute(sheet_pane)
        H.near(report.rows["item/x"].machines, 2 * 1 / (2 * 3), "burn2 on fast assemblers with four speed modules")
    end)

    H.test(shape .. " R4-14 a module that makes the consumer net zero is removed from the diagnostic row, and the sheet solves again", function()
        local world, report, sheet_pane = consumer_sheet(shape)
        world.add_module("prod", "productivity", {productivity = 0.5})
        reconfigure()
        pick_recipe(report, "item/x", "burn2")
        report = recompute(sheet_pane)
        local function slot(row_report, index)
            return row_report.rows["item/x"].module_cell.hxrrc_module_slots.children[index].children[1]
        end
        storage[1].module_setups_by_recipe_name.burn2.modules = {{name = "prod"}} --one module, as an earlier edit left it; a pick into the empty row would fill it (N5)
        report = recompute(sheet_pane)
        H.near(report.rows["item/x"].machines, 4, "one module: net -0.25, four burns")
        local second = slot(report, 2)
        H.pick_module(second, {name = "prod"})
        report = recompute(sheet_pane)
        H.equal(report.rows["item/x"].reason, "hxrrc.consumer_no_longer_consumes", "two modules: net zero, diagnostic")
        H.equal(report.energy_mw, nil, "no totals")
        second = slot(report, 2)
        H.equal(H.slot_value(second).name, "prod", "diagnostic row shows the module")
        H.pick_module(second, nil)
        H.equal(#storage[1].module_setups_by_recipe_name.burn2.modules, 1, "module removed from the diagnostic row")
        report = recompute(sheet_pane)
        H.near(report.rows["item/x"].machines, 4, "solved again")
        H.near(report.energy_mw, 0.21 * 5, "totals back: one make, four burns")
    end)

    H.test(shape .. " R4-15 a machine whose productivity makes the consumer net zero is swapped on the diagnostic row", function()
        local world = consumer_world(shape)
        require "gui.calculator"
        world.add_machine({name = "hot-assembler", categories = {"crafting"}, speed = 1, base_productivity = 1})
        reconfigure()
        local chosen = storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name
        chosen.make, chosen.burn2 = {name = "assembler"}, {name = "hot-assembler"}
        world.bind_consumer("item/x", "burn2")
        local report, sheet_pane = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        H.equal(report.rows["item/x"].reason, "hxrrc.consumer_no_longer_consumes", "hot machine: net zero")
        local button = report.rows["item/x"].machine_button
        H.pick_choice(button, {name = "assembler"})
        H.equal(chosen.burn2.name, "assembler", "machine changed from the diagnostic row")
        report = recompute(sheet_pane)
        H.near(report.rows["item/x"].machines, 2, "solved: two burns")
        H.near(report.energy_mw, 0.21 * 3, "totals back")
    end)

    H.test(shape .. " R4-16 a modded venting recipe that makes nothing consumes an excess fluid", function()
        local world = H.new_world(shape)
        require "gui.calculator"
        world.add_item("raw")
        world.add_item("target")
        world.add_fluid("waste-gas")
        world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
        world.add_machine({name = "flare-stack", type = "furnace", categories = {"venting"}, speed = 1, energy_kw = 50})
        world.add_recipe({name = "crack", category = "crafting", ingredients = {{name = "raw", amount = 1}},
            products = {{name = "target", amount = 1}, {type = "fluid", name = "waste-gas", amount = 30}}})
        world.add_recipe({name = "vent-waste-gas", category = "venting", energy = 1,
            ingredients = {{type = "fluid", name = "waste-gas", amount = 10}}, products = {}})
        world.add_player(1)
        world.init()
        world.bind("item/target", "crack")
        local report, sheet_pane = H.run_sheet({{item = "target", rate = 2, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        H.near(report.rows["fluid/waste-gas"].rate, -60, "waste gas excess")
        pick_recipe(report, "fluid/waste-gas", "vent-waste-gas")
        report = recompute(sheet_pane)
        H.near(report.rows["fluid/waste-gas"].rate, -60, "all of it vented")
        H.near(report.rows["fluid/waste-gas"].machines, 6, "flare stacks")
        H.near(report.energy_mw, 0.21 * 2 + 0.05 * 6, "totals include the flare stacks")
        H.equal(report.row_count, 3, "target, waste gas, raw")
    end)

    H.test(shape .. " R4-7 configuration change keeps a consumer binding while its recipe consumes the product", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn", "binding kept")
        H.equal(storage[1].consumer_product_full_names["item/x"], true, "flag kept")
        H.equal(storage[1].product_full_names_by_recipe_name.burn, "item/x", "inverse binding kept")
    end)

    H.test(shape .. " R4-7 a consumer binding goes with its flag once the recipe stops consuming the product", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        --a mod changes burn to take ore, so x is neither its product nor its ingredient
        prototypes.recipe.burn.ingredients = {{type = "item", name = "ore", amount = 1}}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
        H.equal(storage[1].product_full_names_by_recipe_name.burn, nil, "inverse binding dropped")
    end)

    H.test(shape .. " R4-7 a consumer binding whose recipe now makes the product but no longer eats it is dropped", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        prototypes.recipe.burn.ingredients = {{type = "item", name = "ore", amount = 1}}
        prototypes.recipe.burn.products = {H.product(shape, {name = "x", amount = 1})}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped although burn produces x")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
    end)

    H.test(shape .. " R4-7 a consumer binding of a removed recipe goes with its flag", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        world.remove_recipe("burn")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
    end)

    H.test(shape .. " R4-7 a producer binding still needs the product among the recipe's products", function()
        local world = consumer_world(shape)
        world.bind("item/x", "cast")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "cast", "producer binding kept")
        prototypes.recipe.cast.products = {H.product(shape, {name = "y", amount = 1})}
        prototypes.recipe.cast.ingredients = {{type = "item", name = "x", amount = 1}}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "producer binding dropped although cast now eats x")
    end)

    H.test(shape .. " R4-7 saves from before consumer bindings get an empty flag table and keep their bindings", function()
        local world = consumer_world(shape)
        world.bind("item/x", "cast")
        storage[1].consumer_product_full_names = nil
        reconfigure()
        H.equal(next(storage[1].consumer_product_full_names), nil, "empty flag table")
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "cast", "binding kept as a producer")
    end)
end

H.done("test_recycling")
