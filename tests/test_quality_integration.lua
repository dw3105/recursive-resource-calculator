--Quality loops inside the solver: configurations per target, the loop column's flows, power, configuration changes and research
local H = require "tests.harness"

local S = {} --modules loaded after each new world

--Two qualities (normal, uncommon) unless five = true. A -> X in an assembler; X -> 0.25 A in a recycler; quality module q: +0.25 quality, -0.05 speed.
local function loop_world(shape, options)
    options = options or {}
    local world = H.new_world(shape)
    if not options.five then
        world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    end
    world.add_item("A")
    world.add_item("X")
    world.add_fluid("water")
    world.add_module("q", "quality", {quality = 0.25, speed = -0.05})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = options.craft_slots or 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_recipe({name = "X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    --a second way to get A, so A is not bound to the recycling recipe at init (as with plates in the game)
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    if options.extra then options.extra(world) end
    world.add_player(1)
    world.init()
    S.QualityId = require "logic.quality_id"
    S.QualityLoops = require "logic.quality_loops"
    S.Solver = require "logic.solver"
    return world
end

local function four_q()
    return {{name = "q"}, {name = "q"}, {name = "q"}, {name = "q"}}
end

--The stored loop of a key; every calculate and configuration change stores a fresh table, so tests read it again after those
local function L(key)
    return storage[1].quality_loops_by_key[key]
end

--Stores the valid configuration of an item's loop at a quality, as a first calculate would, and gives every craft tier and the recycler pool the
--given modules (default four quality modules each, as separate tables)
local function configure_loop(item, quality, craft_modules, recycle_modules)
    local key = S.QualityId.encode(item, quality)
    S.QualityLoops.store(1, key, S.QualityLoops.normalized(1, key, {type = "item", name = item, quality = quality}))
    local loop = L(key)
    if loop then
        for _, settings in pairs(loop.crafts) do settings.setup.modules = craft_modules and S.QualityLoops._deep_copy(craft_modules) or four_q() end
        loop.recycle.setup.modules = recycle_modules and S.QualityLoops._deep_copy(recycle_modules) or four_q()
    end
    return key, loop
end

local function configured(quality, craft_modules, recycle_modules)
    return configure_loop("X", quality, craft_modules, recycle_modules)
end

--What on_configuration_changed runs for the mod's data
local function configuration_change()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

local function solve(targets, parts)
    return S.Solver.solve_for(targets, 1, parts)
end

local function parts_of(key, quality)
    return {[key] = {type = "item", name = "X", quality = quality}}
end

local function find_module_buttons(element, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.name == "hxrrc_choose_module_button" and H.slot_value(child) then found[#found + 1] = child end
        find_module_buttons(child, found)
    end
    return found
end

local function loop_column_of(result)
    for _, column in ipairs(result.columns) do
        if column.quality_loop then return column end
    end
end

for _, shape in ipairs({"2.0"}) do
    H.test(shape .. " Q-1 through the solver: a two-tier loop's rates, byproducts and tier flows from prototypes", function()
        loop_world(shape)
        local key, loop = configured("uncommon")
        H.equal(loop.recycle_recipe_name, "X-recycling", "default recycle recipe")
        H.equal(loop.recycle.machine.name, "recycler", "recycle machine")
        H.equal(loop.crafts.normal.machine.name, "assembler", "craft machine")
        H.equal(loop.crafts.uncommon.machine.name, "assembler", "craft machine of the target tier")
        local result = solve({[key] = 2}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "status")
        local column = loop_column_of(result)
        H.equal(column.recipe_name, "quality-loop:" .. key, "column key")
        H.near(result.recipe_rates[column.recipe_name], 2, "loop rate")
        local Y = 0.1225
        H.near(result.unsolved_rates["item/A"], 2 * (1 - 0.2025) / Y, "normal A taken")
        H.near(result.solved_rates[key], 2, "target rate")
        H.equal(column.quality_loop.tiers[1].quality, "normal", "tier 1 quality")
        H.equal(column.quality_loop.tiers[2].quality, "uncommon", "tier 2 quality")
        H.near(column.quality_loop.tiers[1].crafts, 1 / Y, "normal crafts per target")
        H.near(column.quality_loop.tiers[1].recycle_crafts, 0.9 / Y, "recycles per target")
        H.equal(result.product_parts[key].quality, "uncommon", "target parts kept")
    end)

    H.test(shape .. " Q-1 power: both stages draw for their crafts over all tiers, at their setup's speed", function()
        loop_world(shape)
        local key = configured("uncommon")
        local result = solve({[key] = 2}, parts_of(key, "uncommon"))
        local Y = 0.1225
        local craft_rate = 2 * (1 + 0.0225) / Y
        local recycle_rate = 2 * 0.9 / Y
        --speed multiplier 1 - 4 * 0.05 = 0.8; assembler 1 s per craft at 100 kW; recycler 0.5 s at 50 kW
        local expected = craft_rate * 1 / 0.8 * 100e3 + recycle_rate * 0.5 / 0.8 * 50e3
        local energy = require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates)
        H.near_relative(energy, expected, "electric power")
    end)

    H.test(shape .. " Q-7 uncommon and legendary targets of one item keep separate loops; sheets share them", function()
        loop_world(shape, {five = true})
        local uncommon = S.QualityId.encode("X", "uncommon")
        local legendary = configured("legendary")
        S.QualityLoops.store(1, uncommon, S.QualityLoops.normalized(1, uncommon, {type = "item", name = "X", quality = "uncommon"}))
        H.equal(#L(uncommon).crafts.normal.setup.modules, 0, "uncommon loop has its own empty setup")
        H.equal(#L(legendary).crafts.normal.setup.modules, 4, "legendary loop keeps its modules")
        H.equal(solve({[uncommon] = 1}, parts_of(uncommon, "uncommon")).reasons_by_column["quality-loop:" .. uncommon], "quality_target_unreachable",
            "no quality effect in the uncommon loop")
        H.equal(solve({[legendary] = 1}, parts_of(legendary, "legendary")).status, "ok", "legendary loop solves")

        H.run_sheet({{item = "X", quality = "legendary", rate = 1, unit = "/s"}})
        H.run_sheet({{item = "X", quality = "legendary", rate = 3, unit = "/s"}})
        local count = 0
        for _ in pairs(storage[1].quality_loops_by_key) do count = count + 1 end
        H.equal(count, 2, "two sheets add no loop")
        H.equal(#L(legendary).crafts.normal.setup.modules, 4, "shared loop untouched by sheets")
    end)

    H.test(shape .. " the default recycle recipe must be unique and return only the craft's ingredients or the item", function()
        loop_world(shape, {extra = function(world)
            world.add_item("gold")
            world.add_recipe({name = "X-melting", category = "recycling", ingredients = {{name = "X", amount = 2}}, products = {{name = "gold", amount = 1}}})
            world.add_recipe({name = "X-washing", category = "recycling", ingredients = {{name = "X", amount = 1}, {type = "fluid", name = "water", amount = 5}},
                products = {{name = "A", amount = 1}}})
        end})
        local _, loop = configured("uncommon")
        H.equal(loop.recycle_recipe_name, "X-recycling", "gold and fluid-taking recipes are not defaults")

        loop_world(shape, {extra = function(world)
            world.add_recipe({name = "X-shredding", category = "recycling", ingredients = {{name = "X", amount = 1}}, products = {{name = "A", amount = 1, p = 0.5}}})
        end})
        _, loop = configured("uncommon")
        H.equal(loop.recycle_recipe_name, nil, "two candidates: no default")
        H.equal(loop.recycle.machine, nil, "no recycle machine without a recipe")
        local key = S.QualityId.encode("X", "uncommon")
        local result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "loop without recycling solves")
        H.near(result.unsolved_rates["item/X"], -9, "normal X left over")
    end)

    H.test(shape .. " a loop is made only once its item has a producer; an unbound target is not a loop column", function()
        loop_world(shape)
        storage[1].recipes_by_product_full_name["item/X"] = nil
        storage[1].product_full_names_by_recipe_name.X = nil
        local key, loop = configured("uncommon")
        H.equal(loop, nil, "no loop without a producer")
        local result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(loop_column_of(result), nil, "no loop column")
        H.near(result.unsolved_rates[key], 1, "target unselected")
    end)

    H.test(shape .. " Q-5b a normal target of the item takes the loop's leftover normal items first", function()
        loop_world(shape)
        local key = configured("uncommon", four_q(), {})
        storage[1].quality_loops_by_key[key].recycle_recipe_name = nil
        S.QualityLoops.sanitize(1, key)
        local result = solve({[key] = 1, ["item/X"] = 9}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "status")
        H.near(result.recipe_rates.X, 0, "the plain recipe does not run")
        H.near(result.recipe_rates["quality-loop:" .. key], 1, "loop rate")
        H.near(result.unsolved_rates["item/A"], 10, "A for ten normal crafts")
    end)

    H.test(shape .. " Q-16 an unlock-quality research recomputes; a locked target is unreachable until unlocked", function()
        local world = loop_world(shape)
        local key = configured("uncommon")
        world.lock_quality("uncommon")
        H.equal(solve({[key] = 1}, parts_of(key, "uncommon")).reasons_by_column["quality-loop:" .. key], "quality_target_unreachable", "locked")
        world.unlock_quality("uncommon")
        H.equal(solve({[key] = 1}, parts_of(key, "uncommon")).status, "ok", "unlocked")

        require "control"
        world.handlers.on_init()
        storage.computation_stack = {}
        local force = game.players[1].force
        local research = H.lua_object("LuaTechnology", {name = "epic-quality", valid = true, force = force,
            prototype = {effects = {{type = "unlock-quality", quality = "uncommon"}}}}, {"name", "valid", "force", "prototype"})
        world.handlers.events[defines.events.on_research_finished]({research = research})
        assert(storage.computation_stack[1], "no recomputation queued")
    end)

    H.test(shape .. " Q-18 modded: a machine's own quality effect, a recycler taking a fluid, and a recipe forbidding quality (P10)", function()
        loop_world(shape, {extra = function(world)
            world.add_machine({name = "quality-assembler", categories = {"special"}, speed = 1, base_quality = 1, module_slots = 0})
            world.add_item("Z")
            world.add_recipe({name = "Z", category = "special", ingredients = {{name = "A", amount = 1}}, products = {{name = "Z", amount = 1}}})
            world.add_recipe({name = "Z-washing", category = "recycling", ingredients = {{name = "Z", amount = 1}, {type = "fluid", name = "water", amount = 10}},
                products = {{name = "A", amount = 1, p = 0.25}}})
            world.add_recipe({name = "W", category = "special", ingredients = {{name = "A", amount = 1}}, products = {{name = "W", amount = 1}},
                allowed_effects = {"speed", "productivity"}})
            world.add_item("W")
            world.add_recipe({name = "W-recycling", category = "recycling", ingredients = {{name = "W", amount = 1}}, products = {{name = "A", amount = 1, p = 0.25}}})
        end})
        local key = S.QualityId.encode("Z", "uncommon")
        local parts = {[key] = {type = "item", name = "Z", quality = "uncommon"}}
        S.QualityLoops.store(1, key, S.QualityLoops.normalized(1, key, parts[key]))
        local loop = L(key)
        H.equal(loop.crafts.normal.machine.name, "quality-assembler", "modded machine")
        loop.recycle_recipe_name = "Z-washing"
        loop.recycle.machine = {name = "recycler"}
        loop.recycle.setup.modules = four_q()
        local result = solve({[key] = 1}, parts)
        H.equal(result.status, "ok", "status")
        --same numbers as Q-1: base quality effect 1 at the craft, four modules at the recycler
        local Y = 0.1225
        H.near(result.unsolved_rates["fluid/water"], 10 * 0.9 / Y, "water for recycling")
        H.near(result.unsolved_rates["item/A"], (1 - 0.2025) / Y, "normal A")

        local w_key = S.QualityId.encode("W", "uncommon")
        local w_parts = {[w_key] = {type = "item", name = "W", quality = "uncommon"}}
        S.QualityLoops.store(1, w_key, S.QualityLoops.normalized(1, w_key, w_parts[w_key]))
        local w_loop = L(w_key)
        w_loop.recycle_recipe_name, w_loop.recycle.machine = nil, nil
        H.equal(solve({[w_key] = 1}, w_parts).reasons_by_column["quality-loop:" .. w_key], "quality_target_unreachable",
            "the machine's own quality effect does not apply to a recipe forbidding quality")
        --Q-3b: such a recipe is still a loop; a recycler with quality modules reaches the target
        w_loop.recycle_recipe_name = "W-recycling"
        w_loop.recycle.machine = {name = "recycler"}
        w_loop.recycle.setup.modules = four_q()
        result = solve({[w_key] = 1}, w_parts)
        H.equal(result.status, "ok", "a recipe forbidding quality reaches the target through the recycler")
        --normal: 1 craft, all recycled into 0.225 normal A and 0.025 uncommon A; uncommon: 0.025 crafts, output 0.025
        H.near(result.unsolved_rates["item/A"], (1 - 0.225) / 0.025, "normal A per target")
    end)

    H.test(shape .. " Q-19 configuration changes keep loops valid", function()
        local world = loop_world(shape, {extra = function(w)
            w.add_machine({name = "small-assembler", categories = {"crafting"}, speed = 0.5, module_slots = 2})
            w.add_machine({name = "old-recycler", type = "furnace", categories = {"recycling"}, speed = 1, module_slots = 4})
        end})
        local key, loop = configured("uncommon")
        loop.recycle.machine = {name = "old-recycler"}

        --the craft machine goes: the loop takes the recipe's chosen machine, and its setup fits the fewer slots
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name.X = {name = "small-assembler"}
        world.remove_machine("assembler")
        configuration_change()
        H.equal(L(key).crafts.normal.machine.name, "small-assembler", "craft machine replaced")
        H.equal(#L(key).crafts.normal.setup.modules, 2, "setup fits two slots")
        H.equal(#L(key).crafts.uncommon.setup.modules, 2, "every tier's setup fits")

        --the recycle machine goes: another one that recycles
        world.remove_machine("old-recycler")
        configuration_change()
        H.equal(L(key).recycle.machine.name, "recycler", "recycle machine replaced")

        --the recycle recipe goes: no recycling
        world.remove_recipe("X-recycling")
        configuration_change()
        H.equal(L(key).recycle_recipe_name, nil, "recycle recipe dropped")
        H.equal(L(key).recycle.machine, nil, "recycle machine dropped")

        --the craft recipe goes: the binding goes, so the target is no loop any more
        world.remove_recipe("X")
        configuration_change()
        local result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(loop_column_of(result), nil, "no loop column without a producer")

        --the quality goes: the loop goes
        world.remove_quality("uncommon")
        configuration_change()
        H.equal(storage[1].quality_loops_by_key[key], nil, "loop of a removed quality dropped")
    end)

    H.test(shape .. " Q-22 (d) (f) (g) an ineligible recycle recipe is cleared on configuration change and refused by the solver", function()
        local world = loop_world(shape)
        local Utils = require "logic.utils"
        local key, loop = configured("uncommon")
        H.equal(#loop.recycle.setup.modules, 4, "recycle setup has modules")

        --(g) the stored configuration, not normalized, given straight to the column builder: it refuses before dividing by what it consumes
        local recycling = prototypes.recipe["X-recycling"]
        local original_ingredients = recycling.ingredients
        recycling.ingredients = {{type = "fluid", name = "water", amount = 10}}
        local column = S.Solver._loop_column(1, key, {type = "item", name = "X", quality = "uncommon"}, {}, L(key))
        H.equal(column.quality_loop.reason, "quality_loop_recycle_recipe_consumes_no_target", "builder guard")
        H.equal(column.quality_loop.tiers, nil, "nothing balanced")
        --a solve normalizes first, so the same storage solves without recycling and stores nothing
        local result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "normalized before solving")
        H.equal(L(key).recycle_recipe_name, "X-recycling", "a solve does not write storage")

        --(f) the same change through a configuration change: the recipe is cleared and so is its stage
        local nil_recipe_calls = 0
        local any_machine, can_craft = Utils.get_any_crafting_machine_identifier_for, Utils.can_craft
        Utils.get_any_crafting_machine_identifier_for = function(recipe)
            if recipe == nil then nil_recipe_calls = nil_recipe_calls + 1 end
            return any_machine(recipe)
        end
        Utils.can_craft = function(name, recipe)
            if recipe == nil then nil_recipe_calls = nil_recipe_calls + 1 end
            return can_craft(name, recipe)
        end
        configuration_change()
        H.equal(L(key).recycle_recipe_name, nil, "recycle recipe cleared")
        H.equal(L(key).recycle.machine, nil, "recycle machine cleared")
        H.equal(#L(key).recycle.setup.modules, 0, "recycle setup emptied")
        result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "no-recycler state solves")
        H.near(result.unsolved_rates["item/X"], -9, "normal X left over")

        --(d) the recipe prototype removed
        recycling.ingredients = original_ingredients
        L(key).recycle_recipe_name = "X-recycling"
        world.remove_recipe("X-recycling")
        configuration_change()
        H.equal(L(key).recycle_recipe_name, nil, "removed recipe cleared")
        H.equal(nil_recipe_calls, 0, "no machine lookup with a nil recipe")
        Utils.get_any_crafting_machine_identifier_for, Utils.can_craft = any_machine, can_craft
    end)
end

H.test("2.1 Q-14 a target above normal is unavailable, and no loop is configured", function()
    loop_world("2.1")
    local key = S.QualityId.encode("X", "uncommon")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    H.equal(next(storage[1].quality_loops_by_key), nil, "no loop configured")
    local result = solve({[key] = 1}, parts_of(key, "uncommon"))
    H.equal(result.status, "infeasible", "status")
    H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_unavailable", "reason")
    assert(report, "a report is shown")
end)

H.test("2.0 QL-1 a loop starting at uncommon takes its ingredients at uncommon and solves like the two-tier loop", function()
    loop_world("2.0", {extra = function(world) world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}}) end})
    local key = configured("rare")
    L(key).start_quality = "uncommon"
    local parts = {[key] = {type = "item", name = "X", quality = "rare"}}
    local result = solve({[key] = 1}, parts)
    H.equal(result.status, "ok", "status")
    local Y = 0.1225
    local column = loop_column_of(result)
    H.equal(#column.quality_loop.tiers, 2, "uncommon and rare tiers")
    H.equal(column.quality_loop.tiers[1].quality, "uncommon", "first tier")
    H.near(result.unsolved_rates[S.QualityId.encode("A", "uncommon")], (1 - 0.2025) / Y, "A at uncommon")
    H.equal(result.unsolved_rates["item/A"], nil, "no normal A")
    H.equal(result.product_parts[S.QualityId.encode("A", "uncommon")].quality, "uncommon", "parts of the ingredient identity")
end)

H.test("2.0 QL-2 a loop starting at its target crafts once per target from ingredients at that quality", function()
    loop_world("2.0", {five = true})
    local key = configured("legendary")
    L(key).start_quality = "legendary"
    local result = solve({[key] = 2}, {[key] = {type = "item", name = "X", quality = "legendary"}})
    H.equal(result.status, "ok", "status")
    local tiers = loop_column_of(result).quality_loop.tiers
    H.equal(#tiers, 1, "one tier")
    H.near(tiers[1].crafts, 1, "one craft per target")
    H.near(tiers[1].recycle_crafts, 0, "nothing recycled")
    H.near(result.unsolved_rates[S.QualityId.encode("A", "legendary")], 2, "legendary A")
end)

--X crafted from A; A smelted from ore, by a smelter with 4 quality module slots, or by a second recipe that only a quality smelter runs
local function dependency_world()
    local world = loop_world("2.0", {extra = function(w)
        w.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}})
        w.add_item("ore")
        w.add_machine({name = "smelter", categories = {"smelt-1"}, speed = 1, module_slots = 4})
        w.add_machine({name = "quality-smelter", categories = {"smelt-2"}, speed = 1, module_slots = 4, base_quality = 2,
            allowed_effects = {"speed", "productivity", "consumption", "pollution"}})
        w.add_recipe({name = "A-smelting", category = "smelt-1", ingredients = {{name = "ore", amount = 1}}, products = {{name = "A", amount = 1}}})
        w.add_recipe({name = "A-quality-smelting", category = "smelt-2", ingredients = {{name = "ore", amount = 1}}, products = {{name = "A", amount = 1}}})
    end})
    world.bind("item/A", "A-smelting")
    local x_key = configured("rare")
    L(x_key).start_quality = "uncommon"
    return world, x_key
end

H.test("2.0 QL-3 (a) (c) an ingredient above normal is made by its own loop, stored as solved; normalizing is pure and idempotent", function()
    local _, x_key = dependency_world()
    local a_key = S.QualityId.encode("A", "uncommon")
    local a_parts = {type = "item", name = "A", quality = "uncommon"}
    H.equal(L(a_key), nil, "no stored A loop")
    local before = S.QualityLoops._deep_copy(storage[1].quality_loops_by_key)
    local snapshot = S.QualityLoops.normalized(1, a_key, a_parts)
    H.deep_equal(storage[1].quality_loops_by_key, before, "normalized writes nothing")
    assert(snapshot, "a default loop for A")

    local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    assert(L(a_key), "A's loop stored by the calculate")
    local result = solve({[x_key] = 1}, {[x_key] = {type = "item", name = "X", quality = "rare"}})
    local a_column
    for _, column in ipairs(result.columns) do
        if column.quality_loop and column.quality_loop.key == a_key then a_column = column end
    end
    assert(a_column, "A's loop column used")
    H.deep_equal(L(a_key), a_column.quality_loop.config, "stored equals solved")
    H.deep_equal(S.QualityLoops.normalized(1, a_key, a_parts), L(a_key), "idempotent")
    assert(report.loops[a_key], "A's tier rows rendered")
end)

H.test("2.0 QL-3 (b) a stored ingredient loop is repaired before solving when its item's recipe changed on another sheet", function()
    local _, x_key = dependency_world()
    local a_key = S.QualityId.encode("A", "uncommon")
    local a_parts = {type = "item", name = "A", quality = "uncommon"}
    S.QualityLoops.store(1, a_key, S.QualityLoops.normalized(1, a_key, a_parts))
    for _, settings in pairs(L(a_key).crafts) do settings.setup.modules = four_q() end
    H.equal(L(a_key).crafts.normal.machine.name, "smelter", "stored with the smelter")
    --the binding changes elsewhere: only the quality smelter runs the new recipe, with base quality 2 and no room for quality modules
    storage[1].recipes_by_product_full_name["item/A"] = prototypes.recipe["A-quality-smelting"]
    storage[1].product_full_names_by_recipe_name["A-smelting"] = nil
    storage[1].product_full_names_by_recipe_name["A-quality-smelting"] = "item/A"

    local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    H.equal(L(a_key).crafts.normal.machine.name, "quality-smelter", "machine repaired")
    H.equal(#L(a_key).crafts.normal.setup.modules, 0, "modules the machine refuses removed")
    --X loop takes (1 - 0.2025) / 0.1225 A at uncommon per target; A's loop has no recycler, and a craft ends at uncommon with 0.2 × 0.9 = 0.18
    --(the rest of its upgrades go on to rare), so 1/0.18 ore each; the stale smelter's 10% would need 1/0.09, twice as much
    --since M3 the rare A that A's loop leaves over (0.02 / 0.18 = 1/9 per uncommon A) is crafted into rare X: a share phi of the target is made
    --from it, where phi = (1 - phi) * a_demand / 9; the stale smelter leaves the same 1/9 over, so it would still need twice the ore
    local a_demand = (1 - 0.2025) / 0.1225
    local phi = (a_demand / 9) / (1 + a_demand / 9)
    H.near(report.rows["item/ore"].rate, (1 - phi) * a_demand / 0.18, "ore for the repaired loop")
    local result = solve({[x_key] = 1}, {[x_key] = {type = "item", name = "X", quality = "rare"}})
    for _, column in ipairs(result.columns) do
        if column.quality_loop and column.quality_loop.key == a_key then H.deep_equal(L(a_key), column.quality_loop.config, "stored equals solved") end
    end
    H.equal(#find_module_buttons(report.loops[a_key].tiers[1].module_flow), 0, "rendered module cell shows no slot for the refused modules")
end)

H.test("2.0 QL-8 a loop saved by 1.1.19 gets its one craft setup copied to every tier, as separate tables", function()
    loop_world("2.0", {five = true})
    local key = S.QualityId.encode("X", "legendary")
    storage[1].quality_loops_by_key[key] = {item = "X", quality = "legendary", recycle_recipe_name = "X-recycling",
        craft = {machine = {name = "assembler"}, setup = {modules = four_q(), beacons = {}}},
        recycle = {machine = {name = "recycler"}, setup = {modules = four_q(), beacons = {}}}}
    configuration_change()
    local loop = L(key)
    H.equal(loop.craft, nil, "old field gone")
    H.equal(loop.start_quality, nil, "starts at normal")
    for _, quality in ipairs({"normal", "uncommon", "rare", "epic", "legendary"}) do
        H.equal(#loop.crafts[quality].setup.modules, 4, quality .. " tier has the modules")
    end
    table.remove(loop.crafts.legendary.setup.modules)
    H.equal(#loop.crafts.epic.setup.modules, 4, "tiers do not share a table")

    local migrated = solve({[key] = 1}, {[key] = {type = "item", name = "X", quality = "legendary"}})
    loop_world("2.0", {five = true})
    local fresh_key = configured("legendary")
    L(fresh_key).crafts.legendary.setup.modules = {{name = "q"}, {name = "q"}, {name = "q"}}
    local fresh = solve({[fresh_key] = 1}, {[fresh_key] = {type = "item", name = "X", quality = "legendary"}})
    H.near_relative(migrated.unsolved_rates["item/A"], fresh.unsolved_rates["item/A"], "same A as the same settings made today")
end)

H.test("2.0 QL-12 power counts every craft tier with its own setup and the recycler pool once", function()
    loop_world("2.0")
    local key = configured("uncommon")
    L(key).crafts.uncommon.setup.modules = {}
    local result = solve({[key] = 2}, parts_of(key, "uncommon"))
    local Y = 0.1225
    --normal tier: 1/Y crafts at speed 0.8; uncommon tier: 0.0225/Y crafts at speed 1; recyclers: 0.9/Y at 0.5 s and speed 0.8
    local expected = 2 * (1 / Y) / 0.8 * 100e3 + 2 * (0.0225 / Y) / 1 * 100e3 + 2 * (0.9 / Y) * 0.5 / 0.8 * 50e3
    local energy = require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates)
    H.near_relative(energy, expected, "electric power")
end)

H.test("2.0 QL-14 a start quality that is gone, off the chain or above the target falls back to normal, once", function()
    local cases = {
        {"removed", function(world) world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "legendary", level = 5}}) end},
        {"off the chain", function(world)
            world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "legendary", level = 5}})
            world.add_unlinked_quality("rare", 2)
        end},
        {"above the target", function(world) world.set_quality_chain({{name = "normal", level = 0}, {name = "legendary", level = 5}, {name = "rare", level = 2}}) end},
    }
    for _, case in ipairs(cases) do
        local world = loop_world("2.0", {five = true})
        local key = configured("legendary")
        L(key).start_quality = "rare"
        case[2](world)
        configuration_change()
        H.equal(L(key).start_quality, nil, case[1] .. ": starts at normal")
        local once = S.QualityLoops._deep_copy(L(key))
        configuration_change()
        H.deep_equal(L(key), once, case[1] .. ": a second reinitialize changes nothing")
        local report = H.run_sheet({{item = "X", quality = "legendary", rate = 1, unit = "/s"}})
        H.equal(report.loops[key].tiers[1].quality, "normal", case[1] .. ": tiers from normal")
        H.equal(report.loops[key].recipe_button.elem_value.quality, nil, case[1] .. ": button shows normal")
    end
    --the column builder refuses a raw configuration whose start is above its target
    loop_world("2.0", {five = true})
    local key = configured("uncommon")
    local raw = S.QualityLoops._deep_copy(L(key))
    raw.start_quality = "legendary"
    raw.crafts.legendary = raw.crafts.uncommon
    local column = S.Solver._loop_column(1, key, {type = "item", name = "X", quality = "uncommon"}, {}, raw)
    H.equal(column.quality_loop.reason, "quality_loop_start_invalid", "builder guard")
end)

H.done("test_quality_integration")
