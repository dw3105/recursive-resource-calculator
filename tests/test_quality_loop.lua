--Quality loop math: tier chances, the per-tier balance and its failures, checked against hand-solved values, the wiki's table and a simulation
local H = require "tests.harness"

local function loop_module()
    H.new_world("2.0")
    return require "logic.quality_loop"
end

local function all_unlocked(count)
    local unlocked = {}
    for index = 1, count do unlocked[index] = true end
    return unlocked
end

local function probabilities(count, value)
    local list = {}
    for index = 1, count do list[index] = index < count and value or 0 end
    return list
end

local function near_shares(actual, expected, what)
    for tier, share in pairs(expected) do
        H.near(actual[tier] or 0, share, what .. " tier " .. tier)
    end
    for tier, share in pairs(actual) do
        if expected[tier] == nil and share ~= 0 then error(what .. ": unexpected share at tier " .. tier .. ": " .. share) end
    end
end

--spec with defaults: two tiers, vanilla next_probability, no recycler
local function spec(overrides)
    local base = {next_probabilities = probabilities(2, 0.1), unlocked = all_unlocked(2), target = 2, item = "X",
        craft = {quality_effect = 1, output = 1, ingredients = {{name = "A", amount = 1}}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}}}
    for key, value in pairs(overrides) do base[key] = value end
    return base
end

local function recycler(quality_effect, consumed, yields, extra)
    local r = {quality_effect = quality_effect, consumed = consumed, yields = yields, fluid_ingredients = {}, fluid_products = {}}
    for key, value in pairs(extra or {}) do r[key] = value end
    return r
end

H.test("Q-2b the wiki's table: 10% at normal on the vanilla chain", function()
    local Q = loop_module()
    local np, unlocked = probabilities(5, 0.1), all_unlocked(5)
    near_shares(Q.distribution(np, unlocked, 1, 1.0), {0.9, 0.09, 0.009, 0.0009, 0.0001}, "from normal")
    near_shares(Q.distribution(np, unlocked, 2, 1.0), {[2] = 0.9, [3] = 0.09, [4] = 0.009, [5] = 0.001}, "from uncommon")
    near_shares(Q.distribution(np, unlocked, 5, 1.0), {[5] = 1}, "from legendary")
end)

H.test("Q-2c a roll stops below a locked tier", function()
    local Q = loop_module()
    local np = probabilities(5, 0.1)
    local unlocked = all_unlocked(5)
    unlocked[3] = false
    near_shares(Q.distribution(np, unlocked, 1, 1.0), {0.9, 0.1}, "rare locked")
    unlocked[2] = false
    near_shares(Q.distribution(np, unlocked, 1, 1.0), {1}, "uncommon locked")
end)

H.test("Q-3 a modded chain: the first roll uses the start tier's next_probability, later rolls the reached tier's", function()
    local Q = loop_module()
    local np, unlocked = {0.3, 0.05, 0}, all_unlocked(3)
    near_shares(Q.distribution(np, unlocked, 1, 0.2), {0.94, 0.06 * 0.95, 0.06 * 0.05}, "from normal")
    near_shares(Q.distribution(np, unlocked, 2, 0.2), {[2] = 0.99, [3] = 0.01}, "from the second tier")
    near_shares(Q.distribution(np, unlocked, 1, -0.5), {1}, "negative quality effect counts as none")
    near_shares(Q.distribution({20, 0}, all_unlocked(2), 1, 1), {[2] = 1}, "chance capped at 1")
end)

