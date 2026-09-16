local Utils = require "logic.utils"
local ModuleSetup = require "logic.module_setup"
local QualityLoops = require "logic.quality_loops"

local ModuleGUI = {}

local function add_effects_label(cell, setup)
    local label_flow = cell.add{type = "flow", direction = "vertical"}
    local effects = Utils.setup_effects(setup)
    for _, effect in ipairs(Utils.module_effect_names) do
        local effect_value = effects[effect]
        if math.abs(effect_value) >= 0.01 then
            local text
            if effect == "quality" and not Utils.IS_2_1 then
                --in 2.0 a quality effect is the chance of a first upgrade from normal once multiplied by normal's next_probability; 2.1 is unverified
                text = string.format("%+.2f", math.max(0, effect_value) * prototypes.quality.normal.next_probability * 100)
            else
                text = string.format("%+.0f", (effect_value > -0.8 and effect_value or -0.8) * 100)
            end
            label_flow.add{type = "label", caption = {"", {"hxrrc." .. effect}, ": ", text .. "%"}}
        end
    end
end

--A machine receives beacon groups unless it ignores beacon effects, and only when some beacon exists
local function receives_beacons(machine)
    local effect_receiver = machine.effect_receiver
    return not (effect_receiver and effect_receiver.uses_beacon_effects == false) and next(storage.beacon_names) ~= nil
end

