--Quality loops in the report: a row per tier with its own settings, the recycler pool, the loop's recipe and quality control, stale controls,
--failures and the effects label
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Two qualities (normal, uncommon) unless options.chain is given. A -> X in an assembler; X -> 0.25 A in a recycler; quality module q: +0.25 quality,
---0.05 speed; speed module s: +0.25 speed; productivity module p: +0.5 productivity.
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
    world.add_module("s", "speed", {speed = 0.25})
    world.add_module("p", "productivity", {productivity = 0.5})
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

--The stored loop of a key; every calculate stores a fresh table, so read it again after one
local function L(key)
    return storage[1].quality_loops_by_key[key]
end

--Stores the valid configuration of an item's loop at a quality, as a first calculate would, with the given modules on every craft tier and the
--recycler pool (default four q each, as separate tables)
local function configure(item, quality, craft_modules, recycle_modules)
    local key = M.QualityId.encode(item, quality)
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, {type = "item", name = item, quality = quality}))
    local loop = L(key)
    if loop then
        for _, settings in pairs(loop.crafts) do settings.setup.modules = craft_modules and M.QualityLoops._deep_copy(craft_modules) or four("q") end
        loop.recycle.setup.modules = recycle_modules and M.QualityLoops._deep_copy(recycle_modules) or four("q")
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
        if name == nil or child.name == name then found[#found + 1] = child end
        find_all(child, name, found)
    end
    return found
end

local function slots(flow)
    return find_all(flow, "hxrrc_choose_module_button")
end

local function has_module_editor(flow)
    return flow.children[1] and flow.children[1].type == "flow"
end

local Y = 0.1225 --target items per normal craft in the two-tier loop with four q modules in both stages

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " Q-11 a normal and an uncommon target of one item: a solved row, a row per tier with its own editors, and the recycler pool", function()
        loop_world(shape)
        local key = configure("X", "uncommon")
        local report = H.run_sheet({{item = "X", rate = 5, unit = "/s"}, {item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        H.equal(report.energy_caption ~= "hxrrc.totals_unavailable", true, "totals shown")
        H.near(report.rows["item/X"].rate, 5, "normal X row")
        local loop = report.loops[key]
        H.equal(#loop.tiers, 2, "one row per tier")
        H.equal(report.loop_row_count, 3, "two tier rows and the pool")
        H.equal(loop.tiers[1].quality, "normal", "first tier")
        H.equal(loop.tiers[2].quality, "uncommon", "second tier")
        H.near(loop.tiers[2].rate, 1, "target rate on the last tier")
        H.near(loop.tiers[1].rate, 0.9 / Y, "normal X going to the recyclers")
        --speed multiplier 0.8; the assembler takes 1 s per craft and the recycler 0.5 s
        H.near(loop.tiers[1].craft.machines, 1 / Y / 0.8, "normal crafting machines")
        H.near(loop.tiers[2].craft.machines, 0.0225 / Y / 0.8, "uncommon crafting machines")
        H.near(loop.tiers[1].recycle.machines, 0.9 / Y * 0.5 / 0.8, "recyclers at normal")
        H.equal(loop.tiers[1].recycle.machine_button, nil, "no recycler editor on a tier row")
        H.equal(loop.tiers[1].recycle.machine_sprite.sprite, "entity/recycler", "recycler shown")
        H.equal(loop.tiers[2].recycle, nil, "nothing recycled at the target tier")
        H.near(loop.pool.recycle.machines, 0.9 / Y * 0.5 / 0.8, "pool total")
        assert(loop.pool.recycle.machine_button, "pool machine editor")
        H.equal(loop.pool.recycle_button.elem_value, "X-recycling", "recycle recipe on the pool row")
        H.equal(#slots(loop.tiers[1].module_flow), 4, "normal tier module editor")
        H.equal(#slots(loop.tiers[2].module_flow), 4, "uncommon tier module editor")
        H.equal(#slots(loop.pool.module_flow), 4, "pool module editor")
        H.near(report.rows["item/A"].rate, 5 + (1 - 0.2025) / Y, "A for both targets")
        H.equal(loop.recipe_button.name, "hxrrc_choose_loop_recipe_button", "loop recipe control")
        H.equal(loop.recipe_button.elem_type, "recipe-with-quality", "recipe and quality")
        H.equal(loop.recipe_button.elem_value.name, "X", "the item's recipe")
        H.equal(loop.recipe_button.elem_value.quality, nil, "from normal")
        local tooltip = loop.tiers[1].craft.tooltip
        H.equal(tooltip[2][1], "hxrrc.quality_chances_tooltip", "chances tooltip")
        H.equal(tooltip[3][5], "90%", "stays normal")
        H.equal(tooltip[4][5], "10%", "upgrades")
    end)

    H.test(shape .. " QL-9 Q-8 an unreachable loop shows every tier row and the pool with editors and no counts; modules added there make it solve", function()
        loop_world(shape)
        local key = configure("X", "uncommon", {}, {})
        storage[1].module_setups_by_recipe_name.X.modules = {{name = "q"}, {name = "q"}} --the recipe's own setup, which the loop does not use
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local report = H.parse_report(sheet_flow.output_flow)
        local loop = report.loops[key]
        H.equal(report.energy_caption, "hxrrc.totals_unavailable", "no totals")
        H.equal(#loop.tiers, 2, "every tier row")
        H.equal(loop.reason, "hxrrc.quality_target_unreachable", "reason on the first tier")
        for index, tier in ipairs(loop.tiers) do
            H.equal(tier.craft.machines, nil, "no count on tier " .. index)
            assert(tier.craft.machine_button, "machine editor on tier " .. index)
            H.equal(#slots(tier.module_flow), 4, "module editor on tier " .. index)
            for slot_index, slot in ipairs(slots(tier.module_flow)) do
                H.equal(H.slot_value(slot), nil, "tier " .. index .. " slot " .. slot_index .. " shows the loop's empty setup")
            end
        end
        H.equal(loop.pool.recycle.machines, nil, "no pool count")
        assert(loop.pool.recycle.machine_button, "pool editor")
        local slot = slots(loop.tiers[1].module_flow)[1]
        H.pick_module(slot, {name = "q"})
        H.equal(#L(key).crafts.normal.setup.modules, 4, "module fills the normal tier's empty row")
        H.equal(#L(key).crafts.uncommon.setup.modules, 0, "other tier untouched")
        H.equal(#storage[1].module_setups_by_recipe_name.X.modules, 2, "the recipe's own setup untouched")
        report = recompute(sheet_flow)
        loop = report.loops[key]
        H.equal(loop.reason, nil, "solved")
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
        H.equal(#report.loops[first].tiers, 2, "first loop tiers")
        H.equal(#report.loops[second].tiers, 3, "second loop tiers")
    end)

    for _, refire in ipairs({false, true}) do
        local mode = refire and " (re-fire)" or ""
        H.test(shape .. " Q-13 QL-13 stale loop controls are refused and restored" .. mode, function()
            local world = loop_world(shape, {chain = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}},
                extra = function(w)
                    w.add_recipe({name = "X2", category = "crafting", ingredients = {{name = "A", amount = 2}}, products = {{name = "X", amount = 1}}})
                    w.add_recipe({name = "X-melting", category = "recycling", ingredients = {{name = "X", amount = 1}, {name = "A", amount = 1}},
                        products = {{name = "A", amount = 2}}})
                    w.add_machine({name = "big-assembler", categories = {"crafting"}, speed = 2})
                    w.add_item("gold")
                    w.add_recipe({name = "X-sorting", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "gold", amount = 1}}})
                end})
            world.bind("item/X", "X")
            local key = configure("X", "rare")
            for _, settings in pairs(L(key).crafts) do settings.machine = {name = "assembler"} end
            local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
            local _, second_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
            local old = H.parse_report(sheet_flow.output_flow).loops[key]
            H.refire_on_script_set = refire

            --a right click on a loop machine button empties nothing and opens nothing
            local craft_button = old.tiers[1].craft.machine_button
            local crafts_before = M.QualityLoops._deep_copy(L(key).crafts)
            H.pick_choice(craft_button, nil)
            H.deep_equal(L(key).crafts, crafts_before, "right click stores nothing")
            H.equal(storage[1].module_picker, nil, "right click opens no picker")

            --a recycle recipe that takes another item
            local recycle_button = old.pool.recycle_button
            recycle_button.elem_value = "X-melting"
            fire(recycle_button)
            H.equal(recycle_button.elem_value, "X-recycling", "refused recycle pick restored")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.recycle_recipe_refused_error", "refusal text")
            H.equal(L(key).recycle_recipe_name, "X-recycling", "loop unchanged")

            --QL-13: the loop now starts at uncommon: the normal tier's old controls edit nothing
            L(key).start_quality = "uncommon"
            local normal_machine_before = M.QualityLoops._deep_copy(L(key).crafts.normal)
            local normal_button = old.tiers[1].craft.machine_button
            H.equal(H.pick_choice(normal_button, {name = "big-assembler"}), false, "stale button opens no picker")
            H.deep_equal(L(key).crafts.normal, normal_machine_before, "tier outside the loop not edited by its machine button")
            local normal_slot = slots(old.tiers[1].module_flow)[1]
            H.pick_module(normal_slot, nil)
            H.deep_equal(L(key).crafts.normal, normal_machine_before, "tier outside the loop not edited by its module button")
            L(key).start_quality = nil

            --the recycle recipe changes on another sheet: this sheet's recycle button is stale
            M.Sheet.calculate(second_flow.hxrrc_compute_button)
            local other = H.parse_report(second_flow.output_flow).loops[key]
            other.pool.recycle_button.elem_value = nil
            fire(other.pool.recycle_button)
            H.equal(L(key).recycle_recipe_name, nil, "cleared from the other sheet")
            recycle_button.elem_value = "X-sorting"
            fire(recycle_button)
            H.equal(L(key).recycle_recipe_name, nil, "stale recycle button refused")
            H.equal(recycle_button.elem_value, "X-recycling", "stale recycle button shows its snapshot")
            --its old pool machine button and pool module button are stale too
            local pool_button = old.pool.recycle.machine_button
            H.equal(H.pick_choice(pool_button, {name = "recycler", quality = "uncommon"}), false, "stale pool machine button opens no picker")
            H.equal(L(key).recycle.machine, nil, "stale pool machine button refused")
            local pool_slot = slots(old.pool.module_flow)[1]
            H.pick_module(pool_slot, nil)
            H.equal(#L(key).recycle.setup.modules, 0, "stale pool module button stores nothing")

            --the item's recipe changes: every tier's old controls are stale
            storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe.X2
            storage[1].product_full_names_by_recipe_name.X = nil
            storage[1].product_full_names_by_recipe_name.X2 = "item/X"
            local tier_before = M.QualityLoops._deep_copy(L(key).crafts.uncommon)
            local tier_button = old.tiers[2].craft.machine_button
            H.equal(H.pick_choice(tier_button, {name = "big-assembler"}), false, "stale craft machine button opens no picker")
            H.deep_equal(L(key).crafts.uncommon, tier_before, "stale craft machine button refused")
            local tier_slot = slots(old.tiers[2].module_flow)[1]
            H.pick_module(tier_slot, nil)
            H.deep_equal(L(key).crafts.uncommon, tier_before, "stale craft module button stores nothing")
            H.refire_on_script_set = false
        end)
    end

    H.test(shape .. " QL-5 (a) a speed-only module on the rare row changes only that tier's settings and machine count", function()
        loop_world(shape, {chain = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}}})
        local key = configure("X", "rare")
        L(key).crafts.rare.setup.modules = {{name = "q"}, {name = "q"}, {name = "q"}}
        local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
        local before = H.parse_report(sheet_flow.output_flow).loops[key]
        local others = {normal = M.QualityLoops._deep_copy(L(key).crafts.normal), uncommon = M.QualityLoops._deep_copy(L(key).crafts.uncommon)}
        local slot = slots(before.tiers[3].module_flow)[4]
        H.pick_module(slot, {name = "s"})
        H.equal(L(key).crafts.rare.setup.modules[4].name, "s", "stored on the rare tier")
        H.deep_equal(L(key).crafts.normal, others.normal, "normal tier settings unchanged")
        H.deep_equal(L(key).crafts.uncommon, others.uncommon, "uncommon tier settings unchanged")
        local after = recompute(sheet_flow).loops[key]
        --three q (-0.15) and one s (+0.25): speed multiplier 1.1 instead of 0.85
        H.near(after.tiers[3].craft.machines, before.tiers[3].craft.machines * 0.85 / 1.1, "rare tier machines follow its speed")
        for index = 1, 2 do
            H.near(after.tiers[index].craft.machines, before.tiers[index].craft.machines, "tier " .. index .. " machines unchanged")
            H.near(after.tiers[index].rate, before.tiers[index].rate, "tier " .. index .. " rate unchanged")
        end
    end)

    H.test(shape .. " QL-5 (b) productivity on the target tier alone changes the crafts below it", function()
        loop_world(shape)
        local key = configure("X", "uncommon")
        L(key).crafts.uncommon.setup.modules = {{name = "s"}} --one speed module, replaced by productivity below; a pick into an empty row would fill it (N5)
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local report = H.parse_report(sheet_flow.output_flow)
        H.near(report.loops[key].tiers[1].craft.machines, 400 / 49 / 0.8, "yield 49/400 per normal craft")
        local normal_before = M.QualityLoops._deep_copy(L(key).crafts.normal)
        local slot = slots(report.loops[key].tiers[2].module_flow)[1]
        H.pick_module(slot, {name = "p"})
        report = recompute(sheet_flow)
        H.near(report.loops[key].tiers[1].craft.machines, 800 / 107 / 0.8, "yield 107/800 per normal craft")
        H.near(report.loops[key].tiers[1].recycle.machines, 0.9 * 800 / 107 * 0.5 / 0.8, "normal recycling follows")
        H.deep_equal(L(key).crafts.normal, normal_before, "normal tier settings unchanged")
    end)

    for _, refire in ipairs({false, true}) do
        local mode = refire and " (re-fire)" or ""
        H.test(shape .. " QL-6 the loop's recipe and quality button checks the whole pick before storing it" .. mode, function()
            local world = loop_world(shape, {chain = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}},
                extra = function(w)
                    w.add_item("B")
                    w.add_recipe({name = "X2", category = "crafting", ingredients = {{name = "A", amount = 2}}, products = {{name = "X", amount = 1}}})
                    w.add_recipe({name = "X3", category = "crafting", ingredients = {{name = "A", amount = 3}}, products = {{name = "X", amount = 1}}})
                    w.add_recipe({name = "XB", category = "crafting", ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}, {name = "B", amount = 1}}})
                end})
            world.bind("item/X", "X")
            world.bind("item/B", "XB")
            local key = configure("X", "uncommon")
            local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
            local function button()
                return recompute(sheet_flow).loops[key].recipe_button
            end
            H.refire_on_script_set = refire
            local function pick(b, value)
                b.elem_value = value
                fire(b)
            end

            local b = button()
            pick(b, {name = "X2"})
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X2", "name-only change binds")
            H.equal(L(key).start_quality, nil, "start kept")
            H.equal(b.tags.shown.name, "X2", "shown replaced")

            b = button()
            pick(b, {name = "X2", quality = "uncommon"})
            H.equal(L(key).start_quality, "uncommon", "quality-only change sets the start")
            local report = recompute(sheet_flow)
            H.equal(#report.loops[key].tiers, 1, "tiers from the start")
            H.equal(report.loops[key].tiers[1].quality, "uncommon", "first tier is the start")

            b = report.loops[key].recipe_button
            pick(b, {name = "X"})
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X", "combined change: recipe")
            H.equal(L(key).start_quality, nil, "combined change: quality")

            b = button()
            local texts = #world.flying_texts
            pick(b, {name = "X3", quality = "rare"})
            H.equal(world.flying_texts[texts + 1][1], "hxrrc.start_quality_above_target_error", "quality above target refused")
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X", "recipe not stored")
            H.equal(L(key).start_quality, nil, "start not stored")
            H.equal(b.elem_value.name, "X", "restored name")
            H.equal(b.elem_value.quality, nil, "restored quality")

            b = button()
            pick(b, {name = "XB"})
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.recipe_already_used_by_another_product_error", "used recipe refused")
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X", "binding unchanged")

            --stale name: another sheet rebinds the item while the start stays
            b = button()
            require("gui.report").apply_binding(1, "item/X", "X2", false)
            pick(b, {name = "X3"})
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X2", "stale name refused")
            H.equal(b.elem_value.name, "X", "restored to the shown recipe")

            --stale start: changed elsewhere
            b = button()
            L(key).start_quality = "uncommon"
            pick(b, {name = "X3"})
            H.equal(L(key).start_quality, "uncommon", "stale start refused")
            H.equal(storage[1].recipes_by_product_full_name["item/X"].name, "X2", "nor the recipe")
            H.equal(b.elem_value.name, "X2", "restored to the shown recipe")
            H.equal(b.elem_value.quality, nil, "restored to the shown quality")
            --a pick equal to the shown value, "normal" written out, changes nothing and is not restored
            pick(b, {name = "X2", quality = "normal"})
            H.equal(L(key).start_quality, "uncommon", "same value is a no-op")

            --emptying unbinds and keeps the loop
            b = button()
            pick(b, nil)
            H.equal(storage[1].recipes_by_product_full_name["item/X"], nil, "unbound")
            assert(L(key), "configuration kept")
            H.refire_on_script_set = false
        end)
    end

    H.test(shape .. " QL-7 the recycler pool: total of every tier, its own editors, no recycle recipe, a hand-crafted recycle recipe", function()
        local world = loop_world(shape, {chain = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}}})
        local key = configure("X", "rare")
        local sheet_flow = handler_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
        local loop = H.parse_report(sheet_flow.output_flow).loops[key]
        H.near(loop.pool.recycle.machines, loop.tiers[1].recycle.machines + loop.tiers[2].recycle.machines, "pool total")
        H.equal(loop.tiers[2].recycle.machine_button, nil, "tier lines have no editor")
        local slot = slots(loop.pool.module_flow)[1]
        H.pick_module(slot, nil)
        H.equal(#L(key).recycle.setup.modules, 3, "pool module editor edits the recycler pool")
        H.equal(#L(key).crafts.normal.setup.modules, 4, "craft tiers untouched")

        L(key).recycle_recipe_name = nil
        loop = recompute(sheet_flow).loops[key]
        H.equal(loop.pool.recycle_button.elem_value, nil, "empty recycle picker")
        H.equal(loop.pool.recycle.machines, nil, "no pool count")
        H.equal(loop.pool.recycle.machine_button, nil, "no pool machine")
        H.equal(loop.tiers[1].recycle, nil, "no recycle lines")

        L(key).recycle_recipe_name = "X-recycling"
        world.remove_machine("recycler")
        require("logic.indexer").run()
        loop = recompute(sheet_flow).loops[key]
        H.equal(loop.pool.recycle.reason, "hxrrc.not_automatically_craftable", "hand-crafted recycling")
    end)

    H.test(shape .. " Q-15 the effects label shows a quality effect as the chance to upgrade from normal", function()
        loop_world(shape)
        local function quality_caption()
            local report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
            for _, element in ipairs(find_all(report.rows["item/X"].module_cell)) do
                if element.type == "label" and type(element.caption) == "table" and element.caption[2][1] == "hxrrc.quality" then return element.caption[4] end
            end
        end
        storage[1].module_setups_by_recipe_name.X.modules = {{name = "q"}}
        H.equal(quality_caption(), "+2.50%", "quality as chance")
        storage[1].module_setups_by_recipe_name.X.modules = {{name = "bad"}}
        H.equal(quality_caption(), "+0.00%", "a negative quality effect gives no chance")
    end)

    H.test(shape .. " Q-20 diagnostic loop rows hold exactly the editors their configuration has", function()
        loop_world(shape)
        local key = configure("X", "uncommon", {}, {})
        local loop = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}}).loops[key]
        H.equal(#loop.tiers, 2, "every tier")
        for _, tier in ipairs(loop.tiers) do
            assert(tier.craft.machine_button, "craft machine on " .. tier.quality)
            H.equal(has_module_editor(tier.module_flow), true, "module editor on " .. tier.quality)
        end
        assert(loop.pool.recycle.machine_button, "pool machine")
        H.equal(has_module_editor(loop.pool.module_flow), true, "pool module editor")
        H.equal(loop.pool.recycle_button.elem_value, "X-recycling", "recycle button")

        --no recycle recipe from the start (Q-22 (a)): two recipes could recycle X, so none is picked for the new loop
        loop_world(shape, {extra = function(world)
            world.add_recipe({name = "X-shredding", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "A", amount = 1, p = 0.5}}})
        end})
        key = M.QualityId.encode("X", "uncommon")
        loop = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}}).loops[key]
        H.equal(L(key).recycle_recipe_name, nil, "created without a recycle recipe")
        H.equal(loop.tiers[1].recycle, nil, "no recycle line")
        H.equal(loop.pool.recycle.machine_button, nil, "no pool machine")
        H.equal(loop.pool.module_flow.children[1].type, "empty-widget", "no pool module editor")
        H.equal(loop.pool.recycle_button.elem_value, nil, "empty recycle button")

        --hand-crafted item recipe
        loop_world(shape, {extra = function(world)
            world.add_item("H")
            world.add_recipe({name = "H", category = "handcraft", ingredients = {{name = "A", amount = 1}}, products = {{name = "H", amount = 1}}})
        end})
        key = configure("H", "uncommon", {}, {})
        loop = H.run_sheet({{item = "H", quality = "uncommon", rate = 1, unit = "/s"}}).loops[key]
        H.equal(loop.tiers[1].craft.machine_button, nil, "no craft machine button")
        H.equal(loop.reason, "hxrrc.quality_target_unreachable", "reason in the first craft line")
        H.equal(loop.tiers[1].module_flow.children[1].type, "empty-widget", "no craft module editor")
    end)

    H.test(shape .. " QL-10 Q-21 a loop driven backwards by another loop's byproduct shows its rows without counts", function()
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
        L(x_key).recycle_recipe_name = nil
        local power_calls = 0
        package.loaded["logic.compute_power_and_pollution"] = function() power_calls = power_calls + 1 return 0, 0 end
        package.loaded["gui.sheet"] = nil --loaded again, so it takes the spy
        local _, sheet_flow = H.fill_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "B", quality = "uncommon", rate = 0.5, unit = "/s"}})
        M.Sheet = require "gui.sheet"
        M.Sheet.calculate(sheet_flow.hxrrc_compute_button)
        local report = H.parse_report(sheet_flow.output_flow)
        H.equal(power_calls, 0, "power never computed")
        H.equal(report.energy_caption, "hxrrc.totals_unavailable", "no totals")
        local b_loop, x_loop = report.loops[b_key], report.loops[x_key]
        H.equal(b_loop.reason, "hxrrc.recipe_runs_backwards", "B's reason")
        H.equal(#b_loop.tiers, 2, "B shows every tier row")
        for _, tier in ipairs(b_loop.tiers) do
            H.equal(tier.craft.machines, nil, "no count on B's " .. tier.quality .. " row")
            assert(tier.craft.machine_button, "B's machine editor on " .. tier.quality)
        end
        assert(b_loop.recipe_button, "B's recipe editor")
        assert(b_loop.pool, "B's pool row")
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
        H.equal(leftover.kind, "hxrrc.byproduct", "a byproduct")
        H.near(leftover.rate, -1, "one uncommon B per uncommon X")
        H.equal(leftover.recipe_button, nil, "no consumer control")
    end)

    H.test(shape .. " Q-22 (a) (b) (c) (e) (h) a loop without a recycle recipe, through the sheet and the handlers", function()
        local world = loop_world(shape, {extra = function(w)
            w.add_recipe({name = "water-only", category = "recycling", ingredients = {{type = "fluid", name = "water", amount = 1}}, products = {{name = "A", amount = 1}}})
        end})
        local key = configure("X", "uncommon")
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
        local old = H.parse_report(sheet_flow.output_flow).loops[key]
        local old_pool_machine = old.pool.recycle.machine_button
        local old_pool_slot = slots(old.pool.module_flow)[1]

        --(h) refused picks
        for _, name in ipairs({"X", "water-only"}) do
            old.pool.recycle_button.elem_value = name
            fire(old.pool.recycle_button)
            H.equal(old.pool.recycle_button.elem_value, "X-recycling", name .. " refused")
            H.equal(world.flying_texts[#world.flying_texts][1], "hxrrc.recycle_recipe_refused_error", name .. " text")
        end

        --(b) clearing the recycle recipe
        old.pool.recycle_button.elem_value = nil
        fire(old.pool.recycle_button)
        H.equal(L(key).recycle_recipe_name, nil, "cleared")
        H.equal(L(key).recycle.machine, nil, "machine cleared")
        H.equal(#L(key).recycle.setup.modules, 0, "setup emptied")
        H.pick_choice(old_pool_machine, {name = "recycler", quality = "uncommon"})
        H.equal(L(key).recycle.machine, nil, "old pool machine button stale")
        H.pick_module(old_pool_slot, {name = "q"})
        H.equal(#L(key).recycle.setup.modules, 0, "old pool module button stale")

        --(a) rendered without recycling; power counts the craft tiers only
        local report = recompute(sheet_flow)
        local rows = report.loops[key]
        H.equal(rows.tiers[1].recycle, nil, "no recycle line")
        H.equal(rows.pool.module_flow.children[1].type, "empty-widget", "no pool module editor")
        H.equal(rows.pool.recycle_button.elem_value, nil, "empty recycle picker")
        --10 crafts per target at normal (0.9 of each stays) and none at uncommon; assembler at 100 kW with speed 0.8
        H.near(report.energy_mw, 10 / 0.8 * 0.1, "craft stages' power only")

        --(c) picking it again
        rows.pool.recycle_button.elem_value = "X-recycling"
        fire(rows.pool.recycle_button)
        H.equal(L(key).recycle.machine.name, "recycler", "recycle machine back")
        H.equal(#L(key).recycle.setup.modules, 0, "empty setup")
        assert(recompute(sheet_flow).loops[key].tiers[1].recycle, "recycle line back")

        --(e) the only recycle machine removed: the recycler pool is hand-crafted
        world.remove_machine("recycler")
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
        H.equal(L(key).recycle.machine, nil, "no recycle machine left")
        rows = recompute(sheet_flow).loops[key]
        H.equal(rows.tiers[1].recycle.reason, "hxrrc.not_automatically_craftable", "recycle line hand-crafted")
        H.equal(rows.pool.recycle.reason, "hxrrc.not_automatically_craftable", "pool hand-crafted")
        H.equal(rows.pool.module_flow.children[1].type, "empty-widget", "no pool module editor")
    end)

    H.test(shape .. " Q-23 with one machine prototype each tier's machine quality and the pool's can still be picked", function()
        loop_world(shape, {assembler_speeds = {normal = 1, uncommon = 2}, recycler_speeds = {normal = 1, uncommon = 4}})
        local key = configure("X", "uncommon")
        local sheet_flow = handler_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}, {item = "A", rate = 1, unit = "/s"}})
        local rows = H.parse_report(sheet_flow.output_flow).loops[key]
        H.equal(rows.tiers[2].craft.machine_button.enabled, true, "tier craft button enabled")
        H.equal(rows.pool.recycle.machine_button.enabled, true, "pool button enabled")

        local button = rows.tiers[2].craft.machine_button
        H.pick_choice(button, {name = "assembler", quality = "uncommon"})
        H.equal(L(key).crafts.uncommon.machine.quality, "uncommon", "uncommon tier's machine quality stored")
        H.equal(L(key).crafts.normal.machine.quality, nil, "normal tier unchanged")
        rows = recompute(sheet_flow).loops[key]
        H.equal(#slots(rows.tiers[2].module_flow), 5, "slots follow that tier's machine quality")
        H.equal(#slots(rows.tiers[1].module_flow), 4, "other tier's slots unchanged")
        H.near(rows.tiers[1].craft.machines, 1 / Y / 0.8, "normal tier count at normal speed")
        H.near(rows.tiers[2].craft.machines, 0.0225 / Y / 0.8 / 2, "uncommon tier count at uncommon speed")
        H.equal(rows.tiers[2].craft.machine_button.tags.quality, "uncommon", "button shows the quality")

        button = rows.pool.recycle.machine_button
        H.pick_choice(button, {name = "recycler", quality = "uncommon"})
        H.equal(L(key).recycle.machine.quality, "uncommon", "pool machine quality stored")
        rows = recompute(sheet_flow).loops[key]
        H.near(rows.tiers[1].recycle.machines, 0.9 / Y * 0.5 / 0.8 / 4, "recyclers at uncommon speed")
        H.near(rows.pool.recycle.machines, 0.9 / Y * 0.5 / 0.8 / 4, "pool total at uncommon speed")
    end)
end

H.test("2.0 Q-23 an ordinary row's only machine can change quality", function()
    loop_world("2.0", {assembler_speeds = {normal = 1, uncommon = 2}})
    local sheet_flow = handler_sheet({{item = "X", rate = 1, unit = "/s"}})
    local report = H.parse_report(sheet_flow.output_flow)
    local button = report.rows["item/X"].machine_button
    H.equal(button.enabled, true, "enabled with one machine")
    H.pick_choice(button, {name = "assembler", quality = "uncommon"})
    H.equal(storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.X.quality, "uncommon", "stored")
    report = recompute(sheet_flow)
    H.near(report.rows["item/X"].machines, 0.5, "count at uncommon speed")
end)

H.test("2.1 QL-11 Q-14 a target above normal shows why it is unavailable, and the effects label is unchanged", function()
    loop_world("2.1")
    local key = M.QualityId.encode("X", "uncommon")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local loop = report.loops[key]
    H.equal(loop.reason, "hxrrc.quality_loop_unavailable", "reason")
    H.equal(loop.tiers[1].craft.machine_button, nil, "no machine editor")
    H.equal(loop.pool, nil, "no pool row")
    H.equal(loop.recipe_button.name, "hxrrc_choose_recipe_button", "the item's ordinary recipe control")
    H.equal(loop.recipe_button.elem_type, "recipe", "without quality")
    H.equal(loop.recipe_button.tags.product_full_name, "item/X", "recipe editor kept")
    H.equal(next(storage[1].quality_loops_by_key), nil, "no loop configured")
    storage[1].module_setups_by_recipe_name.X.modules = {{name = "q"}}
    report = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
    local quality_caption
    for _, element in ipairs(find_all(report.rows["item/X"].module_cell)) do
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
    H.equal(keys.quality_loop_unavailable and keys.quality_loop_start_invalid and true, true, "scan finds the reasons")
    for _, language in ipairs({"en", "cs", "ro"}) do
        local locale = io.open("locale/" .. language .. "/locale.cfg"):read("*a")
        for key, _ in pairs(keys) do
            if not locale:find("\n" .. key .. "=", 1, true) then error(language .. " locale lacks " .. key) end
        end
    end
end)

H.done("test_quality_report")
