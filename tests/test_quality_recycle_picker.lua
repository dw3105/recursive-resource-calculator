--The loop's recycle recipe control: it lists only recipes that can recycle the item, and excess rows of a loop's own item hold that control
--instead of a consumer or burner control
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Two qualities (normal, uncommon). A -> X in an assembler; X -> 0.25 A in a recycler (category recycling); X -> gold (category sorting, a second
--eligible category); the recycler building takes X and Y (category crafting: takes X, cannot recycle it). Z -> made from A, consumed only with Y.
local function picker_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    world.add_item("A")
    world.add_item("X", options.x_fuel and {value = 1000000, category = "chemical"} or nil)
    world.add_item("Y")
    world.add_item("Z")
    world.add_item("gold")
    world.add_item("recycler-item")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_machine({name = "sorter", categories = {"sorting"}, speed = 1, energy_kw = 50, module_slots = 0})
    world.add_recipe({name = "X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "X-sorting-2", category = "sorting", energy = 1, ingredients = {{name = "X", amount = 1}}, products = {{name = "gold", amount = 1}}})
    world.add_recipe({name = "recycler-building", category = "crafting", energy = 1, ingredients = {{name = "X", amount = 1}, {name = "Y", amount = 1}},
        products = {{name = "recycler-item", amount = 1}}})
    world.add_recipe({name = "Z", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "Z", amount = 1}}})
    world.add_recipe({name = "Z-plus", category = "crafting", energy = 1, ingredients = {{name = "Z", amount = 1}, {name = "Y", amount = 1}},
        products = {{name = "gold", amount = 1}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_recipe({name = "Y-mining", category = "mining", ingredients = {}, products = {{name = "Y", amount = 1}}})
    if options.chain then world.set_quality_chain(options.chain) end
    if options.extra then options.extra(world) end
    if options.x_fuel then
        world.add_burner({name = "tower", type = "reactor", energy_kw = 1000, emissions_per_joule = {}, burner = {fuel_categories = {"chemical"}}})
    end
    world.add_player(1)
    world.init()
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.Sheet = require "gui.sheet"
    require "gui.calculator" --registers the report's handlers
    return world
end

local function four(name)
    return {{name = name}, {name = name}, {name = name}, {name = name}}
end

--Stores the valid configuration of an item's loop with four q modules on every craft tier and the recycler pool
local function configure(item, quality, no_recycle)
    local key = M.QualityId.encode(item, quality)
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, {type = "item", name = item, quality = quality}))
    local loop = storage[1].quality_loops_by_key[key]
    for _, settings in pairs(loop.crafts) do settings.setup.modules = four("q") end
    loop.recycle.setup.modules = four("q")
    if no_recycle then
        loop.recycle_recipe_name = nil
        loop.recycle = {setup = {modules = {}, beacons = {}}}
    end
    return key
end

--A sheet the registered handlers can recompute: its pane is the player's sheet pane, and computations run at once
local function handler_sheet(targets)
    local sheet_pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return sheet_flow
end

local function parse(sheet_flow)
    return H.parse_report(sheet_flow.output_flow)
end

local function fire(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function recompute(sheet_flow)
    storage.computation_stack = {}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return parse(sheet_flow)
end

--Buttons of one name anywhere under an element
local function find_all(element, name, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = child end
        find_all(child, name, found)
    end
    return found
end

--The numbers a report shows, without its GUI elements: rows by product, loop tier and pool counts
local function numbers(report)
    local summary = {rows = {}, loops = {}, energy = report.energy_mw}
    for name, row in pairs(report.rows) do summary.rows[name] = {rate = row.rate, kind = row.kind, machines = row.machines} end
    for key, loop in pairs(report.loops) do
        local tiers = {}
        for index, tier in ipairs(loop.tiers) do
            tiers[index] = {quality = tier.quality, rate = tier.rate, craft = tier.craft and tier.craft.machines, recycle = tier.recycle and tier.recycle.machines}
        end
        summary.loops[key] = {tiers = tiers, pool = loop.pool and loop.pool.recycle and loop.pool.recycle.machines}
    end
    return summary
end

H.test("2.0 QM-1 the recycler pool's recipe control lists only recipes that can recycle the item", function()
    picker_world("2.0")
    local key = configure("X", "uncommon")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local button = report.loops[key].pool.recycle_button
    H.equal(button.name, "hxrrc_choose_recycle_recipe_button", "pool recycle control")
    H.deep_equal(H.recipes_matching(button.elem_filters), {"X-recycling", "X-sorting-2"}, "listed recipes")
    H.equal(button.enabled, true, "enabled")
    H.equal(button.elem_value, "X-recycling", "default recycle recipe still shown")
end)

H.test("2.0 QM-2 an item no recipe can recycle: the pool's recipe control is disabled with a hint", function()
    picker_world("2.0")
    local key = configure("Z", "uncommon")
    local report = H.run_sheet({{item = "Z", quality = "uncommon", rate = 1, unit = "/s"}})
    local button = report.loops[key].pool.recycle_button
    H.equal(button.enabled, false, "disabled")
    H.deep_equal(button.tooltip, {"hxrrc.no_recycle_recipe_tooltip"}, "hint")
    H.equal(button.elem_value, nil, "no recycle recipe")
end)

H.test("2.0 QM-3 excess of a loop's own item: the row holds the loop's recycle control, no consumer or burner, and picking there keeps the loop", function()
    local function start()
        picker_world("2.0", {x_fuel = true})
        local key = configure("X", "uncommon", true)
        return key, handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    end
    local key, sheet_flow = start()
    local row = parse(sheet_flow).rows["item/X"]
    H.equal(row.kind, "hxrrc.byproduct", "normal X left over")
    local pickers = find_all(row.recipe_cell, "hxrrc_choose_recycle_recipe_button")
    H.equal(#pickers, 1, "one recycle control")
    H.equal(pickers[1].tags.loop_key, key, "for the loop")
    H.equal(#find_all(row.recipe_cell, "hxrrc_choose_recipe_button"), 0, "no consumer control")
    H.equal(#find_all(row.recipe_cell, "hxrrc_choose_burner_button"), 0, "no burner control although X burns")
    pickers[1].elem_value = "X-recycling"
    fire(pickers[1])
    local report = recompute(sheet_flow)
    H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X", "craft recipe still bound")
    H.equal(storage[1].consumer_product_full_names["item/X"], nil, "not a consumer")
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, "X-recycling", "loop recycles")
    H.equal(report.rows["item/X"], nil, "no excess X row")
    local from_excess_row = numbers(report)

    key, sheet_flow = start()
    local pool_button = parse(sheet_flow).loops[key].pool.recycle_button
    pool_button.elem_value = "X-recycling"
    fire(pool_button)
    H.deep_equal(from_excess_row, numbers(recompute(sheet_flow)), "same as picking on the pool row")
end)

H.test("2.0 QM-4 two loops leaving the same item over: one recycle control per loop, each changing only its loop", function()
    picker_world("2.0", {chain = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}}})
    local uncommon_key = configure("X", "uncommon", true)
    --two loops that only craft at normal leave uncommon and rare X in the same proportion, a singular system: the rare loop recycles
    local rare_key = configure("X", "rare")
    local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local row = parse(sheet_flow).rows["item/X"]
    local pickers = find_all(row.recipe_cell, "hxrrc_choose_recycle_recipe_button")
    H.equal(#pickers, 2, "two recycle controls")
    H.equal(pickers[1].parent == pickers[2].parent, false, "each in its own flow")
    local keys = {[pickers[1].tags.loop_key] = true, [pickers[2].tags.loop_key] = true}
    H.equal(keys[uncommon_key] and keys[rare_key], true, "one per loop")
    local second = pickers[2]
    local other = second.tags.loop_key == rare_key and uncommon_key or rare_key
    local other_before = storage[1].quality_loops_by_key[other].recycle_recipe_name
    local picked = second.elem_value == nil and "X-recycling" or "X-sorting-2"
    second.elem_value = picked
    fire(second)
    H.equal(storage[1].quality_loops_by_key[second.tags.loop_key].recycle_recipe_name, picked, "picked loop changed")
    H.equal(storage[1].quality_loops_by_key[other].recycle_recipe_name, other_before, "other loop unchanged")
end)

H.test("2.0 QM-5 a stale recycle control on the excess row is refused and restored", function()
    picker_world("2.0")
    local key = configure("X", "uncommon", true)
    local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local report = parse(sheet_flow)
    local Report = require "gui.report"
    local pool_button = report.loops[key].pool.recycle_button
    local excess_button = find_all(report.rows["item/X"].recipe_cell, "hxrrc_choose_recycle_recipe_button")[1]
    pool_button.elem_value = "X-recycling"
    H.equal(Report.handle_recycle_recipe_change({element = pool_button, player_index = 1}), true, "pool pick without recompute")
    excess_button.elem_value = "X-sorting-2"
    H.equal(Report.handle_recycle_recipe_change({element = excess_button, player_index = 1}), false, "stale pick refused")
    H.equal(excess_button.elem_value, nil, "restored")
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, "X-recycling", "loop keeps its recycle recipe")
end)

--gold is made from A with X or Y left over; X burns, Y burns
local function byproduct_recipes(world)
    world.add_recipe({name = "gold-with-X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}},
        products = {{name = "gold", amount = 1}, {name = "X", amount = 1}}})
    world.add_recipe({name = "gold-with-Y", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}},
        products = {{name = "gold", amount = 1}, {name = "Y", amount = 1}}})
end

H.test("2.1 QM-6 a 2.1 loop recycles nothing: excess of its item keeps the consumer control", function()
    picker_world("2.1", {extra = byproduct_recipes})
    storage[1].recipes_by_product_full_name["item/gold"] = prototypes.recipe["gold-with-X"]
    storage[1].product_full_names_by_recipe_name["gold-with-X"] = "item/gold"
    storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.X
    storage[1].product_full_names_by_recipe_name.X = "item/X"
    local Solver = require "logic.solver"
    local result = Solver.solve_for({["item/gold"] = 1}, 1, {})
    H.near(result.unsolved_rates["item/X"], -1, "X left over by gold")
    local key = M.QualityId.encode("X", "uncommon")
    local column = Solver._loop_column(1, key, {type = "item", name = "X", quality = "uncommon"}, result.product_parts)
    H.equal(column.quality_loop.reason, "quality_loop_unavailable", "2.1 loop")
    table.insert(result.columns, column)
    result.reasons_by_column[column.recipe_name] = column.quality_loop.reason
    local output_flow = H.gui_root({type = "flow", name = "output_flow"})
    require("gui.report").new(output_flow, result, 0, 0)
    local row = H.parse_report(output_flow).rows["item/X"]
    H.equal(row.kind, "hxrrc.byproduct", "X left over")
    H.equal(row.recipe_button.name, "hxrrc_choose_recipe_button", "consumer control")
    H.equal(row.recipe_button.tags.consumer, true, "consumer tag")
end)

H.test("2.0 QM-7 excess of another item on a loop's sheet keeps its consumer and burner controls", function()
    local world = picker_world("2.0", {extra = function(w)
        byproduct_recipes(w)
        w.add_item("Y", {value = 1000000, category = "chemical"})
    end, x_fuel = true})
    storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.X
    storage[1].product_full_names_by_recipe_name.X = "item/X"
    storage[1].recipes_by_product_full_name["item/gold"] = prototypes.recipe["gold-with-Y"]
    storage[1].product_full_names_by_recipe_name["gold-with-Y"] = "item/gold"
    configure("X", "uncommon", true)
    local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "gold", rate = 1, unit = "/s"}})
    local row = parse(sheet_flow).rows["item/Y"]
    H.equal(row.kind, "hxrrc.byproduct", "Y left over")
    H.equal(row.recipe_button.name, "hxrrc_choose_recipe_button", "consumer control")
    H.equal(row.burner_button and row.burner_button.name, "hxrrc_choose_burner_button", "burner control")
end)

M.picker_world, M.configure = picker_world, configure

H.done("test_quality_recycle_picker")