H.test("Q-1 two tiers by hand: one ingredient, recycler returning a quarter", function()
    local Q = loop_module()
    --normal: 1 craft, 0.9 X stays and is recycled into 0.225 A: 0.2025 normal, 0.0225 uncommon; 0.1 X reaches uncommon.
    --uncommon: 0.0225 crafts, output 0.1 + 0.0225 = 0.1225 per normal craft.
    local result = Q.balance(spec({recycle = recycler(1, 1, {A = 0.25})}))
    assert(result.tiers, "reason " .. tostring(result.reason))
    local Y = 0.1225
    H.near(result.tiers[1].crafts, 1 / Y, "normal crafts")
    H.near(result.tiers[1].recycle_crafts, 0.9 / Y, "normal recycles")
    H.near(result.tiers[1].x, 0.9 / Y, "normal X")
    H.near(result.tiers[2].crafts, 0.0225 / Y, "uncommon crafts")
    H.near(result.tiers[2].recycle_crafts, 0, "nothing recycled at the target")
    H.near(result.tiers[2].x, 1, "one target per second")
    H.near(result.items.A[1], (0.2025 - 1) / Y, "normal A taken from outside")
    H.equal(result.items.A[2], nil, "uncommon A all used")
    H.equal(result.items.X, nil, "no X left over")
end)

H.test("Q-4 2A + B: A limits the upper tier and B is left over", function()
    local Q = loop_module()
    local craft = {quality_effect = 1, output = 1, ingredients = {{name = "A", amount = 2}, {name = "B", amount = 1}}, fluid_ingredients = {},
        byproducts = {}, fluid_products = {}}
    local result = Q.balance(spec({craft = craft, recycle = recycler(1, 1, {A = 1, B = 1})}))
    assert(result.tiers, "reason " .. tostring(result.reason))
    --normal: x = 0.9, returns 0.81 A and B at normal, 0.09 of each at uncommon; uncommon crafts 0.045 (A), 0.045 B left, output 0.145
    local Y = 0.145
    H.near(result.tiers[2].crafts, 0.045 / Y, "uncommon crafts")
    H.near(result.items.A[1], (0.81 - 2) / Y, "normal A demand")
    H.near(result.items.B[1], (0.81 - 1) / Y, "normal B demand")
    H.equal(result.items.A[2], nil, "uncommon A used up")
    H.near(result.items.B[2], 0.045 / Y, "uncommon B left over")
end)

H.test("Q-4b a tier where one ingredient returns more than it takes: that one gives no bound", function()
    local Q = loop_module()
    local step = Q._tier_step({first = false, recycling = true, items = {"A", "B"}, amounts = {A = 1, B = 1}, supply = {A = 0, B = 0},
        feed = 0.5, own = 0.5, returns = {A = 3, B = 0.25}, self_return = 0})
    H.near(step.crafts, 1 / 7, "crafts")
    H.near(step.x, 4 / 7, "x")
    H.near(step.leftovers.A, 11 / 7, "A left over")
    H.near(step.leftovers.B, 0, "B used up")
end)

H.test("Q-4c an exactly zero coefficient does not bound the crafts", function()
    local Q = loop_module()
    local step = Q._tier_step({first = false, recycling = true, items = {"A", "B"}, amounts = {A = 1, B = 1}, supply = {A = 0, B = 0.25},
        feed = 1, own = 2, returns = {A = 0.5, B = 0}, self_return = 0})
    H.near(step.crafts, 0.25, "B bounds")
    H.near(step.x, 1.5, "x")
    H.near(step.leftovers.A, 0.5, "A left over")
    H.near(step.leftovers.B, 0, "B used up")
end)

H.test("Q-5 a recycler returning the target itself: 10 recycles per upgraded X, half as many crafts when it takes 2", function()
    local Q = loop_module()
    for _, consumed in ipairs({1, 2}) do
        local s = spec({recycle = recycler(1, consumed, {X = consumed})})
        s.craft.quality_effect = 0
        local result = Q.balance(s)
        assert(result.tiers, "reason " .. tostring(result.reason))
        H.near(result.tiers[1].crafts, 1, "normal crafts, consumed " .. consumed)
        H.near(result.tiers[1].x, 10, "normal X, consumed " .. consumed)
        H.near(result.tiers[1].recycle_crafts, 10 / consumed, "recycles, consumed " .. consumed)
        H.near(result.items.A[1], -1, "normal A")
    end
end)

