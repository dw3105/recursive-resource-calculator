--Recycle-only quality loops (round 7): an item no recipe makes (an ore) reaches a higher quality by recycling it into itself, from normal items taken
--from outside. Oracles are computed here from the recurrence, never read back from the code.
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--ore: made by nothing but ore-recycling (1 ore -> 0.25 ore), so init binds it there as the game does; gear: 2 ore in an assembler.
--q: +0.25 quality, so four of them give the recycler a quality effect of 1.0. options.extra(world) adds prototypes before init.
local function ore_world(shape, options)
    options = options or {}
    local world = H.new_world(shape or "2.0")
    if options.chain then world.set_quality_chain(options.chain) end
    world.add_item("ore")
    world.add_item("gear")
    world.add_item("X")
    world.add_item("dust")
    world.add_fluid("water")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_recipe({name = "ore-recycling", category = "recycling", hidden = true, energy = 0.5, ingredients = {{name = "ore", amount = 1}},
        products = {{name = "ore", amount = 1, p = 0.25}}})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "ore", amount = 2}}, products = {{name = "gear", amount = 1}}})
    if options.extra then options.extra(world) end
    world.add_player(1)
    world.init()
    storage[1].calculator = {force_auto_center = function() end}
    M.QualityId = require "logic.quality_id"
    M.QualityLoop = require "logic.quality_loop"
    M.QualityLoops = require "logic.quality_loops"
    M.Solver = require "logic.solver"
    return world
end

local function unbind(product_full_name)
    local player_storage = storage[1]
    local recipe = player_storage.recipes_by_product_full_name[product_full_name]
    if recipe then player_storage.product_full_names_by_recipe_name[recipe.name] = nil end
    player_storage.recipes_by_product_full_name[product_full_name] = nil
    player_storage.consumer_product_full_names[product_full_name] = nil
end

local function four_q()
    return {{name = "q"}, {name = "q"}, {name = "q"}, {name = "q"}}
end

local function key_of(item, quality)
    return M.QualityId.encode(item, quality)
end

--Stores the loop of ore at a quality as a first calculate would, with four q in the recycler pool
local function configure(quality, item)
    item = item or "ore"
    local key = key_of(item, quality)
    local config = M.QualityLoops.normalized(1, key, {type = "item", name = item, quality = quality})
    if config then
        config.recycle.setup.modules = four_q()
        for _, settings in pairs(config.crafts) do settings.setup.modules = four_q() end
    end
    M.QualityLoops.store(1, key, config)
    return key, config
end

local function solve(targets, parts, options)
    return M.Solver.solve_for(targets, 1, parts, options)
end

local function column_of(result, key)
    for _, column in ipairs(result.columns) do
        if column.product_full_name == key then return column end
    end
end

local function column_named(result, name)
    for _, column in ipairs(result.columns) do
        if column.recipe_name == name then return column end
    end
end

--Independent oracle: a chain of n tiers, every next_probability 0.1, a recycler of quality effect e returning yield of each item it takes; target
--tier T. Returns input per target, recycles per target, and {[tier] = amount per target} of items left above T.
local function oracle(n, T, e, yield)
    local function shares(start)
        local result, mass, current, p = {}, 1, start, math.min(1, e * 0.1)
        while true do
            if current == n or p == 0 then
                result[current] = (result[current] or 0) + mass
                return result
            end
            result[current] = mass * (1 - p)
            mass, current, p = mass * p, current + 1, 0.1
        end
    end
    local inflow = {[1] = 1}
    local recycles, above = 0, {}
    for u = 1, T - 1 do
        local d = shares(u)
        local x = (inflow[u] or 0) / (1 - yield * d[u])
        recycles = recycles + x
        for v, share in pairs(d) do
            if v > u then
                if v <= T then
                    inflow[v] = (inflow[v] or 0) + x * yield * share
                else
                    above[v] = (above[v] or 0) + x * yield * share
                end
            end
        end
    end
    local output = inflow[T]
    for v, amount in pairs(above) do above[v] = amount / output end
    return 1 / output, recycles / output, above
end

local function input_spec(extra)
    local spec = {input = true, quality_effect = 0, output = 1, ingredients = {}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}}
    for key, value in pairs(extra or {}) do spec[key] = value end
    return spec
end

