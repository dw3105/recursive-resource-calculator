local Utils = require "logic.utils"

local PlayerDataUpdater = {}

local function reinitialize_chosen_crafting_machines(player_index)
    local machine_identifier_by_recipe_name = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name
    for recipe_name, crafting_machine_identifier in pairs(machine_identifier_by_recipe_name) do
        local recipe = prototypes.recipe[recipe_name]
        if not recipe then
            machine_identifier_by_recipe_name[recipe_name] = nil
        elseif not Utils.can_craft(crafting_machine_identifier.name, recipe) then --also covers machines removed or turned into other entities by a mod
            machine_identifier_by_recipe_name[recipe_name] = Utils.get_any_crafting_machine_identifier_for(recipe)
        elseif crafting_machine_identifier.quality and not prototypes.quality[crafting_machine_identifier.quality] then
            crafting_machine_identifier.quality = nil --the mod adding this quality was removed
        end
    end

    for recipe_name, recipe in pairs(prototypes.recipe) do
        if not machine_identifier_by_recipe_name[recipe_name] then
            machine_identifier_by_recipe_name[recipe_name] = Utils.get_any_crafting_machine_identifier_for(recipe)
        end
    end
end

local function has_product(recipe_prototype, product_full_name)
    for _, product in ipairs(recipe_prototype.products) do
        if product.type .. "/" .. product.name == product_full_name then
            return true
        end
    end
    return false
end

local function rebuild_inverse_recipe_bindings(player_index)
    local product_full_names_by_recipe_name = {}

    for product_full_name, recipe in pairs(storage[player_index].recipes_by_product_full_name) do
        product_full_names_by_recipe_name[recipe.name] = product_full_name
    end

    storage[player_index].product_full_names_by_recipe_name = product_full_names_by_recipe_name
end

local function update_recipe_bindings(player_index)
    local recipes_by_product_full_name = storage[player_index].recipes_by_product_full_name

    --remove recipes that are no longer valid:
    for item_or_fluid_full_name, recipe_prototype in pairs(recipes_by_product_full_name) do
        if not recipe_prototype.valid or not has_product(recipe_prototype, item_or_fluid_full_name) then
            recipes_by_product_full_name[item_or_fluid_full_name] = nil
        end
    end

    rebuild_inverse_recipe_bindings(player_index)
end

local function reinitialize_module_preferences(player_index)
    local module_preferences = storage[player_index].module_preferences_by_recipe_name
    for recipe_name, _ in pairs(prototypes.recipe) do
        if not module_preferences[recipe_name] then
            module_preferences[recipe_name] = {effects = {consumption = 0, speed = 0, productivity = 0, pollution = 0, quality = 0}}
        end
    end
    for recipe_name, preferences_table in pairs(module_preferences) do
        if not prototypes.recipe[recipe_name] then
            module_preferences[recipe_name] = nil
        else
            --module names sit at positive indexes and their counts at the matching negative indexes; keep the pairs whose module still exists
            local kept_module_names, kept_module_counts = {}, {}
            for index, module_name in ipairs(preferences_table) do
                if prototypes.item[module_name] then
                    table.insert(kept_module_names, module_name)
                    table.insert(kept_module_counts, preferences_table[-index])
                end
            end
            if #kept_module_names < #preferences_table then
                for index = 1, #preferences_table do
                    preferences_table[index], preferences_table[-index] = kept_module_names[index], kept_module_counts[index]
                end
                for _, effect in ipairs(Utils.module_effect_names) do
                    preferences_table.effects[effect] = 0
                end
                for index, module_name in ipairs(kept_module_names) do
                    local module = prototypes.item[module_name]
                    for _, effect in ipairs(Utils.module_effect_names) do
                        if module.module_effects[effect] then
                            preferences_table.effects[effect] = preferences_table.effects[effect] + kept_module_counts[index] * module.module_effects[effect]
                        end
                    end
                end
            end
        end
    end
end

function PlayerDataUpdater.reinitialize(player_index)
    reinitialize_chosen_crafting_machines(player_index)
    update_recipe_bindings(player_index)
    reinitialize_module_preferences(player_index)
end

return PlayerDataUpdater