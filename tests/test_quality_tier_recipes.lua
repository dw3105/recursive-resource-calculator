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


local MODES = {byproduct = 1, craft = 2, recycle = 3}

local function child_named(flow, name)
    for _, child in ipairs(flow.children) do
        if child.name == name then return child end
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
    local dropdown = child_named(sheet_flow, "hxrrc_start_leftovers_dropdown")
    dropdown.selected_index = MODES[mode]
    event_handlers.on_gui_selection_state_changed[dropdown.name]({element = dropdown, player_index = 1})
end

H.test("2.0 QS-1 each sheet has the start leftovers choice; old sheets get it; 2.1 has none; a change recomputes only its sheet", function()
    tier_world("2.0")
    configure("rare")
    local sheet_pane, first = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    local dropdown = child_named(first, "hxrrc_start_leftovers_dropdown")
    assert(dropdown, "drop-down on a new sheet")
    H.equal(#dropdown.items, 3, "three choices")
    H.equal(dropdown.selected_index, 1, "left over by default")
    local second = add_sheet(sheet_pane, {item = "X", quality = "rare", rate = 2})
    M.Sheet.calculate(first.hxrrc_compute_button)
    M.Sheet.calculate(second.hxrrc_compute_button)
    local first_report = first.output_flow.children[1]
    select_mode(second, "craft")
    H.equal(first.output_flow.children[1], first_report, "other sheet's report untouched")
    assert(H.parse_report(second.output_flow).loops[M.QualityId.encode("X", "rare")].assist, "changed sheet recomputed with assist crafts")

    child_named(first, "hxrrc_start_leftovers_dropdown").destroy()
    M.Sheet.add_missing_controls(sheet_pane)
    local repaired = child_named(first, "hxrrc_start_leftovers_dropdown")
    assert(repaired, "old sheet repaired")
    H.equal(repaired.selected_index, 1, "repaired with the default")
    local compute_index, dropdown_index
    for index, child in ipairs(first.children) do
        if child == repaired then dropdown_index = index end
        if child.name == "hxrrc_compute_button" then compute_index = index end
    end
    H.equal(dropdown_index + 1, compute_index, "placed before the compute button")

    tier_world("2.1")
    local _, sheet_21 = H.fill_sheet({{item = "X", rate = 1, unit = "/s"}})
    H.equal(child_named(sheet_21, "hxrrc_start_leftovers_dropdown"), nil, "no choice on 2.1")
    M.Sheet.add_missing_controls(sheet_21.parent)
    H.equal(child_named(sheet_21, "hxrrc_start_leftovers_dropdown"), nil, "not added by repair on 2.1")
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
    child_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.craft
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
    slot.elem_value = nil
    fire(slot)
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
    child_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.recycle
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
    child_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.recycle
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
    child_named(sheet_flow, "hxrrc_start_leftovers_dropdown").selected_index = MODES.craft
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

H.done("test_quality_tier_recipes")
