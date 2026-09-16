event_handlers = {}
event_handlers.on_gui_click = {}
event_handlers.on_gui_confirmed = {}
event_handlers.on_gui_elem_changed = {}
event_handlers.on_gui_checked_state_changed = {}
event_handlers.on_gui_selection_state_changed = {}

local Calculator = require "gui.calculator"
local ModulePicker = require "gui.module_picker"
local Pipette = require "gui.pipette"
local Sheet = require "gui.sheet"
local Indexer = require "logic.indexer"
local PlayerData = require "logic.player_data"
local PlayerDataUpdater = require "logic.player_data_updater"
local Updates = require "updates"

async_calls = {Sheet.calculate, Calculator.auto_center}

local function set_up_new_player(player)
    PlayerData.initialize_player_data(player.index)
    Calculator.build(player)
end

script.on_init(function()
    Indexer.run()
    storage.computation_stack = {}
    storage.opened_restores = nil
    for _, player in pairs(game.players) do
        set_up_new_player(player)
    end
end)

script.on_configuration_changed(function(configuration_changed_data)
    Indexer.run()

    local rrc_version_change = configuration_changed_data.mod_changes[script.mod_name]
    if rrc_version_change then
        Updates.update_from(rrc_version_change.old_version)
    end

    storage.computation_stack = {}
    storage.opened_restores = nil --the GUIs are rebuilt and recomputed below; pending focus restores are dropped
    for _, player in pairs(game.players) do
        storage[player.index].backlogged_computation_count = 0 --the stack was just emptied; older versions never decremented this count
        PlayerDataUpdater.reinitialize(player.index)
        Sheet.add_missing_controls(storage[player.index].sheet_section.sheet_pane)
        Calculator.recompute_everything(player.index)
    end
end)

script.on_event(defines.events.on_player_created, function(event)
    set_up_new_player(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_player_removed, function(event)
    storage[event.player_index] = nil
    ModulePicker.forget_player(event.player_index)
    --queued computations of the removed player would reach its destroyed GUI
    for index = #storage.computation_stack, 1, -1 do
        if storage.computation_stack[index].player_index == event.player_index then
            table.remove(storage.computation_stack, index)
        end
    end
end)

script.on_event("hxrrc_toggle_calculator", function(event)
    Calculator.toggle(game.get_player(event.player_index))
end)

script.on_event("hxrrc_pipette", function(event)
    if Pipette.on_pipette(event) then
        Calculator.recompute_everything(event.player_index)
    end
end)

script.on_event("hxrrc_confirm_module_picker", function(event)
    if ModulePicker.confirm(event.player_index) then
        Calculator.recompute_everything(event.player_index)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local element = event.element
    if not element then
        return
    end
    if element.name == "hxrrc_module_picker" then
        ModulePicker.on_engine_closed(event.player_index)
    elseif element.name == "hxrrc_calculator" and element.visible and not (storage[event.player_index] and storage[event.player_index].module_picker) then
        --a picker taking the focus from the calculator must not close it
        Calculator.toggle(game.get_player(event.player_index))
    end
end)

script.on_event(defines.events.on_research_finished, function(event)
    for _, effect in ipairs(event.research.prototype.effects) do
        --productivity changes recipe outputs; an unlocked quality changes how far quality loops reach
        if effect.type == "change-recipe-productivity" or effect.type == "unlock-quality" then
            for _, player in pairs(event.research.force.players) do
                Calculator.recompute_everything(player.index)
            end
            return
        end
    end
end)

--Register handlers for which event.element.name exists
for _, event_type in ipairs({
    "on_gui_click",
    "on_gui_elem_changed",
    "on_gui_confirmed",
    "on_gui_checked_state_changed",
    "on_gui_selection_state_changed",
    }) do
    script.on_event(defines.events[event_type], function(event)
        local handler = event_handlers[event_type][event.element.name]
        if handler then handler(event) end
    end)
end

--Do each sheet calculation in its own tick, oldest request first (computation_stack is used as a queue; the name is kept for existing saves)
script.on_event(defines.events.on_tick, function()
    if storage.computation_stack[1] then
        local async_call_data = table.remove(storage.computation_stack, 1)
        local player_index = async_call_data.player_index
        if storage[player_index] then
            local call = async_calls[async_call_data.call_id]
            call(table.unpack(async_call_data.parameters))
            storage[player_index].backlogged_computation_count = storage[player_index].backlogged_computation_count - 1
            game.get_player(player_index).gui.screen.hxrrc_calculator.enabled = storage[player_index].backlogged_computation_count == 0
        end
    end
    ModulePicker.run_restores()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "hxrrc-displayed-floating-point-precision" then
        Calculator.recompute_everything(event.player_index)
    end
end)