local Utils = require "logic.utils"
local Burners = require "logic.burners"
local QualityLoops = require "logic.quality_loops"

--Beacons draw power once per physical beacon: a group's beacons per machine times the machines, divided by the machines sharing each beacon
local function beacon_energy_consumption(setup, machine_amount)
    local energy_consumption = 0
    for _, group in ipairs(setup.beacons) do
        local beacon = prototypes.entity[group.name]
        local physical_beacons = group.count * machine_amount / group.sharing
        local power_multiplier = prototypes.quality[group.quality or "normal"].beacon_power_usage_multiplier
        energy_consumption = energy_consumption + physical_beacons * beacon.energy_usage * 60 * power_multiplier
    end
    return energy_consumption
end

--A recipe crafted at recipe_rate by the given machine and setup; crafting_machine_identifier nil is hand crafting, which draws and pollutes nothing
local function compute_for_stage(recipe, recipe_rate, crafting_machine_identifier, setup)
    if not crafting_machine_identifier then
        return 0, 0
    end

    local effects = Utils.setup_effects(setup)
    local energy_consumption_multiplier = Utils.effect_multiplier(effects, "consumption")
    local crafting_machine = prototypes.entity[crafting_machine_identifier.name]

    local machine_amount = Utils.machine_amount(recipe, recipe_rate, crafting_machine, crafting_machine_identifier.quality, setup)
    local energy_consumption = crafting_machine.energy_usage * 60 * machine_amount * energy_consumption_multiplier

    local pollution_multiplier = Utils.effect_multiplier(effects, "pollution")
    local pollution = storage.pollution_by_crafting_machine[crafting_machine.name] * machine_amount * pollution_multiplier * energy_consumption_multiplier

    return energy_consumption + beacon_energy_consumption(setup, machine_amount), pollution
end

local function compute_for_recipe(recipe, recipe_rate, player_index)
    local player_storage = storage[player_index]
    return compute_for_stage(recipe, recipe_rate, player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name[recipe.name],
        player_storage.module_setups_by_recipe_name[recipe.name])
end

--Electric energy (J/s) and pollution (per second) of a solved result's columns; burners draw no electricity
return function(player_index, columns, recipe_rates_by_recipe_name)
    local total_energy_usage = 0
    local total_pollution = 0

    for _, column in ipairs(columns) do
        local rate = recipe_rates_by_recipe_name[column.recipe_name]
        if column.quality_loop then
            --each stage with a machine draws for all the crafts it makes over every tier; a missing or hand-crafted stage draws nothing
            local loop = storage[player_index].quality_loops_by_key[column.quality_loop.key]
            for _, stage_name in ipairs({"craft", "recycle"}) do
                local stage = QualityLoops.stage(player_index, loop, stage_name)
                if stage and stage.machine then
                    local crafts = 0
                    for _, tier in ipairs(column.quality_loop.tiers) do
                        crafts = crafts + (stage_name == "craft" and tier.crafts or tier.recycle_crafts)
                    end
                    local energy_usage, pollution = compute_for_stage(stage.recipe, rate * crafts, stage.machine, stage.setup)
                    total_energy_usage = total_energy_usage + energy_usage
                    total_pollution = total_pollution + pollution
                end
            end
        elseif column.burner then
            local units_per_entity, pollution_per_entity = Burners.draw(column.product_full_name, column.burner)
            total_pollution = total_pollution + rate / units_per_entity * pollution_per_entity
        else
            local energy_usage, pollution = compute_for_recipe(prototypes.recipe[column.recipe_name], rate, player_index)
            total_energy_usage = total_energy_usage + energy_usage
            total_pollution = total_pollution + pollution
        end
    end

    return total_energy_usage, total_pollution
end