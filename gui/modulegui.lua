local Utils = require "logic.utils"
local ModuleSetup = require "logic.module_setup"

local ModuleGUI = {}

local function add_effects_label(cell, recipe_name)
    local label_flow = cell.add{type = "flow", direction = "vertical"}
    local effects = Utils.recipe_effects(cell.player_index, recipe_name)
    for _, effect in ipairs(Utils.module_effect_names) do
        local effect_value = effects[effect]
        if math.abs(effect_value) >= 0.01 then
            label_flow.add{type = "label", caption = {"", {"hxrrc." .. effect}, ": ", string.format("%+.0f", (effect_value > -0.8 and effect_value or -0.8) * 100) .. "%"}}
        end
    end
end

--Builds the cell's controls from the stored setup; the cell's tags remember the recipe and the setup it shows
local function fill(cell, recipe, machine, identifier)
    local setup = storage[cell.player_index].module_setups_by_recipe_name[recipe.name]
    cell.tags = {recipe_name = recipe.name, signature = ModuleSetup.signature(setup, identifier)}

    local capacity = ModuleSetup.machine_capacity(machine, identifier.quality)
    local allowed = ModuleSetup.allowed_module_names({machine}, recipe)
    if capacity > 0 and #allowed > 0 then
        local slots = cell.add{type = "flow", direction = "horizontal", name = "hxrrc_module_slots"}
        slots.style.right_padding = 4
        for index = 1, capacity do
            local module = setup.modules[index]
            local value = module and {name = module.name, quality = module.quality}
            slots.add{
                type = "choose-elem-button",
                name = "hxrrc_choose_module_button",
                tooltip = {"hxrrc.choose_module_button_tooltip"},
                elem_type = "item-with-quality",
                ["item-with-quality"] = value,
                elem_filters = {{filter = "name", name = allowed}},
                tags = {index = index, value = value}, --snapshot for refused changes on a stale report
            }
        end
    end

    add_effects_label(cell, recipe.name)
end

function ModuleGUI.new(parent, recipe, machine, identifier)
    if ModuleSetup.machine_capacity(machine, identifier.quality) == 0 then
        parent.add{type = "empty-widget"}
        return
    end
    local cell = parent.add{type = "flow", direction = "vertical"}
    fill(cell, recipe, machine, identifier)
end

local function same_value(a, b)
    if type(a) == "table" and type(b) == "table" then
        return a.name == b.name and (a.quality or "normal") == (b.quality or "normal")
    end
    return a == b
end

--What a refused change puts back: the button's own snapshot, unless its module no longer exists; a removed quality falls back to normal
local function restored_value(button)
    if button.elem_type == "item" then --a slot button built before module slots had qualities; its snapshot sits on its slot flow
        local module_name = button.parent.tags.module_name
        return module_name and prototypes.item[module_name] and module_name or nil
    end
    local value = button.tags.value
    if not (value and prototypes.item[value.name]) then
        return nil
    end
    return {name = value.name, quality = value.quality and prototypes.quality[value.quality] and value.quality or nil}
end

--Returns true when the stored setup changed
function ModuleGUI.on_module_button_changed(event)
    local button = event.element
    local restored = restored_value(button)
    --a refused change restores the button, which may raise this event again: the restored value is then a no-op
    if same_value(button.elem_value, restored) then
        return false
    end

    local cell = button.parent.parent
    local recipe_name = cell.tags.recipe_name
    local player_index = button.player_index
    local setup = storage[player_index].module_setups_by_recipe_name[recipe_name]
    local identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    --stale: the recipe is gone, the cell predates signatures, or the setup or machine changed since the cell was built
    if not setup or not cell.tags.signature or ModuleSetup.signature(setup, identifier) ~= cell.tags.signature then
        button.elem_value = restored
        return false
    end

    local picked = button.elem_value
    local index = button.tags.index
    if picked == nil then
        table.remove(setup.modules, index)
    else
        local module = {name = picked.name, quality = picked.quality ~= "normal" and picked.quality or nil}
        if index <= #setup.modules then
            setup.modules[index] = module
        else --any empty slot appends, so the list never has holes
            setup.modules[#setup.modules + 1] = module
        end
    end
    ModuleSetup.sanitize(player_index, recipe_name)

    cell.clear()
    fill(cell, prototypes.recipe[recipe_name], prototypes.entity[identifier.name], identifier)
    return true
end

return ModuleGUI
