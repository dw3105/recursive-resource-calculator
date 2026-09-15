local Utils = {}

Utils.module_effect_names = {"consumption", "speed", "productivity", "pollution", "quality"}

--Factorio 2.1 renamed recipe and product members, and LuaObjects throw on unknown members, so the API shape is chosen by game version instead of probing
Utils.IS_2_1 = helpers.compare_versions(script.active_mods["base"], "2.1.0") >= 0

--Every category a machine may craft the recipe through, primary first: 2.0 keeps additional categories apart, 2.1 lists them all
function Utils.recipe_categories(recipe)
    if Utils.IS_2_1 then
        return recipe.categories
    end
    return {recipe.category, table.unpack(recipe.additional_categories)}
end

--Products are plain tables, so absent optional keys read as nil; 2.1 defaults are independent_probability = 1 and shared_probability = {min = 0, max = 1}
function Utils.product_probability(product)
    if Utils.IS_2_1 then
        local shared_probability = product.shared_probability
        return (product.independent_probability or 1) * (shared_probability and (shared_probability.max - shared_probability.min) or 1)
    end
    return product.probability or 1
end

--Summed effects of a setup's modules and beacons, each module at its quality; stored setups are kept valid, so every module and beacon still exists
function Utils.setup_effects(setup)
    local totals = {consumption = 0, speed = 0, productivity = 0, pollution = 0, quality = 0}
    for _, module in ipairs(setup.modules) do
        local effects = prototypes.item[module.name].get_module_effects(module.quality) or {} --2.1 marks module effects optional
        for _, effect in ipairs(Utils.module_effect_names) do
            totals[effect] = totals[effect] + (effects[effect] or 0)
        end
    end

    --A beacon passes its modules' effects times its distribution effectivity at its quality, times the profile's sample for the beacons reaching
    --the machine: those of its own type or all of them, as its counter says; the sample past the profile's end is its last value
    local count_by_beacon_name, beacon_total = {}, 0
    for _, group in ipairs(setup.beacons) do
        count_by_beacon_name[group.name] = (count_by_beacon_name[group.name] or 0) + group.count
        beacon_total = beacon_total + group.count
    end
    for _, group in ipairs(setup.beacons) do
        local beacon = prototypes.entity[group.name]
        local effectivity = (beacon.distribution_effectivity or 1)
            + (beacon.distribution_effectivity_bonus_per_quality_level or 0) * prototypes.quality[group.quality or "normal"].level
        local reaching = beacon.beacon_counter == "same_type" and count_by_beacon_name[group.name] or beacon_total
        local profile = beacon.profile
        local sample = profile and profile[math.min(reaching, #profile)] or 1
        local weight = group.count * effectivity * sample
        for _, beacon_module in ipairs(group.modules) do
            local effects = prototypes.item[beacon_module.name].get_module_effects(beacon_module.quality) or {}
            for _, effect in ipairs(Utils.module_effect_names) do
                totals[effect] = totals[effect] + weight * (effects[effect] or 0)
            end
        end
    end
    return totals
end

--Summed effects of the setup stored for a recipe
function Utils.recipe_effects(player_index, recipe_name)
    return Utils.setup_effects(storage[player_index].module_setups_by_recipe_name[recipe_name])
end

--Multiplier of an effect with the engine's lower bound of 20%
function Utils.effect_multiplier(effects, effect)
    local multiplier = effects[effect] + 1
    return multiplier > 0.2 and multiplier or 0.2
end

--quality is the machine's quality name, nil meaning normal; setup is the module setup the machine runs with
function Utils.machine_amount(recipe, recipe_rate, crafting_machine, quality, setup)
    local speed_multiplier = Utils.effect_multiplier(Utils.setup_effects(setup), "speed")
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

--Machines able to craft the recipe, each once, in category order and then in indexing order
function Utils.crafting_machines_for(recipe)
    local machines, seen = {}, {}
    for _, category in ipairs(Utils.recipe_categories(recipe)) do
        for _, machine in ipairs(storage.crafting_machines_by_category[category] or {}) do
            if not seen[machine.name] then
                seen[machine.name] = true
                machines[#machines + 1] = machine
            end
        end
    end
    return machines
end

function Utils.get_any_crafting_machine_identifier_for(recipe)
    local machine = Utils.crafting_machines_for(recipe)[1]
    return machine and {name = machine.name}
end

--Looks the machine up in the index Indexer.run builds, so no member of an entity a mod may have swapped is read
function Utils.can_craft(machine_name, recipe)
    for _, machine in ipairs(Utils.crafting_machines_for(recipe)) do
        if machine.name == machine_name then
            return true
        end
    end
    return false
end

return Utils