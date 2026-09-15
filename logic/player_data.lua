local Utils = require "logic.utils"
local ModuleSetup = require "logic.module_setup"

local PlayerData = {}

local function initialize_chosen_crafting_machines(player_index)
    local machine_identifiers_by_recipe_name = {}
    for recipe_name, recipe in pairs(prototypes.recipe) do
        machine_identifiers_by_recipe_name[recipe_name] = Utils.get_any_crafting_machine_identifier_for(recipe)
    end
    storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name = machine_identifiers_by_recipe_name
end

local function initialize_module_setups(player_index)
    local module_setups_by_recipe_name = {}
    for recipe_name, _ in pairs(prototypes.recipe) do
        module_setups_by_recipe_name[recipe_name] = ModuleSetup.new_setup()
    end
    storage[player_index].module_setups_by_recipe_name = module_setups_by_recipe_name
end

function PlayerData.initialize_recipe_bindings(player_index)
    local recipes_by_product_full_name = {}
    local product_full_names_by_recipe_name = {}

    for product_full_name, recipe_prototype_list in pairs(storage.recipe_lists_by_product_full_name) do
        if #recipe_prototype_list == 1 then
            local unique_recipe = recipe_prototype_list[1]
            if #unique_recipe.products == 1 then
                recipes_by_product_full_name[product_full_name] = unique_recipe
                product_full_names_by_recipe_name[unique_recipe.name] = product_full_name
            end
        end
    end

    storage[player_index].recipes_by_product_full_name = recipes_by_product_full_name
    storage[player_index].product_full_names_by_recipe_name = product_full_names_by_recipe_name
    storage[player_index].consumer_product_full_names = {} --products bound to a recipe picked to consume them; every other binding produces its product
    storage[player_index].burners_by_product_full_name = {} --products burnt as fuel: [product] = {name, quality} of the burning entity
end

function PlayerData.initialize_player_data(player_index)
    storage[player_index] = {}
    storage[player_index].backlogged_computation_count = 0
    initialize_chosen_crafting_machines(player_index)
    initialize_module_setups(player_index)
    PlayerData.initialize_recipe_bindings(player_index)
end

return PlayerData