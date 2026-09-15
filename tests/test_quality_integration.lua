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

--Configures the loop of X at the quality and gives both stages four quality modules
local function configured(quality, craft_modules, recycle_modules)
    local key = S.QualityId.encode("X", quality)
    S.QualityLoops.ensure(1, key, {type = "item", name = "X", quality = quality})
    local loop = storage[1].quality_loops_by_key[key]
    if loop then
        loop.craft.setup.modules = craft_modules or four_q()
        loop.recycle.setup.modules = recycle_modules or four_q()
    end
    return key, loop
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
        H.equal(loop.craft.machine.name, "assembler", "craft machine")
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
        S.QualityLoops.ensure(1, uncommon, {type = "item", name = "X", quality = "uncommon"})
        H.equal(#storage[1].quality_loops_by_key[uncommon].craft.setup.modules, 0, "uncommon loop has its own empty setup")
        H.equal(#storage[1].quality_loops_by_key[legendary].craft.setup.modules, 4, "legendary loop keeps its modules")
        H.equal(solve({[uncommon] = 1}, parts_of(uncommon, "uncommon")).reasons_by_column["quality-loop:" .. uncommon], "quality_target_unreachable",
            "no quality effect in the uncommon loop")
        H.equal(solve({[legendary] = 1}, parts_of(legendary, "legendary")).status, "ok", "legendary loop solves")

        H.run_sheet({{item = "X", quality = "legendary", rate = 1, unit = "/s"}})
        H.run_sheet({{item = "X", quality = "legendary", rate = 3, unit = "/s"}})
        local count = 0
        for _ in pairs(storage[1].quality_loops_by_key) do count = count + 1 end
        H.equal(count, 2, "two sheets add no loop")
        H.equal(#storage[1].quality_loops_by_key[legendary].craft.setup.modules, 4, "shared loop untouched by sheets")
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
        S.QualityLoops.ensure(1, key, parts[key])
        local loop = storage[1].quality_loops_by_key[key]
        H.equal(loop.craft.machine.name, "quality-assembler", "modded machine")
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
        S.QualityLoops.ensure(1, w_key, w_parts[w_key])
        local w_loop = storage[1].quality_loops_by_key[w_key]
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
        H.equal(loop.craft.machine.name, "small-assembler", "craft machine replaced")
        H.equal(#loop.craft.setup.modules, 2, "setup fits two slots")

        --the recycle machine goes: another one that recycles
        world.remove_machine("old-recycler")
        configuration_change()
        H.equal(loop.recycle.machine.name, "recycler", "recycle machine replaced")

        --the recycle recipe goes: no recycling
        world.remove_recipe("X-recycling")
        configuration_change()
        H.equal(loop.recycle_recipe_name, nil, "recycle recipe dropped")
        H.equal(loop.recycle.machine, nil, "recycle machine dropped")

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

        --(g) written straight into storage, not sanitized: the solver refuses before dividing by what it consumes
        local recycling = prototypes.recipe["X-recycling"]
        local original_ingredients = recycling.ingredients
        recycling.ingredients = {{type = "fluid", name = "water", amount = 10}}
        local result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(result.status, "infeasible", "status")
        H.equal(result.recipe_rates, nil, "no rates")
        H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_recycle_recipe_consumes_no_target", "reason")

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
        H.equal(loop.recycle_recipe_name, nil, "recycle recipe cleared")
        H.equal(loop.recycle.machine, nil, "recycle machine cleared")
        H.equal(#loop.recycle.setup.modules, 0, "recycle setup emptied")
        result = solve({[key] = 1}, parts_of(key, "uncommon"))
        H.equal(result.status, "ok", "no-recycler state solves")
        H.near(result.unsolved_rates["item/X"], -9, "normal X left over")

        --(d) the recipe prototype removed
        recycling.ingredients = original_ingredients
        loop.recycle_recipe_name = "X-recycling"
        world.remove_recipe("X-recycling")
        configuration_change()
        H.equal(loop.recycle_recipe_name, nil, "removed recipe cleared")
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

H.done("test_quality_integration")