local function sorted_beacon_names()
    local names = {}
    for beacon_name, _ in pairs(storage.beacon_names) do
        names[#names + 1] = beacon_name
    end
    table.sort(names)
    return names
end

--Each button sits in its own flow: the engine refuses two children with the same name under one parent
local function add_module_buttons(row, name, modules, capacity, allowed, group_index)
    for index = 1, capacity do
        local module = modules[index]
        local value = module and {name = module.name, quality = module.quality}
        row.add{type = "flow"}.add{
            type = "choose-elem-button",
            name = name,
            tooltip = {"hxrrc.choose_module_button_tooltip"},
            elem_type = "item-with-quality",
            ["item-with-quality"] = value,
            elem_filters = {{filter = "name", name = allowed}},
            tags = {group = group_index, index = index, value = value}, --snapshot for refused changes on a stale report
        }
    end
end

--group nil makes the button that adds a group
local function add_beacon_button(row, group, group_index, beacon_filter)
    local value = group and {name = group.name, quality = group.quality}
    row.add{
        type = "choose-elem-button",
        name = "hxrrc_choose_beacon_button",
        tooltip = {"hxrrc.beacon_button_tooltip"},
        elem_type = "entity-with-quality",
        ["entity-with-quality"] = value,
        elem_filters = beacon_filter,
        tags = {group = group_index, value = value},
    }
end

local function add_count_field(row, name, tooltip, group_index, value)
    local text = string.format("%d", value)
    local field = row.add{
        type = "textfield",
        name = name,
        tooltip = {tooltip},
        text = text,
        numeric = true,
        allow_decimal = false,
        allow_negative = false,
        lose_focus_on_confirm = true,
        tags = {group = group_index, text = text},
    }
    field.style.width = 40
end

--The setup a cell edits: a quality loop stage's (owner {loop_key, stage, tier}; tier names the craft tier, nil for the recycler pool) or the recipe's own
local function owned_setup(player_index, recipe_name, owner)
    if owner and owner.loop_key then
        local loop = storage[player_index].quality_loops_by_key[owner.loop_key]
        local settings = loop and (owner.stage == "craft" and loop.crafts[owner.tier] or owner.stage == "recycle" and loop.recycle
            or owner.stage == "assist" and loop.assist)
        return settings and settings.setup
    end
    return storage[player_index].module_setups_by_recipe_name[recipe_name]
end

--Builds the cell's controls from the stored setup; the cell's tags remember the row's product, the recipe, the setup's owner and the setup it shows.
--A rebuild passes no product or owner and keeps the ones already tagged.
local function fill(cell, recipe, machine, identifier, product_full_name, owner)
    local old_tags = cell.tags
    owner = owner or {loop_key = old_tags.loop_key, stage = old_tags.stage, tier = old_tags.tier}
    local setup = owned_setup(cell.player_index, recipe.name, owner)
    cell.tags = {recipe_name = recipe.name, product_full_name = product_full_name or old_tags.product_full_name, signature = ModuleSetup.signature(setup, identifier),
        loop_key = owner.loop_key, stage = owner.stage, tier = owner.tier}

    local capacity = ModuleSetup.machine_capacity(machine, identifier.quality)
    local allowed = ModuleSetup.allowed_module_names({machine}, recipe)
    --stored modules keep their slots even when nothing is offered (a hidden module), so they can still be removed
    if capacity > 0 and (#allowed > 0 or #setup.modules > 0) then
        local slots = cell.add{type = "flow", direction = "horizontal", name = "hxrrc_module_slots"}
        slots.style.right_padding = 4
        add_module_buttons(slots, "hxrrc_choose_module_button", setup.modules, capacity, allowed)
    end

    if receives_beacons(machine) then
        local beacon_filter = {{filter = "name", name = sorted_beacon_names()}}
        for group_index, group in ipairs(setup.beacons) do
            local row = cell.add{type = "flow", direction = "horizontal"}
            add_beacon_button(row, group, group_index, beacon_filter)
            add_count_field(row, "hxrrc_beacon_count_textfield", "hxrrc.beacon_count_textfield_tooltip", group_index, group.count)
            add_count_field(row, "hxrrc_beacon_sharing_textfield", "hxrrc.beacon_sharing_textfield_tooltip", group_index, group.sharing)
            local beacon = prototypes.entity[group.name]
            local beacon_allowed = ModuleSetup.allowed_module_names({beacon, machine}, recipe)
            if #beacon_allowed > 0 or #group.modules > 0 then
                add_module_buttons(row, "hxrrc_choose_beacon_module_button", group.modules, ModuleSetup.beacon_capacity(beacon, group.quality), beacon_allowed, group_index)
            end
        end
        local add_row = cell.add{type = "flow", direction = "horizontal"}
        add_beacon_button(add_row, nil, #setup.beacons + 1, beacon_filter)
    end

    add_effects_label(cell, setup)
end

--owner: {loop_key, stage} for a quality loop stage's setup; nil for the recipe's own
function ModuleGUI.new(parent, recipe, machine, identifier, product_full_name, owner)
    if ModuleSetup.machine_capacity(machine, identifier.quality) == 0 and not receives_beacons(machine) then
        parent.add{type = "empty-widget"}
        return
    end
    local cell = parent.add{type = "flow", direction = "vertical"}
    fill(cell, recipe, machine, identifier, product_full_name, owner or {})
end

--The stored setup a control of a cell acts on, or nil when the cell is stale:
--the recipe is gone, the cell predates signatures, or the setup or machine changed since the cell was built
local function current_setup(element)
    local cell = element.parent
    while cell and not cell.tags.recipe_name do --the cell is the nearest ancestor tagged with a recipe
        cell = cell.parent
    end
    if not cell then
        return nil
    end
    local recipe_name = cell.tags.recipe_name
    local player_index = element.player_index
    if cell.tags.loop_key then
        --a loop stage's cell: stale once the loop, its stage recipe, its machine or its setup changed
        local loop = storage[player_index].quality_loops_by_key[cell.tags.loop_key]
        local stage = loop and (cell.tags.stage ~= "craft" or QualityLoops.crafts_at(loop, cell.tags.tier))
            and QualityLoops.stage(player_index, loop, cell.tags.stage, cell.tags.tier)
        if not (stage and stage.machine and stage.recipe.name == recipe_name) or ModuleSetup.signature(stage.setup, stage.machine) ~= cell.tags.signature then
            return nil
        end
        return stage.setup, cell, recipe_name, stage.machine
    end
    local setup = storage[player_index].module_setups_by_recipe_name[recipe_name]
    local identifier = storage[player_index].identifiers_of_chosen_crafting_machines_by_recipe_name[recipe_name]
    if not setup or not cell.tags.signature or ModuleSetup.signature(setup, identifier) ~= cell.tags.signature then
        return nil
    end
    --the row's product was bound to another recipe since the cell was built, so the cell shows a recipe the row no longer uses
    if storage[player_index].product_full_names_by_recipe_name[recipe_name] ~= cell.tags.product_full_name then
        return nil
    end
    return setup, cell, recipe_name, identifier
end

--Makes the stored setup valid again and rebuilds the cell from it, with a fresh signature
local function apply(cell, recipe_name, identifier)
    if cell.tags.loop_key then
        ModuleSetup.sanitize_setup(owned_setup(cell.player_index, recipe_name, cell.tags), identifier, prototypes.recipe[recipe_name])
    else
        ModuleSetup.sanitize(cell.player_index, recipe_name)
    end
    cell.clear()
    fill(cell, prototypes.recipe[recipe_name], prototypes.entity[identifier.name], identifier)
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

--The stored setup, cell, recipe name and machine identifier a module slot acts on, or nil when its cell is stale
function ModuleGUI.context(element)
    return current_setup(element)
end

--The module list a slot button stores into, with the entities its modules must fit and that list's slot count; nil when the slot's group is gone
function ModuleGUI.slot_target(button, setup, identifier)
    local machine = prototypes.entity[identifier.name]
    if button.name == "hxrrc_choose_beacon_module_button" then
        local group = setup.beacons[button.tags.group]
        if not group then
            return nil
        end
        local beacon = prototypes.entity[group.name]
        return group.modules, {beacon, machine}, ModuleSetup.beacon_capacity(beacon, group.quality)
    end
    return setup.modules, {machine}, ModuleSetup.machine_capacity(machine, identifier.quality)
end

--Stores a value into the slot a button owns the way every pick does: a stale cell refuses it, the module list takes it through
--ModuleSetup.store_pick (so an empty row fills), then the setup is sanitized and the cell rebuilt. picked: {name, quality} or nil to empty the slot.
--Returns true when the stored setup changed. Shared by the chooser, the module picker window and pipette pastes.
function ModuleGUI.pick_into(button, picked)
    local setup, cell, recipe_name, identifier = current_setup(button)
    if not setup then
        return false
    end
    local modules, _, capacity = ModuleGUI.slot_target(button, setup, identifier)
    if not modules or not ModuleSetup.store_pick(modules, button.tags.index, picked, capacity) then
        return false
    end
    apply(cell, recipe_name, identifier)
    return true
end

--A chooser slot (Factorio's own picker, kept for reports built before the module picker window): refused changes restore the button's snapshot.
--Returns true when the stored setup changed
local function on_slot_value_changed(event)
    local button = event.element
    local restored = restored_value(button)
    --a refused change restores the button, which may raise this event again: the restored value is then a no-op
    if same_value(button.elem_value, restored) then
        return false
    end
    if not current_setup(button) then
        button.elem_value = restored
        return false
    end
    return ModuleGUI.pick_into(button, button.elem_value)
end

ModuleGUI.on_module_button_changed = on_slot_value_changed
ModuleGUI.on_beacon_module_button_changed = on_slot_value_changed

local function restored_beacon(beacon_button)
    local value = beacon_button.tags.value
    if not (value and storage.beacon_names[value.name]) then
        return nil
    end
    return {name = value.name, quality = value.quality and prototypes.quality[value.quality] and value.quality or nil}
end

--Returns true when the stored setup changed: the add button appends a group of one beacon per machine, one machine per beacon;
--changing a group's beacon keeps its numbers and the modules the new beacon accepts; emptying it removes the group
function ModuleGUI.on_beacon_button_changed(event)
    local beacon_button = event.element
    local restored = restored_beacon(beacon_button)
    if same_value(beacon_button.elem_value, restored) then
        return false
    end
    local setup, cell, recipe_name, identifier = current_setup(beacon_button)
    if not setup then
        beacon_button.elem_value = restored
        return false
    end
    local picked_beacon = beacon_button.elem_value
    local group_index = beacon_button.tags.group
    if picked_beacon == nil then
        table.remove(setup.beacons, group_index)
    elseif group_index <= #setup.beacons then
        local group = setup.beacons[group_index]
        group.name, group.quality = picked_beacon.name, picked_beacon.quality ~= "normal" and picked_beacon.quality or nil
    else
        setup.beacons[#setup.beacons + 1] = {name = picked_beacon.name, quality = picked_beacon.quality ~= "normal" and picked_beacon.quality or nil,
            count = 1, sharing = 1, modules = {}}
    end
    apply(cell, recipe_name, identifier)
    return true
end

--Text of a count or sharing field as a whole number from 1 to 9999, or nil
local function parse_count(text)
    if not text:match("^%d%d?%d?%d?$") then
        return nil
    end
    local value = tonumber(text)
    return value >= 1 and value or nil
end

local function apply_beacon_number(field, key, value)
    local restored = field.tags.text
    --a refused change restores the text, which may raise this event again: the restored text is then a no-op
    if field.text == restored then
        return false
    end
    local setup, cell, recipe_name, identifier = current_setup(field)
    if not setup or value == nil then
        field.text = restored
        return false
    end
    setup.beacons[field.tags.group][key] = value
    apply(cell, recipe_name, identifier)
    return true
end

--Returns true when the stored setup changed
function ModuleGUI.on_beacon_count_confirmed(event)
    return apply_beacon_number(event.element, "count", parse_count(event.element.text))
end

--Returns true when the stored setup changed
function ModuleGUI.on_beacon_sharing_confirmed(event)
    return apply_beacon_number(event.element, "sharing", parse_count(event.element.text))
end

return ModuleGUI
