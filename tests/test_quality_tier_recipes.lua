--Quality loops crafting with a recipe per tier: a start recipe taking only fluids (casting) with upper tiers crafting from recycled items
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Three qualities. X is cast from 10 molten in a foundry (no items), or assembled from 2 A; X recycles into 2 A at 25% each (0.5 A); A self-recycles
--at 25%. Module q: +0.25 quality. options.no_assembly: X cannot be assembled; options.second_assembly: X also from 3 A in assembler2 (crafting2).
local function tier_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    if options.two_tiers then
        world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    else
        world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}})
    end
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
    if options.a_recycling_category then
        world.add_machine({name = "sorter", categories = {options.a_recycling_category}, speed = 1, energy_kw = 10, module_slots = 0})
    end
    world.add_recipe({name = "A-recycling", category = options.a_recycling_category or "recycling", energy = options.a_recycling_energy or 0.25, hidden = true,
        ingredients = {{name = "A", amount = 1}}, products = {{name = "A", amount = 1, p = 0.25}},
        allowed_effects = options.a_recycling_no_quality and {"consumption", "speed", "productivity", "pollution"} or nil})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    storage[1].calculator = {force_auto_center = function() end}
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

local function solve(key, quality, rate, mode)
    return M.Solver.solve_for({[key] = rate or 1}, 1, {[key] = {type = "item", name = "X", quality = quality}}, mode and {start_leftovers = mode})
end

local function column_of(result, key)
    for _, column in ipairs(result.columns) do
        if column.product_full_name == key then return column end
    end
end

local function handler_sheet(targets)
    local sheet_pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    M.Sheet.calculate(M.Sheet.compute_button_of(sheet_flow))
    return sheet_flow
end

local function recompute(sheet_flow)
    storage.computation_stack = {}
    M.Sheet.calculate(M.Sheet.compute_button_of(sheet_flow))
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


local MODES = {byproduct = 1, craft = 2, recycle = 3}

--First element with the name anywhere under flow, depth first: the drop-down sits inside the base-quality row
local function descendant_named(flow, name)
    for _, child in ipairs(flow.children) do
        if child.name == name then return child end
        local found = descendant_named(child, name)
        if found then return found end
    end
end

