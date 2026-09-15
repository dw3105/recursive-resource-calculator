--Stored quality loop configurations, one per target item and quality, shared by every sheet of a player:
--storage[pi].quality_loops_by_key[identity] = {item, quality, recycle_recipe_name?, craft = {machine?, setup}, recycle = {machine?, setup}}.
--The craft stage runs the recipe the item is bound to; the recycle stage runs recycle_recipe_name, and without one nothing is recycled.
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

--The recipe a stage runs, its machine (nil when hand-crafted), that machine's prototype and the stage's setup; nil for a recycle stage without a recipe
function QualityLoops.stage(player_index, loop, stage_name)
    local recipe
    if stage_name == "craft" then
        recipe = QualityLoops.producer_of(player_index, loop.item)
    else
        recipe = loop.recycle_recipe_name and prototypes.recipe[loop.recycle_recipe_name]
    end
    if not recipe then
        return nil
    end
    local stage = loop[stage_name]
    return {recipe = recipe, machine = stage.machine, prototype = stage.machine and prototypes.entity[stage.machine.name], setup = stage.setup}
end

--The recycle recipe a new loop starts with: the only recipe whose ingredients are all the item, and whose item products are among the craft
--recipe's item ingredients or the item itself. Found through the ingredient index, never by name.
local function default_recycle_recipe_name(item_name, craft_recipe)
    local allowed = {[item_name] = true}
    for _, ingredient in ipairs(craft_recipe.ingredients) do
        if ingredient.type == "item" then allowed[ingredient.name] = true end
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

--A machine identifier kept only while that machine can craft the recipe; a removed quality falls back to normal
local function kept_machine(identifier, recipe)
    if identifier and Utils.can_craft(identifier.name, recipe) then
        return {name = identifier.name, quality = identifier.quality and prototypes.quality[identifier.quality] and identifier.quality or nil}
    end
end

local function sanitize_stage(stage, recipe)
    if stage.machine then
        ModuleSetup.sanitize_setup(stage.setup, stage.machine, recipe)
    else
        stage.setup = ModuleSetup.new_setup()
    end
end

--Makes a stored loop valid for the current prototypes and bindings, or drops it when its item or quality is gone
function QualityLoops.sanitize(player_index, key)
    local loops = storage[player_index].quality_loops_by_key
    local loop = loops[key]
    if not loop then
        return
    end
    if not (prototypes.item[loop.item] and prototypes.quality[loop.quality]) then
        loops[key] = nil
        return
    end

    local craft_recipe = QualityLoops.producer_of(player_index, loop.item)
    if craft_recipe then --otherwise the loop is not used until the item is bound again, and nothing depends on a recipe here
        local chosen = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[craft_recipe.name]
        loop.craft.machine = kept_machine(loop.craft.machine, craft_recipe) or kept_machine(chosen, craft_recipe)
        sanitize_stage(loop.craft, craft_recipe)
    end

    if loop.recycle_recipe_name and QualityLoop.recycler_refusal(prototypes.recipe[loop.recycle_recipe_name], loop.item) then
        loop.recycle_recipe_name = nil
    end
    if loop.recycle_recipe_name then
        local recycle_recipe = prototypes.recipe[loop.recycle_recipe_name]
        loop.recycle.machine = kept_machine(loop.recycle.machine, recycle_recipe) or Utils.get_any_crafting_machine_identifier_for(recycle_recipe)
        sanitize_stage(loop.recycle, recycle_recipe)
    else
        loop.recycle.machine = nil
        loop.recycle.setup = ModuleSetup.new_setup()
    end
end

--Creates the loop of a target above normal quality once its item is bound to a producer, then keeps it valid. parts: {type, name, quality}
function QualityLoops.ensure(player_index, key, parts)
    local loops = storage[player_index].quality_loops_by_key
    if not loops[key] then
        local craft_recipe = QualityLoops.producer_of(player_index, parts.name)
        if not craft_recipe then
            return
        end
        local chosen = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[craft_recipe.name]
        local recycle_recipe_name = default_recycle_recipe_name(parts.name, craft_recipe)
        loops[key] = {
            item = parts.name,
            quality = parts.quality,
            recycle_recipe_name = recycle_recipe_name,
            craft = {machine = chosen and {name = chosen.name, quality = chosen.quality}, setup = ModuleSetup.new_setup()},
            recycle = {machine = recycle_recipe_name and Utils.get_any_crafting_machine_identifier_for(prototypes.recipe[recycle_recipe_name]),
                setup = ModuleSetup.new_setup()},
        }
    end
    QualityLoops.sanitize(player_index, key)
end

--After a configuration change: every stored loop made valid
function QualityLoops.reinitialize(player_index)
    local player_storage = storage[player_index]
    player_storage.quality_loops_by_key = player_storage.quality_loops_by_key or {}
    for key, _ in pairs(player_storage.quality_loops_by_key) do
        QualityLoops.sanitize(player_index, key)
    end
end

return QualityLoops