local function none_spec()
    return {none = true, quality_effect = 0, output = 0, ingredients = {}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}}
end

local function balance(n, T, options)
    options = options or {}
    local next_probabilities, unlocked, tiers = {}, {}, {[1] = input_spec()}
    for index = 1, n do
        next_probabilities[index] = index < n and 0.1 or 0
        unlocked[index] = not (options.locked and options.locked[index])
    end
    for index = 2, T do tiers[index] = none_spec() end
    return M.QualityLoop.balance({next_probabilities = next_probabilities, unlocked = unlocked, start = 1, target = T, item = "ore",
        craft = {tiers = tiers},
        recycle = {quality_effect = options.effect or 1, consumed = 1, yields = {ore = 0.25}, fluid_ingredients = {}, fluid_products = {}}})
end

local function recycles_of(tiers)
    local total = 0
    for _, tier in ipairs(tiers) do total = total + tier.recycle_crafts end
    return total
end

H.test("R1 balance: recycle-only loops over 2, 3 and 5 tiers match the recurrence and the reviewed figures", function()
    ore_world()
    local figures = {[2] = {31, 40}, [3] = {240.25, 319}, [5] = {14430.015625, 19238.6875}}
    for T, expected in pairs(figures) do
        local result = balance(T, T)
        assert(not result.reason, "tier " .. T .. " solved: " .. tostring(result.reason))
        local input, recycles = oracle(T, T, 1, 0.25)
        H.near_relative(input, expected[1], "oracle input " .. T)
        H.near_relative(recycles, expected[2], "oracle recycles " .. T)
        H.near_relative(result.tiers[1].crafts, expected[1], "input per target, " .. T .. " tiers")
        H.near_relative(recycles_of(result.tiers), expected[2], "recycles per target, " .. T .. " tiers")
        H.near_relative(-result.items.ore[1], expected[1], "normal ore taken, " .. T .. " tiers")
        H.equal(result.tiers[T].recycle_crafts, 0, "the target tier is kept, " .. T .. " tiers")
    end
end)

H.test("R1 balance: overshoot above the target is left at its quality, per the recurrence", function()
    ore_world()
    local result = balance(5, 3)
    local input, recycles, above = oracle(5, 3, 1, 0.25)
    H.near_relative(result.tiers[1].crafts, input, "input")
    H.near_relative(recycles_of(result.tiers), recycles, "recycles")
    for tier = 4, 5 do
        assert(above[tier] > 0, "oracle leaves some at tier " .. tier)
        H.near_relative(result.items.ore[tier], above[tier], "left at tier " .. tier)
    end
end)

H.test("R1 balance: a locked tier or no quality effect is unreachable; an input tier that is also the target is refused", function()
    ore_world()
    H.equal(balance(3, 3, {locked = {[2] = true}}).reason, "quality_target_unreachable", "locked middle tier")
    H.equal(balance(3, 3, {effect = 0}).reason, "quality_target_unreachable", "no quality effect")
    local result = M.QualityLoop.balance({next_probabilities = {0.1, 0}, unlocked = {true, true}, start = 2, target = 2, item = "ore",
        craft = {tiers = {[1] = input_spec()}}, recycle = nil})
    H.equal(result.reason, "quality_loop_start_invalid", "one-tier input")
end)

H.test("R13 tier step: a tier without a recipe recycles only when it recycles and is fed; otherwise unchanged", function()
    ore_world()
    local base = {none = true, first = false, items = {}, amounts = {}, supply = {}, own = 0, returns = {}}
    local step = M.QualityLoop._tier_step(setmetatable({recycling = false, feed = 2, self_return = 0.5}, {__index = base}))
    H.equal(step.recycled, false, "no recycling: kept")
    H.equal(step.x, 2, "no recycling: x is the feed")
    step = M.QualityLoop._tier_step(setmetatable({recycling = true, feed = 0, self_return = 0.5}, {__index = base}))
    H.equal(step.recycled, false, "unfed: nothing recycled")
    step = M.QualityLoop._tier_step(setmetatable({recycling = true, feed = 2, self_return = 0.5}, {__index = base}))
    H.equal(step.recycled, true, "fed: recycled")
    H.near(step.x, 4, "fed: recycled until gone or better")
    step = M.QualityLoop._tier_step(setmetatable({recycling = true, feed = 2, self_return = 1}, {__index = base}))
    H.equal(step.reason, "quality_loop_nonconvergent", "self return 1 never converges")
end)

