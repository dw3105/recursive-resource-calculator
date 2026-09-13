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

function Utils.machine_amount(recipe, recipe_rate, crafting_machine, player_index)
    local speed_multiplier = Utils.module_effect_multiplier(player_index, recipe.name, "speed")
    local crafting_speed = crafting_machine.get_crafting_speed() * speed_multiplier
    return recipe_rate * recipe.energy / crafting_speed
end

function Utils.product_amount_from_recipe(recipe, product_full_name)
    for _, product in ipairs(recipe.products) do
        if product.type .. "/" .. product.name == product_full_name then
            return Utils.product_amount(product)
        end
    end
end

function Utils.product_amount(product)
    return (product.amount or (product.amount_min + product.amount_max) / 2) * Utils.product_probability(product)
end

function Utils.get_any_crafting_machine_identifier_for(crafting_category)
    local crafting_machines = storage.crafting_machines_by_category[crafting_category]
    return crafting_machines and {name = crafting_machines[1].name}
end

return Utils