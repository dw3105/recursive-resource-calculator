local Utils = {}

Utils.module_effect_names = {"consumption", "speed", "productivity", "pollution", "quality"}

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
    return (product.amount or (product.amount_min + product.amount_max) / 2) * (product.probability or 1)
end

function Utils.get_any_crafting_machine_identifier_for(crafting_category)
    local crafting_machines = storage.crafting_machines_by_category[crafting_category]
    return crafting_machines and {name = crafting_machines[1].name}
end

return Utils