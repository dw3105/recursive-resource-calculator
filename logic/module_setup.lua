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

function ModuleSetup.beacon_capacity(beacon, quality)
    return beacon.get_inventory_size(defines.inventory.beacon_modules, quality) or 0
end

--Stores a pick into a dense module list and returns true when the list changed. picked: {name, quality} or nil to empty the slot.
--An emptied slot is removed and the rest shift left; emptying a slot that holds nothing changes nothing. A module picked into a row where no slot
--is filled goes into every slot of that row (separate tables), so filling a machine takes one pick; a row already holding a module takes only
--the picked slot, which replaces a module or appends after the last one, so the list never has holes.
function ModuleSetup.store_pick(modules, index, picked, capacity)
    if picked == nil then
        if index > #modules then
            return false
        end
        table.remove(modules, index)
        return true
    end
    local quality = picked.quality ~= "normal" and picked.quality or nil
    if #modules == 0 then
        for slot = 1, math.max(capacity, 1) do
            modules[slot] = {name = picked.name, quality = quality}
        end
    elseif index <= #modules then
        modules[index] = {name = picked.name, quality = quality}
    else
        modules[#modules + 1] = {name = picked.name, quality = quality}
    end
    return true
end

--Beacon counts and sharing are whole numbers from 1 to 9999, so every accepted value is written exactly in a signature; nan and infinities fail here
function ModuleSetup.is_valid_count(value)
    return type(value) == "number" and value >= 1 and value <= 9999 and value == math.floor(value)
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
    for effect, value in pairs(module.module_effects or {}) do --2.1 marks module effects optional
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

--Modules a picker offers: not ones the engine hides, and not blueprint parameter placeholders. Kept out of fits, which also decides whether a
--module already stored in a save survives sanitizing, so a hidden module a player stored keeps its slot and its effects.
local function is_offered(module_name)
    local module = prototypes.item[module_name]
    return not module.hidden and not module.parameter
end

--Names of the modules that fit and are offered, sorted
function ModuleSetup.allowed_module_names(entities, recipe)
    local names = {}
    for module_name, _ in pairs(storage.module_names) do
        if ModuleSetup.fits(module_name, entities, recipe) and is_offered(module_name) then
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

--Makes a setup valid for the machine crafting the recipe with it, in place; identifier nil is hand crafting, which takes no modules or beacons.
--Callers make sure the recipe and machine exist and fit each other.
function ModuleSetup.sanitize_setup(setup, identifier, recipe)
    if not identifier then
        setup.modules, setup.beacons = {}, {}
        return
    end
    local machine = prototypes.entity[identifier.name]
    setup.modules = kept_modules(setup.modules, {machine}, recipe, ModuleSetup.machine_capacity(machine, identifier.quality))

    local kept_groups = {}
    local effect_receiver = machine.effect_receiver
    if not (effect_receiver and effect_receiver.uses_beacon_effects == false) then
        for _, group in ipairs(setup.beacons) do
            --the beacon index is checked first, so nothing is read from an entity a mod turned into something else
            if storage.beacon_names[group.name] and ModuleSetup.is_valid_count(group.count) then
                local beacon = prototypes.entity[group.name]
                local quality = group.quality and prototypes.quality[group.quality] and group.quality or nil
                kept_groups[#kept_groups + 1] = {
                    name = group.name,
                    quality = quality,
                    count = group.count,
                    --a bad count means no beacons, so its group goes; a bad sharing only loses an estimate, so it falls back to one machine per beacon
                    sharing = ModuleSetup.is_valid_count(group.sharing) and group.sharing or 1,
                    modules = kept_modules(group.modules, {beacon, machine}, recipe, ModuleSetup.beacon_capacity(beacon, quality)),
                }
            end
        end
    end
    setup.beacons = kept_groups
end

--Makes a recipe's stored setup valid for its chosen machine; callers make sure the recipe and machine are current
function ModuleSetup.sanitize(player_index, recipe_name)
    local setups = storage[player_index].module_setups_by_recipe_name
    local identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    if not identifier then --hand-crafted recipe
        setups[recipe_name] = ModuleSetup.new_setup()
        return
    end
    ModuleSetup.sanitize_setup(setups[recipe_name], identifier, prototypes.recipe[recipe_name])
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
