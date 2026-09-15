--Quality loops crafting with a recipe per tier: a start recipe taking only fluids (casting) with upper tiers crafting from recycled items
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Three qualities. X is cast from 10 molten in a foundry (no items), or assembled from 2 A; X recycles into 2 A at 25% each (0.5 A); A self-recycles
--at 25%. Module q: +0.25 quality. options.no_assembly: X cannot be assembled; options.second_assembly: X also from 3 A in assembler2 (crafting2).
local function tier_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}})
    world.add_item("A")
    world.add_item("X")
    world.add_fluid("molten")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "foundry", categories = {"metallurgy"}, speed = 2, energy_kw = 400, module_slots = 4})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "assembler2", categories = {"crafting2"}, speed = 1, energy_kw = 150, module_slots = 2})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_recipe({name = "X-casting", category = "metallurgy", energy = 2, ingredients = {{type = "fluid", name = "molten", amount = 10}},
        products = {{name = "X", amount = 1}}})
    if not options.no_assembly then
        world.add_recipe({name = "X-assembly", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 2}}, products = {{name = "X", amount = 1}}})
    end
    if options.second_assembly then
        world.add_recipe({name = "X-assembly2", category = "crafting2", energy = 3, ingredients = {{name = "A", amount = 3}}, products = {{name = "X", amount = 1}}})
    end
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 2, p = 0.25}}})
    world.add_recipe({name = "A-recycling", category = "recycling", energy = 0.25, hidden = true, ingredients = {{name = "A", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/X", options.bind or "X-casting")
    world.bind("item/A", "A-mining")
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.QualityLoop = require "logic.quality_loop"
    M.Solver = require "logic.solver"
    M.Sheet = require "gui.sheet"
    M.Report = require "gui.report"
    require "gui.calculator" --registers the report's handlers
    return world
end

local function four(name)
    return {{name = name}, {name = name}, {name = name}, {name = name}}
end

local function L(key)
    return storage[1].quality_loops_by_key[key]
end

--Stores the loop of X at a quality with four q modules on every craft tier and the recycler pool; no_recycle stores it recycling nothing
local function configure(quality, no_recycle)
    local key = M.QualityId.encode("X", quality)
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, {type = "item", name = "X", quality = quality}))
    local loop = L(key)
    for _, settings in pairs(loop.crafts) do settings.setup.modules = four("q") end
    loop.recycle.setup.modules = four("q")
    if no_recycle then
        loop.recycle_recipe_name = nil
        loop.recycle = {setup = {modules = {}, beacons = {}}}
    end
    return key
end

local function solve(key, quality, rate)
    return M.Solver.solve_for({[key] = rate or 1}, 1, {[key] = {type = "item", name = "X", quality = quality}})
end

local function column_of(result, key)
    for _, column in ipairs(result.columns) do
        if column.product_full_name == key then return column end
    end
end

local function handler_sheet(targets)
    local sheet_pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return sheet_flow
end

local function recompute(sheet_flow)
    storage.computation_stack = {}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return H.parse_report(sheet_flow.output_flow)
end

local function fire(element)
    event_handlers.on_gui_elem_changed[element.name]({element = element, player_index = 1})
end

local function find_all(element, name, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = child end
        find_all(child, name, found)
    end
    return found
end

--Craft-by-craft simulation of the QT-1 loop per normal cast: casting at normal takes no A; uncommon and rare assemble 2 A; every X below rare is
--recycled into 0.5 A. All stages have quality effect 1 (10% first roll, then 10% per tier).
local function simulate_qt1()
    local Q = M.QualityLoop
    local probabilities, unlocked = {0.1, 0.1, 0}, {true, true, true}
    local A, X = {0, 0, 0}, {0, 0, 0}
    local crafts, recycles = {0, 0, 0}, {0, 0, 0}
    local casts = 1
    for _ = 1, 4000 do
        local moved = 0
        for u = 1, 3 do
            local n = u == 1 and casts or A[u] / 2
            if u == 1 then casts = 0 else A[u] = A[u] - 2 * n end
            if n > 0 then
                crafts[u] = crafts[u] + n
                for tier, share in pairs(Q.distribution(probabilities, unlocked, u, 1)) do X[tier] = X[tier] + n * share end
                moved = moved + n
            end
        end
        for u = 1, 2 do
            local x = X[u]
            if x > 0 then
                X[u] = 0
                recycles[u] = recycles[u] + x
                for tier, share in pairs(Q.distribution(probabilities, unlocked, u, 1)) do A[tier] = A[tier] + 0.5 * x * share end
                moved = moved + x
            end
        end
        if moved < 1e-15 then break end
    end
    return {crafts = crafts, recycles = recycles, A = A, target = X[3]}
end

H.test("2.0 QT-1 casting at normal, assembling above: the loop runs and matches a craft-by-craft simulation", function()
    tier_world("2.0")
    local key = configure("rare")
    local result = solve(key, "rare")
    H.equal(result.status, "ok", "solved")
    local info = column_of(result, key).quality_loop
    H.equal(info.reason, nil, "no refusal of a start recipe taking only fluids")
    local sim = simulate_qt1()
    for u = 1, 3 do
        H.near_relative(info.tiers[u].crafts * sim.target, sim.crafts[u], "crafts at tier " .. u)
        H.near_relative(info.tiers[u].recycle_crafts * sim.target, sim.recycles[u], "recycles at tier " .. u)
    end
    H.near_relative(result.unsolved_rates["item/A"] * sim.target, -sim.A[1], "returned normal A left over")
    H.equal(M.QualityLoops.stage(1, L(key), "craft", "normal").recipe.name, "X-casting", "normal tier casts")
    H.equal(M.QualityLoops.stage(1, L(key), "craft", "uncommon").recipe.name, "X-assembly", "uncommon tier assembles")
    H.equal(M.QualityLoops.stage(1, L(key), "craft", "rare").machine.name, "assembler", "rare tier on an assembler")
    H.equal(L(key).recycle_recipe_name, "X-recycling", "default recycle recipe found through the tier recipes")

    local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local loop = H.parse_report(sheet_flow.output_flow).loops[key]
    H.equal(loop.tiers[1].craft.machine.name, "foundry", "foundry on the normal row")
    H.equal(loop.tiers[2].craft.machine.name, "assembler", "assembler on the uncommon row")
    local buttons = find_all(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button")
    H.equal(#buttons, 2, "a recipe control on each tier row above the start")
    H.equal(buttons[1].elem_value, "X-assembly", "automatic recipe shown")
end)

H.test("2.0 QT-2 casting only: without recycling a pure quality roll; with recycling the loop names the missing tier recipe", function()
    tier_world("2.0", {no_assembly = true})
    local key = configure("rare", true)
    local result = solve(key, "rare")
    H.equal(result.status, "ok", "solved")
    local info = column_of(result, key).quality_loop
    H.near_relative(info.tiers[1].crafts, 100, "normal casts per rare X: 1 / (0.1 * 0.1)")
    H.equal(info.tiers[2].crafts, 0, "nothing crafted at uncommon")
    H.equal(info.tiers[3].crafts, 0, "nothing crafted at rare")

    local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local pool_button = H.parse_report(sheet_flow.output_flow).loops[key].pool.recycle_button
    pool_button.elem_value = "X-recycling"
    fire(pool_button)
    local report = recompute(sheet_flow)
    H.equal(report.loops[key].reason, "hxrrc.quality_loop_tier_recipe_missing", "reason on the first tier row")
    H.equal(report.loops[key].tiers[1].craft.machines, nil, "no counts")
    assert(report.loops[key].pool.recycle.machine_button, "pool editors kept")
    local tier_buttons = find_all(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button")
    H.equal(#tier_buttons, 2, "tier recipe controls kept, so a recipe can be chosen")
    H.equal(tier_buttons[1].elem_value, nil, "no recipe for uncommon")
end)

H.test("2.0 QT-3 a start quality above normal needs a recipe taking items", function()
    local world = tier_world("2.0")
    local key = configure("rare")
    L(key).start_quality = "uncommon"
    local result = solve(key, "rare")
    H.equal(column_of(result, key).quality_loop.reason, "quality_loop_recipe_without_item_ingredient", "casting cannot start at uncommon")

    L(key).start_quality = nil
    local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local button = H.parse_report(sheet_flow.output_flow).loops[key].recipe_button
    button.elem_value = {name = "X-casting", quality = "uncommon"}
    fire(button)
    H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.start_quality_needs_item_recipe_error", "refusal text")
    H.equal(L(key).start_quality, nil, "start quality unchanged")
    H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X-casting", "binding unchanged")
    H.deep_equal(button.elem_value, {name = "X-casting"}, "restored")
end)

H.test("2.0 QT-4 the tier recipe control: refusal, choice, automatic again, stale and re-fire", function()
    local world = tier_world("2.0", {second_assembly = true, bind = "X-assembly"})
    local key = configure("rare")
    local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local bindings_before = {recipe = storage[1].recipes_by_product_full_name["item/X"].name, owner = storage[1].product_full_names_by_recipe_name["X-assembly2"]}
    local button = find_all(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button")[1]
    H.equal(button.tags.tier, "uncommon", "first control is the uncommon row's")
    H.equal(button.elem_value, "X-assembly", "the producer crafts above the start")

    button.elem_value = "X-casting"
    fire(button)
    H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.tier_recipe_refused_error", "casting refused above normal")
    H.equal(button.elem_value, "X-assembly", "restored")
    H.equal(L(key).crafts.uncommon.recipe_name, nil, "nothing stored")

    button.elem_value = "X-assembly2"
    fire(button)
    H.equal(L(key).crafts.uncommon.recipe_name, "X-assembly2", "chosen")
    H.equal(L(key).crafts.uncommon.machine.name, "assembler2", "machine fitted to the recipe")
    H.equal(#L(key).crafts.uncommon.setup.modules, 2, "setup fitted to the machine's two slots")
    H.equal(storage[1].recipes_by_product_full_name["item/X"].name, bindings_before.recipe, "item binding unchanged")
    H.equal(storage[1].product_full_names_by_recipe_name["X-assembly2"], bindings_before.owner, "recipe owner unchanged")
    fire(button)
    H.equal(L(key).crafts.uncommon.recipe_name, "X-assembly2", "re-fire is a no-op")

    local report = recompute(sheet_flow)
    button = find_all(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button")[1]
    H.equal(button.elem_value, "X-assembly2", "shown after recompute")
    H.equal(report.loops[key].tiers_by_quality.uncommon.craft.machine.name, "assembler2", "row shows the fitted machine")
    button.elem_value = nil
    fire(button)
    H.equal(L(key).crafts.uncommon.recipe_name, nil, "emptied: automatic again")
    H.equal(button.tags.shown, "X-assembly", "automatic recipe shown")

    recompute(sheet_flow)
    button = find_all(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button")[1]
    L(key).start_quality = "uncommon"
    button.elem_value = "X-assembly2"
    fire(button)
    H.equal(L(key).crafts.uncommon.recipe_name, nil, "stale after the start quality rose: refused")
    H.equal(button.elem_value, "X-assembly", "restored")
end)

H.test("2.0 QT-5 tier recipes after a configuration change, and the default recycle recipe", function()
    local world = tier_world("2.0", {second_assembly = true})
    local key = configure("rare")
    --two assembly recipes: no automatic tier recipe, so no default recycle recipe either; both set by hand
    H.equal(L(key).recycle_recipe_name, nil, "no default with an ambiguous tier recipe")
    L(key).recycle_recipe_name = "X-recycling"
    L(key).crafts.uncommon.recipe_name = "X-assembly2"
    world.remove_recipe("X-assembly2")
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
    H.equal(L(key).crafts.uncommon.recipe_name, nil, "removed recipe cleared")
    local once = M.QualityLoops._deep_copy(L(key))
    require("logic.player_data_updater").reinitialize(1)
    H.deep_equal(L(key), once, "second reinitialize changes nothing")
    H.equal(L(key).recycle_recipe_name, "X-recycling", "stored recycle recipe kept")

    world.remove_recipe("X-assembly")
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
    local fresh = M.QualityId.encode("X", "uncommon")
    local config = M.QualityLoops.normalized(1, fresh, {type = "item", name = "X", quality = "uncommon"})
    H.equal(config.recycle_recipe_name, nil, "no item recipe above normal: nothing recycles into a casting, no default")
end)

H.test("2.0 QT-6 power: every tier draws with its own recipe and machine", function()
    tier_world("2.0")
    local key = configure("rare")
    local result = solve(key, "rare", 2)
    local info = column_of(result, key).quality_loop
    local rate = result.recipe_rates[column_of(result, key).recipe_name]
    --q modules change no speed or consumption: foundry 2 s per cast at speed 2, 400 kW; assembler 1 s at 100 kW; recycler 0.5 s at 50 kW
    local expected = info.tiers[1].crafts * rate * 2 / 2 * 400e3
        + (info.tiers[2].crafts + info.tiers[3].crafts) * rate * 1 * 100e3
        + (info.tiers[1].recycle_crafts + info.tiers[2].recycle_crafts) * rate * 0.5 * 50e3
    local energy = require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates)
    H.near_relative(energy, expected, "electric power")
end)

H.done("test_quality_tier_recipes")