H.test("Q-3b a craft without quality still reaches the target through the recycler; with neither, unreachable", function()
    local Q = loop_module()
    local s = spec({recycle = recycler(1, 1, {A = 0.25})})
    s.craft.quality_effect = 0
    local result = Q.balance(s)
    assert(result.tiers, "reason " .. tostring(result.reason))
    --normal: x = 1 recycled, 0.225 A normal, 0.025 A uncommon -> 0.025 uncommon crafts -> output 0.025
    H.near(result.tiers[2].crafts, 1, "uncommon crafts per target")
    H.near(result.tiers[1].crafts, 40, "normal crafts")
    s.recycle.quality_effect = 0
    H.equal(Q.balance(s).reason, "quality_target_unreachable", "no chance anywhere")
end)

H.test("Q-6 unreachable, nonconvergent and numeric limit are told apart", function()
    local Q = loop_module()
    local none = spec({})
    none.craft.quality_effect = 0
    H.equal(Q.balance(none).reason, "quality_target_unreachable", "zero quality effect everywhere")

    local locked = spec({unlocked = {true, false}})
    H.equal(Q.balance(locked).reason, "quality_target_unreachable", "target locked")

    --half the crafts stay at normal and go into a lossless recycler that never upgrades: den is exactly 0
    local lossless = spec({recycle = recycler(0, 1, {X = 1})})
    lossless.craft.quality_effect = 5
    H.equal(Q.balance(lossless).reason, "quality_loop_nonconvergent", "den exactly 0 with a feed")

    local amplifying = spec({recycle = recycler(1, 4, {X = 5})})
    H.equal(Q.balance(amplifying).reason, "quality_loop_nonconvergent", "den below 0")

    --every craft upgrades: nothing enters the lossless recycler, so it is fine
    local skipping = spec({recycle = recycler(0, 1, {X = 1})})
    skipping.craft.quality_effect = 10
    local result = Q.balance(skipping)
    assert(result.tiers, "reason " .. tostring(result.reason))
    H.near(result.tiers[1].crafts, 1, "one normal craft per target")
    H.near(result.items.A[1], -1, "normal A")
    H.near(result.tiers[1].recycle_crafts, 0, "recycler idle")

    --tiers 0, 1, 2: crafts jump straight to the target; the lossless recycler at tier 1 is never fed
    local unfed = {next_probabilities = {1, 1, 0}, unlocked = all_unlocked(3), target = 3, item = "X",
        craft = {quality_effect = 1, output = 1, ingredients = {{name = "A", amount = 1}}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}},
        recycle = recycler(0, 1, {X = 1})}
    result = Q.balance(unfed)
    assert(result.tiers, "reason " .. tostring(result.reason))
    H.near(result.tiers[1].crafts, 1, "unfed tier: normal crafts")
    H.near(result.tiers[2].x, 0, "unfed tier: nothing at tier 1")

    local slow = {next_probabilities = {1, 0}, unlocked = all_unlocked(2), target = 2, item = "X",
        craft = {quality_effect = 0, output = 1, ingredients = {{name = "A", amount = 1}}, fluid_ingredients = {}, byproducts = {}, fluid_products = {}},
        recycle = recycler(2 ^ -20, 1, {X = 1})}
    result = Q.balance(slow)
    assert(result.tiers, "reason " .. tostring(result.reason))
    H.near_relative(result.tiers[1].recycle_crafts, 2 ^ 20, "about 2^20 recycles per target")

    local rare = spec({next_probabilities = {1e-13, 0}})
    result = Q.balance(rare)
    assert(result.tiers, "tiny positive output is solved, got " .. tostring(result.reason))
    H.near_relative(result.tiers[1].crafts, 1e13, "1e13 crafts per target")

    local too_rare = spec({next_probabilities = {1e-16, 0}})
    H.equal(Q.balance(too_rare).reason, "quality_loop_numeric_limit", "flows above the limit")
end)