H.test("R6 predicates: self-recycle eligibility and whether a recipe can only lose the item", function()
    ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "ore-wet", category = "crafting", ingredients = {{name = "ore", amount = 1}, {type = "fluid", name = "water", amount = 1}},
            products = {{name = "ore", amount = 2}}})
        world.add_recipe({name = "ore-to-dust", category = "recycling", ingredients = {{name = "ore", amount = 1}}, products = {{name = "ore", amount = 1, p = 0.25}, {name = "dust", amount = 1}}})
        world.add_recipe({name = "ore-void", category = "recycling", ingredients = {{name = "ore", amount = 1}}, products = {}})
        world.add_recipe({name = "ore-with-dust", category = "recycling", ingredients = {{name = "ore", amount = 1}, {name = "dust", amount = 1}},
            products = {{name = "ore", amount = 1}}})
        world.add_recipe({name = "ore-productive", category = "recycling", maximum_productivity = 4, ingredients = {{name = "ore", amount = 1}},
            products = {{name = "ore", amount = 1, p = 0.25}}})
    end})
    local recipe = prototypes.recipe
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["ore-recycling"], "ore"), nil, "ore-recycling eligible")
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["ore-wet"], "ore"), nil, "fluid ingredient allowed")
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["ore-to-dust"], "ore"), "quality_loop_recycle_only_needs_self_recycle", "another item product")
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["ore-void"], "ore"), "quality_loop_recycle_only_needs_self_recycle", "no item product")
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["gear"], "ore"), "quality_loop_recycle_only_needs_self_recycle", "makes gear, not ore")
    H.equal(M.QualityLoop.self_recycle_refusal(recipe["ore-with-dust"], "ore"), "quality_loop_recycle_recipe_extra_item", "takes another item")
    H.equal(M.QualityLoop.never_nets_item(recipe["ore-recycling"], "ore"), true, "recycling loses ore")
    H.equal(M.QualityLoop.never_nets_item(recipe["ore-wet"], "ore"), false, "wet recipe nets ore")
    H.equal(M.QualityLoop.never_nets_item(recipe["ore-productive"], "ore"), false, "0.25 at +400% productivity is 1.25: can net ore")
end)

for _, bound in ipairs({false, true}) do
    local label = bound and "R3 bound to ore-recycling" or "R2 unbound"
    H.test("2.0 " .. label .. ": legendary ore 10 /s is one recycle-only loop taking normal ore from outside", function()
        ore_world()
        H.equal(storage[1].recipes_by_product_full_name["item/ore"].name, "ore-recycling", "init binds ore to its only recipe")
        if not bound then unbind("item/ore") end
        local key = configure("legendary")
        H.equal(key and storage[1].quality_loops_by_key[key].recycle_recipe_name, "ore-recycling", "default recycle recipe")
        local result = solve({[key] = 10}, {[key] = {type = "item", name = "ore", quality = "legendary"}})
        H.equal(result.status, "ok", "solved")
        H.equal(#result.columns, 1, "one column")
        local info = column_of(result, key).quality_loop
        H.equal(info.recycle_only, true, "recycle-only")
        H.near_relative(result.unsolved_rates["item/ore"], 144300.15625, "normal ore taken")
        H.near_relative(recycles_of(info.tiers) * 10, 192386.875, "recycle crafts")
        H.near_relative(info.input * 10, 144300.15625, "input kept for the report")
        for _, tier in ipairs(info.tiers) do H.equal(tier.crafts, 0, "no craft machines at " .. tier.quality) end
        H.equal(column_named(result, "ore-recycling"), nil, "no ordinary recycling column")
        H.equal(storage[1].quality_loops_by_key[key].recycle_only, true, "marker stored")
    end)
end

H.test("2.0 R11 power: a recycle-only loop draws recycler energy only", function()
    ore_world()
    local key = configure("uncommon")
    local result = solve({[key] = 1}, {[key] = {type = "item", name = "ore", quality = "uncommon"}})
    H.equal(result.status, "ok", "solved")
    local _, recycles = oracle(5, 2, 1, 0.25)
    local energy = require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates)
    H.near_relative(energy, recycles * 0.5 * 50e3, "recycler energy only")
end)

