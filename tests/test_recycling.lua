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

--Every locale key the code names exists in every language, reasons included
H.test("R4 locale has every key the code names, in every language", function()
    local keys = {}
    for _, file in ipairs({"gui/report.lua", "gui/sheet.lua", "gui/modulegui.lua", "gui/input_container.lua", "gui/calculator.lua", "logic/solver.lua"}) do
        local source = io.open(file):read("*a")
        for key in source:gmatch('"hxrrc%.([%w_]+)"') do keys[key] = true end
        for key in source:gmatch('reasons_by_column%[[%w_.]+%] = "([%w_]+)"') do keys[key] = true end
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
        button.elem_value = {name = "fast-assembler"}
        fire_elem_changed(button)
        H.equal(chosen.a.name, "fast-assembler", "change applies to a")
        H.equal(button.tags.recipe_name, "a", "tags keep the row after a change")
        H.equal(button.tags.name, "fast-assembler", "snapshot follows the change")

        pick_recipe(report, "item/gear", "b")
        storage.computation_stack = {}
        button.elem_value = {name = "assembler"}
        fire_elem_changed(button)
        H.equal(chosen.a.name, "fast-assembler", "a unchanged by the stale button")
        H.equal(chosen.b.name, "assembler", "b unchanged: the neighbour recipe button already shows b")
        H.equal(button.elem_value.name, "fast-assembler", "stale button restored")
        H.equal(#storage.computation_stack, 0, "nothing queued")

        report = recompute(sheet_pane)
        local untagged = report.rows["item/gear"].machine_button
        untagged.tags = {name = "assembler"} --a button built before rows were tagged
        untagged.elem_value = {name = "fast-assembler"}
        fire_elem_changed(untagged)
        H.equal(chosen.b.name, "assembler", "untagged button refused")
        H.equal(untagged.elem_value.name, "assembler", "untagged button restored")
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
