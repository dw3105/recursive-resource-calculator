--Quality loops using higher-quality items made elsewhere on the sheet (Amendment M3): fed parts mixed into loop columns, shares found by a bracketed
--search, loops possible only with outside items, discovery to a closure
local H = require "tests.harness"

local M = {} --modules loaded after each new world

local CHAINS = {
    [2] = {{name = "normal", level = 0}, {name = "uncommon", level = 1}},
    [3] = {{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}},
}

--A world with the given quality chain length (2 or 3), items and recipes. Machines: assembler (crafting, 4 slots, speed 1, 100 kW); miner (mining,
--base quality 1: 10% first roll), miner0 (mining, no quality), both no slots, 50 kW; recycler (recycling, 4 slots, 50 kW); chem (chemistry, 100 kW).
--Modules: q (+0.25 quality), qq (+2.5 quality). recipes: {{name, category, ingredients = {{name, amount, type}}, products = {{name, amount, type}}}}.
local function feed_world(shape, tiers, items, fluids, recipes)
    local world = H.new_world(shape)
    world.set_quality_chain(CHAINS[tiers])
    for _, name in ipairs(items) do world.add_item(name) end
    for _, name in ipairs(fluids or {}) do world.add_fluid(name) end
    world.add_module("q", "quality", {quality = 0.25})
    world.add_module("qq", "quality", {quality = 2.5})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "miner", categories = {"mining"}, speed = 1, energy_kw = 50, module_slots = 0, base_quality = 1})
    world.add_machine({name = "miner0", categories = {"mining"}, speed = 1, energy_kw = 50, module_slots = 0})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_machine({name = "chem", categories = {"chemistry"}, speed = 1, energy_kw = 100, module_slots = 0})
    for _, recipe in ipairs(recipes) do
        world.add_recipe({name = recipe.name, category = recipe.category or "crafting", energy = recipe.energy or 1, ingredients = recipe.ingredients,
            products = recipe.products, hidden = recipe.category == "recycling"})
    end
    world.add_player(1)
    world.init()
    storage[1].calculator = {force_auto_center = function() end}
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.QualityLoop = require "logic.quality_loop"
    M.Solver = require "logic.solver"
    M.Sheet = require "gui.sheet"
    require "gui.calculator"
    M.Solver._reverse_visit_order = false
    return world
end

local function item(name, amount) return {name = name, amount = amount or 1} end

--Binds each product to its recipe and picks each recipe's machine: {["item/A"] = {"A-make", "miner"}}
local function setup(world, bindings)
    for product, entry in pairs(bindings) do
        world.bind(product, entry[1])
        if entry[2] then storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name[entry[1]] = {name = entry[2]} end
    end
end

local function modules(name, count)
    local list = {}
    for index = 1, count or 4 do list[index] = {name = name} end
    return list
end

--Stores the loop of an item at a quality. options: {modules = {[tier] = module list}, recipes = {[tier] = recipe name}, recycle = recipe name,
--recycle_modules, start}
local function loop(item_name, quality, options)
    options = options or {}
    local key = M.QualityId.encode(item_name, quality)
    local parts = {type = "item", name = item_name, quality = quality}
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, parts))
    local stored = storage[1].quality_loops_by_key[key]
    stored.start_quality = options.start
    stored.recycle_recipe_name = options.recycle
    if not options.recycle then stored.recycle = {setup = {modules = {}, beacons = {}}} end
    for tier, recipe_name in pairs(options.recipes or {}) do
        stored.crafts[tier] = stored.crafts[tier] or {setup = {modules = {}, beacons = {}}}
        stored.crafts[tier].recipe_name = recipe_name
    end
    M.QualityLoops.store(1, key, M.QualityLoops.normalized(1, key, parts))
    stored = storage[1].quality_loops_by_key[key]
    for tier, list in pairs(options.modules or {}) do stored.crafts[tier].setup.modules = list end
    if options.recycle_modules then stored.recycle.setup.modules = options.recycle_modules end
    return key, parts
end

local function solve(targets)
    local rates, parts = {}, {}
    for _, target in ipairs(targets) do
        rates[target.key] = target.rate
        parts[target.key] = target.parts
    end
    return M.Solver.solve_for(rates, 1, parts)
end

local function column_of(result, key)
    for _, column in ipairs(result.columns) do
        if column.product_full_name == key or column.recipe_name == key then return column end
    end
end

local function loop_column(result, key)
    return column_of(result, M.Solver.LOOP_PREFIX .. key)
end