H.test("2.0 R4 a crafted loop starting at uncommon pulls in a recycle-only loop for its uncommon ore", function()
    ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "gear-recycling", category = "recycling", hidden = true, energy = 0.5, ingredients = {{name = "gear", amount = 1}},
            products = {{name = "ore", amount = 2, p = 0.25}}})
    end})
    local gear_key, config = configure("rare", "gear")
    config.start_quality = "uncommon"
    M.QualityLoops.store(1, gear_key, config)
    local ore_key = configure("uncommon")
    local result = solve({[gear_key] = 1}, {[gear_key] = {type = "item", name = "gear", quality = "rare"}})
    H.equal(result.status, "ok", "solved")
    local ore_column = column_of(result, ore_key)
    assert(ore_column, "uncommon ore loop found")
    H.equal(ore_column.quality_loop.recycle_only, true, "recycle-only")
    assert(result.recipe_rates[ore_column.recipe_name] > 0, "it runs")
    assert(result.unsolved_rates["item/ore"] > 0, "normal ore from outside")
    H.equal(column_of(result, gear_key).quality_loop.recycle_only, false, "the gear loop is ordinary")
end)

H.test("2.0 R6 guard scope: normal ore with a producer that nets ore, a consumer binding, or on 2.1 solves as before", function()
    local function wet(world)
        world.add_recipe({name = "ore-wet", category = "crafting", ingredients = {{name = "ore", amount = 1}, {type = "fluid", name = "water", amount = 1}},
            products = {{name = "ore", amount = 2}}})
        world.add_recipe({name = "X", category = "crafting", ingredients = {{name = "dust", amount = 1}}, products = {{name = "X", amount = 1}, {name = "ore", amount = 1}}})
    end
    for _, shape in ipairs({"2.0", "2.1"}) do
        local world = ore_world(shape, {extra = wet})
        world.bind("item/ore", "ore-wet")
        local result = solve({["item/ore"] = 10})
        H.equal(result.status, "ok", shape .. " wet producer solved")
        H.near(result.recipe_rates["ore-wet"], 10, shape .. " wet producer rate")

        world = ore_world(shape, {extra = wet})
        world.bind_consumer("item/ore", "ore-recycling")
        result = solve({["item/ore"] = 10})
        H.equal(result.status, "infeasible", shape .. " consumer as target")
        H.equal(#result.columns, 1, shape .. " consumer column kept for a target")
        H.near(result.recipe_rates["ore-recycling"], -40 / 3, shape .. " consumer runs backwards")
        world.bind("item/gear", "gear")
        result = solve({["item/gear"] = 10})
        H.equal(result.status, "infeasible", shape .. " consumer as ingredient")
        H.near(result.recipe_rates["ore-recycling"], -80 / 3, shape .. " consumer column kept for an ingredient")
        world.bind("item/X", "X")
        result = solve({["item/X"] = 10})
        H.equal(result.status, "ok", shape .. " byproduct disposal solved")
        H.near(result.recipe_rates["ore-recycling"], 40 / 3, shape .. " byproduct recycled away")
    end
    --the screenshot's producer on 2.1: as before
    ore_world("2.1")
    local result = solve({["item/gear"] = 10})
    H.equal(result.status, "infeasible", "2.1 recycling producer")
    H.near(result.recipe_rates["ore-recycling"], -80 / 3, "2.1 recycling producer column kept")
    --and on 2.0: normal ore is raw input
    ore_world("2.0")
    result = solve({["item/gear"] = 10})
    H.equal(result.status, "ok", "2.0 recycling producer: ore raw")
    H.equal(column_named(result, "ore-recycling"), nil, "2.0 no recycling column")
    H.near(result.unsolved_rates["item/ore"], 20, "2.0 ore taken from outside")
end)

H.test("2.0 R7 default pool recipe follows the self-recycle rule", function()
    local cases = {
        {"ore only", function() end, "ore-recycling"},
        {"with water", function(world)
            world.remove_recipe("ore-recycling")
            world.add_recipe({name = "ore-wash", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}, {type = "fluid", name = "water", amount = 1}},
                products = {{name = "ore", amount = 1, p = 0.25}}})
        end, "ore-wash"},
        {"with a destruction recipe", function(world)
            world.add_recipe({name = "ore-void", category = "recycling", ingredients = {{name = "ore", amount = 1}}, products = {}})
        end, "ore-recycling"},
    }
    for _, case in ipairs(cases) do
        ore_world("2.0", {extra = case[2]})
        unbind("item/ore")
        local key = key_of("ore", "uncommon")
        local config = M.QualityLoops.normalized(1, key, {type = "item", name = "ore", quality = "uncommon"})
        assert(config, case[1] .. ": configured")
        H.equal(config.recycle_recipe_name, case[3], case[1] .. ": default")
        H.equal(config.recycle_only, true, case[1] .. ": marked")
    end
    --two eligible, ore bound to one of them: the producer route is active, the pool has no unique default
    local world = ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "ore-recycling-2", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}}, products = {{name = "ore", amount = 1, p = 0.5}}})
    end})
    world.bind("item/ore", "ore-recycling")
    local key = configure("uncommon")
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, nil, "no unique default")
    local result = solve({[key] = 1}, {[key] = {type = "item", name = "ore", quality = "uncommon"}})
    H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_recycle_only_needs_recycle", "reason")
    storage[1].quality_loops_by_key[key].recycle_recipe_name = "ore-recycling-2"
    storage[1].quality_loops_by_key[key].recycle.machine = {name = "recycler"}
    result = solve({[key] = 1}, {[key] = {type = "item", name = "ore", quality = "uncommon"}})
    H.equal(result.status, "ok", "a picked pool recipe solves")
