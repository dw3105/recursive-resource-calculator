local Indexer = {}

local function insert_multimap(multimap, key, value)
    if not multimap[key] then
        multimap[key] = {value}
    else
        table.insert(multimap[key], value)
    end
end

local function index_recipes()
    local recipes = {}
    for _, recipe_prototype in pairs(prototypes.recipe) do
        for _, product in ipairs(recipe_prototype.products) do
            if product.type ~= "research-progress" then
                insert_multimap(recipes, product.type .. "/" .. product.name, recipe_prototype)
            end
        end
    end
    storage.recipe_lists_by_product_full_name = recipes
end

local function compute_pollution(entity_prototype)
    local energy_source = entity_prototype.electric_energy_source_prototype or entity_prototype.burner_prototype or entity_prototype.heat_energy_source_prototype or entity_prototype.fluid_energy_source_prototype or entity_prototype.void_energy_source_prototype
    if energy_source then
      --emissions are keyed by pollutant, and a machine may emit none of the "pollution" kind
      return entity_prototype.get_max_energy_usage() * (energy_source.emissions_per_joule.pollution or 0) * 60
    end
    return 0
end

local function index_crafting_machines()
    local crafting_machines_by_category = {}
    for _, machine in pairs(prototypes.get_entity_filtered{{filter="crafting-machine"}}) do
        for category, _ in pairs(machine.crafting_categories) do
            insert_multimap(crafting_machines_by_category, category, machine)
        end
    end
    storage.crafting_machines_by_category = crafting_machines_by_category
end

local function index_crafting_machine_pollution()
    local pollution_by_crafting_machine = {}
    for machine_name, machine in pairs(prototypes.get_entity_filtered{{filter="crafting-machine"}}) do
        pollution_by_crafting_machine[machine_name] = compute_pollution(machine)
    end
    storage.pollution_by_crafting_machine = pollution_by_crafting_machine
end

--Names of every module and every beacon, so a stored name is checked before anything is read from its prototype
local function index_modules()
    local module_names = {}
    for module_name, _ in pairs(prototypes.get_item_filtered({{filter="type", type="module"}})) do
        module_names[module_name] = true
    end
    storage.module_names = module_names
    storage.names_of_allowed_modules_by_recipe_name = nil --kept by versions before module slots

    local beacon_names = {}
    for beacon_name, _ in pairs(prototypes.get_entity_filtered({{filter="type", type="beacon"}})) do
        beacon_names[beacon_name] = true
    end
    storage.beacon_names = beacon_names
end

function Indexer.run()
    index_recipes()
    index_crafting_machines()
    index_crafting_machine_pollution()
    index_modules()
end

return Indexer