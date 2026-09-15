--Quality loops in the report: one row per tier, the loop's editors, stale controls, failures and the effects label
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Two qualities (normal, uncommon) unless options.chain is given. A -> X in an assembler; X -> 0.25 A in a recycler; quality module q: +0.25 quality, -0.05 speed.
local function loop_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    if options.chain ~= "vanilla" then
        world.set_quality_chain(options.chain or {{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    end
    world.add_item("A")
    world.add_item("X")
    world.add_fluid("water")
    world.add_module("q", "quality", {quality = 0.25, speed = -0.05})
    world.add_module("bad", "quality", {quality = -0.1})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4,
        speeds_by_quality = options.assembler_speeds, quality_affects_module_slots = options.assembler_speeds and true or nil})
    if not options.no_recycler then
        world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4,
            speeds_by_quality = options.recycler_speeds})
    end
    world.add_recipe({name = "X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    if options.extra then options.extra(world) end
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

--Configures the loop of an item at a quality, with the given modules in each stage (default four q in both)
local function configure(item, quality, craft_modules, recycle_modules)
    local key = M.QualityId.encode(item, quality)
    M.QualityLoops.ensure(1, key, {type = "item", name = item, quality = quality})
    local loop = storage[1].quality_loops_by_key[key]
    if loop then
        loop.craft.setup.modules = craft_modules or four("q")
        loop.recycle.setup.modules = recycle_modules or four("q")
    end
    return key, loop
end

--A sheet the registered handlers can recompute: its pane is the player's sheet pane, and computations run at once
local function handler_sheet(targets)
    local sheet_pane, sheet_flow = H.fill_sheet(targets)
    storage[1].sheet_section = {sheet_pane = sheet_pane}
    M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
    return sheet_flow, sheet_pane
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

local function count_machine_buttons(tier)
    local count = 0
    for _, line in pairs({tier.craft, tier.recycle}) do
        if line.machine_button then count = count + 1 end
    end
    return count
end

local Y = 0.1225 --target items per normal craft in the two-tier loop with four q modules in both stages

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " Q-11 a normal and an uncommon target of one item: a solved row and tier rows with exact counts", function()
        loop_world(shape)
        local key = configure("X", "uncommon")
        local report = H.run_sheet({{item = "X", rate = 5, unit = "/s"}, {item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        H.equal(report.energy_caption ~= "hxrrc.totals_unavailable", true, "totals shown")
        H.near(report.rows["item/X"].rate, 5, "normal X row")
        local loop = report.loops[key]
        assert(loop, "no loop rows")
        H.equal(#loop.tiers, 2, "one row per tier")
        H.equal(report.loop_row_count, 2, "loop rows counted apart")
        H.equal(loop.tiers[1].quality, "normal", "first tier")
        H.equal(loop.tiers[2].quality, "uncommon", "second tier")
        H.near(loop.tiers[2].rate, 1, "target rate on the last tier")
        H.near(loop.tiers[1].rate, 0.9 / Y, "normal X going to the recycler")
        --speed multiplier 0.8; the assembler takes 1 s per craft and the recycler 0.5 s
        H.near(loop.tiers[1].craft.machines, 1 / Y / 0.8, "normal crafting machines")
        H.near(loop.tiers[1].recycle.machines, 0.9 / Y * 0.5 / 0.8, "normal recyclers")
        H.near(loop.tiers[2].craft.machines, 0.0225 / Y / 0.8, "uncommon crafting machines")
        H.equal(loop.tiers[2].recycle, nil, "nothing recycled at the target tier")
        H.near(report.rows["item/A"].rate, 5 + (1 - 0.2025) / Y, "A for both targets")
        H.equal(loop.recipe_button.tags.product_full_name, "item/X", "recipe control binds the plain item")
        H.equal(loop.recycle_button.elem_value, "X-recycling", "recycle control")
        assert(loop.module_flows.craft and loop.module_flows.recycle, "both module editors")
        H.equal(#find_all(loop.module_flows.craft, "hxrrc_choose_module_button"), 4, "craft module slots")
        local tooltip = loop.tiers[1].craft.tooltip
        H.equal(tooltip[2][1], "hxrrc.quality_chances_tooltip", "chances tooltip")
        H.equal(tooltip[3][5], "90%", "stays normal")
        H.equal(tooltip[4][5], "10%", "upgrades")
    end)

    H.test(shape .. " Q-9 Q-8 an unreachable loop shows its editors without totals; modules added there make it solve", function()
        loop_world(shape)
        local key = configure("X", "uncommon", {}, {})
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local report = H.parse_report(sheet_flow.output_flow)
        local loop = report.loops[key]
        H.equal(report.energy_caption, "hxrrc.totals_unavailable", "no totals")
        H.equal(#loop.tiers, 1, "one diagnostic row")
        H.equal(loop.reason, "hxrrc.quality_target_unreachable", "reason")
        H.equal(loop.tiers[1].craft.machines, nil, "no count")
        local craft_slots = find_all(loop.module_flows.craft, "hxrrc_choose_module_button")
        H.equal(#craft_slots, 4, "craft module editor shown")
        craft_slots[1].elem_value = {name = "q"}
        fire(craft_slots[1])
        H.equal(#storage[1].quality_loops_by_key[key].craft.setup.modules, 1, "module stored in the loop")
        H.equal(#storage[1].module_setups_by_recipe_name.X.modules, 0, "the recipe's own setup untouched")
        report = recompute(sheet_flow)
        loop = report.loops[key]
        H.equal(loop.reason, nil, "solved")
        H.equal(#loop.tiers, 2, "tier rows")
        H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X", "binding unchanged")
        H.equal(report.energy_caption ~= "hxrrc.totals_unavailable", true, "totals back")
    end)

    H.test(shape .. " Q-12 an item named a@rare and item a at rare render apart, and delimiter names keep separate loops", function()
        loop_world(shape, {chain = "vanilla", extra = function(world)
            world.add_item("a")
            world.add_item("a@rare")
            world.add_recipe({name = "make-a", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "a", amount = 1}}})
            world.add_recipe({name = "make-a@rare", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "a@rare", amount = 1}}})
        end})
        local key = configure("a", "rare")
        local report = H.run_sheet({{item = "a@rare", rate = 5, unit = "/s"}, {item = "a", quality = "rare", rate = 1, unit = "/s"}})
        H.near(report.rows["item/a@rare"].rate, 5, "legacy row")
        assert(report.loops[key], "quality loop rows")
        H.equal(report.loops[key].tiers[#report.loops[key].tiers].quality, "rare", "loop ends at rare")
        H.equal(report.rows["item/a@rare"].recipe_button.elem_filters[1].elem_filters[1].name, "a@rare", "legacy filter")
        H.equal(report.loops[key].recipe_button.elem_filters[1].elem_filters[1].name, "a", "loop filter")

        loop_world(shape, {chain = {{name = "normal", level = 0}, {name = "c", level = 1}, {name = "b:c", level = 2}}, extra = function(world)
            world.add_item("a")
            world.add_item("a:b")
            world.add_recipe({name = "make-a", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "a", amount = 1}}})
            world.add_recipe({name = "make-a:b", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "a:b", amount = 1}}})
        end})
        local first = configure("a:b", "c")
        local second = configure("a", "b:c")
        local _, sheet_flow = H.fill_sheet({{item = "a:b", quality = "c", rate = 1, unit = "/s"}, {item = "a", quality = "b:c", rate = 2, unit = "/s"}})
        local rates, parts = require("gui.input_container").get_desired_production_rates_by_full_item_name(sheet_flow.input_container)
        H.near(rates[first], 1, "first demand")
        H.near(rates[second], 2, "second demand")
        H.equal(parts[first].name .. "|" .. parts[first].quality, "a:b|c", "first parts")
        H.equal(parts[second].name .. "|" .. parts[second].quality, "a|b:c", "second parts")
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        report = H.parse_report(sheet_flow.output_flow)
        local count = 0
        for _ in pairs(storage[1].quality_loops_by_key) do count = count + 1 end
        H.equal(count, 2, "two loop configurations")
        assert(report.loops[first] and report.loops[second], "two sets of tier rows")
        H.equal(#report.loops[first].tiers, 2, "first loop tiers")
        H.equal(#report.loops[second].tiers, 3, "second loop tiers")
    end)

    for _, refire in ipairs({false, true}) do
        local mode = refire and " (re-fire)" or ""
        H.test(shape .. " Q-13 stale loop controls are refused and restored" .. mode, function()
            local world = loop_world(shape, {extra = function(w)
                local world = w
                world.add_recipe({name = "X2", category = "crafting", ingredients = {{name = "A", amount = 2}}, products = {{name = "X", amount = 1}}})
                world.add_recipe({name = "X-melting", category = "recycling", ingredients = {{name = "X", amount = 1}, {name = "A", amount = 1}},
                    products = {{name = "A", amount = 2}}})
                world.add_machine({name = "big-assembler", categories = {"crafting"}, speed = 2})
            end})
            storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.X
            storage[1].product_full_names_by_recipe_name.X = "item/X"
            local key, loop = configure("X", "uncommon")
            loop.craft.machine = {name = "assembler"}
            local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
            local _, second_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
            local report = H.parse_report(sheet_flow.output_flow)
            local old = report.loops[key]
            H.refire_on_script_set = refire

            --emptying a loop machine button
            local craft_button = old.tiers[1].craft.machine_button
            craft_button.elem_value = nil
            fire(craft_button)
            H.equal(craft_button.elem_value.name, "assembler", "emptied button restored")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.cannot_empty_a_choose_crafting_machine_button_error", "flying text")

            --a recycle recipe that takes another item
            local recycle_button = old.recycle_button
            recycle_button.elem_value = "X-melting"
            fire(recycle_button)
            H.equal(recycle_button.elem_value, "X-recycling", "refused recycle pick restored")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.recycle_recipe_refused_error", "refusal text")
            H.equal(loop.recycle_recipe_name, "X-recycling", "loop unchanged")

            --the recycle recipe changes on another sheet: this sheet's recycle button is stale
            M.Sheet.calculate(second_flow.hxrrc_compute_button)
            local other = H.parse_report(second_flow.output_flow).loops[key]
            other.recycle_button.elem_value = nil
            fire(other.recycle_button)
            H.equal(loop.recycle_recipe_name, nil, "cleared from the other sheet")
            recycle_button.elem_value = "X-recycling"
            fire(recycle_button)
            H.equal(loop.recycle_recipe_name, nil, "stale recycle button refused")
            H.equal(recycle_button.elem_value, "X-recycling", "stale recycle button shows its snapshot")
            --its old recycle machine button is stale too, as is its old recycle module button
            local recycle_machine_button = old.tiers[1].recycle.machine_button
            recycle_machine_button.elem_value = {name = "recycler", quality = "uncommon"}
            fire(recycle_machine_button)
            H.equal(loop.recycle.machine, nil, "stale recycle machine button refused")
            local recycle_slot = find_all(old.module_flows.recycle, "hxrrc_choose_module_button")[1]
            recycle_slot.elem_value = nil
            fire(recycle_slot)
            H.equal(#loop.recycle.setup.modules, 0, "stale recycle module button stores nothing")

            --the item's recipe changes: the craft stage's old controls are stale
            storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.X2
            storage[1].product_full_names_by_recipe_name.X = nil
            storage[1].product_full_names_by_recipe_name.X2 = "item/X"
            M.QualityLoops.ensure(1, key, {type = "item", name = "X", quality = "uncommon"})
            local modules_before = #loop.craft.setup.modules
            craft_button.elem_value = {name = "big-assembler"}
            fire(craft_button)
            H.equal(loop.craft.machine.name, "assembler", "stale craft machine button refused")
            H.equal(craft_button.elem_value.name, "assembler", "restored")
            local craft_slot = find_all(old.module_flows.craft, "hxrrc_choose_module_button")[1]
            craft_slot.elem_value = nil
            fire(craft_slot)
            H.equal(#loop.craft.setup.modules, modules_before, "stale craft module button stores nothing")
            H.refire_on_script_set = false
        end)
    end

    H.test(shape .. " Q-15 the effects label shows a quality effect as the chance to upgrade from normal", function()
        loop_world(shape)
        storage[1].module_setups_by_recipe_name.X.modules = {{name = "q"}}
        local report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
        local labels = find_all(report.rows["item/X"].module_cell, nil)
        local captions = {}
        for _, element in ipairs(labels) do
            if element.type == "label" and type(element.caption) == "table" then captions[element.caption[2][1]] = element.caption[4] end
        end
        H.equal(captions["hxrrc.quality"], "+2.50%", "quality as chance")
        H.equal(captions["hxrrc.speed"], "-5%", "speed unchanged")
        storage[1].module_setups_by_recipe_name.X.modules = {{name = "bad"}}
        report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
        captions = {}
        for _, element in ipairs(find_all(report.rows["item/X"].module_cell, nil)) do
            if element.type == "label" and type(element.caption) == "table" then captions[element.caption[2][1]] = element.caption[4] end
        end
        H.equal(captions["hxrrc.quality"], "+0.00%", "a negative quality effect gives no chance")
    end)

    H.test(shape .. " Q-20 diagnostic loop rows hold exactly the editors their configuration has", function()
        --both stages with machines
        loop_world(shape)
        local key = configure("X", "uncommon", {}, {})
        local loop = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}}).loops[key]
        H.equal(#loop.tiers, 1, "one row")
        H.equal(count_machine_buttons(loop.tiers[1]), 2, "two machine buttons")
        H.equal(loop.module_flows.craft.children[1].type, "flow", "craft module cell")
        H.equal(loop.module_flows.recycle.children[1].type, "flow", "recycle module cell")
        H.equal(loop.recycle_button.elem_value, "X-recycling", "recycle button")

        --no recycle recipe from the start (Q-22 (a)): two recipes could recycle X, so none is picked for the new loop
        loop_world(shape, {extra = function(world)
            world.add_recipe({name = "X-shredding", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "A", amount = 1, p = 0.5}}})
        end})
        loop = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}}).loops[M.QualityId.encode("X", "uncommon")]
        key = M.QualityId.encode("X", "uncommon")
        H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, nil, "created without a recycle recipe")
        H.equal(count_machine_buttons(loop.tiers[1]), 1, "one machine button")
        H.equal(loop.tiers[1].recycle, nil, "no recycle line")
        H.equal(loop.module_flows.recycle.children[1].type, "empty-widget", "no recycle module editor")
        H.equal(loop.recycle_button.elem_value, nil, "empty recycle button")

        --hand-crafted item recipe
        loop_world(shape, {extra = function(world)
            world.add_item("H")
            world.add_recipe({name = "H", category = "handcraft", ingredients = {{name = "A", amount = 1}}, products = {{name = "H", amount = 1}}})
        end})
        key = configure("H", "uncommon", {}, {})
        loop = H.run_sheet({{item = "H", quality = "uncommon", rate = 1, unit = "/s"}}).loops[key]
        H.equal(loop.tiers[1].craft.machine_button, nil, "no craft machine button")
        H.equal(loop.reason, "hxrrc.quality_target_unreachable", "reason in the craft line")
        H.equal(loop.module_flows.craft.children[1].type, "empty-widget", "no craft module editor")
    end)

    H.test(shape .. " Q-21 a loop driven backwards by another loop's byproduct shows its reason, editors and no counts", function()
        loop_world(shape, {extra = function(world)
            world.add_item("B")
            world.add_item("C")
            world.add_machine({name = "quality-assembler", categories = {"special"}, speed = 1, energy_kw = 100, base_quality = 5, module_slots = 0})
            world.add_recipe({name = "XB", category = "special", ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}, {name = "B", amount = 1}}})
            world.add_recipe({name = "B", category = "special", ingredients = {{name = "C", amount = 1}}, products = {{name = "B", amount = 1}}})
        end})
        storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.XB
        storage[1].product_full_names_by_recipe_name.XB = "item/X"
        storage[1].recipes_by_product_full_name["item/B"] = prototypes.recipe.B
        storage[1].product_full_names_by_recipe_name.B = "item/B"
        local x_key = configure("X", "uncommon", {}, {})
        local b_key = configure("B", "uncommon", {}, {})
        storage[1].quality_loops_by_key[x_key].recycle_recipe_name = nil
        M.QualityLoops.sanitize(1, x_key)
        local power_calls = 0
        package.loaded["logic.compute_power_and_pollution"] = function() power_calls = power_calls + 1 return 0, 0 end
        package.loaded["gui.sheet"] = nil --loaded again, so it takes the spy
        local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "B", quality = "uncommon", rate = 0.5, unit = "/s"}})
        M.Sheet = require "gui.sheet"
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        local report = H.parse_report(sheet_flow.output_flow)
        H.equal(power_calls, 0, "power never computed")
        H.equal(report.energy_caption, "hxrrc.totals_unavailable", "no totals")
        local b_loop, x_loop = report.loops[b_key], report.loops[x_key]
        H.equal(b_loop.reason, "hxrrc.recipe_runs_backwards", "B's reason")
        H.equal(#b_loop.tiers, 1, "B shows one row")
        H.equal(b_loop.tiers[1].craft.machines, nil, "no count on B")
        assert(b_loop.tiers[1].craft.machine_button, "B's machine editor")
        assert(b_loop.recipe_button, "B's recipe editor")
        H.equal(#x_loop.tiers, 2, "X keeps its tier rows")
        H.near(x_loop.tiers[1].craft.machines, 2, "X's normal crafting machines")

        local row = sheet_flow.input_container.children[2]
        row.rate_textfield.text = "2"
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        report = H.parse_report(sheet_flow.output_flow)
        H.equal(report.loops[b_key].reason, nil, "B solves")
        H.near(report.loops[b_key].tiers[1].craft.machines, 2, "B crafts 2 per second for 1 per second of its own")
        H.equal(power_calls, 1, "totals computed once solved")
        H.near(report.rows["item/C"].rate, 2, "C for B's crafts")

        --without a B target, the uncommon B the X loop leaves is a byproduct row, even though B's loop is configured
        row.rate_textfield.text = "0"
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        report = H.parse_report(sheet_flow.output_flow)
        H.equal(report.loops[b_key], nil, "B's loop not used")
        local leftover = report.rows[b_key]
        assert(leftover, "no uncommon B row")
        H.equal(leftover.kind, "hxrrc.byproduct", "a byproduct")
        H.near(leftover.rate, -1, "one uncommon B per uncommon X")
        H.equal(leftover.recipe_button, nil, "no consumer control")
    end)

    H.test(shape .. " Q-22 (a) (b) (c) (e) (h) a loop without a recycle recipe, through the sheet and the handlers", function()
        local world = loop_world(shape, {extra = function(w)
            w.add_recipe({name = "water-only", category = "recycling", ingredients = {{type = "fluid", name = "water", amount = 1}}, products = {{name = "A", amount = 1}}})
        end})
        local key, loop = configure("X", "uncommon")
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local old = H.parse_report(sheet_flow.output_flow).loops[key]
        local old_recycle_machine = old.tiers[1].recycle.machine_button
        local old_recycle_slot = find_all(old.module_flows.recycle, "hxrrc_choose_module_button")[1]

        --(h) refused picks
        for _, name in ipairs({"X", "water-only"}) do
            old.recycle_button.elem_value = name
            fire(old.recycle_button)
            H.equal(old.recycle_button.elem_value, "X-recycling", name .. " refused")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.recycle_recipe_refused_error", name .. " text")
        end

        --(b) clearing the recycle recipe
        old.recycle_button.elem_value = nil
        fire(old.recycle_button)
        H.equal(loop.recycle_recipe_name, nil, "cleared")
        H.equal(loop.recycle.machine, nil, "machine cleared")
        H.equal(#loop.recycle.setup.modules, 0, "setup emptied")
        old_recycle_machine.elem_value = {name = "recycler", quality = "uncommon"}
        fire(old_recycle_machine)
        H.equal(loop.recycle.machine, nil, "old recycle machine button stale")
        old_recycle_slot.elem_value = {name = "q"}
        fire(old_recycle_slot)
        H.equal(#loop.recycle.setup.modules, 0, "old recycle module button stale")

        --(a) rendered without recycling; power counts the craft stage only
        local report = recompute(sheet_flow)
        local rows = report.loops[key]
        H.equal(rows.tiers[1].recycle, nil, "no recycle line")
        H.equal(rows.module_flows.recycle.children[1].type, "empty-widget", "no recycle module editor")
        H.equal(rows.recycle_button.elem_value, nil, "empty recycle picker")
        --crafts per target 10 (normal 0.9 of each stays), assembler at 100 kW with speed 0.8
        H.near(report.energy_mw, 10 / 0.8 * 0.1, "craft stage power only")

        --(c) picking it again
        rows.recycle_button.elem_value = "X-recycling"
        fire(rows.recycle_button)
        H.equal(loop.recycle.machine.name, "recycler", "recycle machine back")
        H.equal(#loop.recycle.setup.modules, 0, "empty setup")
        report = recompute(sheet_flow)
        assert(report.loops[key].tiers[1].recycle, "recycle line back")

        --(e) the only recycle machine removed: the stage is hand-crafted
        world.remove_machine("recycler")
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
        H.equal(loop.recycle.machine, nil, "no recycle machine left")
        report = recompute(sheet_flow)
        rows = report.loops[key]
        H.equal(rows.tiers[1].recycle.reason, "hxrrc.not_automatically_craftable", "recycle line hand-crafted")
        H.equal(rows.module_flows.recycle.children[1].type, "empty-widget", "no recycle module editor")
    end)

    H.test(shape .. " Q-23 with one machine prototype its quality can still be picked, on loop lines and ordinary rows", function()
        loop_world(shape, {assembler_speeds = {normal = 1, uncommon = 2}, recycler_speeds = {normal = 1, uncommon = 4}})
        local key, loop = configure("X", "uncommon")
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "A", rate = 1, unit = "/s"}})
        local report = H.parse_report(sheet_flow.output_flow)
        local rows = report.loops[key]
        H.equal(rows.tiers[2].craft.machine_button.enabled, true, "loop craft button enabled")
        H.equal(rows.tiers[1].recycle.machine_button.enabled, true, "loop recycle button enabled")

        local button = rows.tiers[2].craft.machine_button
        button.elem_value = {name = "assembler", quality = "uncommon"}
        fire(button)
        H.equal(loop.craft.machine.quality, "uncommon", "craft machine quality stored")
        report = recompute(sheet_flow)
        rows = report.loops[key]
        H.equal(#find_all(rows.module_flows.craft, "hxrrc_choose_module_button"), 5, "slots follow the machine quality")
        H.near(rows.tiers[1].craft.machines, 1 / Y / 0.8 / 2, "normal tier count at uncommon speed")
        H.near(rows.tiers[2].craft.machines, 0.0225 / Y / 0.8 / 2, "uncommon tier count at uncommon speed")
        for index, tier in ipairs(rows.tiers) do
            H.equal(tier.craft.machine_button.elem_value.quality, "uncommon", "tier " .. index .. " button shows the quality")
        end

        button = rows.tiers[1].recycle.machine_button
        button.elem_value = {name = "recycler", quality = "uncommon"}
        fire(button)
        H.equal(loop.recycle.machine.quality, "uncommon", "recycle machine quality stored")
        report = recompute(sheet_flow)
        H.near(report.loops[key].tiers[1].recycle.machines, 0.9 / Y * 0.5 / 0.8 / 4, "recyclers at uncommon speed")
    end)
end

H.test("2.0 Q-23 an ordinary row's only machine can change quality", function()
    loop_world("2.0", {assembler_speeds = {normal = 1, uncommon = 2}})
    local sheet_flow = handler_sheet({{item = "X", rate = 1, unit = "/s"}})
    local report = H.parse_report(sheet_flow.output_flow)
    local button = report.rows["item/X"].machine_button
    H.equal(button.enabled, true, "enabled with one machine")
    button.elem_value = {name = "assembler", quality = "uncommon"}
    fire(button)
    H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.X.quality, "uncommon", "stored")
    report = recompute(sheet_flow)
    H.near(report.rows["item/X"].machines, 0.5, "count at uncommon speed")
end)

H.test("2.1 Q-14 a target above normal shows why it is unavailable, and the effects label is unchanged", function()
    loop_world("2.1")
    local key = M.QualityId.encode("X", "uncommon")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local loop = report.loops[key]
    H.equal(loop.reason, "hxrrc.quality_loop_unavailable", "reason")
    H.equal(loop.tiers[1].craft.machine_button, nil, "no machine editor")
    H.equal(loop.recycle_button, nil, "no recycle editor")
    H.equal(loop.recipe_button.tags.product_full_name, "item/X", "recipe editor kept")
    storage[1].module_setups_by_recipe_name.X.modules = {{name = "q"}}
    report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
    local quality_caption
    for _, element in ipairs(find_all(report.rows["item/X"].module_cell, nil)) do
        if element.type == "label" and type(element.caption) == "table" and element.caption[2][1] == "hxrrc.quality" then quality_caption = element.caption[4] end
    end
    H.equal(quality_caption, "+25%", "2.1 label as before")
end)

H.test("locale has every quality loop reason in every language", function()
    local keys = {}
    for _, file in ipairs({"logic/quality_loop.lua", "logic/solver.lua"}) do
        local source = io.open(file):read("*a")
        for key in source:gmatch('"(quality_loop_[%w_]+)"') do keys[key] = true end
        for key in source:gmatch('"(quality_target_[%w_]+)"') do keys[key] = true end
    end
    H.equal(keys.quality_loop_unavailable and keys.quality_loop_recycle_recipe_consumes_no_target and true, true, "scan finds the reasons")
    for _, language in ipairs({"en", "cs", "ro"}) do
        local locale = io.open("locale/" .. language .. "/locale.cfg"):read("*a")
        for key, _ in pairs(keys) do
            if not locale:find("\n" .. key .. "=", 1, true) then error(language .. " locale lacks " .. key) end
        end
    end
end)

H.done("test_quality_report")
