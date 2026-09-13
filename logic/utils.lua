local Utils = {}

Utils.module_effect_names = {"consumption", "speed", "productivity", "pollution", "quality"}

--Factorio 2.1 renamed recipe and product members, and LuaObjects throw on unknown members, so the API shape is chosen by game version instead of probing
Utils.IS_2_1 = helpers.compare_versions(script.active_mods["base"], "2.1.0") >= 0

function Utils.recipe_category(recipe)
    if Utils.IS_2_1 then
        return recipe.categories[1]
    end
    return recipe.category
end

--Products are plain tables, so absent optional keys read as nil; 2.1 defaults are independent_probability = 1 and shared_probability = {min = 0, max = 1}
function Utils.product_probability(product)
    if Utils.IS_2_1 then
        local shared_probability = product.shared_probability
        return (product.independent_probability or 1) * (shared_probability and (shared_probability.max - shared_probability.min) or 1)
    end
    return product.probability or 1
end

function Utils.module_effect_multiplier(player_index, recipe_name, effect)
    local multiplier = storage[player_index].module_preferences_by_recipe_name[recipe_name].effects[effect] + 1
    return multiplier > 0.2 and multiplier or 0.2
end

--quality is the chosen machine's quality name, nil meaning normal
function Utils.machine_amount(recipe, recipe_rate, crafting_machine, player_index, quality)
    local speed_multiplier = Utils.module_effect_multiplier(player_index, recipe.name, "speed")
    local crafting_speed = crafting_machine.get_crafting_speed(quality) * speed_multiplier
    return recipe_rate * recipe.energy / crafting_speed
end

function Utils.product_amount_from_recipe(recipe, product_full_name)
    for _, product in ipairs(recipe.products) do
        if product.type .. "/" .. product.name == product_full_name then
            return Utils.product_amount(product)
        end
    end
end

--Mean amount above the ignored count: items are a whole number uniformly distributed over [min, max], fluids a continuous uniform amount.
--Each outcome is clamped before averaging, since productivity never takes back more than an outcome gives.
local function mean_amount_above(product, min, max, ignored)
    if product.type == "fluid" then
        if min == max then
            return math.max(0, min - ignored)
        elseif ignored <= min then
            return (min + max) / 2 - ignored
        elseif ignored >= max then
            return 0
        end
        return (max - ignored) ^ 2 / (2 * (max - min))
    end

    local lowest_counted = math.max(min, math.ceil(ignored))
    if lowest_counted > max then
        return 0
    end
    local counted = max - lowest_counted + 1
    return (counted * (lowest_counted + max) / 2 - counted * ignored) / (max - min + 1)
end

--Expected amount of a product per craft, with productivity_bonus being the recipe's total bonus (0.1 = +10%).
--Extra count is weighted by probability, as measured on Factorio 2.0.77; ignored_by_productivity defaults to ignored_by_stats in the prototype.
function Utils.product_amount(product, productivity_bonus)
    local min = product.amount or product.amount_min
    local max = product.amount or product.amount_max
    if max < min then
        max = min
    end
    local probability = Utils.product_probability(product)
    local extra_count_fraction = product.extra_count_fraction or 0

    local amount = probability * ((min + max) / 2 + extra_count_fraction)
    if productivity_bonus and productivity_bonus ~= 0 then
        local ignored = product.ignored_by_productivity or product.ignored_by_stats or 0
        amount = amount + productivity_bonus * probability * (mean_amount_above(product, min, max, ignored) + extra_count_fraction)
    end
    return amount
end

--Net amount per craft of each item or fluid: every product entry of it summed, minus every ingredient entry of it. Zero nets are left out.
function Utils.net_amounts_by_full_name(recipe, productivity_bonus)
    local net_amounts = {}
    for _, product in ipairs(recipe.products) do
        if product.type ~= "research-progress" then
            local full_name = product.type .. "/" .. product.name
            net_amounts[full_name] = (net_amounts[full_name] or 0) + Utils.product_amount(product, productivity_bonus)
        end
    end
    for _, ingredient in ipairs(recipe.ingredients) do
        local full_name = ingredient.type .. "/" .. ingredient.name
        net_amounts[full_name] = (net_amounts[full_name] or 0) - ingredient.amount
    end
    for full_name, net_amount in pairs(net_amounts) do
        if net_amount == 0 then
            net_amounts[full_name] = nil
        end
    end
    return net_amounts
end

function Utils.get_any_crafting_machine_identifier_for(crafting_category)
    local crafting_machines = storage.crafting_machines_by_category[crafting_category]
    return crafting_machines and {name = crafting_machines[1].name}
end

return Utils