--Global balance of an identity: made minus taken minus demand, over the solved rates
local function balance(result, full_name, demand)
    local total = -(demand or 0)
    for _, column in ipairs(result.columns) do
        total = total + result.recipe_rates[column.recipe_name] * (column.net_amounts[full_name] or 0)
    end
    return total
end

local function all_finite(result)
    for name, rate in pairs(result.recipe_rates or {}) do
        if rate ~= rate or rate == math.huge or rate == -math.huge then error("rate of " .. name .. " is not finite") end
    end
    for _, column in ipairs(result.columns) do
        for name, amount in pairs(column.net_amounts) do
            if amount ~= amount or amount == math.huge or amount == -math.huge then error("net " .. name .. " is not finite") end
        end
        for _, tier in ipairs(column.quality_loop and column.quality_loop.tiers or {}) do
            if tier.crafts ~= tier.crafts then error("tier crafts not finite") end
        end
    end
end

local function energy(result)
    return require("logic.compute_power_and_pollution")(1, result.columns, result.recipe_rates)
end

local function taken(result, key, tier_quality, identity)
    local info = loop_column(result, key).quality_loop
    for _, entry in ipairs(info.feed and info.feed[tier_quality] or {}) do
        if entry.identity == identity then return entry.amount * result.recipe_rates[M.Solver.LOOP_PREFIX .. key] end
    end
    return 0
end

--QF-1 world: X from 1 A (assembler), A mined 90% normal / 10% uncommon
local function qf1_world(shape)
    local world = feed_world(shape or "2.0", 2, {"A", "X"}, {}, {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    })
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/A"] = {"A-make", "miner"}})
    return world
end

