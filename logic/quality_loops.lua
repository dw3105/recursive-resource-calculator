--Stored quality loop configurations, one per target item and quality, shared by every sheet of a player:
--storage[pi].quality_loops_by_key[identity] = {item, quality, start_quality?, recycle_recipe_name?, crafts = {[quality name] = {machine?, setup}},
--  recycle = {machine?, setup}}; a tier's settings may also name recipe_name, the recipe it crafts with above the start quality (nil: chosen
--  automatically, see QualityLoops.tier_recipe).
--A loop crafts the recipe its item is bound to at every quality from start_quality (normal when nil) to its target, each with its own machine and
--setup, and recycles what misses the target with recycle_recipe_name in one shared pool; without a recycle recipe nothing is recycled.
--Nothing reads a stored configuration directly for a solve: QualityLoops.normalized gives a fresh copy that is valid now.
local Utils = require "logic.utils"
local ModuleSetup = require "logic.module_setup"
local QualityLoop = require "logic.quality_loop"

local QualityLoops = {}

--The recipe an item is bound to as its producer, or nil (unbound, or bound to a recipe picked to consume it)
function QualityLoops.producer_of(player_index, item_name)
    local player_storage = storage[player_index]
    local full_name = "item/" .. item_name
    local recipe = player_storage.recipes_by_product_full_name[full_name]
    if recipe and recipe.valid and not player_storage.consumer_product_full_names[full_name] then
        return recipe
    end
end

--Chain positions by quality name, from normal following next
local function chain_indexes()
    local indexes, chain = {}, QualityLoop.chain()
    for index, quality in ipairs(chain) do indexes[quality.name] = index end
    return indexes, chain
end

