--Excess items and fluids burnt as fuel in reactors, boilers and burner generators: rates, counts, pollution, bindings and their checks
local H = require "tests.harness"

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

local function recompute(sheet_pane)
    require("gui.sheet").calculate(nil, sheet_pane, 1)
    return H.parse_report(sheet_pane.tabs[1].content.output_flow)
end

local function fire_elem_changed(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function pick(button, value)
    button.elem_value = value
    fire_elem_changed(button)
end

--A world whose "make" recipe turns raw into one target and `excess` of a product; the assembler draws 210 kW and emits nothing
local function excess_world(shape, excess)
    local world = H.new_world(shape)
    require "gui.calculator" --registers the event handlers the tests fire
    world.add_item("raw")
    world.add_item("target")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, pollution_per_minute = 0})
    return world, function()
        world.add_recipe({name = "make", category = "crafting", ingredients = {{name = "raw", amount = 1}},
            products = {{name = "target", amount = 1}, excess}})
        world.add_player(1)
        world.init()
        world.bind("item/target", "make")
        local report, sheet_pane = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        storage[1].sheet_section = {sheet_pane = sheet_pane}
        return report, sheet_pane
    end
end

local TOWER_EMISSIONS = 100 / (40e6 * 60) --100 per minute at a full 40 MW