H.test("2.0 QF-1 one loop fed by the row that also makes its normal input: the share settles exactly, no oscillation", function()
    qf1_world()
    local key, parts = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local result = solve({{key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "solved")
    local info = loop_column(result, key).quality_loop
    --share theta from outside: offer (1 - theta) * 10 / 9 = use theta, so theta = 10/19
    H.near_relative(info.tiers[1].crafts, 90 / 19, "normal X crafts")
    H.near_relative(info.tiers[2].crafts, 10 / 19, "uncommon X crafts")
    H.near_relative(result.recipe_rates["A-make"], 100 / 19, "A crafts")
    H.near_relative(taken(result, key, "uncommon", M.QualityId.encode("A", "uncommon")), 10 / 19, "uncommon A used")
    H.near(balance(result, M.QualityId.encode("A", "uncommon")), 0, "uncommon A balances")
    H.near(balance(result, "item/A"), 0, "normal A balances")
    H.near(balance(result, key, 1), 0, "target met")
    H.equal(result.feed_rounds <= 2, true, "at most two rounds, the second only confirming")
    --QF-10: assembler 1 s per craft at 100 kW for every X craft, miner 1 s at 50 kW
    H.near_relative(energy(result), (100 / 19) * 100e3 + (100 / 19) * 50e3, "power from the mixed crafts")
end)

H.test("2.0 QF-13 the tier row shows what the loop takes from other rows", function()
    qf1_world()
    local key = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local tooltip = report.loops[key].tiers_by_quality.uncommon.rate_tooltip
    H.equal(tooltip[2][1], "hxrrc.quality_loop_external_tooltip", "header")
    H.equal(tonumber(tooltip[3][5]) and math.abs(tonumber(tooltip[3][5]) - 10 / 19) < 1e-9, true, "uncommon A per second")
    H.equal(report.rows[M.QualityId.encode("A", "uncommon")], nil, "no uncommon A byproduct row")
    H.equal(report.loops[key].tiers_by_quality.normal.rate_tooltip, nil, "nothing taken at normal")
end)

--QF-2 world: X from 1 A with no quality effect anywhere in the loop, A mined by miner (quality) or miner0
local function qf2_world(a_machine, extra_recipes)
    local recipes = {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    }
    for _, recipe in ipairs(extra_recipes or {}) do recipes[#recipes + 1] = recipe end
    local world = feed_world("2.0", 2, {"A", "X", "gold"}, {}, recipes)
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/A"] = {"A-make", a_machine or "miner"}})
    return world
end

H.test("2.0 QF-2 a loop possible only with outside items: forced, rebound producer, and a real shortage", function()
    qf2_world()
    local key, parts = loop("X", "uncommon")
    local result = solve({{key = "item/A", rate = 9}, {key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "(a) solved with 9 normal A")
    local info = loop_column(result, key).quality_loop
    H.equal(info.forced, true, "forced")
    H.near(info.tiers[1].crafts, 0, "no normal X crafts")
    H.near(info.tiers[2].crafts, 1, "one uncommon craft")
    H.near(result.recipe_rates["A-make"], 10, "ten A crafts")
    H.equal(result.unsolved_rates[M.QualityId.encode("A", "uncommon")], nil, "uncommon A used up")
    result = solve({{key = "item/A", rate = 18}, {key = key, rate = 1, parts = parts}})
    H.near(result.unsolved_rates[M.QualityId.encode("A", "uncommon")], -1, "(a) with 18 normal A, one uncommon A left over")

    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["A-make"] = {name = "miner0"}
    result = solve({{key = "item/A", rate = 9}, {key = key, rate = 1, parts = parts}})
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. key], "quality_target_unreachable", "(b) without the miner's quality")
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["A-make"] = {name = "miner"}
    result = solve({{key = "item/A", rate = 9}, {key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "(b) restored")

    result = solve({{key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "(c) no normal A target")
    local miner = column_of(result, "A-make")
    assert(miner, "(c) A's producer found by discovery")
    H.equal(miner.product_full_name, M.QualityId.encode("A", "uncommon"), "(c) rebound to uncommon A")
    H.equal(miner.binding_full_name, "item/A", "(c) still A's binding")
    H.near(result.recipe_rates["A-make"], 10, "(c) ten A crafts")
    H.near(result.unsolved_rates["item/A"], -9, "(c) nine normal A left over")
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    H.near(report.rows[M.QualityId.encode("A", "uncommon")].rate, 1, "(c) row under uncommon A")
    H.equal(report.rows[M.QualityId.encode("A", "uncommon")].recipe_button.elem_value, "A-make", "(c) with A's recipe control")
    H.near(report.rows["item/A"].rate, -9, "(c) normal A byproduct row")

    --(d) uncommon A only as a byproduct of gold, too little
    qf2_world("miner0", {{name = "gold-make", category = "mining", ingredients = {}, products = {item("gold"), item("A")}}})
    local world_bind = function(product, recipe, machine)
        storage[1].recipes_by_product_full_name[product] = prototypes.recipe[recipe]
        storage[1].product_full_names_by_recipe_name[recipe] = product
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe] = {name = machine}
    end
    world_bind("item/gold", "gold-make", "miner")
    key, parts = loop("X", "uncommon")
    result = solve({{key = "item/gold", rate = 0.9}, {key = key, rate = 1, parts = parts}})
    H.equal(result.status, "infeasible", "(d) short")
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. key], "quality_loop_outside_supply_short", "(d) reason")
    H.equal(result.recipe_rates, nil, "(d) no rates")
    local diagnostic = H.run_sheet({{item = "gold", rate = 0.9, unit = "/s"}, {item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    H.equal(diagnostic.loops[key].reason, "hxrrc.quality_loop_outside_supply_short", "(d) shown on the loop")
    H.equal(diagnostic.loops[key].tiers[2].craft.machines, nil, "(d) no counts")
end)

H.test("2.0 QF-3 a loop at rate zero takes nothing and nothing divides by its rate", function()
    local world = feed_world("2.0", 2, {"A", "B", "X", "Y", "Z"}, {}, {
        {name = "XYZ", ingredients = {item("A")}, products = {item("X"), item("Y"), item("Z")}},
        {name = "Y-from-A", ingredients = {item("A")}, products = {item("Y")}},
        {name = "Z-from-AB", ingredients = {item("A"), item("B")}, products = {item("Z")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
    })
    setup(world, {["item/X"] = {"XYZ", "assembler"}, ["item/Y"] = {"Y-from-A", "assembler"}, ["item/Z"] = {"Z-from-AB", "assembler"},
        ["item/A"] = {"A-make", "miner"}, ["item/B"] = {"B-make", "miner0"}})
    local q4 = {normal = modules("q"), uncommon = modules("q")}
    local x_key, x_parts = loop("X", "uncommon", {modules = q4})
    local y_key, y_parts = loop("Y", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local z_key, z_parts = loop("Z", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local result = solve({{key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 1, parts = y_parts}, {key = z_key, rate = 1, parts = z_parts}})
    H.equal(result.status, "ok", "solved")
    all_finite(result)
    H.near(result.recipe_rates[M.Solver.LOOP_PREFIX .. y_key], 0, "Y's loop idle: X's loop makes the uncommon Y")
    H.near(taken(result, y_key, "uncommon", M.QualityId.encode("A", "uncommon")), 0, "idle loop takes nothing")
    H.near(balance(result, M.QualityId.encode("A", "uncommon")), 0, "uncommon A balances")
    H.equal(loop_column(result, z_key).quality_loop.parts, nil, "(b) Z needs uncommon B, which nothing makes: no fed part")

    result = solve({{key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 2, parts = y_parts}, {key = z_key, rate = 1, parts = z_parts}})
    H.near(result.recipe_rates[M.Solver.LOOP_PREFIX .. y_key], 1, "Y's loop runs once its target is raised")
    all_finite(result)
    local a_uncommon = M.QualityId.encode("A", "uncommon")
    H.near_relative(taken(result, x_key, "uncommon", a_uncommon), taken(result, y_key, "uncommon", a_uncommon), "one level: equal needs take equally")
end)

--QF-4b/QF-6 world: X (uncommon recipe takes A and B) and Y (A); rows P and Q make 3/4 uncommon A and 1/4 uncommon B for their own targets
local function shared_world(y_amount)
    local world = feed_world("2.0", 2, {"A", "B", "X", "Y", "P", "Q"}, {}, {
        {name = "X-craft", ingredients = {item("A"), item("B")}, products = {item("X")}},
        {name = "Y-craft", ingredients = {item("A", y_amount or 1)}, products = {item("Y")}},
        {name = "PA", category = "mining", ingredients = {}, products = {item("P"), item("A")}},
        {name = "QB", category = "mining", ingredients = {}, products = {item("Q"), item("B")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
    })
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/Y"] = {"Y-craft", "assembler"}, ["item/P"] = {"PA", "miner"}, ["item/Q"] = {"QB", "miner"},
        ["item/A"] = {"A-make", "miner0"}, ["item/B"] = {"B-make", "miner0"}})
    return world
end

H.test("2.0 QF-4 two loops share one identity in proportion to their full needs", function()
    feed_world("2.0", 2, {"A", "X", "Y"}, {}, {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "Y-craft", ingredients = {item("A", 2)}, products = {item("Y")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    })
    local world_setup = {["item/X"] = {"X-craft", "assembler"}, ["item/Y"] = {"Y-craft", "assembler"}, ["item/A"] = {"A-make", "miner"}}
    for product, entry in pairs(world_setup) do
        storage[1].recipes_by_product_full_name[product] = prototypes.recipe[entry[1]]
        storage[1].product_full_names_by_recipe_name[entry[1]] = product
        storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name[entry[1]] = {name = entry[2]}
    end
    local x_key, x_parts = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local y_key, y_parts = loop("Y", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local a_uncommon = M.QualityId.encode("A", "uncommon")
    local result = solve({{key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 1, parts = y_parts}})
    H.equal(result.status, "ok", "solved")
    H.near_relative(taken(result, x_key, "uncommon", a_uncommon) * 2, taken(result, y_key, "uncommon", a_uncommon), "use 1 : 2, as full needs 1 : 2")
    H.near(balance(result, a_uncommon), 0, "uncommon A used up")
    result = solve({{key = "item/A", rate = 1000}, {key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 1, parts = y_parts}})
    H.near_relative(taken(result, x_key, "uncommon", a_uncommon), 1, "full need of X")
    H.near_relative(taken(result, y_key, "uncommon", a_uncommon), 2, "full need of Y")
    H.near_relative(result.unsolved_rates[a_uncommon], -(1000 / 9 - 3), "the rest left over")
end)

H.test("2.0 QF-4b a loop held back by its scarcer ingredient leaves its share of the other to the rest", function()
    shared_world()
    local x_key, x_parts = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local y_key, y_parts = loop("Y", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    --P 6.75 normal from 7.5 crafts: 0.75 uncommon A; Q 2.25 from 2.5 crafts: 0.25 uncommon B
    local result = solve({{key = "item/P", rate = 6.75}, {key = "item/Q", rate = 2.25}, {key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 1, parts = y_parts}})
    H.equal(result.status, "ok", "solved")
    local a_uncommon, b_uncommon = M.QualityId.encode("A", "uncommon"), M.QualityId.encode("B", "uncommon")
    H.near_relative(taken(result, x_key, "uncommon", b_uncommon), 1 / 4, "X limited by B to 1/4")
    H.near_relative(taken(result, x_key, "uncommon", a_uncommon), 1 / 4, "X takes 1/4 A")
    H.near_relative(taken(result, y_key, "uncommon", a_uncommon), 1 / 2, "Y takes the rest: level 1/2")
    H.near(balance(result, a_uncommon), 0, "uncommon A used up")
    H.near(balance(result, b_uncommon), 0, "uncommon B used up")
end)

H.test("2.0 QF-6 a multi-item tier is limited by its scarcest outside item; the other stays over", function()
    shared_world()
    local x_key, x_parts = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local result = solve({{key = "item/P", rate = 6.75}, {key = "item/Q", rate = 2.25}, {key = x_key, rate = 1, parts = x_parts}})
    local a_uncommon, b_uncommon = M.QualityId.encode("A", "uncommon"), M.QualityId.encode("B", "uncommon")
    H.near_relative(taken(result, x_key, "uncommon", b_uncommon), 1 / 4, "share = B's level")
    H.near_relative(result.unsolved_rates[a_uncommon], -1 / 2, "uncommon A left over")
    H.near(balance(result, b_uncommon), 0, "uncommon B used up")
end)

H.test("2.0 QF-4c a loop covered by higher-tier items leaves its lower-tier share to another loop", function()
    local world = feed_world("2.0", 3, {"A", "B", "X", "Y", "P"}, {}, {
        {name = "X-from-B", ingredients = {item("B")}, products = {item("X")}},
        {name = "X-from-A", ingredients = {item("A")}, products = {item("X")}},
        {name = "Y-from-B", ingredients = {item("B")}, products = {item("Y")}},
        {name = "Y-from-A", ingredients = {item("A", 5)}, products = {item("Y")}},
        {name = "PA", category = "mining", ingredients = {}, products = {item("P"), item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
    })
    setup(world, {["item/X"] = {"X-from-B", "assembler"}, ["item/Y"] = {"Y-from-B", "assembler"}, ["item/P"] = {"PA", "miner"}, ["item/B"] = {"B-make", "miner0"}})
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["X-from-A"] = {name = "assembler"}
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["Y-from-A"] = {name = "assembler"}
    --X: uncommon crafts all rise to rare (qq), so one uncommon A per target from its uncommon part; one rare A from its rare part
    local x_key, x_parts = loop("X", "rare", {recipes = {uncommon = "X-from-A", rare = "X-from-A"},
        modules = {normal = modules("q"), uncommon = modules("qq"), rare = modules("q")}})
    local y_key, y_parts = loop("Y", "uncommon", {recipes = {uncommon = "Y-from-A"}, modules = {normal = modules("q"), uncommon = modules("q")}})
    --P from 50 crafts: 4.5 uncommon and 0.5 rare A
    local result = solve({{key = "item/P", rate = 45}, {key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 1, parts = y_parts}})
    H.equal(result.status, "ok", "solved")
    local a_uncommon, a_rare = M.QualityId.encode("A", "uncommon"), M.QualityId.encode("A", "rare")
    H.near_relative(taken(result, x_key, "rare", a_rare), 1 / 2, "rare A covers half of X")
    H.near_relative(taken(result, x_key, "uncommon", a_uncommon), 1 / 2, "X's uncommon share capped at the other half")
    --Y's level 4/5 is above X's cap: 1/2 + 5 * level = 4.5
    H.near_relative(taken(result, y_key, "uncommon", a_uncommon), 4, "Y takes the rest at level 4/5")
    H.near(balance(result, a_uncommon), 0, "uncommon A used up")
    H.near(balance(result, a_rare), 0, "rare A used up")
end)

--QF-5/QF-9 world: 3 tiers, X from 1 A on four q in every tier, A mined 90/9/1
local function multi_tier_world()
    local world = feed_world("2.0", 3, {"A", "X"}, {}, {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    })
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/A"] = {"A-make", "miner"}})
    return loop("X", "rare", {modules = {normal = modules("q"), uncommon = modules("q"), rare = modules("q")}})
end

H.test("2.0 QF-5 two feed tiers of one loop: top tier first, exact shares against a closed form", function()
    local key, parts = multi_tier_world()
    local result = solve({{key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "solved")
    --own share s needs 100 s normal A, mined as 1000 s / 9 crafts: 0.01 of them rare (= rare share 10 s / 9), 0.09 uncommon (= 10 * uncommon share),
    --so s + 10 s / 9 + s = 1: s = 9/28, rare share 5/14, uncommon share 9/28
    local s = 9 / 28
    H.near_relative(result.recipe_rates["A-make"], s * 1000 / 9, "A crafts")
    H.near_relative(taken(result, key, "rare", M.QualityId.encode("A", "rare")), 5 / 14, "rare A")
    H.near_relative(taken(result, key, "uncommon", M.QualityId.encode("A", "uncommon")), 10 * 9 / 28, "uncommon A")
    H.near(balance(result, M.QualityId.encode("A", "uncommon")), 0, "uncommon A balances")
    H.near(balance(result, M.QualityId.encode("A", "rare")), 0, "rare A balances")
    H.equal(result.feed_rounds >= 2, true, "coupled identities take more than one round")
    M.qf5_rounds = result.feed_rounds
end)

H.test("2.0 QF-9 a search that cannot settle within its limit says so, without claiming the sheet impossible", function()
    local key, parts = multi_tier_world()
    M.Solver.FEED_ROUND_LIMIT = 1
    local ok, err = pcall(function()
        local result = solve({{key = key, rate = 1, parts = parts}})
        H.equal(result.status, "infeasible", "stopped")
        H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. key], "quality_feed_solve_limit", "calculator limit reason")
        local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
        H.equal(report.loops[key].reason, "hxrrc.quality_feed_solve_limit", "shown on the loop")
        H.equal(report.loops[key].tiers[1].craft.machines, nil, "no counts")
        assert(report.loops[key].tiers[1].craft.machine_button, "editors kept")
    end)
    M.Solver.FEED_ROUND_LIMIT = 50
    if not ok then error(err, 0) end
    local locale = io.open("locale/en/locale.cfg"):read("*a")
    H.equal(locale:find("quality_feed_solve_limit=[^\n]*may still be possible") ~= nil, true, "text says the sheet may still be possible")
    H.equal(solve({{key = key, rate = 1, parts = parts}}).status, "ok", "limit restored: solved")
end)

H.test("2.0 QF-7 an identity another loop is solved for is not fed", function()
    local world = feed_world("2.0", 2, {"A", "X", "Z"}, {}, {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "Z-craft", ingredients = {item("A")}, products = {item("Z")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    })
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/Z"] = {"Z-craft", "assembler"}, ["item/A"] = {"A-make", "miner"}})
    local x_key, x_parts = loop("X", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local z_key, z_parts = loop("Z", "uncommon", {start = "uncommon"})
    local result = solve({{key = x_key, rate = 1, parts = x_parts}, {key = z_key, rate = 1, parts = z_parts}})
    assert(loop_column(result, M.QualityId.encode("A", "uncommon")), "uncommon A solved by its own loop")
    H.equal(loop_column(result, x_key).quality_loop.parts, nil, "X not fed from a solved identity")
    H.equal(result.feed_rounds, nil, "no share search")
end)

H.test("2.0 QF-8 a loop's leftovers feed another loop", function()
    --X crafts from B at normal and from A above, so the normal A Y's loop leaves over is a plain byproduct
    local world = feed_world("2.0", 2, {"A", "B", "C", "X", "Y"}, {}, {
        {name = "X-from-B", ingredients = {item("B")}, products = {item("X")}},
        {name = "X-from-A", ingredients = {item("A")}, products = {item("X")}},
        {name = "Y-craft", ingredients = {item("C")}, products = {item("Y"), item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
        {name = "C-make", category = "mining", ingredients = {}, products = {item("C")}},
    })
    setup(world, {["item/X"] = {"X-from-B", "assembler"}, ["item/Y"] = {"Y-craft", "assembler"}, ["item/B"] = {"B-make", "miner0"}, ["item/C"] = {"C-make", "miner0"}})
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["X-from-A"] = {name = "assembler"}
    local x_key, x_parts = loop("X", "uncommon", {recipes = {uncommon = "X-from-A"}, modules = {normal = modules("q"), uncommon = modules("q")}})
    local y_key, y_parts = loop("Y", "uncommon", {modules = {normal = modules("q"), uncommon = modules("q")}})
    local result = solve({{key = x_key, rate = 1, parts = x_parts}, {key = y_key, rate = 10, parts = y_parts}})
    H.equal(result.status, "ok", "solved")
    local a_uncommon = M.QualityId.encode("A", "uncommon")
    assert(loop_column(result, x_key).quality_loop.parts, "X fed")
    H.equal(taken(result, x_key, "uncommon", a_uncommon) > 0, true, "X takes Y's uncommon A")
    H.equal(balance(result, a_uncommon) >= -1e-9, true, "never more taken than made")
end)

H.test("2.1 QF-11 no fed parts and no search on 2.1", function()
    qf1_world("2.1")
    local calls = 0
    local balance_function = M.QualityLoop.balance
    M.QualityLoop.balance = function(...) calls = calls + 1; return balance_function(...) end
    local key = M.QualityId.encode("X", "uncommon")
    local result = solve({{key = key, rate = 1, parts = {type = "item", name = "X", quality = "uncommon"}}})
    M.QualityLoop.balance = balance_function
    H.equal(calls, 0, "no balance")
    H.equal(result.feed_rounds, nil, "no search")
end)

H.test("2.0 QF-12 sheets without outside higher-quality items: no fed parts, no search", function()
    feed_world("2.0", 2, {"A", "X"}, {}, {
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "X-recycling", category = "recycling", energy = 0.5, ingredients = {item("X")}, products = {{name = "A", amount = 1, p = 0.25}}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
    })
    storage[1].recipes_by_product_full_name["item/X"] = prototypes.recipe["X-craft"]
    storage[1].product_full_names_by_recipe_name["X-craft"] = "item/X"
    storage[1].recipes_by_product_full_name["item/A"] = prototypes.recipe["A-make"]
    storage[1].product_full_names_by_recipe_name["A-make"] = "item/A"
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["A-make"] = {name = "miner0"}
    local key, parts = loop("X", "uncommon", {recycle = "X-recycling", modules = {normal = modules("q"), uncommon = modules("q")}, recycle_modules = modules("q")})
    local result = solve({{key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "solved")
    H.equal(loop_column(result, key).quality_loop.parts, nil, "no fed part")
    H.equal(result.feed_rounds, nil, "no search")
    --QL-1-like numbers unchanged: four q in both stages give 0.1225 target per normal craft
    H.near_relative(loop_column(result, key).quality_loop.tiers[1].crafts, 1 / 0.1225, "normal crafts as before")
end)

H.test("2.0 QF-14 outside items complement the loop's own returned leftovers", function()
    local world = feed_world("2.0", 2, {"A", "B", "X"}, {}, {
        {name = "X-craft", ingredients = {item("A", 2), item("B")}, products = {item("X")}},
        {name = "X-recycling", category = "recycling", ingredients = {item("X")}, products = {item("A"), item("B")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
    })
    setup(world, {["item/X"] = {"X-craft", "assembler"}, ["item/A"] = {"A-make", "miner"}, ["item/B"] = {"B-make", "miner0"}})
    local key, parts = loop("X", "uncommon", {recycle = "X-recycling", modules = {normal = modules("q"), uncommon = modules("q")}, recycle_modules = modules("q")})
    local result = solve({{key = key, rate = 1, parts = parts}})
    H.equal(result.status, "ok", "solved")
    local info = loop_column(result, key).quality_loop
    H.near_relative(info.tiers[1].crafts, 100 / 19, "normal X crafts")
    H.near_relative(info.tiers[2].crafts, 9 / 19, "uncommon X crafts")
    H.near_relative(result.recipe_rates["A-make"], 1190 / 171, "A crafts")
    H.near_relative(result.recipe_rates["B-make"], 1, "B crafts")
    local a_uncommon, b_uncommon = M.QualityId.encode("A", "uncommon"), M.QualityId.encode("B", "uncommon")
    H.near_relative(taken(result, key, "uncommon", a_uncommon), 9 / 19, "outside uncommon A")
    H.near_relative(result.unsolved_rates[a_uncommon], -2 / 9, "uncommon A left over")
    H.equal(result.unsolved_rates[b_uncommon], nil, "uncommon B used up")
    H.equal(taken(result, key, "uncommon", b_uncommon), 0, "own B not listed as taken")
end)

--QF-15 world: B mined 90/10; Y from B leaving A; X from A; A mined normal only
local function chain_world(b_machine)
    local world = feed_world("2.0", 2, {"A", "B", "C", "X", "Y", "P", "Z"}, {}, {
        {name = "Y-craft", ingredients = {item("B")}, products = {item("Y"), item("A")}},
        {name = "X-craft", ingredients = {item("A")}, products = {item("X")}},
        {name = "P-craft", ingredients = {item("C")}, products = {item("P"), item("A")}},
        {name = "Z-craft", ingredients = {item("A")}, products = {item("Z"), item("C")}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
        {name = "C-make", category = "mining", ingredients = {}, products = {item("C")}},
    })
    setup(world, {["item/Y"] = {"Y-craft", "assembler"}, ["item/X"] = {"X-craft", "assembler"}, ["item/P"] = {"P-craft", "assembler"},
        ["item/Z"] = {"Z-craft", "assembler"}, ["item/A"] = {"A-make", "miner0"}, ["item/B"] = {"B-make", b_machine or "miner"},
        ["item/C"] = {"C-make", "miner0"}})
end

H.test("2.0 QF-15 a chain of loops possible only with outside items, in any visiting order, and no self-seeded cycle", function()
    chain_world()
    local y_key, y_parts = loop("Y", "uncommon")
    local x_key, x_parts = loop("X", "uncommon")
    local targets = {{key = "item/B", rate = 9}, {key = y_key, rate = 1, parts = y_parts}, {key = x_key, rate = 1, parts = x_parts}}
    local function check(result, what)
        H.equal(result.status, "ok", what .. ": solved")
        H.near(result.recipe_rates["B-make"], 10, what .. ": B crafts")
        H.near(loop_column(result, y_key).quality_loop.tiers[2].crafts, 1, what .. ": uncommon Y crafts")
        H.near(loop_column(result, x_key).quality_loop.tiers[2].crafts, 1, what .. ": uncommon X crafts")
        H.near(loop_column(result, y_key).quality_loop.tiers[1].crafts, 0, what .. ": no normal Y crafts")
        H.near(balance(result, M.QualityId.encode("B", "uncommon")), 0, what .. ": uncommon B balances")
        H.near(balance(result, M.QualityId.encode("A", "uncommon")), 0, what .. ": uncommon A balances")
    end
    check(solve(targets), "in order")
    check(solve({targets[3], targets[2], targets[1]}), "targets reversed")
    M.Solver._reverse_visit_order = true
    local ok, err = pcall(check, solve(targets), "queue reversed")
    M.Solver._reverse_visit_order = false
    if not ok then error(err, 0) end

    chain_world("miner0")
    y_key, y_parts = loop("Y", "uncommon")
    x_key, x_parts = loop("X", "uncommon")
    local result = solve({{key = "item/B", rate = 9}, {key = y_key, rate = 1, parts = y_parts}, {key = x_key, rate = 1, parts = x_parts}})
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. y_key], "quality_target_unreachable", "no uncommon B: Y unreachable")
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. x_key], "quality_target_unreachable", "and X")

    chain_world()
    local p_key, p_parts = loop("P", "uncommon")
    local z_key, z_parts = loop("Z", "uncommon")
    result = solve({{key = p_key, rate = 1, parts = p_parts}, {key = z_key, rate = 1, parts = z_parts}})
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. p_key], "quality_target_unreachable", "cycle P unseeded")
    H.equal(result.reasons_by_column[M.Solver.LOOP_PREFIX .. z_key], "quality_target_unreachable", "cycle Z unseeded")
end)

H.test("2.0 QF-16 a fed tier's fluid input brings in its producer", function()
    local world = feed_world("2.0", 2, {"A", "B", "C", "X"}, {"F"}, {
        {name = "X-from-B", ingredients = {item("B")}, products = {item("X")}},
        {name = "X-from-AF", ingredients = {item("A"), {type = "fluid", name = "F", amount = 1}}, products = {item("X")}},
        {name = "F-make", category = "chemistry", ingredients = {item("C", 2)}, products = {{type = "fluid", name = "F", amount = 1}}},
        {name = "A-make", category = "mining", ingredients = {}, products = {item("A")}},
        {name = "B-make", category = "mining", ingredients = {}, products = {item("B")}},
    })
    setup(world, {["item/X"] = {"X-from-B", "assembler"}, ["item/A"] = {"A-make", "miner"}, ["item/B"] = {"B-make", "miner0"}, ["fluid/F"] = {"F-make", "chem"}})
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["X-from-AF"] = {name = "assembler"}
    local key, parts = loop("X", "uncommon", {recipes = {uncommon = "X-from-AF"}, modules = {normal = modules("q")}})
    local targets = {{key = "item/A", rate = 9}, {key = key, rate = 1, parts = parts}}
    local result = solve(targets)
    H.equal(result.status, "ok", "solved")
    H.near(result.recipe_rates["F-make"], 1, "F producer at one craft")
    H.near(result.unsolved_rates["item/C"], 2, "two C a second")
    --miner 10 crafts at 50 kW, uncommon X 1 craft at 100 kW, F 1 craft at 100 kW
    H.near_relative(energy(result), 10 * 50e3 + 1 * 100e3 + 1 * 100e3, "power includes the F producer")

    storage[1].recipes_by_product_full_name["fluid/F"] = nil
    storage[1].product_full_names_by_recipe_name["F-make"] = nil
    result = solve(targets)
    H.near(result.unsolved_rates["fluid/F"], 1, "unbound F shown as needed")
    H.equal(column_of(result, "F-make"), nil, "no F producer")
    world.bind("fluid/F", "F-make")
    result = solve(targets)
    H.near(result.recipe_rates["F-make"], 1, "binding restored")
end)

H.done("test_quality_feed")
