event_handlers = {}
event_handlers.on_gui_click = {}
event_handlers.on_gui_confirmed = {}
event_handlers.on_gui_elem_changed = {}
event_handlers.on_gui_checked_state_changed = {}
event_handlers.on_gui_selection_state_changed = {}

local Calculator = require "gui.calculator"
local ModulePicker = require "gui.module_picker"
--Round 8 modules. Requiring them here is what registers their GUI handlers and their remote interface.
local Jobs = require "logic.jobs"
local Registry = require "logic.registry"
local Generation = require "logic.bp.generation"
local BlueprintDelivery = require "gui.blueprint_delivery"
--Loaded here so their registry entries exist before any handler runs: a handler may never call require.
local Snapshot = require "logic.snapshot"
local SolverSteps = require "logic.solver_steps"
local Reset = require "logic.reset"
local EngineTestApi = require "logic.engine_test_api"
local Pipette = require "gui.pipette"
local Sheet = require "gui.sheet"
local ExportDialog = require "gui.export_dialog"
local BlueprintDialog = require "gui.blueprint_dialog"
local Indexer = require "logic.indexer"
local PlayerData = require "logic.player_data"
local PlayerDataUpdater = require "logic.player_data_updater"
local Updates = require "updates"
--Load the calculation job kind while control.lua is parsed; handlers may never require it at runtime.
local CalcPipeline = require "logic.calc_pipeline"
--Publishes Registry.calculation: the record preparation reads instead of solving again (contracts §19)
local Calculation = require "logic.calculation_result"

--Ids 1 and 2 keep their meaning: a save made by an older version can hold queued entries naming them.
async_calls = {Sheet.calculate, Calculator.auto_center, Jobs.step}

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
    --Prototypes may have changed under any running job, so no result computed before this point may commit
    Jobs.invalidate_all("configuration_changed")
    local stopped = Generation.stop_all("mod_updated")
    for _, player in pairs(game.players) do
        local player_index = player.index
        if type(Registry.progress_sweep) == "function" then Registry.progress_sweep(player_index) end
    end
    for _, item in ipairs(stopped) do
        if type(Registry.progress_note) == "function" then
            Registry.progress_note(item.player_index, item.sheet_id, {"hxrrc.blueprint_stopped_update"})
        end
    end
    --Prototypes changed, so every stored solver result describes a world that no longer exists
    Calculation.forget_all()
    for _, player in pairs(game.players) do
        --a picker saved by an older version holds a state this version does not read; closed before anything is repaired
        ModulePicker.close(player.index, false)
        storage[player.index].pipette_requests = nil --targets and machines may be gone
        storage[player.index].backlogged_computation_count = 0 --the stack was just emptied; older versions never decremented this count
        PlayerDataUpdater.reinitialize(player.index)
        Sheet.add_missing_controls(storage[player.index].sheet_section.sheet_pane)
        Calculator.recompute_everything(player.index)
    end
end)

--The in-game test companion calls this candidate rather than imitating it; absent in a source checkout, where
--EngineTestApi reports packaged = false and the companion refuses to write evidence.
EngineTestApi.register()

script.on_event(defines.events.on_player_created, function(event)
    set_up_new_player(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_player_removed, function(event)
    Jobs.forget_player(event.player_index)
    Reset.forget_player(event.player_index)
    Calculation.forget_player(event.player_index)
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

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
    Pipette.on_cursor_changed(event)
    local player = game.get_player(event.player_index)
    if player and not (player.cursor_stack and player.cursor_stack.valid_for_read)
        and player.cursor_ghost == nil and player.cursor_record == nil then
        if BlueprintDelivery.retry(event.player_index) then
            local data = storage[event.player_index]
            local sheet_id = data and data.blueprint_delivery_sheet
            if sheet_id ~= nil and type(Registry.progress_note) == "function" then
                Registry.progress_note(event.player_index, sheet_id, nil)
            end
            if data then data.blueprint_delivery_sheet = nil end
        end
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
    --Esc and the close key reach the window through player.opened. The engine clears player.opened and fires
    --this event; without these two branches the frame stayed on screen and neither key closed it.
    elseif element.name == ExportDialog.FRAME_NAME then
        ExportDialog.close(event.player_index)
    elseif element.name == BlueprintDialog.FRAME_NAME then
        BlueprintDialog.close(event.player_index)
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
script.on_event(defines.events.on_tick, function(event)
    --pastes recorded in earlier ticks, before the queued computations, so a paste's recompute follows it
    for _, player_index in ipairs(Pipette.run_requests(event.tick)) do
        Calculator.recompute_everything(player_index)
    end
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
    --Incremental work runs after the legacy queue, under one budget shared by every player (CALC-06)
    Jobs.on_tick(event)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "hxrrc-displayed-floating-point-precision" then
        Calculator.recompute_everything(event.player_index)
    end
end)

--Headless tests (tools/game_test.sh) stage the mod with "? factorio-test"; a release zip never loads that mod, so this
--branch is dead in the shipped game. Parse-time require only, as Factorio demands.
local factorio_test_init = script.active_mods["factorio-test"] and require("__factorio-test__/init")
if factorio_test_init then factorio_test_init(require("tests.game.index"), {load_luassert = true, default_timeout = 36000}) end
