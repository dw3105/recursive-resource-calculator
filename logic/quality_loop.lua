--Quality loop math: how a target item at a quality above normal is made by crafting with quality effects and recycling what falls short.
--Pure: it reads prototypes and a force it is given, and never reads the GUI or writes storage.
--
--Tiers are the qualities from normal following next. A craft or recycle starting at tier t rolls once with the machine's quality effect times t's
--next_probability; every further roll, from the tier s just reached, uses s's next_probability (P2). A roll never reaches a locked tier (P3).
--
--The loop policy (see the plan's Round 5 section): each tier crafts as many sets as its ingredients allow, every item below the target tier is
--recycled when a recycle recipe is set (otherwise it is a byproduct), and nothing is crafted above the target tier. Normal crafts are the scale.
local Utils = require "logic.utils"

local QualityLoop = {}

--Largest normalized flow the loop supports; beyond it the result is refused rather than shown
QualityLoop.FLOW_LIMIT = 1e15

local function clamp_probability(p)
    return math.max(0, math.min(1, p))
end

--The quality prototypes from normal following next, each once (a modded chain may loop)
function QualityLoop.chain()
    local chain, seen = {}, {}
    local quality = prototypes.quality.normal
    while quality and not seen[quality.name] do
        seen[quality.name] = true
        chain[#chain + 1] = quality
        quality = quality.next
    end
    return chain
end

--Share of a roll starting at chain index t that ends at each index: {[index] = share}.
--next_probabilities[i]: next_probability of chain index i; unlocked[i]: whether index i is unlocked; quality_effect: the machine's total quality effect.
function QualityLoop.distribution(next_probabilities, unlocked, start, quality_effect)
    local shares = {}
    local mass = 1
    local current = start
    local probability = clamp_probability(math.max(0, quality_effect) * next_probabilities[start])
    while true do
        if current == #next_probabilities or not unlocked[current + 1] or probability == 0 then
            shares[current] = (shares[current] or 0) + mass
            return shares
        end
        shares[current] = mass * (1 - probability)
        mass = mass * probability
        current = current + 1
        probability = clamp_probability(next_probabilities[current])
    end
end

--Reason the recipe making the target cannot run the loop, or nil
function QualityLoop.recipe_refusal(recipe, item_name)
    local has_item_ingredient = false
    for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "item" then
            if ingredient.name == item_name then
                return "quality_loop_recipe_consumes_target"
            end
            has_item_ingredient = true
        end
    end
    if not has_item_ingredient then
        return "quality_loop_recipe_without_item_ingredient"
    end
end

--Reason a recipe cannot craft the target at a tier (chain_index: its position from normal), or nil. A fluid has no quality, so a recipe taking no
--items only crafts at normal. One rule for the tier recipe control, QualityLoops.normalized and the solver.
function QualityLoop.tier_recipe_refusal(recipe, item_name, chain_index)
    local has_item_ingredient = false
    for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "item" then
            if ingredient.name == item_name then
                return "quality_loop_recipe_consumes_target"
            end
            has_item_ingredient = true
        end
    end
    if not has_item_ingredient and chain_index > 1 then
        return "quality_loop_recipe_without_item_ingredient"
    end
    local made = 0
    for _, product in ipairs(recipe.products) do
        if product.type == "item" and product.name == item_name then made = made + Utils.product_amount(product, 0) end
    end
    if not (made > 0) then
        return "quality_loop_tier_recipe_no_target"
    end
end

--Reason a recipe cannot recycle the target, or nil; recipe nil means its prototype is gone. Used when picking it, when sanitizing, and before
--the loop divides by the amount it consumes. Returns the consumed amount as second value when eligible.
function QualityLoop.recycler_refusal(recipe, item_name)
    if not recipe then
        return "quality_loop_recycle_recipe_missing"
    end
    local consumed = 0
    for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "item" then
            if ingredient.name ~= item_name then
                return "quality_loop_recycle_recipe_extra_item"
            end
            consumed = consumed + ingredient.amount
        end
    end
    if not (consumed > 0) then
        return "quality_loop_recycle_recipe_consumes_no_target"
    end
    return nil, consumed
end

--One tier of the balance. t: {first, recycling, items = {names}, amounts = {[name] = a_i}, supply = {[name] = A_i(u)}, feed = F_u, own = m_u,
--  returns = {[name] = g_i}, self_return = y_X·D_r(u,u)}.
--Returns {crafts, x, leftovers = {[name] = net amount at this tier}} or {reason}.
function QualityLoop._tier_step(t)
    if t.none then --a tier without a recipe crafts nothing; what reaches it stays
        local leftovers = {}
        for _, name in ipairs(t.items) do leftovers[name] = t.supply[name] end
        return {crafts = 0, x = t.feed, leftovers = leftovers, recycled = false}
    end
    local seeded
    if t.first then
        seeded = t.own > 0
    else
        --only the ingredients this tier's craft takes have to be supplied
        local all_supplied = false
        for _, name in ipairs(t.items) do
            if t.amounts[name] > 0 then
                all_supplied = true
            end
        end
        for _, name in ipairs(t.items) do
            if t.amounts[name] > 0 and not (t.supply[name] > 0) then all_supplied = false end
        end
        seeded = t.feed > 0 or (all_supplied and t.own > 0)
    end

    local recycling = t.recycling and seeded
    local denominator = recycling and 1 - t.self_return or 1
    if recycling and denominator <= 0 then
        return {reason = "quality_loop_nonconvergent"}
    end

    local crafts
    if t.first then
        crafts = 1
    else
        for _, name in ipairs(t.items) do
            local g = recycling and t.returns[name] or 0
            local coefficient = t.amounts[name] - g * t.own / denominator
            if coefficient > 0 then
                local bound = (t.supply[name] + g * t.feed / denominator) / coefficient
                crafts = crafts and math.min(crafts, bound) or bound
            end
        end
        if not crafts then
            return {reason = "quality_loop_nonconvergent"}
        end
    end

    local x = seeded and (t.feed + crafts * t.own) / denominator or t.feed
    local leftovers = {}
    for _, name in ipairs(t.items) do
        local g = recycling and t.returns[name] or 0
        local used = t.amounts[name] * crafts
        local leftover = t.supply[name] + g * x - used
        if not t.first then
            local rhs = t.supply[name] + g * t.feed / denominator
            if leftover < -1e-9 * math.max(used, rhs) then
                return {reason = "quality_loop_numeric_limit"}
            end
            leftover = math.max(0, leftover)
        end
        leftovers[name] = leftover
    end
    return {crafts = crafts, x = x, leftovers = leftovers, recycled = recycling}
end

local function add(table_of_tiers, name, tier, amount)
    if amount == 0 then return end
    table_of_tiers[name] = table_of_tiers[name] or {}
    table_of_tiers[name][tier] = (table_of_tiers[name][tier] or 0) + amount
end

local function is_finite(x)
    return x == x and x ~= math.huge and x ~= -math.huge
end

--The loop's flows per 1 target item per second.
--spec: {next_probabilities, unlocked (by chain index), start (chain index of the ingredients' quality), target (chain index), item (target name),
--  craft = {tiers = {[tier] = {quality_effect, output (n: net target per craft), ingredients = {{name, amount}} (items), fluid_ingredients = {{name, amount}},
--    byproducts = {{name, amount}} (items other than the target), fluid_products = {{name, amount}}}}} with tier 1 = start … target - start + 1,
--  recycle = nil | {quality_effect, consumed (k), yields = {[item] = amount per craft}, fluid_ingredients, fluid_products},
--  assist = nil | a craft tier spec run at the start tier on the items returned there (only for a start recipe taking no items),
--  ingredient_recycles = nil | {[item] = {quality_effect, consumed, yield}}: items returned at the start tier recycled into themselves until gone or better}
--Returns {reason} or {offset, tiers = {{crafts, recycle_crafts, x, craft_chances, recycle_chances, assist_crafts?, assist_chances?,
--  ingredient_recycles? = {[item] = crafts}}}, items = {[name] = {[tier] = net}}, fluids = {[name] = net}};
--tier indexes count from the start tier, so chain index = tier + offset.
function QualityLoop.balance(spec)
    local start = spec.start or 1
    if not (spec.target and start >= 1 and start <= spec.target) then --a configuration nobody sanitized
        return {reason = "quality_loop_start_invalid"}
    end
    local offset = start - 1
    local next_probabilities, unlocked = {}, {}
    for index = start, #spec.next_probabilities do
        next_probabilities[index - offset] = spec.next_probabilities[index]
        unlocked[index - offset] = spec.unlocked[index]
    end
    local T = spec.target - offset
    local craft, recycle, assist = spec.craft, spec.recycle, spec.assist
    local craft_chances, recycle_chances = {}, {}
    local assist_chances = assist and QualityLoop.distribution(next_probabilities, unlocked, 1, assist.quality_effect)
    for u = 1, T do
        craft_chances[u] = QualityLoop.distribution(next_probabilities, unlocked, u, craft.tiers[u].quality_effect)
        if recycle and u < T then
            recycle_chances[u] = QualityLoop.distribution(next_probabilities, unlocked, u, recycle.quality_effect)
        end
    end

    --structural reachability: some chain of positive chances leads from the start tier to the target, before any division
    if not unlocked[T] then
        return {reason = "quality_target_unreachable"}
    end
    local reached = {[1] = true}
    for u = 1, T - 1 do
        if reached[u] then
            for _, chances in ipairs({craft_chances[u], recycle_chances[u], u == 1 and assist_chances or nil}) do
                for tier, share in pairs(chances or {}) do
                    if share > 0 then reached[tier] = true end
                end
            end
        end
    end
    if not reached[T] then
        return {reason = "quality_target_unreachable"}
    end

    --every item any tier takes, in a fixed order; each tier's amounts, 0 where that tier's craft nets none of it
    local item_names, seen, amounts_by_tier = {}, {}, {}
    for u = 1, T do
        amounts_by_tier[u] = {}
        for _, ingredient in ipairs(craft.tiers[u].ingredients) do
            if not seen[ingredient.name] then
                seen[ingredient.name] = true
                item_names[#item_names + 1] = ingredient.name
            end
            amounts_by_tier[u][ingredient.name] = ingredient.amount
        end
    end
    local assist_amounts = {}
    for _, ingredient in ipairs(assist and assist.ingredients or {}) do
        if not seen[ingredient.name] then
            seen[ingredient.name] = true
            item_names[#item_names + 1] = ingredient.name
        end
        assist_amounts[ingredient.name] = ingredient.amount
    end
    table.sort(item_names)
    for u = 1, T do
        for _, name in ipairs(item_names) do amounts_by_tier[u][name] = amounts_by_tier[u][name] or 0 end
    end
    for _, name in ipairs(item_names) do assist_amounts[name] = assist_amounts[name] or 0 end
    local x_yield = recycle and (recycle.yields[spec.item] or 0) / recycle.consumed or 0

    local supply, x_returns, x_from_crafts = {}, {}, {}
    for _, name in ipairs(item_names) do supply[name] = {} end
    local items, fluids = {}, {}
    local tiers = {}

    for u = 1, T do
        for _, name in ipairs(item_names) do supply[name][u] = supply[name][u] or 0 end
        local recycling = recycle ~= nil and u < T
        local returns = {}
        if recycling then
            for _, name in ipairs(item_names) do
                returns[name] = (recycle.yields[name] or 0) / recycle.consumed * (recycle_chances[u][u] or 0)
            end
        end
        local step_supply = {}
        for _, name in ipairs(item_names) do step_supply[name] = supply[name][u] end
        local step
        if u == 1 and assist then
            --the start crafts (one, taking no items) feed the tier; the assist crafts are bound by what recycling returns there, like an upper tier's
            step = QualityLoop._tier_step({
                first = false, recycling = recycling, items = item_names, amounts = assist_amounts, supply = step_supply,
                feed = craft.tiers[1].output * (craft_chances[1][1] or 0), own = assist.output * (assist_chances[1] or 0),
                returns = returns, self_return = recycling and x_yield * (recycle_chances[1][1] or 0) or 0,
            })
        else
            step = QualityLoop._tier_step({
                first = u == 1, none = craft.tiers[u].none, recycling = recycling, items = item_names, amounts = amounts_by_tier[u], supply = step_supply,
                feed = (x_from_crafts[u] or 0) + (x_returns[u] or 0), own = craft.tiers[u].output * (craft_chances[u][u] or 0),
                returns = returns, self_return = recycling and x_yield * (recycle_chances[u][u] or 0) or 0,
            })
        end
        if step.reason then
            return {reason = step.reason}
        end
        local crafts, x = step.crafts, step.x
        local assist_crafts
        if u == 1 and assist then
            crafts, assist_crafts = 1, step.crafts
        end
        local tier_craft = craft.tiers[u]

        --items returned at the start tier recycled into themselves: what stays at the tier is recycled again, what rises feeds the tiers above
        local ingredient_recycles
        if u == 1 and spec.ingredient_recycles then
            ingredient_recycles = {}
            for _, name in ipairs(item_names) do
                local recycler = spec.ingredient_recycles[name]
                local left = step.leftovers[name]
                if recycler and left > 0 then
                    local shares = QualityLoop.distribution(next_probabilities, unlocked, 1, recycler.quality_effect)
                    local per_item = recycler.yield / recycler.consumed
                    local denominator = 1 - per_item * (shares[1] or 0)
                    if denominator <= 0 then
                        return {reason = "quality_loop_nonconvergent"}
                    end
                    local recycled = left / denominator
                    for tier, share in pairs(shares) do
                        if tier > 1 then
                            if tier <= T then
                                supply[name][tier] = (supply[name][tier] or 0) + recycled * per_item * share
                            else
                                add(items, name, tier, recycled * per_item * share)
                            end
                        end
                    end
                    step.leftovers[name] = 0
                    ingredient_recycles[name] = recycled / recycler.consumed
                end
            end
        end

        --ingredients: what is left at this tier (at normal, negative is what the loop takes from outside)
        for _, name in ipairs(item_names) do
            add(items, name, u, step.leftovers[name])
        end
        --crafts send the target and their byproducts up the chain
        for tier, share in pairs(craft_chances[u]) do
            local made = crafts * tier_craft.output * share
            if tier > u and tier <= T then
                x_from_crafts[tier] = (x_from_crafts[tier] or 0) + made
            elseif tier > T then
                add(items, spec.item, tier, made)
            end
            for _, byproduct in ipairs(tier_craft.byproducts) do
                add(items, byproduct.name, tier, crafts * byproduct.amount * share)
            end
        end
        for _, fluid in ipairs(tier_craft.fluid_ingredients) do
            fluids[fluid.name] = (fluids[fluid.name] or 0) - crafts * fluid.amount
        end
        for _, fluid in ipairs(tier_craft.fluid_products) do
            fluids[fluid.name] = (fluids[fluid.name] or 0) + crafts * fluid.amount
        end
        if assist_crafts then
            for tier, share in pairs(assist_chances) do
                local made = assist_crafts * assist.output * share
                if tier > 1 and tier <= T then
                    x_from_crafts[tier] = (x_from_crafts[tier] or 0) + made
                elseif tier > T then
                    add(items, spec.item, tier, made)
                end
                for _, byproduct in ipairs(assist.byproducts) do
                    add(items, byproduct.name, tier, assist_crafts * byproduct.amount * share)
                end
            end
            for _, fluid in ipairs(assist.fluid_ingredients) do
                fluids[fluid.name] = (fluids[fluid.name] or 0) - assist_crafts * fluid.amount
            end
            for _, fluid in ipairs(assist.fluid_products) do
                fluids[fluid.name] = (fluids[fluid.name] or 0) + assist_crafts * fluid.amount
            end
        end

        local recycle_crafts = 0
        if step.recycled then
            recycle_crafts = x / recycle.consumed
            for tier, share in pairs(recycle_chances[u]) do
                if tier > u then
                    for item, amount in pairs(recycle.yields) do
                        local returned = recycle_crafts * amount * share
                        if item == spec.item then
                            if tier <= T then
                                x_returns[tier] = (x_returns[tier] or 0) + returned
                            else
                                add(items, item, tier, returned)
                            end
                        elseif supply[item] and tier <= T then --ingredients returned above the target tier are leftovers, below
                            supply[item][tier] = (supply[item][tier] or 0) + returned
                        else
                            add(items, item, tier, returned)
                        end
                    end
                elseif tier == u then
                    --same-tier returns of ingredients and of the target are in the step; anything else is a byproduct
                    for item, amount in pairs(recycle.yields) do
                        if item ~= spec.item and not supply[item] then
                            add(items, item, tier, recycle_crafts * amount * share)
                        end
                    end
                end
            end
            for _, fluid in ipairs(recycle.fluid_ingredients) do
                fluids[fluid.name] = (fluids[fluid.name] or 0) - recycle_crafts * fluid.amount
            end
            for _, fluid in ipairs(recycle.fluid_products) do
                fluids[fluid.name] = (fluids[fluid.name] or 0) + recycle_crafts * fluid.amount
            end
        elseif u < T then
            add(items, spec.item, u, x) --not recycled: the target at this tier is left over
        end

        tiers[u] = {crafts = crafts, recycle_crafts = recycle_crafts, x = x, craft_chances = craft_chances[u], recycle_chances = recycle_chances[u],
            assist_crafts = assist_crafts, assist_chances = u == 1 and assist_chances or nil, ingredient_recycles = ingredient_recycles}
    end

    local output = tiers[T].x
    if output == 0 then
        return {reason = "quality_target_unreachable"}
    end

    local function normalized(value)
        local result = value / output
        if not is_finite(result) or math.abs(result) > QualityLoop.FLOW_LIMIT then
            return nil
        end
        return result
    end
    for _, tier in ipairs(tiers) do
        tier.crafts, tier.recycle_crafts, tier.x = normalized(tier.crafts), normalized(tier.recycle_crafts), normalized(tier.x)
        if not (tier.crafts and tier.recycle_crafts and tier.x) then
            return {reason = "quality_loop_numeric_limit"}
        end
        if tier.assist_crafts then
            tier.assist_crafts = normalized(tier.assist_crafts)
            if not tier.assist_crafts then return {reason = "quality_loop_numeric_limit"} end
        end
        for name, recycles in pairs(tier.ingredient_recycles or {}) do
            tier.ingredient_recycles[name] = normalized(recycles)
            if not tier.ingredient_recycles[name] then return {reason = "quality_loop_numeric_limit"} end
        end
    end
    for _, by_tier in pairs(items) do
        for tier, amount in pairs(by_tier) do
            by_tier[tier] = normalized(amount)
            if not by_tier[tier] then return {reason = "quality_loop_numeric_limit"} end
        end
    end
    for name, amount in pairs(fluids) do
        fluids[name] = normalized(amount)
        if not fluids[name] then return {reason = "quality_loop_numeric_limit"} end
    end

    return {offset = offset, tiers = tiers, items = items, fluids = fluids}
end

return QualityLoop