H.test("Q-4d byproducts of the craft and of the recycler get quality too; fluids do not", function()
    local Q = loop_module()
    local s = spec({recycle = recycler(1, 1, {A = 0.25, S = 0.5}, {fluid_ingredients = {{name = "water", amount = 10}}})})
    s.craft.byproducts = {{name = "B", amount = 2}}
    s.craft.fluid_ingredients = {{name = "steam", amount = 4}}
    local result = Q.balance(s)
    assert(result.tiers, "reason " .. tostring(result.reason))
    local Y = 0.1225
    local crafts = {1, 0.0225}
    H.near(result.items.B[1], 2 * 0.9 / Y, "normal B from normal crafts")
    H.near(result.items.B[2], (2 * 0.1 + 2 * 0.0225) / Y, "uncommon B from both tiers")
    H.near(result.items.S[1], 0.5 * 0.9 * 0.9 / Y, "normal scrap from normal recycles")
    H.near(result.items.S[2], 0.5 * 0.9 * 0.1 / Y, "uncommon scrap from normal recycles")
    H.near(result.fluids.steam, -4 * (crafts[1] + crafts[2]) / Y, "steam per craft")
    H.near(result.fluids.water, -10 * 0.9 / Y, "water per recycle")
end)

H.test("Q-5b without a recycler, X below the target is a byproduct", function()
    local Q = loop_module()
    local result = Q.balance(spec({}))
    assert(result.tiers, "reason " .. tostring(result.reason))
    H.near(result.tiers[1].crafts, 10, "crafts per target")
    H.near(result.items.A[1], -10, "normal A")
    H.near(result.items.X[1], 9, "normal X left over")
    H.near(result.tiers[1].recycle_crafts, 0, "no recycles")
end)

H.test("Q-2 vanilla five tiers match a craft-by-craft simulation", function()
    local Q = loop_module()
    local craft = {quality_effect = 1, output = 1, ingredients = {{name = "A", amount = 2}, {name = "B", amount = 3}}, fluid_ingredients = {},
        byproducts = {}, fluid_products = {}}
    local s = {next_probabilities = probabilities(5, 0.1), unlocked = all_unlocked(5), target = 5, item = "X", craft = craft,
        recycle = recycler(1, 1, {A = 0.5, B = 0.75})}
    local result = Q.balance(s)
    assert(result.tiers, "reason " .. tostring(result.reason))

    --simulation: inventories per tier; each round every tier crafts what its stock allows and every X below the target is recycled
    local inventory = {A = {0, 0, 0, 0, 0}, B = {0, 0, 0, 0, 0}, X = {0, 0, 0, 0, 0}}
    local crafts_total, recycles_total = {0, 0, 0, 0, 0}, {0, 0, 0, 0, 0}
    local normal_crafts = 1
    for _ = 1, 2000 do
        local moved = 0
        for u = 1, 5 do
            local crafts = u == 1 and normal_crafts or math.min(inventory.A[u] / 2, inventory.B[u] / 3)
            if u == 1 then normal_crafts = 0 end
            if crafts > 0 then
                inventory.A[u] = inventory.A[u] - 2 * crafts
                inventory.B[u] = inventory.B[u] - 3 * crafts
                crafts_total[u] = crafts_total[u] + crafts
                for tier, share in pairs(Q.distribution(s.next_probabilities, s.unlocked, u, 1)) do
                    inventory.X[tier] = inventory.X[tier] + crafts * share
                end
                moved = moved + crafts
            end
        end
        for u = 1, 4 do
            local x = inventory.X[u]
            if x > 0 then
                inventory.X[u] = 0
                recycles_total[u] = recycles_total[u] + x
                for tier, share in pairs(Q.distribution(s.next_probabilities, s.unlocked, u, 1)) do
                    inventory.A[tier] = inventory.A[tier] + 0.5 * x * share
                    inventory.B[tier] = inventory.B[tier] + 0.75 * x * share
                end
                moved = moved + x
            end
        end
        if moved < 1e-15 then break end
    end
    local Y = inventory.X[5]
    for u = 1, 5 do
        H.near_relative(result.tiers[u].crafts * Y, crafts_total[u], "crafts at tier " .. u)
        H.near_relative(result.tiers[u].recycle_crafts * Y, recycles_total[u], "recycles at tier " .. u)
    end
    --normal stock left: negative is what came from outside
    H.near_relative(result.items.A[1] * Y, inventory.A[1], "normal A")
    H.near_relative(result.items.B[1] * Y, inventory.B[1], "normal B")
    for u = 2, 5 do
        H.near_relative((result.items.A[u] or 0) * Y, inventory.A[u], "A left at tier " .. u)
        H.near_relative((result.items.B[u] or 0) * Y, inventory.B[u], "B left at tier " .. u)
    end
end)

