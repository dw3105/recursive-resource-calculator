local Utils = require "logic.utils"
local Burners = require "logic.burners"
local QualityLoops = require "logic.quality_loops"

local function copy_state_data(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" then return value end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if value_type == "userdata" then
        local name = value.name
        return type(name) == "string" and {name = name} or nil
    end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = copy_state_data(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

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

local function sorted_names(map)
    local names = {}
    for name, _ in pairs(map or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function add_stage_totals(state, recipe, rate, machine, setup)
    if not machine then return end
    local energy_usage, pollution = compute_for_stage(recipe, rate, machine, setup)
    state.energy = state.energy + energy_usage
    state.pollution = state.pollution + pollution
end

local function finish_column(state)
    state.cursor.column = state.cursor.column + 1
    state.cursor.part = "column"
    state.cursor.tier = 1
    state.cursor.recycle_name = 1
    state.cursor.recycle_crafts = 0
    state.cursor.recycle_names = nil
end

local function begin_quality_column(state, info)
    state.cursor.part = "tier"
    state.cursor.tier = 1
    state.cursor.recycle_name = 1
    state.cursor.recycle_crafts = 0
    state.cursor.recycle_names = nil
end

local function step_quality_column(state, column, rate)
    local info = column.quality_loop
    local cursor = state.cursor

    if cursor.part == "column" then
        begin_quality_column(state, info)
    end

    if cursor.part == "tier" then
        local tier = info.tiers and info.tiers[cursor.tier]
        if tier then
            local stage = QualityLoops.stage(state.player_index, info.config, "craft", tier.quality)
            add_stage_totals(state, stage and stage.recipe, rate * (tier.crafts or 0), stage and stage.machine, stage and stage.setup)
            cursor.recycle_crafts = cursor.recycle_crafts + (tier.recycle_crafts or 0)
            cursor.tier = cursor.tier + 1
            return
        end
        cursor.part = "recycle"
    end

    if cursor.part == "recycle" then
        local recycle = QualityLoops.stage(state.player_index, info.config, "recycle")
        add_stage_totals(state, recycle and recycle.recipe, rate * cursor.recycle_crafts, recycle and recycle.machine, recycle and recycle.setup)
        cursor.recycle_names = sorted_names(info.tiers and info.tiers[1] and info.tiers[1].ingredient_recycles)
        cursor.part = "ingredient_recycle"
        return
    end

    if cursor.part == "ingredient_recycle" then
        local name = cursor.recycle_names[cursor.recycle_name]
        if name then
            local recycler = info.ingredient_recycles and info.ingredient_recycles[name]
            local recycle = QualityLoops.stage(state.player_index, info.config, "recycle")
            add_stage_totals(state, recycler and prototypes.recipe[recycler.recipe_name], rate * info.tiers[1].ingredient_recycles[name],
                recycle and recycle.machine, recycler and recycler.setup)
            cursor.recycle_name = cursor.recycle_name + 1
            return
        end
        cursor.part = "assist"
    end

    if cursor.part == "assist" then
        local assist_crafts = info.tiers and info.tiers[1] and info.tiers[1].assist_crafts
        local assist = assist_crafts and QualityLoops.stage(state.player_index, info.config, "assist")
        add_stage_totals(state, assist and assist.recipe, rate * (assist_crafts or 0), assist and assist.machine, assist and assist.setup)
        finish_column(state)
    end
end

--A plain-data power job. The cursor is deliberately inside quality-loop tiers and ingredient recycles, not just at columns.
local Power = {}

function Power.begin(player_index, columns, recipe_rates_by_recipe_name)
    return {
        player_index = player_index,
        columns = copy_state_data(columns) or {},
        recipe_rates = copy_state_data(recipe_rates_by_recipe_name) or {},
        cursor = {column = 1, part = "column", tier = 1, recycle_name = 1, recycle_crafts = 0},
        energy = 0,
        pollution = 0,
        done_units = 0,
        done = false,
    }
end

function Power.step(state, budget)
    budget = budget or {ops = 0}
    if state.done or budget.ops <= 0 then return state end

    local column = state.columns[state.cursor.column]
    if not column then
        state.done = true
    elseif column.quality_loop then
        step_quality_column(state, column, state.recipe_rates[column.recipe_name] or 0)
    elseif column.burner then
        local rate = state.recipe_rates[column.recipe_name] or 0
        local units_per_entity, pollution_per_entity = Burners.draw(column.product_full_name, column.burner)
        state.pollution = state.pollution + rate / units_per_entity * pollution_per_entity
        finish_column(state)
    else
        local rate = state.recipe_rates[column.recipe_name] or 0
        local energy_usage, pollution = compute_for_recipe(prototypes.recipe[column.recipe_name], rate, state.player_index)
        state.energy = state.energy + energy_usage
        state.pollution = state.pollution + pollution
        finish_column(state)
    end

    budget.ops = budget.ops - 1
    state.done_units = state.done_units + 1
    return state
end

function Power.compute(player_index, columns, recipe_rates_by_recipe_name)
    local state = Power.begin(player_index, columns, recipe_rates_by_recipe_name)
    local budget = {ops = math.huge}
    while not state.done do Power.step(state, budget) end
    return state.energy, state.pollution
end

--Callable table keeps the old synchronous module contract while exposing the resumable pair to report_steps.lua.
return setmetatable(Power, {__call = function(_, player_index, columns, recipe_rates_by_recipe_name)
    return Power.compute(player_index, columns, recipe_rates_by_recipe_name)
end})