--The quality names a loop crafts at, from its start to its target, in chain order; just the target when the target is off the chain
function QualityLoops.tier_names(loop)
    local indexes, chain = chain_indexes()
    local target = indexes[loop.quality]
    if not target then
        return {loop.quality}
    end
    local names = {}
    for index = indexes[loop.start_quality or "normal"] or 1, target do names[#names + 1] = chain[index].name end
    return names
end

--Whether the loop crafts at a quality now (settings for other qualities are kept, but no control may edit them)
function QualityLoops.crafts_at(loop, tier)
    for _, name in ipairs(QualityLoops.tier_names(loop)) do
        if name == tier then return true end
    end
    return false
end

--The only recipe making the item that can craft it at a chain position, found through the product index; nil when none or several
local function auto_tier_recipe(item_name, chain_index)
    local found
    for _, recipe in ipairs(storage.recipe_lists_by_product_full_name["item/" .. item_name] or {}) do
        if recipe.valid and not QualityLoop.tier_recipe_refusal(recipe, item_name, chain_index) then
            if found then
                return nil
            end
            found = recipe
        end
    end
    return found
end

--The recipe a loop crafts at a tier: the item's producer at the start quality; above it the tier's chosen recipe while it can craft there, else the
--producer while it can, else the only recipe making the item that can; nil when there is none. Pure: storage is only read.
function QualityLoops.tier_recipe(player_index, loop, tier)
    local producer = QualityLoops.producer_of(player_index, loop.item)
    local indexes = chain_indexes()
    local index = indexes[tier]
    if not index or index <= (indexes[loop.start_quality or "normal"] or 1) then
        return producer
    end
    local chosen_name = loop.crafts[tier] and loop.crafts[tier].recipe_name
    local chosen = chosen_name and prototypes.recipe[chosen_name]
    if chosen and not QualityLoop.tier_recipe_refusal(chosen, loop.item, index) then
        return chosen
    end
    if producer and not QualityLoop.tier_recipe_refusal(producer, loop.item, index) then
        return producer
    end
    return auto_tier_recipe(loop.item, index)
end

--The recipe a stage runs, its machine (nil when hand-crafted), that machine's prototype and the stage's setup; nil for a recycle stage without a
--recipe, or a craft stage without a recipe (see QualityLoops.tier_recipe) or without settings for that tier
function QualityLoops.stage(player_index, loop, stage_name, tier)
    local recipe, settings
    if stage_name == "craft" then
        recipe = QualityLoops.tier_recipe(player_index, loop, tier)
        settings = loop.crafts[tier]
    else
        recipe = loop.recycle_recipe_name and prototypes.recipe[loop.recycle_recipe_name]
        settings = loop.recycle
    end
    if not (recipe and settings) then
        return nil
    end
    return {recipe = recipe, machine = settings.machine, prototype = settings.machine and prototypes.entity[settings.machine.name], setup = settings.setup}
end

--The recycle recipe a new loop starts with: the only recipe whose ingredients are all the item, and whose item products are among the item
--ingredients of the recipes the loop crafts with, or the item itself. Found through the ingredient index, never by name.
local function default_recycle_recipe_name(item_name, craft_recipes)
    local allowed = {[item_name] = true}
    for _, craft_recipe in ipairs(craft_recipes) do
        for _, ingredient in ipairs(craft_recipe.ingredients) do
            if ingredient.type == "item" then allowed[ingredient.name] = true end
        end
    end
    local found
    for _, recipe in ipairs(storage.recipe_lists_by_ingredient_full_name["item/" .. item_name] or {}) do
        local fits = #recipe.ingredients > 0
        for _, ingredient in ipairs(recipe.ingredients) do
            if ingredient.type ~= "item" or ingredient.name ~= item_name then fits = false end
        end
        for _, product in ipairs(recipe.products) do
            if product.type == "item" and not allowed[product.name] then fits = false end
        end
        if fits and not QualityLoop.recycler_refusal(recipe, item_name) then
            if found then
                return nil --not unique
            end
            found = recipe.name
        end
    end
    return found
end

--Primary categories of the recipes that can recycle an item (QualityLoop.recycler_refusal), sorted, each once; found through the ingredient index.
--A recipe picker filtered by the item and these categories lists those recipes (recipe filters have no name filter).
function QualityLoops.recycle_recipe_categories(item_name)
    local seen, categories = {}, {}
    for _, recipe in ipairs(storage.recipe_lists_by_ingredient_full_name["item/" .. item_name] or {}) do
        local category = Utils.recipe_categories(recipe)[1]
        if category and not seen[category] and not QualityLoop.recycler_refusal(recipe, item_name) then
            seen[category] = true
            categories[#categories + 1] = category
        end
    end
    table.sort(categories)
    return categories
end

--A copy of a machine identifier kept only while that machine can craft the recipe; a removed quality falls back to normal
local function kept_machine(identifier, recipe)
    if identifier and Utils.can_craft(identifier.name, recipe) then
        return {name = identifier.name, quality = identifier.quality and prototypes.quality[identifier.quality] and identifier.quality or nil}
    end
end

local function copy_identifier(identifier)
    return identifier and {name = identifier.name, quality = identifier.quality}
end

--A fresh copy of a setup made valid for the machine crafting the recipe (none when hand-crafted); the stored setup is never touched
local function valid_setup_copy(setup, machine, recipe)
    if not (machine and setup) then
        return ModuleSetup.new_setup()
    end
    local copy = {modules = setup.modules, beacons = setup.beacons}
    ModuleSetup.sanitize_setup(copy, machine, recipe) --builds new module and beacon lists, so the stored lists stay as they were
    return copy
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = deep_copy(inner) end
    return copy
end

--The loop configuration of a target that is valid now, as a fresh copy, or nil when there is none: its item or quality is gone, or it was never
--stored and its item has no producer. Pure: storage is only read. parts: the target's {name, quality}, or nil to take them from storage.
--Applies: the configuration of 1.1.19 (one craft stage) copied to every quality up to the target; a start quality that is gone, off the chain or
--above the target falls back to normal; craft machines that cannot craft the current producer replaced by its chosen machine; a recycle recipe
--that cannot recycle the item cleared; recycle machine replaced when it cannot run the recipe; setups fitted to their machines; settings for
--every crafted tier that has none.
function QualityLoops.normalized(player_index, key, parts)
    local player_storage = storage[player_index]
    local stored = player_storage.quality_loops_by_key[key]
    local item = parts and parts.name or stored and stored.item
    local quality = parts and parts.quality or stored and stored.quality
    if not (item and quality and prototypes.item[item] and prototypes.quality[quality]) then
        return nil
    end
    local craft_recipe = QualityLoops.producer_of(player_index, item)
    if not (stored or craft_recipe) then
        return nil
    end
    local indexes, chain = chain_indexes()
    local target = indexes[quality]
    local config = {item = item, quality = quality}

    local start = stored and stored.start_quality
    if start == "normal" or not (start and prototypes.quality[start] and indexes[start] and target and indexes[start] <= target) then
        start = nil
    end
    config.start_quality = start

    --the settings of 1.1.19, one craft stage for the whole loop, become every tier's up to the target
    local stored_crafts = stored and stored.crafts
    if stored and not stored_crafts and stored.craft then
        stored_crafts = {}
        for index = 1, target or 0 do stored_crafts[chain[index].name] = stored.craft end
    end
    --each tier's chosen recipe first, kept while it can craft that tier, so the tier recipes below can be resolved
    config.crafts = {}
    for tier, settings in pairs(stored_crafts or {}) do
        if prototypes.quality[tier] then
            local recipe_name = settings.recipe_name
            local recipe = recipe_name and prototypes.recipe[recipe_name]
            if not (recipe and not QualityLoop.tier_recipe_refusal(recipe, item, indexes[tier] or 1)) then recipe_name = nil end
            config.crafts[tier] = {recipe_name = recipe_name, machine = settings.machine, setup = settings.setup}
        end
    end
    if craft_recipe and target then
        for index = indexes[start or "normal"], target do
            local tier = chain[index].name
            config.crafts[tier] = config.crafts[tier] or {}
        end
    end
    local tier_recipes = {}
    if craft_recipe then
        for tier, _ in pairs(config.crafts) do
            tier_recipes[tier] = QualityLoops.tier_recipe(player_index, config, tier)
        end
    end

    local recycle_recipe_name
    if stored then
        recycle_recipe_name = stored.recycle_recipe_name
    else
        local recipes, seen = {}, {}
        for _, recipe in pairs(tier_recipes) do
            if not seen[recipe.name] then
                seen[recipe.name] = true
                recipes[#recipes + 1] = recipe
            end
        end
        table.sort(recipes, function(a, b) return a.name < b.name end)
        recycle_recipe_name = default_recycle_recipe_name(item, recipes)
    end
    if recycle_recipe_name and QualityLoop.recycler_refusal(prototypes.recipe[recycle_recipe_name], item) then
        recycle_recipe_name = nil
    end
    config.recycle_recipe_name = recycle_recipe_name
    local stored_recycle = stored and stored.recycle or {}
    if recycle_recipe_name then
        local recipe = prototypes.recipe[recycle_recipe_name]
        local machine = kept_machine(stored_recycle.machine, recipe) or Utils.get_any_crafting_machine_identifier_for(recipe)
        config.recycle = {machine = machine, setup = valid_setup_copy(stored_recycle.setup, machine, recipe)}
    else
        config.recycle = {setup = ModuleSetup.new_setup()}
    end

    --machines and setups fitted to each tier's recipe; a tier without a recipe keeps its settings as they are until it has one
    local chosen_machines = player_storage.identifiers_of_chosen_crafting_machines_by_recipe_name
    for tier, settings in pairs(config.crafts) do
        local recipe = tier_recipes[tier]
        if recipe then
            local machine = kept_machine(settings.machine, recipe) or kept_machine(chosen_machines[recipe.name], recipe)
            config.crafts[tier] = {recipe_name = settings.recipe_name, machine = machine,
                setup = settings.setup and valid_setup_copy(settings.setup, machine, recipe) or ModuleSetup.new_setup()}
        else
            config.crafts[tier] = deep_copy(settings)
            config.crafts[tier].setup = config.crafts[tier].setup or ModuleSetup.new_setup()
        end
    end
    return config
end

--Replaces a stored loop configuration (nil removes it)
function QualityLoops.store(player_index, key, config)
    storage[player_index].quality_loops_by_key[key] = config
end

--Makes a stored loop valid for the current prototypes and bindings, or drops it when its item or quality is gone
function QualityLoops.sanitize(player_index, key)
    QualityLoops.store(player_index, key, QualityLoops.normalized(player_index, key))
end

--After a configuration change: every stored loop made valid
function QualityLoops.reinitialize(player_index)
    local player_storage = storage[player_index]
    player_storage.quality_loops_by_key = player_storage.quality_loops_by_key or {}
    local keys = {}
    for key, _ in pairs(player_storage.quality_loops_by_key) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        QualityLoops.sanitize(player_index, key)
    end
end

QualityLoops._deep_copy = deep_copy

return QualityLoops