local function add_tower(world, name, burnt_inventory_size)
    world.add_burner({name = name or "tower", type = "reactor", energy_kw = 40000, emissions_per_joule = {pollution = TOWER_EMISSIONS},
        burner = {fuel_categories = {"chemical"}, effectivity = 2.5, burnt_inventory_size = burnt_inventory_size or 0}})
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " A-1 excess solid fuel burnt in heating towers: rate, tower count, no electricity, 100 pollution per minute per tower", function()
        local world, start = excess_world(shape, {name = "solid-fuel", amount = 2})
        world.add_item("solid-fuel", {value = 12e6, category = "chemical"})
        add_tower(world)
        local report, sheet_pane = start()
        H.equal(report.rows["item/solid-fuel"].kind, "hxrrc.byproduct", "excess before burning")
        local button = report.rows["item/solid-fuel"].burner_button
        H.equal(button.name, "hxrrc_choose_burner_button", "byproduct row offers burning")
        H.equal(table.concat(button.elem_filters[1].name, ","), "tower", "only the tower accepts chemical fuel")
        pick(button, {name = "tower"})
        report = recompute(sheet_pane)
        local row = report.rows["item/solid-fuel"]
        H.equal(row.kind, "burner", "burner row")
        H.near(row.rate, -2, "two fuel per second burnt")
        H.near(row.machines, 2 * 12 / 16, "towers: 24 MW of fuel over 40 MW / 2.5 each")
        H.near(report.energy_mw, 0.21, "towers draw no electricity")
        H.near(report.pollution_per_minute, 150, "1.5 towers at 100 per minute")
        H.equal(row.recipe_button.tags.consumer, true, "burner row can switch to a consumer recipe")
        H.equal(row.burner_button.elem_value.name, "tower", "and shows its burner")
    end)

    H.test(shape .. " A-1b fuel emissions multipliers scale burner pollution only; a burner without a pollution key emits none", function()
        for _, case in ipairs({{0, 0}, {1, 150}, {2, 300}}) do
            local world, start = excess_world(shape, {name = "solid-fuel", amount = 2})
            world.add_item("solid-fuel", {value = 12e6, category = "chemical", emissions_multiplier = case[1]})
            add_tower(world)
            local report, sheet_pane = start()
            pick(report.rows["item/solid-fuel"].burner_button, {name = "tower"})
            report = recompute(sheet_pane)
            H.near(report.rows["item/solid-fuel"].machines, 1.5, "multiplier " .. case[1] .. ": count unchanged")
            H.near(report.pollution_per_minute, case[2], "multiplier " .. case[1] .. ": pollution")
        end
        local world, start = excess_world(shape, {name = "solid-fuel", amount = 2})
        world.add_item("solid-fuel", {value = 12e6, category = "chemical"})
        world.add_burner({name = "clean", type = "reactor", energy_kw = 40000, emissions_per_joule = {},
            burner = {fuel_categories = {"chemical"}, effectivity = 2.5}})
        local report, sheet_pane = start()
        pick(report.rows["item/solid-fuel"].burner_button, {name = "clean"})
        report = recompute(sheet_pane)
        H.near(report.pollution_per_minute, 0, "no pollution key: no pollution")
    end)

    H.test(shape .. " A-2 the burnt result of burnt fuel is processed once it gets a consumer recipe or a burner of its own", function()
        local world, start = excess_world(shape, {name = "f", amount = 2})
        world.add_item("f", {value = 10e6, category = "chemical"})
        world.add_item("g", {value = 5e6, category = "chemical"})
        world.add_item("h")
        world.add_item("slag")
        world.set_burnt_result("f", "g")
        --two products, so neither is bound to g-melt on its own
        world.add_recipe({name = "g-melt", category = "crafting", ingredients = {{name = "g", amount = 1}},
            products = {{name = "h", amount = 1}, {name = "slag", amount = 1}}})
        add_tower(world, "tower", 1)
        local report, sheet_pane = start()
        pick(report.rows["item/f"].burner_button, {name = "tower"})
        report = recompute(sheet_pane)
        H.near(report.rows["item/g"].rate, -2, "one g left per f burnt")
        H.equal(report.rows["item/g"].kind, "hxrrc.byproduct", "g is excess")

        pick(report.rows["item/g"].recipe_button, "g-melt")
        report = recompute(sheet_pane)
        H.equal(report.rows["item/g"].kind, "solved", "g consumed by g-melt")
        H.near(report.rows["item/g"].rate, -2, "g consumed")
        H.near(report.rows["item/g"].machines, 2, "g-melt assemblers")
        H.near(report.rows["item/h"].rate, -2, "g-melt's outputs show up")
        H.near(report.rows["item/slag"].rate, -2, "both of them")
        H.near(report.rows["item/f"].machines, 2 * 10 * 2.5 / 40, "f towers (1.25)")
        H.near(report.energy_mw, 0.21 * 3, "make and two g-melt")
        H.near(report.pollution_per_minute, 125, "f towers only")

        pick(report.rows["item/g"].burner_button, {name = "tower"})
        H.equal(storage[1].recipes_by_product_full_name["item/g"], nil, "burning g replaced g-melt")
        report = recompute(sheet_pane)
        H.equal(report.rows["item/g"].kind, "burner", "g burnt")
        H.near(report.rows["item/g"].machines, 2 * 5 * 2.5 / 40, "g towers (0.625)")
        H.equal(report.rows["item/h"], nil, "no h any more")
        H.near(report.energy_mw, 0.21, "make only")
        H.near(report.pollution_per_minute, 125 + 62.5, "f and g towers")
    end)

    H.test(shape .. " A-2b fuels burning into each other terminate the walk and report no single answer", function()
        local world, start = excess_world(shape, {name = "f", amount = 1})
        world.add_item("f", {value = 10e6, category = "chemical"})
        world.add_item("g", {value = 10e6, category = "chemical"})
        world.set_burnt_result("f", "g")
        world.set_burnt_result("g", "f")
        add_tower(world, "tower", 1)
        local _, sheet_pane = start()
        storage[1].burners_by_product_full_name["item/f"] = {name = "tower"}
        storage[1].burners_by_product_full_name["item/g"] = {name = "tower"}
        local report = recompute(sheet_pane)
        H.equal(report.energy_caption, "hxrrc.system_with_no_solution_error", "unsolvable")
        H.equal(report.rows["item/f"].kind, "burner", "f burner row listed")
        H.equal(report.rows["item/g"].kind, "burner", "g burner row listed")
        H.equal(report.rows["item/g"].burner_button.elem_value.name, "tower", "editable")
    end)

    H.test(shape .. " A-3 fluid burners: scaled, unscaled, capped, uncapped and underpowered draw and pollution", function()
        local world, start = excess_world(shape, {type = "fluid", name = "waste", amount = 60})
        world.add_fluid("waste", {value = 1e6})
        world.add_fluid("steam")
        local function boiler(name, fluid)
            world.add_burner({name = name, type = "boiler", energy_kw = 1000, emissions_per_joule = {pollution = 1e-6}, fluid = fluid})
        end
        boiler("scaled", {scale_fluid_usage = true, fluid_usage_per_tick = 1})
        boiler("unscaled", {fluid_usage_per_tick = 1})
        boiler("capped", {scale_fluid_usage = true, fluid_usage_per_tick = 1 / 64})
        boiler("uncapped", {scale_fluid_usage = true})
        boiler("under", {fluid_usage_per_tick = 1 / 128})
        boiler("unscaled-zero", {})
        boiler("filtered", {scale_fluid_usage = true, filter = "steam"})
        local report, sheet_pane = start()
        H.equal(table.concat(report.rows["fluid/waste"].burner_button.elem_filters[1].name, ","), "capped,scaled,uncapped,under,unscaled",
            "undefined draw and a filter for another fluid are not offered")
        for _, case in ipairs({{"scaled", 60, 60}, {"unscaled", 1, 1}, {"capped", 64, 60}, {"uncapped", 60, 60}, {"under", 128, 60}}) do
            pick(report.rows["fluid/waste"].burner_button, {name = case[1]})
            report = recompute(sheet_pane)
            H.near(report.rows["fluid/waste"].rate, -60, case[1] .. ": all waste burnt")
            H.near(report.rows["fluid/waste"].machines, case[2], case[1] .. ": entities")
            H.near(report.pollution_per_minute, case[3] * 60, case[1] .. ": pollution on delivered energy")
        end
    end)

    H.test(shape .. " A-3 a fluid's emissions multiplier combines with a binding cap", function()
        local world, start = excess_world(shape, {type = "fluid", name = "waste", amount = 60})
        world.add_fluid("waste", {value = 1e6, emissions_multiplier = 2})
        world.add_burner({name = "capped", type = "boiler", energy_kw = 1000, emissions_per_joule = {pollution = 1e-6},
            fluid = {scale_fluid_usage = true, fluid_usage_per_tick = 1 / 64}})
        local report, sheet_pane = start()
        pick(report.rows["fluid/waste"].burner_button, {name = "capped"})
        report = recompute(sheet_pane)
        H.near(report.rows["fluid/waste"].machines, 64, "entities")
        H.near(report.pollution_per_minute, 120 * 60, "60 MW delivered, doubled")
    end)

    H.test(shape .. " A-4 burning and recipe bindings replace each other", function()
        local world, start = excess_world(shape, {name = "x", amount = 1})
        world.add_item("x", {value = 1e6, category = "chemical"})
        world.add_item("ore")
        world.add_recipe({name = "burn-x", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {}})
        world.add_recipe({name = "cast", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "x", amount = 1}}})
        add_tower(world)
        local report, sheet_pane = start()
        local player_storage = storage[1]

        pick(report.rows["item/x"].recipe_button, "burn-x")
        report = recompute(sheet_pane)
        H.equal(report.rows["item/x"].burner_button.name, "hxrrc_choose_burner_button", "a consumer row offers burning too")
        pick(report.rows["item/x"].burner_button, {name = "tower"})
        H.equal(player_storage.recipes_by_product_full_name["item/x"], nil, "consumer binding cleared")
        H.equal(player_storage.consumer_product_full_names["item/x"], nil, "consumer flag cleared")
        H.equal(player_storage.product_full_names_by_recipe_name["burn-x"], nil, "burn-x released")
        H.equal(player_storage.burners_by_product_full_name["item/x"].name, "tower", "burner set")

        report = recompute(sheet_pane)
        pick(report.rows["item/x"].recipe_button, "burn-x")
        H.equal(player_storage.burners_by_product_full_name["item/x"], nil, "a consumer pick clears the burner")
        H.equal(player_storage.recipes_by_product_full_name["item/x"].name, "burn-x", "consumer bound")

        pick(report.rows["item/x"].recipe_button, nil)
        world.bind("item/x", "cast")
        report = recompute(sheet_pane)
        local burner_button = report.rows["item/x"].burner_button
        storage.computation_stack = {}
        pick(burner_button, nil)
        H.equal(player_storage.recipes_by_product_full_name["item/x"].name, "cast", "clearing an empty burner button keeps the producer")
        H.equal(#storage.computation_stack, 0, "nothing queued")
    end)

    H.test(shape .. " A-5 a product nothing offered can burn gets no burner button", function()
        local world, start = excess_world(shape, {name = "rock", amount = 1})
        world.add_item("rock")
        world.add_item("food", {value = 1e6, category = "nutrients"})
        world.add_item("waste")
        add_tower(world)
        world.add_burner({name = "bio-assembler", type = "assembling-machine", energy_kw = 100, burner = {fuel_categories = {"nutrients"}}})
        world.add_burner({name = "train", type = "locomotive", energy_kw = 600, burner = {fuel_categories = {"nutrients"}}})
        world.add_recipe({name = "waste-food", category = "crafting", ingredients = {{name = "rock", amount = 1}},
            products = {{name = "food", amount = 1}, {name = "waste", amount = 1}}})
        local report = start()
        H.equal(report.rows["item/rock"].burner_button, nil, "no fuel value: no burner button")
        local Burners = require "logic.burners"
        H.equal(#Burners.accepted_names("item/food"), 0, "nutrients only burn in a crafting machine or a locomotive: not offered")
        H.equal(Burners.accepts("train", "item/food"), false, "locomotive refused")
    end)

    H.test(shape .. " A-6 configuration change drops burner bindings that can no longer burn, and drops a removed quality", function()
        for _, case in ipairs({"entity removed", "fuel category changed", "fuel value removed", "quality removed"}) do
            local world, start = excess_world(shape, {name = "fuel", amount = 1})
            world.add_item("fuel", {value = 1e6, category = "chemical"})
            add_tower(world)
            start()
            storage[1].burners_by_product_full_name["item/fuel"] = {name = "tower", quality = "rare"}
            if case == "entity removed" then
                prototypes.entity.tower = nil
            elseif case == "fuel category changed" then
                prototypes.item.fuel.fuel_category = "nuclear"
            elseif case == "fuel value removed" then
                prototypes.item.fuel.fuel_value = 0
            else
                world.remove_quality("rare")
            end
            reconfigure()
            local binding = storage[1].burners_by_product_full_name["item/fuel"]
            if case == "quality removed" then
                H.equal(binding.name, "tower", case .. ": binding kept")
                H.equal(binding.quality, nil, case .. ": falls back to normal")
            else
                H.equal(binding, nil, case .. ": binding dropped")
            end
        end
    end)

    H.test(shape .. " A-7 a stale burner entity button refuses changes and restores once, and emptying is refused", function()
        local world, start = excess_world(shape, {name = "fuel", amount = 1})
        world.add_item("fuel", {value = 12e6, category = "chemical"})
        add_tower(world)
        add_tower(world, "tower-2")
        local report, pane_a = start()
        pick(report.rows["item/fuel"].burner_button, {name = "tower"})
        report = recompute(pane_a)
        local entity_button = report.rows["item/fuel"].machine_button
        H.equal(entity_button.name, "hxrrc_choose_burner_entity_button", "burner entity button")

        pick(entity_button, nil)
        H.equal(entity_button.elem_value.name, "tower", "emptying refused")
        H.equal(world.flying_texts[1][1], "hxrrc.cannot_empty_a_choose_crafting_machine_button_error", "message")

        pick(entity_button, {name = "tower-2"})
        H.equal(storage[1].burners_by_product_full_name["item/fuel"].name, "tower-2", "current button changes the entity")
        H.equal(entity_button.tags.name, "tower-2", "snapshot follows")

        local _, pane_b = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
        local report_b = H.parse_report(pane_b.tabs[1].content.output_flow)
        pick(report_b.rows["item/fuel"].burner_button, nil) --cleared through the other sheet
        storage.computation_stack = {}
        H.refire_on_script_set = true
        entity_button.elem_value = {name = "tower"}
        H.equal(entity_button.elem_value.name, "tower-2", "stale button restored without a loop")
        H.equal(storage[1].burners_by_product_full_name["item/fuel"], nil, "binding stays cleared")
        H.equal(#storage.computation_stack, 0, "nothing queued")
    end)

    H.test(shape .. " A-8 a burner driven backwards is infeasible with its editors, also next to a column of tiny yield", function()
        for _, with_trace in ipairs({false, true}) do
            local world = H.new_world(shape)
            require "gui.calculator"
            world.add_item("raw")
            world.add_item("target")
            world.add_item("trace")
            world.add_item("trace-ore")
            world.add_item("fuel", {value = 12e6, category = "chemical"})
            world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
            local ingredients = {{name = "raw", amount = 1}, {name = "fuel", amount = 1}}
            if with_trace then ingredients[3] = {name = "trace", amount = 1} end
            world.add_recipe({name = "make", category = "crafting", ingredients = ingredients, products = {{name = "target", amount = 1}}})
            world.add_recipe({name = "trace-make", category = "crafting", ingredients = {{name = "trace-ore", amount = 1}},
                products = {{name = "trace", amount = 1, p = 1e-12}}})
            add_tower(world)
            world.add_player(1)
            world.init()
            storage[1].burners_by_product_full_name["item/fuel"] = {name = "tower"}
            local what = with_trace and "with a trace column" or "alone"
            local report = H.run_sheet({{item = "target", rate = 1, unit = "/s"}})
            H.equal(report.rows["item/fuel"].reason, "hxrrc.recipe_runs_backwards", what .. ": the needed fuel cannot be burnt")
            H.equal(report.energy_caption, "hxrrc.totals_unavailable", what .. ": no totals")
            H.equal(report.rows["item/fuel"].machine_button.name, "hxrrc_choose_burner_entity_button", what .. ": entity editor present")
            H.equal(report.rows["item/fuel"].burner_button.elem_value.name, "tower", what .. ": burner editor present")
        end
    end)

    H.test(shape .. " A-9 a modded reactor with its own fuel category burns faster at a better quality", function()
        local world, start = excess_world(shape, {name = "pellet", amount = 4})
        world.add_item("pellet", {value = 1e6, category = "biomass"})
        world.add_burner({name = "bio-reactor", type = "reactor", energy_kw = 1000, energy_kw_by_quality = {rare = 2000},
            burner = {fuel_categories = {"biomass"}}})
        local report, sheet_pane = start()
        pick(report.rows["item/pellet"].burner_button, {name = "bio-reactor"})
        report = recompute(sheet_pane)
        H.near(report.rows["item/pellet"].machines, 4, "normal reactors")
        pick(report.rows["item/pellet"].machine_button, {name = "bio-reactor", quality = "rare"})
        H.equal(storage[1].burners_by_product_full_name["item/pellet"].quality, "rare", "quality stored")
        report = recompute(sheet_pane)
        H.near(report.rows["item/pellet"].machines, 2, "rare reactors draw twice as much")
    end)

    if shape == "2.1" then
        H.test("2.1 A-3b fluid sources that give spent fluid through an output box are not offered", function()
            local world, start = excess_world(shape, {type = "fluid", name = "waste", amount = 60})
            world.add_fluid("steam")
            world.add_fluid("waste", {value = 1e6, spent_fluid = {name = "steam", amount = 1}})
            world.add_burner({name = "out-own", type = "boiler", energy_kw = 1000,
                fluid = {scale_fluid_usage = true, output_fluid_box = true, spent_fluid = {name = "steam", amount = 1}}})
            world.add_burner({name = "out-fallback", type = "boiler", energy_kw = 1000, fluid = {scale_fluid_usage = true, output_fluid_box = true}})
            world.add_burner({name = "no-out", type = "boiler", energy_kw = 1000, fluid = {scale_fluid_usage = true}})
            local report = start()
            H.equal(table.concat(report.rows["fluid/waste"].burner_button.elem_filters[1].name, ","), "no-out", "only the source without an output box")
        end)
    else
        H.test(shape .. " A-3b the 2.0 fluid source is never asked for an output fluid box", function()
            local world, start = excess_world(shape, {type = "fluid", name = "waste", amount = 60})
            world.add_fluid("waste", {value = 1e6})
            world.add_burner({name = "no-out", type = "boiler", energy_kw = 1000, fluid = {scale_fluid_usage = true}})
            local report = start() --the 2.0 source mock throws on output_fluid_box
            H.equal(table.concat(report.rows["fluid/waste"].burner_button.elem_filters[1].name, ","), "no-out", "offered")
        end)
    end
end

H.done("test_burning")