--Adds a second sheet to a pane and types one target into it
local function add_sheet(sheet_pane, target)
    M.Sheet.new(sheet_pane)
    local sheet_flow = sheet_pane.tabs[#sheet_pane.tabs].content
    local row = sheet_flow.input_container.children[1]
    row.rate_textfield.text = tostring(target.rate)
    row.time_unit_dropdown.selected_index = 2
    row.hxrrc_desired_item_button.elem_value = {name = target.item, quality = target.quality}
    event_handlers.on_gui_elem_changed.hxrrc_desired_item_button({element = row.hxrrc_desired_item_button, player_index = 1})
    return sheet_flow
end

local function select_mode(sheet_flow, mode)
    local dropdown = descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown")
    dropdown.selected_index = MODES[mode]
    event_handlers.on_gui_selection_state_changed[dropdown.name]({element = dropdown, player_index = 1})
end

H.test("2.0 QS-1 each sheet has the start leftovers choice; old sheets get it; 2.1 has none; a change recomputes only its sheet", function()
    tier_world("2.0")
    configure("rare")
    local sheet_pane, first = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local dropdown = descendant_named(first, "hxrrc_start_leftovers_dropdown")
    assert(dropdown, "drop-down on a new sheet")
    H.equal(#dropdown.items, 3, "three choices")
    H.equal(dropdown.selected_index, 1, "left over by default")
    local second = add_sheet(sheet_pane, {item = "X", quality = "rare", rate = 2})
    M.Sheet.calculate(M.Sheet.compute_button_of(first))
    M.Sheet.calculate(M.Sheet.compute_button_of(second))
    local first_report = first.output_flow.children[1]
    select_mode(second, "craft")
    H.equal(first.output_flow.children[1], first_report, "other sheet's report untouched")
    assert(H.parse_report(second.output_flow).loops[M.QualityId.encode("X", "rare")].assist, "changed sheet recomputed with assist crafts")

    local controls_of_sheet = descendant_named(first, "hxrrc_sheet_controls")
    local index = controls_of_sheet.get_index_in_parent()
    controls_of_sheet.destroy()
    first.add{type = "checkbox", name = "hxrrc_round_up_machines_checkbox", caption = "r", state = false, index = index}
    first.add{type = "button", name = "hxrrc_compute_button", caption = "c", index = index + 1}
    M.Sheet.add_missing_controls(sheet_pane)
    local repaired = descendant_named(first, "hxrrc_start_leftovers_dropdown")
    assert(repaired, "old sheet repaired")
    H.equal(repaired.selected_index, 1, "repaired with the default")
    H.equal(descendant_named(first, "hxrrc_sheet_controls").get_index_in_parent(), index, "placed where the old controls were")

    tier_world("2.1")
    local _, sheet_21 = H.fill_sheet({{item = "X", rate = 1, unit = "/s"}})
    H.equal(descendant_named(sheet_21, "hxrrc_start_leftovers_dropdown"), nil, "no choice on 2.1")
    M.Sheet.add_missing_controls(sheet_21.parent)
    H.equal(descendant_named(sheet_21, "hxrrc_start_leftovers_dropdown"), nil, "not added by repair on 2.1")
end)

local function loop_numbers(result, key)
    local column = column_of(result, key)
    local tiers = {}
    for index, tier in ipairs(column.quality_loop.tiers or {}) do
        tiers[index] = {crafts = tier.crafts, recycle_crafts = tier.recycle_crafts, x = tier.x, assist_crafts = tier.assist_crafts}
    end
    return {nets = column.net_amounts, tiers = tiers, reason = column.quality_loop.reason}
end

H.test("2.0 QS-2 left over: the choice changes nothing from QT-1, and returned normal A is a byproduct", function()
    tier_world("2.0")
    local key = configure("rare")
    H.deep_equal(loop_numbers(solve(key, "rare", 1, "byproduct"), key), loop_numbers(solve(key, "rare"), key), "same as no choice")
    local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    H.equal(H.parse_report(sheet_flow.output_flow).rows["item/A"].kind, "hxrrc.byproduct", "normal A left over")
end)

H.test("2.0 QS-3 crafted by another recipe: assist crafts bound by the returns, their row and settings", function()
    tier_world("2.0", {two_tiers = true})
    local key = configure("uncommon")
    L(key).recycle.setup.modules = {} --recycling returns A at normal only
    L(key).assist.setup.modules = four("q")
    local result = solve(key, "uncommon", 1, "craft")
    local info = column_of(result, key).quality_loop
    --per cast: X at normal 0.9 (quality 1: 10% up); recycled into 0.5 A each; assist crafts c = 0.45 / (2 - 0.5 * 0.9) = 9/31; target (1 + c) * 0.1 = 4/31
    H.near_relative(info.tiers[1].crafts, 31 / 4, "casts per target")
    H.near_relative(info.tiers[1].assist_crafts, 9 / 4, "assist crafts per target")
    H.near_relative(info.tiers[1].recycle_crafts, 9, "normal X recycled per target: (0.9 + 0.9 * 9/31) * 31/4")
    H.equal(column_of(result, key).net_amounts["item/A"], nil, "no normal A left over")
    H.near_relative(-column_of(result, key).net_amounts["fluid/molten"], 77.5, "molten per target")
    --cross-check with a craft-by-craft simulation of the same loop
    local A, X_normal, target, casts, assists, recycled = 0, 0, 0, 1, 0, 0
    for _ = 1, 4000 do
        local moved = 0
        if casts > 0 then X_normal = X_normal + 0.9 * casts; target = target + 0.1 * casts; moved = moved + casts; casts = 0 end
        local c = A / 2
        if c > 0 then A = 0; assists = assists + c; X_normal = X_normal + 0.9 * c; target = target + 0.1 * c; moved = moved + c end
        if X_normal > 0 then A = A + 0.5 * X_normal; recycled = recycled + X_normal; moved = moved + X_normal; X_normal = 0 end
        if moved < 1e-15 then break end
    end
    H.near_relative(info.tiers[1].assist_crafts, assists / target, "simulated assist crafts")

    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.craft
    local report = recompute(sheet_flow)
    local loop = report.loops[key]
    assert(loop.assist, "assist row")
    H.equal(loop.assist.row_index, 2, "right after the normal tier row")
    H.equal(loop.assist.machine.name, "assembler", "assist machine")
    H.near_relative(loop.assist.machines, 9 / 4, "assist machines: 2.25 crafts/s, 1 s each")
    H.equal(loop.assist.recipe_button.elem_value, "X-assembly", "assist recipe shown")
    local slot = find_all(loop.assist.module_flow, "hxrrc_choose_module_button")[1]
    local crafts_before = M.QualityLoops._deep_copy(L(key).crafts)
    local modules_before = #L(key).assist.setup.modules
    H.pick_module(slot, nil)
    H.equal(#L(key).assist.setup.modules, modules_before - 1, "assist setup changed")
    H.deep_equal(L(key).crafts, crafts_before, "tier setups unchanged")

    local second = add_sheet(sheet_pane, {item = "X", quality = "uncommon", rate = 1})
    local second_report = recompute(second)
    H.equal(second_report.loops[key].assist, nil, "a sheet leaving items over shows no assist row")
    H.equal(second_report.rows["item/A"].kind, "hxrrc.byproduct", "and leaves A over")
end)

H.test("2.0 QS-4 crafted by another recipe without one: the loop names the missing assist recipe", function()
    tier_world("2.0", {two_tiers = true, no_assembly = true})
    local key = configure("uncommon", true)
    H.equal(loop_numbers(solve(key, "uncommon", 1, "craft"), key).reason, "quality_loop_assist_recipe_missing", "reason")
end)

H.test("2.0 QS-5 recycled into themselves: returned A recycled until gone or upgraded; a pool machine that cannot do it keeps A over", function()
    tier_world("2.0", {two_tiers = true})
    local key = configure("uncommon")
    local result = solve(key, "uncommon", 1, "recycle")
    local column = column_of(result, key)
    local info = column.quality_loop
    --per cast (all quality effects 1): normal X 0.9 recycled into A 0.5 at 90% normal / 10% uncommon -> normal A 0.405, uncommon A 0.045;
    --normal A recycled: kept share 0.25 * 0.9, so V = 0.405 / 0.775 recycled, 0.025 V rising; uncommon crafts take 2 A; target 0.1 + uncommon A / 2
    local V = 0.405 / 0.775
    local target = 0.1 + (0.045 + 0.025 * V) / 2
    H.near_relative(info.tiers[1].crafts, 1 / target, "casts per target")
    H.near_relative(info.tiers[1].ingredient_recycles.A, V / target, "A recycled per target")
    H.equal(column.net_amounts["item/A"], nil, "no normal A left over")
    H.near_relative(info.tiers[2].crafts, (0.045 + 0.025 * V) / 2 / target, "uncommon crafts")

    tier_world("2.0", {two_tiers = true, a_recycling_category = "sorting"})
    key = configure("uncommon")
    result = solve(key, "uncommon", 1, "recycle")
    column = column_of(result, key)
    H.deep_equal(column.quality_loop.kept_ingredients, {"A"}, "A kept")
    H.near_relative(column.net_amounts["item/A"], 0.405 / 0.1225, "normal A left over as without recycling")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.recycle
    local tooltip = recompute(sheet_flow).loops[key].pool.recycle.tooltip
    local found = false
    for index = 3, #tooltip do
        if type(tooltip[index][3]) == "table" and tooltip[index][3][1] == "hxrrc.recycler_pool_ingredient_kept" then found = true end
    end
    H.equal(found, true, "pool tooltip names the kept item")
end)

H.test("2.0 QS-5b pooled recipes count their own work, and a recipe forbidding quality recycles without it", function()
    tier_world("2.0", {two_tiers = true, a_recycling_energy = 4})
    local key = configure("uncommon")
    local result = solve(key, "uncommon", 2, "recycle")
    local column = column_of(result, key)
    local rate = result.recipe_rates[column.recipe_name]
    local tier = column.quality_loop.tiers[1]
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 2, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.recycle
    local pool = recompute(sheet_flow).loops[key].pool.recycle
    --X recycling 0.5 s, A recycling 4 s, speed 1 (q changes no speed)
    local x_machines = tier.recycle_crafts * rate * 0.5
    local a_machines = tier.ingredient_recycles.A * rate * 4
    H.near_relative(pool.machines, x_machines + a_machines, "pool machines: each recipe's own time")
    local expected_energy = tier.crafts * rate * 2 / 2 * 400e3 + column.quality_loop.tiers[2].crafts * rate * 100e3 + (x_machines + a_machines) * 50e3
    H.near_relative(require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates), expected_energy, "power per recipe")

    tier_world("2.0", {two_tiers = true, a_recycling_no_quality = true})
    key = configure("uncommon")
    local stored_pool = M.QualityLoops._deep_copy(L(key).recycle)
    result = solve(key, "uncommon", 1, "recycle")
    local info = column_of(result, key).quality_loop
    --A recycling may not use quality: its modules are dropped for it, so recycled A only stays normal: V = 0.405 / 0.75, nothing rises
    local target = 0.1 + 0.045 / 2
    H.near_relative(info.tiers[1].ingredient_recycles.A, 0.405 / 0.75 / target, "A recycled without quality")
    H.near_relative(info.tiers[2].crafts, 0.045 / 2 / target, "uncommon crafts only from X recycling")
    H.deep_equal(info.ingredient_recycles.A.setup.modules, {}, "modules dropped for that recipe")
    H.deep_equal(L(key).recycle, stored_pool, "pool setup unchanged")
    H.equal((info.tiers[1].recycle_chances[2] or 0) > 0, true, "X recycling still uses quality")
end)

H.test("2.0 QS-6 a start recipe taking items: every choice gives the same loop and no assist row", function()
    tier_world("2.0", {bind = "X-assembly"})
    local key = configure("rare")
    local byproduct = loop_numbers(solve(key, "rare", 1, "byproduct"), key)
    H.deep_equal(loop_numbers(solve(key, "rare", 1, "craft"), key), byproduct, "craft")
    H.deep_equal(loop_numbers(solve(key, "rare", 1, "recycle"), key), byproduct, "recycle")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.craft
    H.equal(recompute(sheet_flow).loops[key].assist, nil, "no assist row")
end)

H.test("2.0 QS-7 power with assist crafts", function()
    tier_world("2.0", {two_tiers = true})
    local key = configure("uncommon")
    L(key).recycle.setup.modules = {}
    L(key).assist.setup.modules = four("q")
    local result = solve(key, "uncommon", 2, "craft")
    local column = column_of(result, key)
    local rate = result.recipe_rates[column.recipe_name]
    local tiers = column.quality_loop.tiers
    local expected = tiers[1].crafts * rate * 2 / 2 * 400e3 + (tiers[1].assist_crafts + tiers[2].crafts) * rate * 100e3 + tiers[1].recycle_crafts * rate * 0.5 * 50e3
    H.near_relative(require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates), expected, "assist crafts draw")
    H.near_relative(tiers[1].assist_crafts * rate, 2 * 9 / 4, "assist crafts per second")
end)

--N1/S1: the sheet controls grid (base-quality label | drop-down, round-up checkbox | Compute); the base-quality pair shows only while the sheet
--targets an item above normal quality

local function controls_of(sheet_flow) return descendant_named(sheet_flow, "hxrrc_sheet_controls") end
local function label_of(sheet_flow) return descendant_named(sheet_flow, "hxrrc_start_leftovers_label") end
local function dropdown_of(sheet_flow) return descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown") end

local function cell_names(controls)
    local names = {}
    for index, cell in ipairs(controls.children) do names[index] = cell.name end
    return table.concat(names, ",")
end

--Types a target into the sheet's first row the way the player does: value into the button, then its changed event
local function set_target(sheet_flow, value, fluid)
    local row = sheet_flow.input_container.children[1]
    local button = fluid and row.hxrrc_desired_fluid_button or row.hxrrc_desired_item_button
    button.elem_value = value
    event_handlers.on_gui_elem_changed[button.name]({element = button, player_index = 1})
end

--A sheet as 1.1.23 saved it: checkbox, the drop-down itself, Compute, all in the sheet flow where the grid now sits
local function as_saved_by_1_1_23(sheet_flow, selected_index, round_up)
    local controls = controls_of(sheet_flow)
    local index = controls.get_index_in_parent()
    controls.destroy()
    sheet_flow.add{type = "checkbox", name = "hxrrc_round_up_machines_checkbox", caption = "r", state = round_up == true, index = index}
    sheet_flow.add{type = "drop-down", name = "hxrrc_start_leftovers_dropdown", items = {"a", "b", "c"}, selected_index = selected_index, index = index + 1}
    sheet_flow.add{type = "button", name = "hxrrc_compute_button", caption = "c", index = index + 2}
    return index
end

H.test("2.0 N1a N1b S1a the controls are one two-column grid: label | drop-down, checkbox | Compute, right and left aligned, 8 px apart", function()
    tier_world("2.0")
    local _, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local controls = controls_of(sheet_flow)
    assert(controls, "S1a: grid on a new sheet")
    H.equal(controls.type, "table", "S1a: a table")
    H.equal(controls.column_count, 2, "S1a: two columns")
    H.equal(controls.style.column_alignments[1], "middle-right", "S1a: first column right")
    H.equal(controls.style.column_alignments[2], "middle-left", "S1a: second column left")
    H.equal(controls.style.horizontal_spacing, 8, "S1a: 8 px apart")
    H.equal(cell_names(controls), "start_leftovers_label_cell,start_leftovers_dropdown_cell,round_up_cell,compute_cell", "S1a: cell order")
    H.equal(controls.start_leftovers_label_cell.children[1].caption[1], "hxrrc.start_leftovers_caption", "label caption")
    H.equal(controls.start_leftovers_label_cell.children[1].tooltip[1], "hxrrc.start_leftovers_tooltip", "label tooltip")
    local keys = {}
    for index, item in ipairs(dropdown_of(sheet_flow).items) do keys[index] = item[1] end
    H.deep_equal(keys, {"hxrrc.start_leftovers_byproduct", "hxrrc.start_leftovers_craft", "hxrrc.start_leftovers_recycle"}, "N1b: bare choice keys")
    H.equal(controls.round_up_cell.children[1].name, "hxrrc_round_up_machines_checkbox", "S1a: checkbox under the label")
    H.equal(controls.compute_cell.children[1].name, "hxrrc_compute_button", "S1a: Compute under the drop-down")
    local names = {}
    for index, child in ipairs(sheet_flow.children) do names[index] = child.name end
    H.equal(table.concat(names, ","), "input_container,hxrrc_sheet_controls,output_flow", "S1a: nothing else between inputs and output")
end)

H.test("2.0 S1f the sheet flow of a checkbox, a drop-down and a Compute button is the sheet owning them", function()
    tier_world("2.0")
    local _, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    H.equal(M.Sheet.sheet_flow_of(M.Sheet.round_up_checkbox_of(sheet_flow)), sheet_flow, "checkbox")
    H.equal(M.Sheet.sheet_flow_of(dropdown_of(sheet_flow)), sheet_flow, "drop-down")
    H.equal(M.Sheet.sheet_flow_of(M.Sheet.compute_button_of(sheet_flow)), sheet_flow, "Compute")
end)

H.test("2.0 N1c N1d a 1.1.23 sheet gets the grid in its controls' place with its choice and checkbox; repairing twice leaves one grid", function()
    tier_world("2.0")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local index = as_saved_by_1_1_23(sheet_flow, 3, true)
    M.Sheet.add_missing_controls(sheet_pane)
    M.Sheet.add_missing_controls(sheet_pane)
    local grids, flat = 0, 0
    for _, child in ipairs(sheet_flow.children) do
        if child.name == "hxrrc_sheet_controls" then grids = grids + 1 end
        if child.name == "hxrrc_start_leftovers_dropdown" or child.name == "hxrrc_round_up_machines_checkbox" or child.name == "hxrrc_compute_button" then flat = flat + 1 end
    end
    H.equal(grids, 1, "one grid")
    H.equal(flat, 0, "no flat control left")
    H.equal(controls_of(sheet_flow).get_index_in_parent(), index, "in the old controls' place")
    H.equal(dropdown_of(sheet_flow).selected_index, 3, "choice kept")
    H.equal(M.Sheet.round_up_checkbox_of(sheet_flow).state, true, "checkbox kept")
end)

H.test("2.0 N1e S1e a choice or a tick in one sheet recomputes only that sheet, also after a 1.1.23 sheet is repaired; Compute works through its handler", function()
    tier_world("2.0")
    configure("rare")
    local sheet_pane, first = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local second = add_sheet(sheet_pane, {item = "X", quality = "rare", rate = 2})
    event_handlers.on_gui_click.hxrrc_compute_button({element = M.Sheet.compute_button_of(first), player_index = 1})
    assert(first.output_flow.children[1], "S1e: Compute through its handler")
    M.Sheet.calculate(M.Sheet.compute_button_of(second))
    local first_report = first.output_flow.children[1]
    select_mode(second, "craft")
    H.equal(first.output_flow.children[1], first_report, "other sheet untouched")
    assert(H.parse_report(second.output_flow).loops[M.QualityId.encode("X", "rare")].assist, "own sheet recomputed")
    local second_report = second.output_flow.children[1]
    local checkbox = M.Sheet.round_up_checkbox_of(first)
    checkbox.state = true
    event_handlers.on_gui_checked_state_changed[checkbox.name]({element = checkbox, player_index = 1})
    H.equal(second.output_flow.children[1], second_report, "S1e: a tick leaves the other sheet untouched")
    assert(first.output_flow.children[1] ~= first_report, "S1e: a tick recomputes its own sheet")
    as_saved_by_1_1_23(first, 1)
    M.Sheet.add_missing_controls(sheet_pane)
    local repaired = dropdown_of(first)
    repaired.selected_index = 2
    second_report = second.output_flow.children[1]
    event_handlers.on_gui_selection_state_changed[repaired.name]({element = repaired, player_index = 1})
    assert(H.parse_report(first.output_flow).loops[M.QualityId.encode("X", "rare")].assist, "repaired drop-down reaches its own sheet")
    H.equal(second.output_flow.children[1], second_report, "and only its own sheet")
end)

H.test("2.1 N1f S1b on 2.1 the grid holds only the checkbox and Compute, built or repaired", function()
    tier_world("2.1")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", rate = 1, unit = "/s"}})
    H.equal(cell_names(controls_of(sheet_flow)), "round_up_cell,compute_cell", "S1b: built")
    local controls = controls_of(sheet_flow)
    local index = controls.get_index_in_parent()
    controls.destroy()
    sheet_flow.add{type = "checkbox", name = "hxrrc_round_up_machines_checkbox", caption = "r", state = true, index = index}
    sheet_flow.add{type = "button", name = "hxrrc_compute_button", caption = "c", index = index + 1}
    M.Sheet.add_missing_controls(sheet_pane)
    H.equal(cell_names(controls_of(sheet_flow)), "round_up_cell,compute_cell", "S1b: repaired")
    H.equal(M.Sheet.round_up_checkbox_of(sheet_flow).state, true, "S1b: checkbox kept")
    H.equal(dropdown_of(sheet_flow), nil, "N1f: no choice on 2.1")
end)

H.test("2.0 N1g N1h S1c the label and drop-down hide for normal items and fluids, show for a target above normal; the four cells always stay", function()
    tier_world("2.0")
    local _, sheet_flow = H.fill_sheet({})
    local function shown()
        H.equal(#controls_of(sheet_flow).children, 4, "S1c: four cells")
        H.equal(label_of(sheet_flow).visible, dropdown_of(sheet_flow).visible, "S1c: label and drop-down together")
        return dropdown_of(sheet_flow).visible
    end
    H.equal(shown(), false, "empty sheet")
    set_target(sheet_flow, {name = "X"})
    H.equal(shown(), false, "normal item")
    set_target(sheet_flow, {name = "X", quality = "rare"})
    H.equal(shown(), true, "item above normal")
    set_target(sheet_flow, nil)
    H.equal(shown(), false, "cleared")
    set_target(sheet_flow, {name = "X", quality = "uncommon"})
    H.equal(shown(), true, "shown again")
    set_target(sheet_flow, {name = "X", quality = "normal"})
    H.equal(shown(), false, "set to normal")
    set_target(sheet_flow, {name = "X", quality = "rare"})
    set_target(sheet_flow, "molten", true)
    H.equal(shown(), false, "replaced by a fluid")
    for _, cell in ipairs(controls_of(sheet_flow).children) do H.equal(cell.visible, true, "S1c: cell " .. cell.name .. " never hidden") end
    local _, fluid_sheet = H.fill_sheet({{fluid = "molten", rate = 1, unit = "/s"}})
    H.equal(dropdown_of(fluid_sheet).visible, false, "fluid sheet")
end)

H.test("2.0 N1i a hidden drop-down keeps its choice and the solver still gets it", function()
    tier_world("2.0")
    local _, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    select_mode(sheet_flow, "recycle")
    set_target(sheet_flow, {name = "X"})
    H.equal(dropdown_of(sheet_flow).visible, false, "hidden")
    H.equal(dropdown_of(sheet_flow).selected_index, 3, "choice kept")
    local seen
    local solve_for = M.Solver.solve_for
    M.Solver.solve_for = function(rates, player_index, parts, options)
        seen = options.start_leftovers
        return solve_for(rates, player_index, parts, options)
    end
    M.Sheet.calculate(M.Sheet.compute_button_of(sheet_flow))
    M.Solver.solve_for = solve_for
    H.equal(seen, "recycle", "hidden drop-down's choice reaches the solver")
end)

H.test("2.0 N1j repair shows the base-quality pair on an old sheet with a target above normal and hides it on a normal-only one", function()
    tier_world("2.0")
    local quality_pane, quality_sheet = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    as_saved_by_1_1_23(quality_sheet, 1)
    M.Sheet.add_missing_controls(quality_pane)
    H.equal(dropdown_of(quality_sheet).visible, true, "quality sheet shows it")
    H.equal(label_of(quality_sheet).visible, true, "with its label")
    local normal_pane, normal_sheet = H.fill_sheet({{item = "X", rate = 1, unit = "/s"}})
    as_saved_by_1_1_23(normal_sheet, 1)
    M.Sheet.add_missing_controls(normal_pane)
    H.equal(dropdown_of(normal_sheet).visible, false, "normal-only sheet hides it")
end)

H.test("2.0 N1k a target change that re-raises its handler leaves the right visibility", function()
    tier_world("2.0")
    local _, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    H.equal(dropdown_of(sheet_flow).visible, true, "shown")
    H.refire_on_script_set = true
    set_target(sheet_flow, "molten", true) --clears the item button, which raises the handler again
    H.refire_on_script_set = false
    H.equal(dropdown_of(sheet_flow).visible, false, "hidden after the nested handler")
end)

--N3: the recycler pool and returned-items rows lead with the recycling arrows, their old text as its tooltip

local function assist_and_pool_report()
    local key = configure("uncommon")
    L(key).assist.setup.modules = four("q")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    descendant_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.craft
    return recompute(sheet_flow).loops[key]
end

H.test("2.0 N3a N3b N3d the pool row shows the recycle icon with its text as tooltip; the assist row shows the item button then the icon; both still parse", function()
    tier_world("2.0", {two_tiers = true})
    local loop = assist_and_pool_report()
    assert(loop.pool and loop.assist, "both rows parsed")
    H.equal(loop.pool.icon.type, "sprite", "pool icon")
    H.equal(loop.pool.icon.sprite, "hxrrc_recycling", "recycling arrows")
    H.equal(loop.pool.icon.tooltip[1], "hxrrc.recycler_pool", "pool text as tooltip")
    H.equal(loop.assist.item_button.type, "sprite-button", "assist row still leads with the item")
    H.equal(loop.assist.item_button.sprite, "item/X", "the item")
    H.equal(loop.assist.icon.type, "sprite", "assist icon after the item")
    H.equal(loop.assist.icon.sprite, "hxrrc_recycling", "recycling arrows")
    H.equal(loop.assist.icon.tooltip[1], "hxrrc.assist_row", "assist text as tooltip")
    assert(loop.pool.recycle and loop.assist.module_flow, "the rows' other cells still parse")
end)

H.test("2.0 N3c without the recycling sprite both rows fall back to their text", function()
    local world = tier_world("2.0", {two_tiers = true})
    world.remove_sprite("hxrrc_recycling")
    local loop = assist_and_pool_report()
    H.equal(loop.pool.icon.type, "label", "pool text")
    H.equal(loop.pool.icon.caption[1], "hxrrc.recycler_pool", "pool caption")
    H.equal(loop.assist.icon.type, "label", "assist text")
    H.equal(loop.assist.icon.caption[1], "hxrrc.assist_row", "assist caption")
end)

H.done("test_quality_tier_recipes")