end)

H.test("2.0 R8 activation: a stored choice survives a second eligible recipe; a marked loop survives a cleared or ambiguous choice", function()
    local function second(world)
        world.add_recipe({name = "ore-recycling-2", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}}, products = {{name = "ore", amount = 1, p = 0.5}}})
    end
    local function third(world)
        world.add_recipe({name = "ore-recycling-3", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}}, products = {{name = "ore", amount = 1, p = 0.5}}})
    end
    local parts_of = function(key) return {[key] = {type = "item", name = "ore", quality = "uncommon"}} end
    local key = key_of("ore", "uncommon")

    local function prototypes_changed()
        require("logic.indexer").run()
        require("logic.player_data_updater").reinitialize(1)
    end

    --saved with A, then B appears: A still used, also without the marker
    local world = ore_world()
    unbind("item/ore")
    configure("uncommon")
    storage[1].quality_loops_by_key[key].recycle_only = nil --only the explicit choice keeps it
    second(world)
    prototypes_changed()
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, "ore-recycling", "A kept by reinitialize")
    local result = solve({[key] = 1}, parts_of(key))
    H.equal(result.status, "ok", "A kept")
    H.equal(column_of(result, key).quality_loop.config.recycle_recipe_name, "ore-recycling", "A used")

    --cleared with A and B present: still found through the marker, with a reason
    local config = storage[1].quality_loops_by_key[key]
    config.recycle_only = true
    config.recycle_recipe_name = nil
    result = solve({[key] = 1}, parts_of(key))
    assert(column_of(result, key), "cleared: column found")
    H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_recycle_only_needs_recycle", "cleared: reason")

    --saved A removed while B and C remain: found, reason
    world = ore_world()
    unbind("item/ore")
    configure("uncommon")
    second(world)
    third(world)
    world.remove_recipe("ore-recycling")
    prototypes_changed()
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, nil, "removed choice cleared")
    result = solve({[key] = 1}, parts_of(key))
    assert(column_of(result, key), "ambiguous: column found")
    H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_recycle_only_needs_recycle", "ambiguous: reason")

    --every eligible recipe gone: raw input
    world.remove_recipe("ore-recycling-2")
    world.remove_recipe("ore-recycling-3")
    prototypes_changed()
    result = solve({[key] = 1}, parts_of(key))
    H.equal(column_of(result, key), nil, "none left: no column")
    H.near(result.unsolved_rates[key], 1, "none left: raw input")

    --fresh item with A and B, nothing stored: raw input
    ore_world("2.0", {extra = second})
    unbind("item/ore")
    result = solve({[key] = 1}, parts_of(key))
    H.equal(column_of(result, key), nil, "fresh ambiguous: no column")
end)

