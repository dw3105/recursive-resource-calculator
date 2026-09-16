--The pipette key (Q, or whatever the player bound the pipette to) over the calculator: copies the module under the cursor into the hand as a ghost.
--Factorio 2.0.77 gives the custom input event the GUI element under the cursor; anything that is not one of the calculator's controls is left to
--the vanilla pipette, which runs on the same press.
local ModuleGUI = require "gui.modulegui"
local Report = require "gui.report"
local QualityLoops = require "logic.quality_loops"

local Pipette = {}

local MODULE_SLOTS = {hxrrc_choose_module_button = true, hxrrc_choose_beacon_module_button = true}
local MACHINE_BUTTONS = {hxrrc_choose_crafting_machine_button = true, hxrrc_choose_loop_machine_button = true}

--The item that places an entity, never assumed to share the entity's name; nil when the entity has none (items_to_place_this is optional)
local function placing_item(entity_name)
    local prototype = prototypes.entity[entity_name]
    local items = prototype and prototype.items_to_place_this
    return items and items[1] and items[1].name
end

--Remembers a fresh row's or loop stage's machine and a copy of its setup that shares no table with it, and puts the machine's item in the hand.
--The clipboard forgives exactly one cursor notification, in this tick: the one this ghost write raises (see gui/pipette.lua N13).
local function copy_machine(player, button, tick)
    local context = Report.machine_context(button)
    if not context then
        return
    end
    local item = placing_item(context.machine.name)
    if not item then
        player.create_local_flying_text{text = {"hxrrc.machine_has_no_item_error"}, create_at_cursor = true}
        return
    end
    local id = storage.pipette_next_id or 1
    storage.pipette_next_id = id + 1
    storage[player.index].pipette = {
        id = id,
        kind = "machine",
        item = {name = item, quality = context.machine.quality},
        machine = {name = context.machine.name, quality = context.machine.quality},
        setup = QualityLoops.fitted_setup_copy(context.setup, context.machine, context.recipe),
        own_notifications = 1,
        copied_tick = tick,
    }
    player.cursor_ghost = {name = item, quality = context.machine.quality}
end

--A quality given as a prototype or a name, as a name; nil for normal
local function quality_name(quality)
    local name = type(quality) == "table" and quality.name or quality
    return name ~= "normal" and name or nil
end

--What the player holds as {name, quality, real | ghost}, names only, quality nil for normal; nil for an empty hand.
--A real item in the cursor stack comes first: Factorio 2.0.77 gives it priority over the cursor ghost. Both reads return prototypes.
function Pipette.held(player)
    local stack = player.cursor_stack
    if stack and stack.valid_for_read then
        return {name = stack.name, quality = quality_name(stack.quality), real = true}
    end
    local ghost = player.cursor_ghost
    if ghost then
        local name = type(ghost.name) == "table" and ghost.name.name or ghost.name
        return {name = name, quality = quality_name(ghost.quality), ghost = true}
    end
end

--The module stored in the slot a button shows, or nil for an empty slot or a stale cell. The stored setup is read, never the button's own value.
local function stored_module(button)
    local setup, _, _, identifier = ModuleGUI.context(button)
    if not setup then
        return nil
    end
    local modules = ModuleGUI.slot_target(button, setup, identifier)
    return modules and modules[button.tags.index]
end

--Returns true when stored sheet state changed (so the caller recomputes)
function Pipette.on_pipette(event)
    local element = event.element
    if not (element and element.valid) then
        return false
    end
    local player = game.get_player(event.player_index)
    if MODULE_SLOTS[element.name] then
        if Pipette.held(player) == nil then
            local module = stored_module(element)
            if module then
                player.cursor_ghost = {name = module.name, quality = module.quality}
            end
        end
        return false
    end
    if MACHINE_BUTTONS[element.name] then
        if Pipette.held(player) == nil then
            copy_machine(player, element, event.tick)
        end
        return false
    end
    return false
end

return Pipette
