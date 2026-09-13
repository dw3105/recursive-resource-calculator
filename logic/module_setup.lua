--The modules chosen per recipe: how many slots a machine has, which modules fit, keeping stored setups valid, converting old saves,
--and the signature a report cell keeps to recognise a setup that changed after the cell was built
local ModuleSetup = {}

--modules: dense list of {name, quality} in slot order, quality nil meaning normal; beacons: beacon groups
function ModuleSetup.new_setup()
    return {modules = {}, beacons = {}}
end

--The engine's slot count at this quality, quality bonuses and the machine's own per-quality bonuses included; none when the machine ignores module effects
function ModuleSetup.machine_capacity(machine, quality)
    local effect_receiver = machine.effect_receiver
    if effect_receiver and effect_receiver.uses_module_effects == false then
        return 0
    end
    return machine.get_inventory_size(defines.inventory.crafter_modules, quality) or 0
end

--An entity without a list of allowed effects allows none; a recipe without one allows all
local function allows(allowed_effects, effect, allowed_when_absent)
    if allowed_effects == nil then
        return allowed_when_absent
    end
    return allowed_effects[effect] == true
end

--A module fits when the entities and the recipe accept its category and every effect it raises; lowering a disallowed effect never refuses it.
--The module index is checked first, so nothing is read from an item a mod turned into something else.
function ModuleSetup.fits(module_name, entities, recipe)
    if not storage.module_names[module_name] then
        return false
    end
    local module = prototypes.item[module_name]
    local category = module.category
    for _, entity in ipairs(entities) do
        if entity.allowed_module_categories and not entity.allowed_module_categories[category] then
            return false
        end
    end
    if recipe.allowed_module_categories and not recipe.allowed_module_categories[category] then
        return false
    end
    for effect, value in pairs(module.module_effects) do
        if value > 0 then
            for _, entity in ipairs(entities) do
                if not allows(entity.allowed_effects, effect, false) then
                    return false
                end
            end
            if not allows(recipe.allowed_effects, effect, true) then
                return false
            end
        end
    end
    return true
end

--Names of the modules that fit, sorted
function ModuleSetup.allowed_module_names(entities, recipe)
    local names = {}
    for module_name, _ in pairs(storage.module_names) do
        if ModuleSetup.fits(module_name, entities, recipe) then
            names[#names + 1] = module_name
        end
    end
    table.sort(names)
    return names
end

--A quality is kept only while it exists; nil is normal
local function existing_quality(quality)
    return quality and prototypes.quality[quality] and quality or nil
end

--Modules that still fit, in order; refused modules are left out before capping, so they take no slot
local function kept_modules(modules, entities, recipe, capacity)
    local kept = {}
    for _, module in ipairs(modules) do
        if ModuleSetup.fits(module.name, entities, recipe) then
            kept[#kept + 1] = {name = module.name, quality = existing_quality(module.quality)}
        end
    end
    for index = capacity + 1, #kept do
        kept[index] = nil
    end
    return kept
end

--Makes a recipe's stored setup valid for its chosen machine; callers make sure the recipe and machine are current
function ModuleSetup.sanitize(player_index, recipe_name)
    local setups = storage[player_index].module_setups_by_recipe_name
    local identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    if not identifier then --hand-crafted recipe
        setups[recipe_name] = ModuleSetup.new_setup()
        return
    end
    local setup = setups[recipe_name]
    local machine = prototypes.entity[identifier.name]
    setup.modules = kept_modules(setup.modules, {machine}, prototypes.recipe[recipe_name], ModuleSetup.machine_capacity(machine, identifier.quality))
end

--After a configuration change, once chosen machines are valid: a setup for every recipe and none for removed ones, each made valid
function ModuleSetup.reinitialize(player_index)
    local setups = storage[player_index].module_setups_by_recipe_name
    for recipe_name, _ in pairs(setups) do
        if not prototypes.recipe[recipe_name] then
            setups[recipe_name] = nil
        end
    end
    for recipe_name, _ in pairs(prototypes.recipe) do
        setups[recipe_name] = setups[recipe_name] or ModuleSetup.new_setup()
        ModuleSetup.sanitize(player_index, recipe_name)
    end
end

--Converts module data saved before module slots (names at positive indexes, counts at negative ones) into slots, once:
--whole counts fill slots in stored order; modules that do not fit, fractions and counts past the machine's slots are dropped
function ModuleSetup.migrate(player_index)
    local player_storage = storage[player_index]
    player_storage.module_setups_by_recipe_name = player_storage.module_setups_by_recipe_name or {}
    local old_preferences_by_recipe_name = player_storage.module_preferences_by_recipe_name
    if not old_preferences_by_recipe_name then
        return
    end
    local setups = player_storage.module_setups_by_recipe_name
    for recipe_name, preferences in pairs(old_preferences_by_recipe_name) do
        local recipe = prototypes.recipe[recipe_name]
        local identifier = player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
        if recipe and identifier then
            local machine = prototypes.entity[identifier.name]
            local capacity = ModuleSetup.machine_capacity(machine, identifier.quality)
            local setup = setups[recipe_name] or ModuleSetup.new_setup()
            setups[recipe_name] = setup
            for index, module_name in ipairs(preferences) do
                local count = preferences[-index]
                if type(module_name) == "string" and type(count) == "number" and ModuleSetup.fits(module_name, {machine}, recipe) then
                    --the loop bound never comes from the saved count itself, so a huge count cannot stall loading
                    local copies = math.min(math.floor(count), capacity - #setup.modules)
                    for _ = 1, copies do
                        setup.modules[#setup.modules + 1] = {name = module_name}
                    end
                end
            end
        end
    end
    player_storage.module_preferences_by_recipe_name = nil
end

--Strings are length-prefixed and every list is preceded by its length, so different setups never share a signature
local function text(value)
    return #value .. ":" .. value
end

local function quality_text(quality)
    return quality == nil and "-" or text(quality)
end

--Counts are whole numbers from 1 to 9999, which "%d" writes exactly
local function integer_text(value)
    return text(string.format("%d", value))
end

local function add_modules_text(out, modules)
    out[#out + 1] = #modules .. ";"
    for _, module in ipairs(modules) do
        out[#out + 1] = text(module.name) .. quality_text(module.quality)
    end
end

function ModuleSetup.signature(setup, machine_identifier)
    local out = {"M", machine_identifier and (text(machine_identifier.name) .. quality_text(machine_identifier.quality)) or "-", "S"}
    add_modules_text(out, setup.modules)
    out[#out + 1] = "B" .. #setup.beacons .. ";"
    for _, group in ipairs(setup.beacons) do
        out[#out + 1] = "G" .. text(group.name) .. quality_text(group.quality) .. integer_text(group.count) .. integer_text(group.sharing)
        add_modules_text(out, group.modules)
    end
    return table.concat(out)
end

return ModuleSetup
