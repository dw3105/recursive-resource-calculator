--Entities that burn an excess item or fluid as fuel: which ones accept a product, how fast one burns it, and what burning leaves behind.
--Only reactors, boilers and burner generators are offered; other entities with a burner burn fuel only while doing their own job.
local Utils = require "logic.utils"

local Burners = {}

Burners.TYPES = {"reactor", "boiler", "burner-generator"}
Burners.COLUMN_PREFIX = "hxrrc-burn:"

--Names of every entity of the offered types, so a stored name is checked before anything is read from its prototype
function Burners.index()
    local names = {}
    for name, _ in pairs(prototypes.get_entity_filtered({{filter = "type", type = Burners.TYPES}})) do
        names[name] = true
    end
    storage.burner_names = names
end

local function split(product_full_name)
    local slash = string.find(product_full_name, "/", 1, true)
    return product_full_name:sub(1, slash - 1), product_full_name:sub(slash + 1)
end

--The item or fluid prototype of a product, nil once removed
local function product_prototype(product_full_name)
    local type, name = split(product_full_name)
    return type, (type == "item" and prototypes.item[name]) or (type == "fluid" and prototypes.fluid[name]) or nil
end

--Fluid burnt per second by one entity, or nil when the runtime data leaves it undefined.
--Scaled sources burn what the delivered energy needs, no more than a positive usage per tick; unscaled ones burn exactly their usage per tick.
local function fluid_units_per_second(source, delivered, fuel_value)
    local cap = source.fluid_usage_per_tick * 60
    if source.scale_fluid_usage then
        local needed = delivered / (source.effectivity * fuel_value)
        return cap > 0 and math.min(needed, cap) or needed
    end
    return cap > 0 and cap or nil
end

--Energy one entity delivers at full load, in joules per second
local function full_load(entity, quality)
    if entity.type == "burner-generator" then
        return entity.get_max_power_output(quality) * 60
    end
    return entity.get_max_energy_usage(quality) * 60
end

--Whether the named entity can burn the product; checks the index first, so nothing is read from an entity a mod turned into something else
function Burners.accepts(entity_name, product_full_name)
    if not storage.burner_names[entity_name] then
        return false
    end
    local type, prototype = product_prototype(product_full_name)
    if not prototype or not (prototype.fuel_value > 0) then
        return false
    end
    local entity = prototypes.entity[entity_name]
    if type == "item" then
        local burner = entity.burner_prototype
        return burner ~= nil and prototype.fuel_category ~= nil and burner.fuel_categories[prototype.fuel_category] == true
    end
    local source = entity.fluid_energy_source_prototype
    if not (source and source.burns_fluid) then
        return false
    end
    local filter = source.fluid_box.filter
    if filter and filter.name ~= prototype.name then
        return false
    end
    --2.1 sources with an output fluid box turn fuel into spent fluid, a material output this calculator does not carry
    if Utils.IS_2_1 and source.output_fluid_box ~= nil then
        return false
    end
    return fluid_units_per_second(source, full_load(entity, nil), prototype.fuel_value) ~= nil
end

--Names of the entities that can burn the product, sorted
function Burners.accepted_names(product_full_name)
    local names = {}
    for name, _ in pairs(storage.burner_names) do
        if Burners.accepts(name, product_full_name) then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

--For an accepted binding: units of the product one entity burns per second, and the pollution it emits per second.
--Pollution is taken on the energy the entity actually delivers, at most its full load, times the fuel's emissions multiplier.
function Burners.draw(product_full_name, identifier)
    local type, prototype = product_prototype(product_full_name)
    local entity = prototypes.entity[identifier.name]
    local delivered = full_load(entity, identifier.quality)
    local source, units, multiplier
    if type == "item" then
        source = entity.burner_prototype
        units = delivered / (source.effectivity * prototype.fuel_value)
        multiplier = prototype.fuel_emissions_multiplier
    else
        source = entity.fluid_energy_source_prototype
        units = fluid_units_per_second(source, delivered, prototype.fuel_value)
        multiplier = prototype.emissions_multiplier
    end
    local actual = math.min(delivered, units * prototype.fuel_value * source.effectivity)
    return units, (source.emissions_per_joule.pollution or 0) * actual * multiplier
end

--Net amounts per unit burnt: the product goes, and an item's burnt result comes back when the entity keeps burnt results
function Burners.net_amounts(product_full_name, identifier)
    local net_amounts = {[product_full_name] = -1}
    local type, prototype = product_prototype(product_full_name)
    local entity = prototypes.entity[identifier.name]
    if type == "item" and prototype.burnt_result and entity.burner_prototype.burnt_inventory_size > 0 then
        local burnt_full_name = "item/" .. prototype.burnt_result.name
        net_amounts[burnt_full_name] = (net_amounts[burnt_full_name] or 0) + 1
        if net_amounts[burnt_full_name] == 0 then
            net_amounts[burnt_full_name] = nil
        end
    end
    return net_amounts
end

--After a configuration change: bindings whose entity or product can no longer burn together go; a removed quality falls back to normal
function Burners.reinitialize(player_index)
    local player_storage = storage[player_index]
    player_storage.burners_by_product_full_name = player_storage.burners_by_product_full_name or {}
    for product_full_name, identifier in pairs(player_storage.burners_by_product_full_name) do
        if not Burners.accepts(identifier.name, product_full_name) then
            player_storage.burners_by_product_full_name[product_full_name] = nil
        elseif identifier.quality and not prototypes.quality[identifier.quality] then
            identifier.quality = nil
        end
    end
end

return Burners