H.test("2.0 R3b the marker survives an ordinary producer and brings the loop back once unbound", function()
    local world = ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "ore-recycling-2", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}}, products = {{name = "ore", amount = 1, p = 0.5}}})
        world.add_recipe({name = "ore-from-dust", category = "crafting", ingredients = {{name = "dust", amount = 1}}, products = {{name = "ore", amount = 1}}})
    end})
    unbind("item/ore")
    local key = key_of("ore", "uncommon")
    local parts = {[key] = {type = "item", name = "ore", quality = "uncommon"}}
    storage[1].quality_loops_by_key[key] = {item = "ore", quality = "uncommon", recycle_only = true, crafts = {},
        recycle = {setup = {modules = {}, beacons = {}}}}
    world.bind("item/ore", "ore-from-dust")
    local config = M.QualityLoops.normalized(1, key, parts[key])
    H.equal(config.recycle_only, true, "marker kept while an ordinary producer is bound")
    M.QualityLoops.store(1, key, config)
    H.equal(M.QualityLoops.recycle_only(1, "ore", key), false, "ordinary while bound")
    local result = solve({[key] = 1}, parts)
    H.equal(column_of(result, key).quality_loop.recycle_only, false, "solved as ordinary loop")
    unbind("item/ore")
    H.equal(M.QualityLoops.recycle_only(1, "ore", key), true, "recycle-only once unbound")
    result = solve({[key] = 1}, parts)
    H.equal(result.reasons_by_column["quality-loop:" .. key], "quality_loop_recycle_only_needs_recycle", "reason after unbinding")
end)

H.test("2.0 R9 a stored gear loop never becomes recycle-only when gear is unbound", function()
    ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "gear-recycling", category = "recycling", hidden = true, ingredients = {{name = "gear", amount = 1}},
            products = {{name = "ore", amount = 2, p = 0.25}}})
    end})
    local key = configure("uncommon", "gear")
    H.equal(storage[1].quality_loops_by_key[key].recycle_only, nil, "an ordinary loop gets no marker")
    unbind("item/gear")
    H.equal(M.QualityLoops.recycle_only(1, "gear", key), false, "not recycle-only")
    local result = solve({[key] = 1}, {[key] = {type = "item", name = "gear", quality = "uncommon"}})
    H.equal(column_of(result, key), nil, "no column")
end)

