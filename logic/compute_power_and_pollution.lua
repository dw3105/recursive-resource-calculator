local Utils = require "logic.utils"

--Beacons draw power once per physical beacon: a group's beacons per machine times the machines, divided by the machines sharing each beacon
local function beacon_energy_consumption(player_index, recipe_name, machine_amount)
    local energy_consumption = 0
    for _, group in ipairs(storage[player_index].module_setups_by_recipe_name[recipe_name].beacons) do
        local beacon = prototypes.entity[group.name]
        local physical_beacons = group.count * machine_amount / group.sharing
        local power_multiplier = prototypes.quality[group.quality or "normal"].beacon_power_usage_multiplier
        energy_consumption = energy_consumption + physical_beacons * beacon.energy_usage * 60 * power_multiplier
    end
    return energy_consumption
end

local function compute_for_recipe(recipe, recipe_rate, player_index)
    local crafting_machine_identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name]
    if not crafting_machine_identifier then --manually crafted recipe
        return 0, 0
    end

    local energy_consumption_multiplier = Utils.module_effect_multiplier(player_index, recipe.name, "consumption")
    local crafting_machine = prototypes.entity[crafting_machine_identifier.name]

    local machine_amount = Utils.machine_amount(recipe, recipe_rate, crafting_machine, player_index, crafting_machine_identifier.quality)
    local energy_consumption = crafting_machine.energy_usage * 60 * machine_amount * energy_consumption_multiplier

    local pollution_multiplier = Utils.module_effect_multiplier(player_index, recipe.name, "pollution")
    local pollution = storage.pollution_by_crafting_machine[crafting_machine.name] * machine_amount * pollution_multiplier * energy_consumption_multiplier

    return energy_consumption + beacon_energy_consumption(player_index, recipe.name, machine_amount), pollution
end

return function(player_index, recipe_rates_by_recipe_name)
    local total_energy_usage = 0
    local total_pollution = 0

    for recipe_name, recipe_rate in pairs(recipe_rates_by_recipe_name) do
        local recipe = prototypes.recipe[recipe_name]
        local energy_usage, pollution = compute_for_recipe(recipe, recipe_rate, player_index)
        total_energy_usage = total_energy_usage + energy_usage
        total_pollution = total_pollution + pollution
    end

    return total_energy_usage, total_pollution
end