H.test("recycler and recipe refusals", function()
    local world = H.new_world("2.0")
    world.add_item("X")
    world.add_item("Y")
    world.add_fluid("X")
    world.add_fluid("water")
    local Q = require "logic.quality_loop"
    local function recipe(ingredients)
        return {ingredients = ingredients}
    end
    local cases = {
        {nil, "quality_loop_recycle_recipe_missing", "missing prototype"},
        {recipe({{type = "fluid", name = "water", amount = 10}}), "quality_loop_recycle_recipe_consumes_no_target", "fluid-only replacement"},
        {recipe({}), "quality_loop_recycle_recipe_consumes_no_target", "no ingredients"},
        {recipe({{type = "fluid", name = "X", amount = 1}}), "quality_loop_recycle_recipe_consumes_no_target", "same-named fluid"},
        {recipe({{type = "item", name = "X", amount = 0}}), "quality_loop_recycle_recipe_consumes_no_target", "zero X"},
        {recipe({{type = "item", name = "X", amount = 1}}), nil, "valid X"},
        {recipe({{type = "item", name = "X", amount = 1}, {type = "fluid", name = "water", amount = 5}}), nil, "X plus fluid"},
        {recipe({{type = "item", name = "X", amount = 1}, {type = "item", name = "Y", amount = 1}}), "quality_loop_recycle_recipe_extra_item", "X plus item"},
        {recipe({{type = "item", name = "X", amount = 1}, {type = "item", name = "X", amount = 2}}), nil, "repeated X"},
    }
    for _, case in ipairs(cases) do
        H.equal(Q.recycler_refusal(case[1], "X"), case[2], case[3])
    end
    local _, consumed = Q.recycler_refusal(cases[9][1], "X")
    H.equal(consumed, 3, "repeated X entries add up")
    H.equal(Q.recipe_refusal(recipe({{type = "item", name = "Y", amount = 1}, {type = "item", name = "X", amount = 1}}), "X"),
        "quality_loop_recipe_consumes_target", "target among ingredients")
    H.equal(Q.recipe_refusal(recipe({{type = "fluid", name = "water", amount = 1}}), "X"), "quality_loop_recipe_without_item_ingredient", "fluid only")
    H.equal(Q.recipe_refusal(recipe({{type = "item", name = "Y", amount = 1}}), "X"), nil, "eligible")
end)

H.test("the chain follows next from normal and stops on a cycle", function()
    local world = H.new_world("2.0")
    local Q = require "logic.quality_loop"
    local names = {}
    for _, quality in ipairs(Q.chain()) do names[#names + 1] = quality.name end
    H.equal(table.concat(names, ","), "normal,uncommon,rare,epic,legendary", "vanilla chain")
    world.set_quality_chain({{name = "normal", level = 0}, {name = "shiny", level = 1}})
    prototypes.quality.shiny.next = prototypes.quality.normal
    names = {}
    for _, quality in ipairs(Q.chain()) do names[#names + 1] = quality.name end
    H.equal(table.concat(names, ","), "normal,shiny", "cycle stops")
end)

H.done("test_quality_loop")