H.test("2.1 R14 legendary ore stays raw input", function()
    ore_world("2.1")
    unbind("item/ore")
    local key = key_of("ore", "legendary")
    H.equal(M.QualityLoops.recycle_only(1, "ore", key), false, "never on 2.1")
    local result = solve({[key] = 10}, {[key] = {type = "item", name = "ore", quality = "legendary"}})
    H.equal(#result.columns, 0, "no column")
    H.near(result.unsolved_rates[key], 10, "raw input")
end)

--Report: a sheet with the targets, computed; recompute reads the report again
local function sheet(targets)
    local _, sheet_flow = H.fill_sheet(targets)
    M.Sheet = require "gui.sheet"
    M.Report = require "gui.report"
    require "gui.calculator"
    M.Sheet.calculate(M.Sheet.compute_button_of(sheet_flow))
    return sheet_flow, H.parse_report(sheet_flow.output_flow)
end

local function recompute(sheet_flow)
    storage.computation_stack = {}
    M.Sheet.calculate(M.Sheet.compute_button_of(sheet_flow))
    return H.parse_report(sheet_flow.output_flow)
end

local function find_named(element, name, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.name == name then found[#found + 1] = child end
        find_named(child, name, found)
    end
    return found
end

local function quality_name(value)
    local quality = value and value.quality
    if type(quality) == "string" then return quality ~= "normal" and quality or nil end
    return quality and quality.name ~= "normal" and quality.name or nil
end

H.test("2.0 R12 report: a recycle-only loop shows what it takes from outside, recyclers per tier and the pool, and no craft controls", function()
    local world = ore_world()
    local key = configure("uncommon")
    local sheet_flow, report = sheet({{item = "ore", quality = "uncommon", rate = 1, unit = "/s"}})
    local loop = report.loops[key]
    assert(loop, "loop rows")
    local input, recycles = oracle(5, 2, 1, 0.25)
    H.equal(#loop.tiers, 2, "normal and uncommon rows")
    local first = loop.tiers[1]
    H.equal(first.craft.reason, "hxrrc.quality_loop_recycle_only_input", "first row: taken from outside")
    H.near_relative(tonumber(first.craft.caption[2]), input, "input rate shown")
    H.equal(first.craft.machine_button, nil, "no craft machine")
    H.equal(loop.tiers[2].craft, nil, "no craft line above the first row")
    assert(first.recycle and first.recycle.machines > 0, "normal recyclers counted")
    H.near_relative(loop.pool.recycle.machines, recycles * 0.5, "pool machines")
    H.equal(#find_named(sheet_flow.output_flow, "hxrrc_choose_tier_recipe_button"), 0, "no tier recipe buttons")
    H.equal(#find_named(loop.tiers[1].module_flow, "hxrrc_choose_module_button"), 0, "no craft module editor, first row")
    H.equal(#find_named(loop.tiers[2].module_flow, "hxrrc_choose_module_button"), 0, "no craft module editor, second row")
    H.equal(loop.recipe_button.elem_value.name, "ore-recycling", "loop recipe button shows the bound recipe")
    H.equal(loop.pool.recycle_button.elem_value, "ore-recycling", "pool recipe")
    for _, language in ipairs({"en", "cs", "ro"}) do
        local locale = io.open("locale/" .. language .. "/locale.cfg"):read("*a")
        for _, name in ipairs({"quality_loop_recycle_only_input", "quality_loop_recycle_only_needs_recycle", "quality_loop_recycle_only_needs_self_recycle",
            "start_quality_recycle_only_error", "recycle_only_recipe_refused_error"}) do
            assert(locale:find("\n" .. name .. "=", 1, true), language .. " has " .. name)
        end
    end
    local _ = world
end)

H.test("2.0 R5 the loop recipe button of a recycle-only loop shows normal, refuses a quality and keeps the stored start quality", function()
    local world = ore_world()
    local key, config = configure("rare")
    config.start_quality = "uncommon"
    M.QualityLoops.store(1, key, config)
    local sheet_flow, report = sheet({{item = "ore", quality = "rare", rate = 1, unit = "/s"}})
    local loop = report.loops[key]
    H.equal(loop.tiers[1].quality, "normal", "starts at normal")
    local button = loop.recipe_button
    H.equal(quality_name(button.elem_value), nil, "displays normal")
    H.equal(storage[1].quality_loops_by_key[key].start_quality, "uncommon", "stored start kept")
    local function pick(value)
        button.elem_value = value
        return M.Report.handle_loop_recipe_change({element = button, player_index = 1})
    end
    for index, quality in ipairs({"uncommon", "rare"}) do
        H.equal(pick({name = "ore-recycling", quality = quality}), false, quality .. ": no recalc")
        H.equal(#world.flying_texts, index, quality .. ": one message")
        H.equal(world.flying_texts[index][1], "hxrrc.start_quality_recycle_only_error", quality .. ": message")
        H.equal(button.elem_value.name, "ore-recycling", quality .. ": recipe restored")
        H.equal(quality_name(button.elem_value), nil, quality .. ": displays normal")
        H.equal(storage[1].quality_loops_by_key[key].start_quality, "uncommon", quality .. ": stored start kept")
    end
    H.equal(pick({name = "ore-recycling"}), false, "reselect normal: no recalc")
    H.equal(#world.flying_texts, 2, "reselect normal: no message")
    --stale: the stored start changed after the button was built
    storage[1].quality_loops_by_key[key].start_quality = "rare"
    H.equal(pick(nil), false, "stale: no recalc")
    H.equal(#world.flying_texts, 2, "stale: no message")
    H.equal(button.elem_value.name, "ore-recycling", "stale: restored")
    H.equal(storage[1].recipes_by_product_full_name["item/ore"].name, "ore-recycling", "stale: binding kept")
    storage[1].quality_loops_by_key[key].start_quality = "uncommon"
    --clear: unbound, the stored start stays, the loop stays recycle-only
    H.equal(pick(nil), true, "clear: recalc")
    H.equal(storage[1].recipes_by_product_full_name["item/ore"], nil, "clear: unbound")
    H.equal(storage[1].quality_loops_by_key[key].start_quality, "uncommon", "clear: stored start kept")
    H.equal(M.QualityLoops.recycle_only(1, "ore", key), true, "clear: still recycle-only")
    report = recompute(sheet_flow)
    loop = report.loops[key]
    H.equal(loop.tiers[1].craft.reason, "hxrrc.quality_loop_recycle_only_input", "clear: still solved")
    assert(loop.pool.recycle.machines > 0, "clear: pool counts")
    H.equal(loop.recipe_button.elem_value, nil, "clear: recipe button empty")
end)

H.test("2.0 R8 report: clearing the pool recipe of an unbound loop with two eligible recipes keeps the loop and its picker; picking B solves", function()
    local world = ore_world("2.0", {extra = function(world)
        world.add_recipe({name = "ore-recycling-2", category = "recycling", hidden = true, energy = 0.5, ingredients = {{name = "ore", amount = 1}},
            products = {{name = "ore", amount = 1, p = 0.5}}})
    end})
    unbind("item/ore")
    local key = key_of("ore", "uncommon")
    storage[1].quality_loops_by_key[key] = {item = "ore", quality = "uncommon", recycle_recipe_name = "ore-recycling", crafts = {},
        recycle = {machine = {name = "recycler"}, setup = {modules = four_q(), beacons = {}}}}
    local sheet_flow, report = sheet({{item = "ore", quality = "uncommon", rate = 1, unit = "/s"}})
    local loop = report.loops[key]
    assert(loop.pool.recycle.machines and loop.pool.recycle.machines > 0, "A solves: " .. tostring(loop.reason) .. " " .. tostring(loop.pool.recycle.reason))
    local button = loop.pool.recycle_button
    button.elem_value = nil
    H.equal(M.Report.handle_recycle_recipe_change({element = button, player_index = 1}), true, "cleared")
    report = recompute(sheet_flow)
    loop = report.loops[key]
    assert(loop, "cleared: loop rows kept")
    H.equal(loop.reason, "hxrrc.quality_loop_recycle_only_needs_recycle", "cleared: reason")
    button = loop.pool.recycle_button
    H.equal(button.enabled, true, "cleared: picker enabled")
    button.elem_value = "ore-recycling-2"
    H.equal(M.Report.handle_recycle_recipe_change({element = button, player_index = 1}), true, "B picked")
    storage[1].quality_loops_by_key[key].recycle.setup.modules = four_q() --clearing emptied the pool's modules
    report = recompute(sheet_flow)
    assert((report.loops[key].pool.recycle.machines or 0) > 0, "B solves")
    local _ = world
end)

H.test("2.0 R10 a recycle-only loop refuses a pool recipe returning other items; an ordinary loop still takes it", function()
    local function dust(world)
        world.add_recipe({name = "ore-to-dust", category = "recycling", hidden = true, ingredients = {{name = "ore", amount = 1}},
            products = {{name = "ore", amount = 1, p = 0.25}, {name = "dust", amount = 1}}})
    end
    local world = ore_world("2.0", {extra = dust})
    local key = configure("uncommon")
    local _, report = sheet({{item = "ore", quality = "uncommon", rate = 1, unit = "/s"}})
    local button = report.loops[key].pool.recycle_button
    button.elem_value = "ore-to-dust"
    H.equal(M.Report.handle_recycle_recipe_change({element = button, player_index = 1}), false, "refused")
    H.equal(world.flying_texts[1][1], "hxrrc.recycle_only_recipe_refused_error", "message")
    H.equal(button.elem_value, "ore-recycling", "restored")
    H.equal(storage[1].quality_loops_by_key[key].recycle_recipe_name, "ore-recycling", "stored recipe kept")

    world = ore_world("2.0", {extra = function(world)
        dust(world)
        world.add_recipe({name = "ore-from-dust", category = "crafting", ingredients = {{name = "dust", amount = 1}}, products = {{name = "ore", amount = 1}}})
    end})
    world.bind("item/ore", "ore-from-dust")
    key = configure("uncommon")
    _, report = sheet({{item = "ore", quality = "uncommon", rate = 1, unit = "/s"}})
    button = report.loops[key].pool.recycle_button
    button.elem_value = "ore-to-dust"
    H.equal(M.Report.handle_recycle_recipe_change({element = button, player_index = 1}), true, "ordinary loop takes it")
end)

H.done("test_quality_recycle_only")
