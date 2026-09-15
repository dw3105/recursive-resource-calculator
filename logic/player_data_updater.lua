local Utils = require "logic.utils"
local ModuleSetup = require "logic.module_setup"
local Burners = require "logic.burners"

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

local function has_ingredient(recipe_prototype, product_full_name)
    for _, ingredient in ipairs(recipe_prototype.ingredients) do
        if ingredient.type .. "/" .. ingredient.name == product_full_name then
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

--Saves from before consumer bindings have no flags: every binding there produces its product
local function update_recipe_bindings(player_index)
    local recipes_by_product_full_name = storage[player_index].recipes_by_product_full_name
    storage[player_index].consumer_product_full_names = storage[player_index].consumer_product_full_names or {}
    local consumer_product_full_names = storage[player_index].consumer_product_full_names

    --remove recipes that are no longer valid: a consumer binding needs the product among the ingredients, any other binding among the products
    for item_or_fluid_full_name, recipe_prototype in pairs(recipes_by_product_full_name) do
        local still_fits = false
        if recipe_prototype.valid then
            if consumer_product_full_names[item_or_fluid_full_name] then
                still_fits = has_ingredient(recipe_prototype, item_or_fluid_full_name)
            else
                still_fits = has_product(recipe_prototype, item_or_fluid_full_name)
            end
        end
        if not still_fits then
            recipes_by_product_full_name[item_or_fluid_full_name] = nil
        end
    end
    for item_or_fluid_full_name, _ in pairs(consumer_product_full_names) do
        if not recipes_by_product_full_name[item_or_fluid_full_name] then
            consumer_product_full_names[item_or_fluid_full_name] = nil
        end
    end

    rebuild_inverse_recipe_bindings(player_index)
end

--Chosen machines first, so module setups are made valid for machines that still exist
function PlayerDataUpdater.reinitialize(player_index)
    reinitialize_chosen_crafting_machines(player_index)
    update_recipe_bindings(player_index)
    Burners.reinitialize(player_index)
    ModuleSetup.migrate(player_index)
    ModuleSetup.reinitialize(player_index)
end

return PlayerDataUpdater